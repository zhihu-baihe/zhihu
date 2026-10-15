#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""派生贴图烘焙：从 CC0 源烘焙「项目专用变体」。

为什么要烘焙，而不是直接换贴图
------------------------------
`mat_cache.gd` 里 ALBEDO = tint.rgb × Color贴图(sRGB→线性)，两个硬约束：

  1. tint 是**乘性**的，只能压暗、不能把贴图提亮。
     贴图自身的线性反射率就是它的天花板。
  2. Godot 的 StandardMaterial3D **没有色相映射**，乘法无法把橙红变成青灰。

于是当「形对但色不对」或「色对但太暗」时，唯一干净的解法是在
`assets/processed/` 里烘一份变体 —— 反正这一层本来就叫 processed。

三件事合一个工具
----------------
  * recolor：保留源图的明暗结构，换成目标色相（例：红陶瓦 → 青瓦）
  * lift   ：保留源图的色相，整体抬到目标反射率（例：过暗的木板）
  * neutral：抹掉色相只留明暗，得到「可被任意 tint 染色的中性织纹」

用法
----
  python tools/bake_textures.py --list
  python tools/bake_textures.py --all
  python tools/bake_textures.py --only RoofTilesQing
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = ROOT / "assets" / "processed" / "textures"
MANIFEST = TEX_DIR / "_derived.json"

# 输出通道 → 是否从源同名通道直接复制（都是色相无关的物理量，可原样复用）
COPY_CHANNELS = ["NormalGL", "Roughness", "AmbientOcclusion"]

JPEG_Q = 95


# ---------------------------------------------------------------- 色彩空间

def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def hex_to_linear(hexstr: str) -> np.ndarray:
    s = hexstr.lstrip("#")
    rgb = np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255.0
    return srgb_to_linear(rgb)


def lum(rgb: np.ndarray) -> np.ndarray:
    """线性域相对亮度（Rec.709）。传入最后一维为 3。"""
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


# ---------------------------------------------------------------- 烘焙配方
#
# mode:
#   "recolor" —— 结构取自源图，色相由 target 指定
#   "lift"    —— 色相取自源图，整体亮度抬到 level
#   "neutral" —— 只保留明暗（灰度），亮度抬到 level
#
# level：输出 Color 图的**线性域平均反射率**。
#        参考：现实青瓦 0.10~0.15、旧木 0.08~0.12、白灰墙 0.55~0.75。

BAKES: dict[str, dict] = {
    # 现成 CC0 里没有任何一套青灰瓦：ambientCG 的 RoofingTiles 系列全是欧洲红陶
    # （色相 16°~20°），Poly Haven 只有 thatch。唯一色相正确的 RoofingTiles013A
    # 既平（无瓦楞）又极暗（线性 0.031）。故取 014A 的瓦楞（NormalGL 主频 19 条
    # 纵向脊、占比 0.206，是全部贴图里最强的周期信号）重染为青瓦。
    "RoofTilesQing": dict(
        src="RoofingTiles014A", mode="recolor",
        target="#6b7681", level=0.130, contrast=1.00,
    ),
    # Planks037A 线性均值仅 0.053（≈5% 反射率），再乘中间亮度 tint 就是纯黑。
    # 保留它本身偏暖的旧木色相抬到可用亮度。
    "PlanksWood": dict(
        src="Planks037A", mode="lift",
        target=None, level=0.100, contrast=0.95,
    ),
    # 织物要同时供红/金/绿三种摊棚用，而 Fabric085 本身是橙红（色相 15°）。
    # 用橙红去乘绿色只会得到脏橄榄绿，所以先中和成灰色织纹，再交给 tint 染色。
    "FabricWeave": dict(
        src="Fabric085", mode="neutral",
        target="#b8b8b8", level=0.300, contrast=1.00,
    ),
}


# ---------------------------------------------------------------- 核心

def bake_color(name: str, spec: dict) -> tuple[np.ndarray, dict]:
    src = TEX_DIR / spec["src"] / f'{spec["src"]}_1K-JPG_Color.jpg'
    img = Image.open(src).convert("RGB")
    srgb = np.asarray(img, dtype=np.float64) / 255.0
    lin = srgb_to_linear(srgb)

    mode = spec["mode"]
    level = float(spec["level"])
    contrast = float(spec.get("contrast", 1.0))

    if mode == "lift":
        # 纯增益：均值落到 level，色相比例不变
        cur = float(lin.mean())
        out = lin * (level / max(cur, 1e-6))
        chroma_dir = None
    else:
        l = lum(lin)
        l = l / max(float(l.mean()), 1e-6)          # 结构归一到均值 1
        if contrast != 1.0:
            l = np.clip(l, 1e-4, None) ** contrast
            l = l / max(float(l.mean()), 1e-6)      # 再归一，保证 level 精确
        if mode == "neutral":
            chroma_dir = np.ones(3)
        else:
            t = hex_to_linear(spec["target"])
            chroma_dir = t / max(float(lum(t)), 1e-6)   # 只取色度方向
        out = chroma_dir * (l[..., None] * level)

    out = linear_to_srgb(out)
    stats = {
        "mode": mode,
        "level_target": level,
        "lin_mean_before": round(float(lin.mean()), 4),
        "lin_mean_after": round(float(srgb_to_linear(out).mean()), 4),
        "srgb_mean_after": round(float((0.2126 * out[..., 0] + 0.7152 * out[..., 1]
                                        + 0.0722 * out[..., 2]).mean()), 4),
    }
    return (out * 255.0 + 0.5).astype(np.uint8), stats


def bake_one(name: str, spec: dict) -> dict:
    outdir = TEX_DIR / name
    outdir.mkdir(parents=True, exist_ok=True)
    arr, stats = bake_color(name, spec)
    Image.fromarray(arr).save(outdir / f"{name}_1K-JPG_Color.jpg",
                              quality=JPEG_Q, subsampling=0)

    copied = []
    for ch in COPY_CHANNELS:
        p = TEX_DIR / spec["src"] / f'{spec["src"]}_1K-JPG_{ch}.jpg'
        if not p.exists():
            continue
        # 【必须逐字节拷贝】不能重新保存：法线/粗糙/AO 已是 JPEG，
        # 再压一遍就是二次压缩，法线图的高频会被磨掉（几何细节直接变糊）。
        shutil.copyfile(p, outdir / f"{name}_1K-JPG_{ch}.jpg")
        copied.append(ch)

    # 让 Godot 复用源贴图的导入参数（compress/mode 等），否则法线会被 VRAM 压缩磨花。
    # 但**不能整份照抄**，有两个坑（都踩过）：
    #   1. uid 必须删掉 —— 沿用它就是两个资源共用一个 UID，Godot 会改写其中一个。
    #   2. source_file 里带源目录名，必须一并替换，否则指向不存在的文件。
    # path / dest_files 里的 hash 不重要：Godot 重新导入时会自己重算。
    for ch in ["Color"] + copied:
        src_imp = TEX_DIR / spec["src"] / f'{spec["src"]}_1K-JPG_{ch}.jpg.import'
        if not src_imp.exists():
            continue
        txt = src_imp.read_text(encoding="utf-8", errors="replace")
        txt = re.sub(r'^uid="[^"]*"\n', "", txt, flags=re.M)
        txt = txt.replace(f'assets/processed/textures/{spec["src"]}',
                          f'assets/processed/textures/{name}')
        txt = txt.replace(spec["src"], name)
        (outdir / f"{name}_1K-JPG_{ch}.jpg.import").write_text(
            txt, encoding="utf-8")

    print(f"  {name:<16} ← {spec['src']:<18} {spec['mode']:<8} "
          f"线性 {stats['lin_mean_before']:.3f} → {stats['lin_mean_after']:.3f}  "
          f"复制 {len(copied)} 通道")
    return {"derived_from": spec["src"], "spec": spec,
            "copied_channels": copied, **stats}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--only", nargs="*", default=None)
    args = ap.parse_args()

    if args.list or (not args.all and not args.only):
        print("配方：")
        for k, v in BAKES.items():
            print(f"  {k:<16} ← {v['src']:<18} {v['mode']:<8} "
                  f"target={v.get('target')} level={v['level']}")
        print("\n用 --all 全部烘焙，或 --only <名字> 逐个。")
        return 0

    names = list(BAKES) if args.all else [n for n in (args.only or []) if n in BAKES]
    unknown = [n for n in (args.only or []) if n not in BAKES]
    if unknown:
        print(f"未知配方：{unknown}", file=sys.stderr)
        return 2

    print("烘焙派生贴图：")
    manifest = {}
    if MANIFEST.exists():
        try:
            manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            manifest = {}
    for n in names:
        manifest[n] = bake_one(n, BAKES[n])
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                        encoding="utf-8")
    print(f"\n清单已更新：{MANIFEST}")
    print("提示：新增带 .import 的贴图后需重跑一次 --headless --import。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
