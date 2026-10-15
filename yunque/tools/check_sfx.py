#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验音效资产是否符合规格。

用法（在 yunque/ 下执行）：

    python tools/check_sfx.py                  # 校验资产目录本身
    python tools/check_sfx.py --dir /tmp/x     # 校验别处
    python tools/check_sfx.py --vs /tmp/x      # 资产目录 与 另一批 逐文件对照

校验项：
    - 帧数必须等于规格表（时长错会让 AudioDirector 的循环点错位）
    - 峰值必须等于目标值（各类音效之间的响度平衡是刻意设定的）
    - 尾部残留不得超过峰值的 8%（否则截断处会"咔"一声）
    - 直流偏移（听不出来，但没必要留着）

对照模式额外报告过零率差异。过零率是频谱质心的粗糙代理，
差距超过 2 倍说明音色明显不同，值得看一眼。
"""

import argparse
import os
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx as spec          # 复用规格表，避免两处各写一份

TAIL_LIMIT = 0.08               # 尾部残留上限（占峰值比例）
DC_LIMIT = 200                  # 直流偏移上限（16 bit 满刻度 32767）


def load(path):
    with wave.open(path, "rb") as w:
        n, sw = w.getnframes(), w.getsampwidth()
        raw = w.readframes(n)
    return struct.unpack("<%dh" % (len(raw) // 2), raw) if sw == 2 else ()


def stats(vals):
    n = len(vals)
    if n == 0:
        return dict(n=0, peak=0, zcr=0.0, dc=0.0, tail=0)
    peak = max(abs(v) for v in vals)
    dc = sum(vals) / float(n)
    zc = 0
    for i in range(1, n):
        if (vals[i - 1] < 0) != (vals[i] < 0):
            zc += 1
    tail = max(abs(v) for v in vals[-300:]) if n >= 300 else peak
    return dict(n=n, peak=peak, zcr=zc / (n / 44100.0), dc=dc, tail=tail)


def check_dir(path):
    """校验一批文件是否符合规格。返回失败项数。"""
    names = sorted(n for n in os.listdir(path) if n.endswith(".wav"))
    if not names:
        print("目录下没有 .wav：%s" % path)
        return 1

    fails = 0
    for name in names:
        key_f, key_p = spec.frames_key(name), spec.peak_key(name)
        if key_f not in spec._FRAMES:
            print("  %-22s 不在规格表中（新增音效需先补 _FRAMES）" % name)
            fails += 1
            continue
        s = stats(load(os.path.join(path, name)))
        problems = []
        want_frames = spec._FRAMES[key_f]
        if s["n"] != want_frames:
            problems.append("帧数 %d≠%d" % (s["n"], want_frames))
        want_peak = int(spec._TARGET_PEAK[key_p] * 32767)
        if abs(s["peak"] - want_peak) > max(2, want_peak * 0.005):
            problems.append("峰值 %d≠%d" % (s["peak"], want_peak))
        if not name.startswith("amb_"):
            if s["tail"] > s["peak"] * TAIL_LIMIT:
                problems.append("尾部残留 %.0f%%" % (s["tail"] * 100.0 / max(1, s["peak"])))
        if abs(s["dc"]) > DC_LIMIT:
            problems.append("直流 %d" % s["dc"])

        if problems:
            fails += 1
            print("  %-22s ✗ %s" % (name, " / ".join(problems)))
        else:
            print("  %-22s ✓ %7d 帧  峰值 %5d  过零 %5.0f Hz" % (name, s["n"], s["peak"], s["zcr"]))
    return fails


def compare(a_dir, b_dir):
    """对照两批文件（a 为参照，通常是已入库的旧版）。返回失败项数。"""
    names = sorted(n for n in os.listdir(a_dir) if n.endswith(".wav"))
    fails = 0
    print("%-22s %-28s %-28s %s" % ("file", "参照 a", "待检 b", "判定"))
    print("-" * 112)
    for name in names:
        pa, pb = os.path.join(a_dir, name), os.path.join(b_dir, name)
        if not os.path.exists(pb):
            print("%-22s %s" % (name, "b 缺失"))
            fails += 1
            continue
        sa, sb = stats(load(pa)), stats(load(pb))
        flags = []
        if sa["n"] != sb["n"]:
            flags.append("帧数")
        if sa["peak"] and abs(sb["peak"] - sa["peak"]) / float(sa["peak"]) > 0.03:
            flags.append("峰值(%d→%d)" % (sa["peak"], sb["peak"]))
        if sb["tail"] > sb["peak"] * 0.10 and not name.startswith("amb_"):
            flags.append("尾部残留")
        if abs(sb["dc"]) > DC_LIMIT:
            flags.append("直流")
        zr = (sb["zcr"] / sa["zcr"]) if sa["zcr"] > 0 else 0.0
        note = "" if 0.5 <= zr <= 2.0 else "  [过零×%.2f]" % zr
        if flags:
            fails += 1
        print("%-22s %6dpx %6.0fHz | %6dpx %6.0fHz | %s%s"
              % (name, sa["peak"], sa["zcr"], sb["peak"], sb["zcr"],
                 "OK" if not flags else " / ".join(flags), note))
    print("-" * 112)
    return fails


def main():
    parser = argparse.ArgumentParser(description="校验音效资产")
    here = os.path.dirname(os.path.abspath(__file__))
    parser.add_argument("--dir", default=os.path.join(here, "..", "assets", "processed", "audio"),
                        help="要校验的目录")
    parser.add_argument("--vs", default=None, help="对照目录（作为参照物）")
    args = parser.parse_args()

    if args.vs:
        fails = compare(os.path.abspath(args.vs), os.path.abspath(args.dir))
        print("对照完成，异常 %d 个" % fails)
    else:
        print("校验目录：%s" % os.path.abspath(args.dir))
        fails = check_dir(os.path.abspath(args.dir))
        print("校验完成，异常 %d 个" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
