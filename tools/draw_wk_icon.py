#!/usr/bin/env python3
"""自绘菜单栏用的 "WK" 模板图标。

原应用图标里的文字是 "Ctrl2cmd"（天蓝底 + 白字），并没有 W 和 K，
所以这里按原图测得的字体特征自绘 WK，保持风格一致：

  · 笔画宽度 19px（1024 画布基准）
  · 大写字母高 72px
  · 圆头收笔

输出菜单栏模板图（纯黑 + alpha），系统会按菜单栏明暗自动着色。
"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "Resources"

STROKE = 17          # 笔画宽（略细于 19，小尺寸下更清晰）
CAP = 70             # 大写高
H = 77               # 画布高（与原文字区一致）
PAD = 3
GAP = 16             # W 与 K 的间距


def rounded_line(draw, p1, p2, width):
    """圆头线段：直线 + 两端圆点，模拟原字体的圆头收笔。"""
    draw.line([p1, p2], fill=(0, 0, 0, 255), width=width)
    r = width / 2
    for (x, y) in (p1, p2):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(0, 0, 0, 255))


def draw_W():
    w_width = 112
    img = Image.new("RGBA", (w_width + PAD * 2, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top, bot = PAD, PAD + CAP
    x0, x1 = PAD + STROKE / 2, w_width + PAD - STROKE / 2
    span = x1 - x0
    v1 = x0 + span * 0.28
    peak = x0 + span * 0.50
    peak_y = top + CAP * 0.62        # 中峰明显低于顶边，避免小尺寸糊成一团
    v2 = x0 + span * 0.72
    rounded_line(d, (x0, top), (v1, bot), STROKE)
    rounded_line(d, (v1, bot), (peak, peak_y), STROKE)
    rounded_line(d, (peak, peak_y), (v2, bot), STROKE)
    rounded_line(d, (v2, bot), (x1, top), STROKE)
    return img


def draw_K():
    k_width = 74
    img = Image.new("RGBA", (k_width + PAD * 2, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top, bot = PAD, PAD + CAP
    stem_x = PAD + STROKE / 2
    rounded_line(d, (stem_x, top), (stem_x, bot), STROKE)
    arm_x = k_width + PAD - STROKE / 2
    mid_y = top + CAP * 0.50
    rounded_line(d, (stem_x, mid_y), (arm_x, top), STROKE)
    rounded_line(d, (stem_x, mid_y), (arm_x, bot), STROKE)
    return img


def main():
    w_img, k_img = draw_W(), draw_K()
    total = w_img.width + GAP + k_img.width
    wk = Image.new("RGBA", (total, H), (0, 0, 0, 0))
    wk.paste(w_img, (0, 0))
    wk.paste(k_img, (w_img.width + GAP, 0))
    wk.save(OUT / "menubar-wk.png")
    print(f"WK 源图: {wk.size}")

    # 菜单栏 15pt 高
    for height_1x, name in [(15, "MenuBarIcon.png"), (30, "MenuBarIcon@2x.png")]:
        w = int(height_1x * wk.width / wk.height)
        wk.resize((w, height_1x), Image.LANCZOS).save(OUT / name)
        print(f"{name}: {w}x{height_1x} ({w if height_1x == 15 else w // 2}pt 宽)")


if __name__ == "__main__":
    main()
