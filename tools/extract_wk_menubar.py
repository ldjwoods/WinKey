#!/usr/bin/env python3
"""从 WK.icns 提取白色 WK 字形，生成菜单栏模板图标。

WK.icns 是设计者提供的 1024 画布天蓝 squircle + 白色 WK 字样。
菜单栏需要的是「单色 + 透明」的模板图（系统按明暗自动着色），
所以这里只取字形、丢掉蓝色底。

用法: python3 tools/extract_wk_menubar.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Resources" / "WK.icns"
OUT = ROOT / "Resources"

# WK.icns 里白色字形的包围盒（实测）
GLYPH_BOX = (268, 414, 754, 611)      # left, top, right, bottom

LUM_THRESHOLD = 170                    # 高于此亮度视为字形
HEIGHT_1X = 12                         # 菜单栏图标高度（pt）


def extract():
    im = Image.open(SRC).convert("RGBA")
    l, t, r, b = GLYPH_BOX
    tw, th = r - l, b - t

    sil = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    sp, ip = sil.load(), im.load()
    for y in range(th):
        for x in range(tw):
            pr, pg, pb, pa = ip[l + x, t + y]
            lum = (pr * 299 + pg * 587 + pb * 114) // 1000
            if pa > 150 and lum > LUM_THRESHOLD:
                # 按亮度换算 alpha，保留抗锯齿边缘
                alpha = min(255, int((lum - LUM_THRESHOLD) * 255 / (255 - LUM_THRESHOLD)) + 70)
                sp[x, y] = (0, 0, 0, alpha)
    return sil


def main():
    sil = extract()
    print(f"提取字形: {sil.size}  宽高比 {sil.width / sil.height:.2f}:1")
    sil.save(OUT / "menubar-wk-source.png")

    for height, name in [(HEIGHT_1X, "MenuBarIcon.png"),
                         (HEIGHT_1X * 2, "MenuBarIcon@2x.png")]:
        w = int(height * sil.width / sil.height)
        sil.resize((w, height), Image.LANCZOS).save(OUT / name)
        pt = height if height == HEIGHT_1X else height // 2
        print(f"{name}: {w}x{height} ({pt}pt 逻辑尺寸, {w if height == HEIGHT_1X else w // 2}pt 宽)")


if __name__ == "__main__":
    main()
