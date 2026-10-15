#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""贴图标定：为 TEX_MAP 反推 world_scale 与 tint。

为什么需要它
------------
`mat_cache.gd::textured()` 里 ALBEDO 的计算实际是：
      ALBEDO = tint.rgb(原始 0~1 数值) × Color贴图(sRGB→线性后)
两个反直觉的后果：
  1. tint 是**乘性**的。把调色板里用于纯色的中间亮度直接当 tint 用，
     等于把贴图整体压暗到原来的 30% —— 屋顶变黑板就是这么来的。
  2. 贴图必须先做 sRGB→线性，再去比亮度。sRGB 均值 0.198 的贴图，
     线性只有 0.032（差 6 倍）。用 sRGB 均值判断「够不够亮」会严重高估。

本工具输出三项：
  A. 线性域反射率（均值 / p75 / p95）—— 判断贴图亮度是否够
  B. 横向 / 纵向砖块数（FFT 主频）—— 反推 world_scale
  C. 预览图（缩小后拼图），供人眼复核块数

用法
----
  python tools/calibrate_textures.py                      # 标定全部
  python tools/calibrate_textures.py --only RoofingTiles012A PavingStones070
  python tools/calibrate_textures.py --preview            # 额外导出预览拼图
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = ROOT / "assets" / "processed" / "textures"


# ------------------------------------------------------------------ 色彩

def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    """sRGB(0~1) → 线性。着色器拿到的是这个值。"""
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def luminance(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGB"), dtype=np.float64) / 255.0
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


# ------------------------------------------------------------------ 块数

def count_cycles(profile: np.ndarray, lo: int = 2, hi: int | None = None) -> tuple[int, float]:
    """对一维灰度剖面做 FFT，返回 (主频周期数, 该峰占比)。

    先去掉低频趋势（大尺度明暗），再加 Hann 窗抑制泄漏，最后取幅度谱峰值。
    周期的「周期数」= 峰值所在的频率 bin，含义是「整张图里重复了多少次」。
    """
    n = profile.shape[0]
    if hi is None:
        hi = n // 2
    # 去趋势：减去大窗口滑动平均
    win = max(3, n // 8)
    kernel = np.ones(win) / win
    trend = np.convolve(profile, kernel, mode="same")
    d = profile - trend
    d = d - d.mean()
    d *= np.hanning(n)
    spec = np.abs(np.fft.rfft(d))
    if hi <= lo:
        return 0, 0.0
    band = spec[lo:hi]
    if band.size == 0:
        return 0, 0.0
    k = int(np.argmax(band)) + lo
    total = spec[lo:].sum()
    share = float(spec[k] / total) if total > 0 else 0.0
    return k, share


def block_counts(img: Image.Image) -> tuple[int, int, float, float]:
    """返回 (横向周期数, 纵向周期数, 横向置信度, 纵向置信度)。"""
    g = luminance(img)
    g = g - g.mean()
    col = g.mean(axis=0)   # 沿列平均 → 反映横向重复
    row = g.mean(axis=1)   # 沿行平均 → 反映纵向重复
    cx, sx = count_cycles(col)
    cy, sy = count_cycles(row)
    return cx, cy, sx, sy


# ------------------------------------------------------------------ 主流程

def analyze(name: str) -> dict:
    d = TEX_DIR / name
    color_p = d / f"{name}_1K-JPG_Color.jpg"
    disp_p = d / f"{name}_1K-JPG_Displacement.jpg"
    if not color_p.exists():
        raise FileNotFoundError(color_p)
    cimg = Image.open(color_p)
    lin = srgb_to_linear(luminance(cimg))
    srgb = luminance(cimg)

    # 用位移图数块：缝隙是明确的高低差，比彩色图干净得多
    cnt_src = disp_p if disp_p.exists() else color_p
    bimg = Image.open(cnt_src)
    cx, cy, sx, sy = block_counts(bimg)

    return {
        "name": name,
        "size": cimg.size,
        "srgb_mean": float(srgb.mean()),
        "lin_mean": float(lin.mean()),
        "lin_p50": float(np.percentile(lin, 50)),
        "lin_p75": float(np.percentile(lin, 75)),
        "lin_p95": float(np.percentile(lin, 95)),
        "cx": cx, "cy": cy, "sx": sx, "sy": sy,
        "count_src": cnt_src.name.split("_1K-JPG_")[-1],
    }


def preview(names: list[str], out: Path, cell: int = 420) -> None:
    imgs = []
    for n in names:
        p = TEX_DIR / n / f"{n}_1K-JPG_Color.jpg"
        if not p.exists():
            continue
        im = Image.open(p).convert("RGB")
        im.thumbnail((cell, cell), Image.LANCZOS)
        imgs.append((n, im))
    if not imgs:
        return
    cols = min(3, len(imgs))
    rows = math.ceil(len(imgs) / cols)
    lab = 22
    canvas = Image.new("RGB", (cols * cell, rows * (cell + lab)), (18, 20, 24))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(canvas)
    for i, (n, im) in enumerate(imgs):
        r, c = divmod(i, cols)
        x, y = c * cell, r * (cell + lab)
        canvas.paste(im, (x, y + lab))
        dr.text((x + 6, y + 4), n, fill=(235, 235, 235))
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f"\n预览已导出：{out}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--target-block", type=float, default=None,
                    help="目标单块尺寸(m)，给出后直接打印 world_scale")
    args = ap.parse_args()

    names = args.only or sorted(p.name for p in TEX_DIR.iterdir() if p.is_dir())
    rows = []
    for n in names:
        try:
            rows.append(analyze(n))
        except FileNotFoundError:
            continue

    print(f"{'贴图':<18}{'尺寸':>11}{'sRGB均值':>10}{'线性均值':>10}"
          f"{'线性p75':>10}{'横向块':>7}{'纵向块':>7}{'置信':>13}")
    print("-" * 98)
    for r in rows:
        w, h = r["size"]
        print(f"{r['name']:<18}{f'{w}x{h}':>11}{r['srgb_mean']:>10.3f}{r['lin_mean']:>10.3f}"
              f"{r['lin_p75']:>10.3f}{r['cx']:>7}{r['cy']:>7}"
              f"{f'{r[chr(115)+chr(120)]:.2f}/{r[chr(115)+chr(121)]:.2f}':>13}")

    if args.target_block:
        print(f"\n目标单块尺寸 = {args.target_block:.3f} m → world_scale = 1/(块数×尺寸)")
        print(f"{'贴图':<18}{'横向周期(m)':>14}{'纵向周期(m)':>14}{'world_scale(x)':>16}{'world_scale(y)':>16}")
        print("-" * 80)
        for r in rows:
            if r["cx"] == 0 or r["cy"] == 0:
                continue
            px = r["cx"] * args.target_block
            py = r["cy"] * args.target_block
            print(f"{r['name']:<18}{px:>14.3f}{py:>14.3f}{1.0/px:>16.4f}{1.0/py:>16.4f}")
        print("\n注：三平面映射只有一组 uv1_scale，x/y 不一致时取折中值，"
              "或换用纵横块数接近的贴图。")

    if args.preview:
        preview([r["name"] for r in rows], ROOT / "_tmp" / "tex_preview.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
