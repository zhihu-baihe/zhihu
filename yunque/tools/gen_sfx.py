#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""云阙行：九灯照夜 —— 音效程序化合成

为什么是脚本而不是音频文件：项目硬约束是零预算、无外部资产、改参数即可重现。
19 个音全部由标准库合成（math / random / struct / wave），不依赖 numpy、不联网。

用法（在 yunque/ 下执行）：

    python tools/gen_sfx.py                # 覆盖生成到 assets/processed/audio/
    python tools/gen_sfx.py --out /tmp/x   # 生成到别处（用于比对）

改完必须重跑本脚本，再让 Godot 重新导入；**不要直接编辑 WAV 二进制**。

规格来源：开发文档 07《角色动画与音效方案》§4、05《美术标准》§14。
"""

import argparse
import math
import os
import random
import struct
import wave

SR = 44100          # 采样率：全项目统一
XFADE_SEC = 0.35    # 循环音首尾交叉淡化长度（美术标准 §14.2 硬规则）
TAIL = 0.08         # 尾部残留上限：超过峰值的这个比例就算"没淡出"，会被自检拦下

# 逐文件帧数。这些不是随手取的数：AudioDirector 按固定时长装载，
# 且与已入库的 19 个 WAV 严格一致（合计 34.4 s），改动会让自检与听感同时漂移。
_FRAMES = {
    "step_stone": 5733,        # 0.130 s
    "step_wood": 6615,         # 0.150 s
    "ui_click": 2425,          # 0.055 s（≤60 ms，美术标准 §14.2）
    "ui_hover": 2646,          # 0.060 s
    "ui_open": 9702,           # 0.220 s
    "ui_close": 8820,          # 0.200 s
    "pickup": 14994,           # 0.340 s
    "clue": 66150,             # 1.500 s
    "dialogue_blip": 1543,     # 0.035 s
    "bell_far": 198450,        # 4.500 s
    "lantern_chime": 26460,    # 0.600 s
    "amb": 381466,             # 8.650 s（循环）
}
_XFADE_N = int(XFADE_SEC * SR)

# 目标峰值（线性，1.0 = 满刻度）。**不要统一改成某个值**：
# 这些数是按已入库资产实测反推出来的，代表各类音效之间的响度平衡关系。
# 引擎侧再按美术标准 §14.1 分三层加 dB（环境 −14/−17/−25，反馈 −6~−19，事件 −8~−10）。
_TARGET_PEAK = {
    "step_stone": 0.62,
    "step_wood": 0.60,
    "ui_click": 0.22,
    "ui_hover": 0.14,
    "ui_open": 0.28,
    "ui_close": 0.24,
    "pickup": 0.55,
    "clue": 0.62,
    "dialogue_blip": 0.208,
    "bell_far": 0.38,
    "lantern_chime": 0.34,
    "amb_night": 0.40,
    "amb_water": 0.36,
    "amb_crickets": 0.26,
}


# ------------------------------------------------------------------ 基础工具

def white(n, rng):
    """白噪声。"""
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def slow_noise(n, step, rng):
    """超低频噪声：每 step 个样本换一个新随机值，中间线性插值。

    为什么不直接用 lowpass()：一阶 EMA 的极点是 p = 1 − 2π·fc/sr，
    就算把 fc 压到 180 Hz，p 仍有 0.974，过零率还在 3 kHz 以上 ——
    也就是说它**听起来并不"低"**，只会把噪声稍微变闷。
    需要真正缓慢的起伏（风的一阵一阵、虫鸣的背景）时必须用本函数。
    """
    out = [0.0] * n
    prev = rng.uniform(-1.0, 1.0)
    i = 0
    while i < n:
        nxt = rng.uniform(-1.0, 1.0)
        for j in range(step):
            if i + j >= n:
                break
            out[i + j] = prev + (nxt - prev) * (j / float(step))
        prev = nxt
        i += step
    return out


def lowpass(x, cutoff, sr=SR):
    """一阶 RC 低通。够用：本轮只需要"闷一点/亮一点"，不需要砖墙。"""
    k = 2.0 * math.pi * cutoff / sr
    a = k / (k + 1.0)
    out = [0.0] * len(x)
    prev = 0.0
    for i, v in enumerate(x):
        prev += a * (v - prev)
        out[i] = prev
    return out


def highpass(x, cutoff, sr=SR):
    """一阶 RC 高通，与 lowpass 互补。"""
    k = 2.0 * math.pi * cutoff / sr
    a = k / (k + 1.0)
    out = [0.0] * len(x)
    prev_in = 0.0
    prev_out = 0.0
    for i, v in enumerate(x):
        prev_out = a * (prev_out + v - prev_in)
        prev_in = v
        out[i] = prev_out
    return out


def bandpass(x, lo, hi, sr=SR):
    return highpass(lowpass(x, hi, sr), lo, sr)


def sine(freq, n, sr=SR, phase=0.0):
    w = 2.0 * math.pi * freq / sr
    return [math.sin(w * i + phase) for i in range(n)]


def triangle(freq, n, sr=SR):
    w = 2.0 * math.pi * freq / sr
    return [(2.0 / math.pi) * math.asin(math.sin(w * i)) for i in range(n)]


def square(freq, n, sr=SR):
    w = 2.0 * math.pi * freq / sr
    return [1.0 if math.sin(w * i) >= 0.0 else -1.0 for i in range(n)]


def sweep(f0, f1, n, shape=1.0, sr=SR):
    """扫频。用相位累加而不是 sin(2πf(t)·t)，否则频率变化时会有相位跳变。

    shape < 1 表示先快后慢（UI 开合的听感更自然）。
    """
    out = [0.0] * n
    ph = 0.0
    span = n - 1 if n > 1 else 1
    for i in range(n):
        t = (i / span) ** shape
        ph += 2.0 * math.pi * (f0 + (f1 - f0) * t) / sr
        out[i] = math.sin(ph)
    return out


def exp_env(n, tau, sr=SR):
    """指数衰减包络（tau 单位：秒）。"""
    return [math.exp(-i / (tau * sr)) for i in range(n)]


def bell_env(n, attack, decay, sr=SR):
    """钟形包络：升余弦淡入 + 指数收尾。

    decay 取 tau 的语义 —— 要让包络在文件结束前落到近零，
    否则尾部突然截断会"咔"一声（见 tail_guard）。
    """
    a = max(1, int(attack * sr))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            out[i] = 0.5 - 0.5 * math.cos(math.pi * i / a)
        else:
            out[i] = math.exp(-(i - a) / (decay * sr))
    return out


def apply_env(x, env):
    return [v * e for v, e in zip(x, env)]


def mix(*args):
    """mix(layer1, gain1, layer2, gain2, ...)：按增益叠加，长度取第一层。"""
    n = len(args[0])
    out = [0.0] * n
    for i in range(0, len(args), 2):
        layer = args[i]
        gain = args[i + 1] if i + 1 < len(args) else 1.0
        for j in range(n):
            out[j] += layer[j] * gain
    return out


def remove_dc(x):
    """去直流。低频正弦叠指数包络后常留一点直流残余，听不出来但没必要留着。"""
    if not x:
        return list(x)
    mean = sum(x) / len(x)
    return [v - mean for v in x]


def normalize(x, peak):
    """去直流 + 归一化到目标峰值。

    去直流必须在这里做：夹在归一化之后会改动峰值，峰值就不再等于目标值
    （早期版本踩过：step_stone 归一化到 20315 又被直流抬成 20145）。
    """
    x = remove_dc(x)
    m = 0.0
    for v in x:
        if abs(v) > m:
            m = abs(v)
    if m < 1e-9:
        return list(x)
    k = peak / m
    return [v * k for v in x]


def fade_out(x, sec, sr=SR):
    """尾部升余弦淡出。

    用升余弦而不是线性：线性淡出在起点有一阶不连续，短音上仍可能听出轻微的"噗"。
    sec 必须足够覆盖尾部残留，否则淡出本身就成了新的爆音源。
    """
    m = min(len(x), int(sec * sr))
    if m <= 0:
        return list(x)
    out = list(x)
    base = len(out) - m
    for i in range(m):
        out[base + i] *= 0.5 + 0.5 * math.cos(math.pi * i / m)
    return out


def xfade_loop(x, sec=XFADE_SEC, sr=SR):
    """首尾交叉淡化 → 循环点无缝。

    做法：裁掉尾部 sec，再把裁掉的那段淡入地叠回开头。
    输出长度 = 输入长度 − sec，所以调用方要多生成 sec 的量。
    """
    m = int(sec * sr)
    n = len(x)
    if m <= 0 or n <= m:
        return list(x)
    out = list(x[:n - m])
    for i in range(m):
        a = (i + 1) / m
        out[i] = x[n - m + i] * (1.0 - a) + x[i] * a
    return out


def tail_guard(x, name, sec=0.010, sr=SR):
    """收尾：淡出 → 检查尾部确实落到近零。

    检查会拦住"包络还没衰减完就结束"的情况 —— 那种文件在游戏里会咔哒，
    而且只有反复播放才听得出来，属于最容易漏掉的缺陷。
    （去直流已由 normalize 完成，此处不再重复。）
    """
    out = fade_out(x, sec)
    peak = max(abs(v) for v in out) if out else 0.0
    tail = max(abs(v) for v in out[-300:]) if len(out) >= 300 else peak
    if peak > 1e-9 and tail > peak * TAIL:
        raise RuntimeError("%s 尾部残留 %.1f%%（上限 %.0f%%）：收尾包络没配好"
                           % (name, tail / peak * 100.0, TAIL * 100.0))
    return out


def write_wav(path, x, sr=SR):
    frames = bytearray()
    for v in x:
        s = int(max(-1.0, min(1.0, v)) * 32767.0)
        frames += struct.pack("<h", s)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(frames))


# ------------------------------------------------------------------ 脚步
# 美术标准 §14.2：同一音效连续触发必须变异，不得出现"机关枪"式重复。
# 因此每个变体的衰减时间与噪声相位都抽取随机，只是种子固定以保证可复现。

def gen_step_stone(rng):
    """石板脚步：噪声脉冲（低通 1.9k + 高通 3.6k）+ 92 Hz 闷响。"""
    n = _FRAMES["step_stone"]

    # 主体：脚跟落地的闷响（低通噪声 + 快衰减）
    main = lowpass(white(n, rng), 1900.0)
    main = apply_env(main, exp_env(n, rng.uniform(0.021, 0.030)))

    # 颗粒：石面沙砾的细碎感（高通噪声，衰减更快）
    grit = highpass(white(n, rng), 3600.0)
    grit = apply_env(grit, exp_env(n, rng.uniform(0.005, 0.010)))

    # 低频闷响：石板的"钝"
    thud = sine(92.0, n, phase=rng.uniform(0.0, 2.0 * math.pi))
    thud = apply_env(thud, exp_env(n, rng.uniform(0.024, 0.032)))

    # 石板脚步以 92 Hz 闷响为主体：石板上踩一脚本来就是"咚"而不是"沙"。
    # （入库资产实测过零率仅 400~500 Hz，若让噪声层主导会飙到 2000 Hz 以上，
    #   听感就从石板变成了碎石。）
    out = mix(main, 0.32, grit, 0.11, thud, 1.0)
    out = normalize(out, _TARGET_PEAK["step_stone"])
    return tail_guard(out, "step_stone", 0.004)


def gen_step_wood(rng):
    """木板脚步：更脆（截止更高）+ 205 / 428 Hz 板腔共鸣。"""
    n = _FRAMES["step_wood"]

    click = bandpass(white(n, rng), 900.0, 5200.0)
    click = apply_env(click, exp_env(n, rng.uniform(0.009, 0.015)))

    # 板腔模态：两个低 Q 共鸣。衰减必须比 150 ms 的总长短得多，
    # 否则最后一个样本还挂着 30% 幅度 → 截断咔哒。
    m1 = apply_env(sine(205.0, n, phase=rng.uniform(0.0, 2.0 * math.pi)),
                   exp_env(n, rng.uniform(0.028, 0.038)))
    m2 = apply_env(sine(428.0, n, phase=rng.uniform(0.0, 2.0 * math.pi)),
                   exp_env(n, rng.uniform(0.018, 0.026)))

    # 木板比石板"脆"：敲击瞬态要压过板腔共鸣，否则两个脚步听起来一样。
    out = mix(click, 1.8, m1, 0.62, m2, 0.34)
    out = normalize(out, _TARGET_PEAK["step_wood"])
    return tail_guard(out, "step_wood", 0.005)


# ------------------------------------------------------------------ UI
# 美术标准 §14.2：反馈音不得刺耳 —— 走正弦/三角波 + 快衰减，避免方波长音。
# ui_click 是唯一的方波（要"咔"的瞬态），靠 55 ms 时长 + 4.2 kHz 软低通兜住。

def gen_ui_click(rng):
    n = _FRAMES["ui_click"]
    tone = lowpass(square(1180.0, n), 4200.0)
    tone = apply_env(tone, exp_env(n, 0.008))
    return tail_guard(normalize(tone, _TARGET_PEAK["ui_click"]), "ui_click", 0.003)


def gen_ui_hover(rng):
    """比 click 更轻更软：三角波，音高比 click 低一点（≈1 kHz）。"""
    n = _FRAMES["ui_hover"]
    tone = lowpass(triangle(1050.0, n), 5000.0)
    tone = apply_env(tone, exp_env(n, 0.010))
    return tail_guard(normalize(tone, _TARGET_PEAK["ui_hover"]), "ui_hover", 0.003)


def gen_ui_open(rng):
    """上扫频 + 钟形包络。"""
    n = _FRAMES["ui_open"]
    tone = apply_env(sweep(420.0, 1180.0, n, shape=0.7), bell_env(n, 0.055, 0.038))
    return tail_guard(normalize(tone, _TARGET_PEAK["ui_open"]), "ui_open", 0.008)


def gen_ui_close(rng):
    """下扫频，与 open 互为镜像。"""
    n = _FRAMES["ui_close"]
    tone = apply_env(sweep(1080.0, 400.0, n, shape=0.8), bell_env(n, 0.045, 0.035))
    return tail_guard(normalize(tone, _TARGET_PEAK["ui_close"]), "ui_close", 0.008)


# ------------------------------------------------------------------ 反馈

def gen_pickup(rng):
    """880 / 1320 / 1760 Hz 三连快衰减。"""
    n = _FRAMES["pickup"]
    out = [0.0] * n
    freqs = (880.0, 1320.0, 1760.0)
    step = n // len(freqs)
    for i, f in enumerate(freqs):
        start = i * step
        seg_n = n - start
        seg = apply_env(sine(f, seg_n), exp_env(seg_n, 0.030))
        for j in range(seg_n):
            out[start + j] += seg[j]
    out = normalize(out, _TARGET_PEAK["pickup"])
    return tail_guard(out, "pickup", 0.012)


def gen_clue(rng):
    """392→523→659→784 Hz 四音上行，正弦 + 2、3 次泛音（≈古琴拨弦）。

    注意这是**唯一**带音阶的反馈音：线索是稀疏事件，可以承担"记住这一刻"的作用；
    但不得做成奖励反馈音（美术标准 §14.2 明令禁止"叮"）。

    四个音只占前 4/5 时长，最后 1/5 专门留给末音的余韵 —— 否则最后一个音
    还没衰减完文件就结束了。
    """
    n = _FRAMES["clue"]
    out = [0.0] * n
    notes = (392.0, 523.25, 659.25, 783.99)   # G4 C5 E5 G5
    step = n // (len(notes) + 1)
    for i, f in enumerate(notes):
        start = i * step
        seg_n = n - start
        layer = mix(sine(f, seg_n), 1.0,
                    sine(f * 2.0, seg_n), 0.32,
                    sine(f * 3.0, seg_n), 0.14)
        layer = apply_env(layer, exp_env(seg_n, 0.19))
        for j in range(seg_n):
            out[start + j] += layer[j]
    out = normalize(out, _TARGET_PEAK["clue"])
    return tail_guard(out, "clue", 0.025)


def gen_dialogue_blip(rng):
    """对白打字音：35 ms 三角波 620 Hz。要短到"有节奏感但不吵"。"""
    n = _FRAMES["dialogue_blip"]
    tone = apply_env(triangle(620.0, n), exp_env(n, 0.008))
    return tail_guard(normalize(tone, _TARGET_PEAK["dialogue_blip"]), "dialogue_blip", 0.004)


# ------------------------------------------------------------------ 环境音

def gen_amb_night(rng):
    """夜风：低通噪声 + 两个阵风 LFO（0.13 / 0.047 Hz）。

    两个 LFO 频率互不成整数比，避免合成出周期性的"喘息"。
    不加旋律（美术标准 §14.2），只有质感。
    """
    n = _FRAMES["amb"] + _XFADE_N
    base = lowpass(white(n, rng), 900.0)
    lfo1 = sine(0.13, n)
    lfo2 = sine(0.047, n)
    for i in range(n):
        base[i] *= max(0.10, 0.55 + 0.30 * lfo1[i] + 0.22 * lfo2[i])

    # 高频层：树叶摩擦，让风"有表面"
    leaf = highpass(white(n, rng), 3600.0)
    for i in range(n):
        leaf[i] *= 0.12

    out = mix(base, 1.0, leaf, 1.0)
    return normalize(xfade_loop(out), _TARGET_PEAK["amb_night"])


def gen_amb_water(rng):
    """河水：中频流动 + 低频水体厚度。"""
    n = _FRAMES["amb"] + _XFADE_N
    flow = bandpass(white(n, rng), 700.0, 3200.0)
    lfo1 = sine(0.21, n)
    lfo2 = sine(0.083, n)
    for i in range(n):
        flow[i] *= 0.60 + 0.26 * lfo1[i] + 0.18 * lfo2[i]

    body = lowpass(white(n, rng), 240.0)
    out = mix(flow, 1.0, body, 0.34)
    return normalize(xfade_loop(out), _TARGET_PEAK["amb_water"])


def gen_amb_crickets(rng):
    """虫鸣：随机高频脉冲串 + 极低幅底噪。

    真实的蟋蟀是脉冲串（3~6 个 12 ms 的"唧"连发），不是长音；照抄这个结构，
    听感才对得上。

    底噪务必**压低频**（几百 Hz 以上会让整个音变成"沙沙"的宽带噪声，
    虫鸣就被淹没了）。
    """
    n = _FRAMES["amb"] + _XFADE_N
    out = [0.0] * n
    t = int(0.2 * SR)                       # 开头留一点静默，避免 xfade 时叠出突兀声
    while t < n:
        # 2.4~3.0 kHz：入库资产实测过零率只有 ~890 Hz，对应的鸣叫频率就在这个区间。
        # 定到 4 kHz 以上会让过零率翻五倍，听感从"虫鸣"变成"电流声"。
        freq = rng.uniform(2400.0, 3000.0)
        amplitude = rng.uniform(0.5, 0.95)
        chirps = rng.randint(3, 6)
        for _ in range(chirps):
            m = int(0.012 * SR)
            if t + m >= n:
                break
            pulse = apply_env(
                sine(freq, m, phase=rng.uniform(0.0, 2.0 * math.pi)),
                exp_env(m, 0.0035))
            for j in range(m):
                out[t + j] += pulse[j] * amplitude
            t += m + int(rng.uniform(0.018, 0.026) * SR)
        t += int(rng.uniform(0.10, 0.45) * SR)

    # 底噪只起两个作用：避免静音段让交叉淡化失真，以及给极远的背景一点"空气"。
    # 因此必须真的慢（见 slow_noise 的说明）—— 用普通低通会变成"沙沙"的宽带噪声，
    # 把虫鸣整个淹掉。
    floor = slow_noise(n, 1600, rng)
    for i in range(n):
        floor[i] *= 0.012
    out = mix(out, 1.0, floor, 1.0)
    return normalize(xfade_loop(out), _TARGET_PEAK["amb_crickets"])


def gen_bell_far(rng):
    """远钟：非谐波部分音叠加 + 敲击瞬态。

    钟的频谱不是谐波列（这是它听起来"是钟"的全部原因），
    且高部分音衰减显著快于低频 —— 所以每个部分音有各自的 tau。
    """
    n = _FRAMES["bell_far"]
    partials = (
        (110.0, 1.00, 2.20),
        (165.0, 0.52, 1.70),
        (220.0, 0.34, 1.30),
        (330.0, 0.24, 1.00),
        (493.0, 0.16, 0.72),
        (660.0, 0.11, 0.55),
    )
    out = [0.0] * n
    for freq, amp, tau in partials:
        p = sine(freq, n, phase=rng.uniform(0.0, 2.0 * math.pi))
        p = apply_env(p, exp_env(n, tau))
        for j in range(n):
            out[j] += p[j] * amp

    # 敲击瞬态：钟锤撞上钟体的那一瞬
    strike = apply_env(bandpass(white(n, rng), 1200.0, 6000.0), exp_env(n, 0.006))
    for j in range(n):
        out[j] += strike[j] * 0.35

    out = normalize(out, _TARGET_PEAK["bell_far"])
    return tail_guard(out, "bell_far", 0.020)


def gen_lantern_chime(rng):
    """灯笼轻响：1568 / 2093 / 2637 Hz 三音铃，带极短错时。

    每个音加一点 2.76 倍非谐波成分 —— 纯整数倍听起来像电子铃声。
    """
    n = _FRAMES["lantern_chime"]
    out = [0.0] * n
    voices = (
        (1568.0, 1.00, 0.13, 0.000),
        (2093.0, 0.70, 0.11, 0.018),
        (2637.0, 0.50, 0.09, 0.036),
    )
    for freq, amp, tau, offset in voices:
        tone = apply_env(sine(freq, n), exp_env(n, tau))
        overtone = apply_env(sine(freq * 2.76, n), exp_env(n, tau * 0.5))
        delay = int(offset * SR)
        for j in range(delay, n):
            k = j - delay
            out[j] += tone[k] * amp + overtone[k] * amp * 0.18

    out = normalize(out, _TARGET_PEAK["lantern_chime"])
    return tail_guard(out, "lantern_chime", 0.015)


# ------------------------------------------------------------------ 驱动

def build_all():
    """返回 [(文件名, 生成函数)]。顺序即生成顺序（随机流顺序也跟着固定）。"""
    jobs = []
    for i in range(1, 5):
        jobs.append(("step_stone_%d.wav" % i, gen_step_stone))
    for i in range(1, 4):
        jobs.append(("step_wood_%d.wav" % i, gen_step_wood))
    jobs += [
        ("ui_click.wav", gen_ui_click),
        ("ui_hover.wav", gen_ui_hover),
        ("ui_open.wav", gen_ui_open),
        ("ui_close.wav", gen_ui_close),
        ("pickup.wav", gen_pickup),
        ("clue.wav", gen_clue),
        ("dialogue_blip.wav", gen_dialogue_blip),
        ("bell_far.wav", gen_bell_far),
        ("lantern_chime.wav", gen_lantern_chime),
        ("amb_night.wav", gen_amb_night),
        ("amb_water.wav", gen_amb_water),
        ("amb_crickets.wav", gen_amb_crickets),
    ]
    return jobs


def frames_key(filename):
    """_FRAMES 的键：同类音效共用一种时长（脚步变体、环境音三层）。"""
    stem = filename[:-4]
    if stem.startswith("step_stone"):
        return "step_stone"
    if stem.startswith("step_wood"):
        return "step_wood"
    if stem.startswith("amb_"):
        return "amb"
    return stem


def peak_key(filename):
    """_TARGET_PEAK 的键：脚步变体共用一个目标，其余逐个文件。"""
    stem = filename[:-4]
    if stem.startswith("step_stone"):
        return "step_stone"
    if stem.startswith("step_wood"):
        return "step_wood"
    return stem


def main():
    parser = argparse.ArgumentParser(description="云阙行音效程序化合成")
    parser.add_argument("--out", default=None,
                        help="输出目录，默认 yunque/assets/processed/audio")
    args = parser.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.abspath(args.out or os.path.join(here, "..", "assets", "processed", "audio"))
    os.makedirs(out_dir, exist_ok=True)

    # 固定种子：同一版脚本永远产出同一批文件（可复现是本项目的硬约束）
    rng = random.Random(20261015)

    jobs = build_all()
    total_frames = 0
    for name, fn in jobs:
        samples = fn(rng)
        expect = _FRAMES[frames_key(name)]
        if len(samples) != expect:
            raise RuntimeError("%s 生成了 %d 帧，规格要求 %d 帧" % (name, len(samples), expect))
        write_wav(os.path.join(out_dir, name), samples)
        total_frames += len(samples)
        print("  %-22s %7d 帧  %6.3f s  峰值 %.3f"
              % (name, len(samples), len(samples) / SR, _TARGET_PEAK[peak_key(name)]))

    print("\n完成：%d 个音效 → %s" % (len(jobs), out_dir))
    print("合计 %.1f 秒（与美术标准记录的 34.4 s 对齐）" % (total_frames / SR))


if __name__ == "__main__":
    main()
