#!/usr/bin/env python3
"""把用户提供的图形做成 macOS 应用图标 + 菜单栏图标。

源图：`Resources/Ctrl2cmd2.png`（344x298，白底灰阶线稿）

处理流程：
  1. 裁掉白边，只留内容
  2. 白底转透明（亮度反相生成 alpha，保留抗锯齿边缘）
  3. 放到圆角底板中央 —— 原图是深色线条，透明底在深色壁纸下会看不见
  4. 放进 1024x1024 正方形画布，图形约占 80%，符合 macOS 图标留白惯例
  5. 输出完整尺寸阶梯并打包 .icns
  6. 另外导出菜单栏用的模板图标（单色剪影，由系统自动着色）

底板颜色可用环境变量覆盖：
  PLATE_COLOR=light python3 tools/import_icon.py
"""
import os
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Resources" / "artwork.png"
OUT = ROOT / "Resources"

CANVAS = 1024
CONTENT_RATIO = 0.80          # 图形占画布比例
CORNER_RATIO = 0.225          # 圆角半径 / 画布宽

# 底板配色：顶/底两色形成轻微纵向渐变
PLATE_THEMES = {
    "orange": {"top": (255, 172, 76), "bottom": (240, 130, 32)},
    "light":  {"top": (252, 252, 252), "bottom": (238, 238, 238)},
    "dark":   {"top": (46, 48, 58), "bottom": (30, 32, 40)},
}
DEFAULT_THEME = "orange"


def load_transparent():
    """读取已提取好的图形（透明底、深灰线条），并按需归一化。

    artwork.png 的来源：从用户提供的源图提取出的图形部分，
    已裁掉白边、转成透明底。参见 README 的图标说明。
    """
    im = Image.open(SRC).convert("RGBA")
    W, H = im.size
    px = im.load()

    # 归一化：把线条颜色统一到较深的灰，保证在橙色底上对比足够
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a <= 4:
                px[x, y] = (0, 0, 0, 0)
                continue
            lum = (r * 299 + g * 587 + b * 114) // 1000
            v = min(lum, 60)           # 压深线条
            px[x, y] = (v, v, v, a)
    return im


def make_plate(canvas, theme):
    """生成圆角底板（带轻微纵向渐变）。"""
    cfg = PLATE_THEMES[theme]
    top, bottom = cfg["top"], cfg["bottom"]

    grad = Image.new("RGBA", (canvas, canvas))
    gd = ImageDraw.Draw(grad)
    for y in range(canvas):
        t = y / max(1, canvas - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        gd.line([(0, y), (canvas, y)], fill=(*c, 255))

    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, canvas - 1, canvas - 1],
        radius=int(canvas * CORNER_RATIO),
        fill=255,
    )
    grad.putalpha(mask)
    return grad


def invert(im):
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    opx, ipx = out.load(), im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = ipx[x, y]
            if a > 0:
                opx[x, y] = (255 - r, 255 - g, 255 - b, a)
    return out


def render(theme=DEFAULT_THEME):
    art = load_transparent()
    plate = make_plate(CANVAS, theme)

    art_size = int(CANVAS * CONTENT_RATIO)
    scale = art_size / max(art.size)
    art = art.resize(
        (max(1, int(art.width * scale)), max(1, int(art.height * scale))),
        Image.LANCZOS,
    )
    # 深色底板上要反相，否则深色线条在深底上看不见
    if sum(PLATE_THEMES[theme]["top"]) / 3 < 128:
        art = invert(art)

    plate.alpha_composite(art, ((CANVAS - art.width) // 2,
                                (CANVAS - art.height) // 2))
    return plate


def export(img, name):
    img.save(OUT / f"{name}.png")
    iconset = OUT / f"{name}.iconset"
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    iconset.mkdir(parents=True)
    for size, fname in [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]:
        img.resize((size, size), Image.LANCZOS).save(iconset / fname)
    icns = OUT / f"{name}.icns"
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    print(f"已生成 {name}.png 与 {name}.icns")


def export_menu_bar():
    """导出菜单栏用的模板图标。

    要点：
      · 模板图只看 alpha 通道，系统会按菜单栏明暗自动着色，
        所以内容要填成纯黑、只保留形状。
      · 当前采用的是从图标里提取的 "WinKey" 文字，12pt 高、68pt 宽。
        文字宽高比约 5.7:1，比方形图标宽，但比 14pt（89pt 宽）短 20%。
        生成逻辑见 _build_menubar_text()，此处保留方块轮廓作为兜底。
    """
    art = load_transparent()
    size = 64
    scale = (size * 0.92) / max(art.size)
    art = art.resize(
        (max(1, int(art.width * scale)), max(1, int(art.height * scale))),
        Image.LANCZOS,
    )

    silhouette = Image.new("RGBA", art.size, (0, 0, 0, 0))
    spx, apx = silhouette.load(), art.load()
    for y in range(art.height):
        for x in range(art.width):
            a = apx[x, y][3]
            if a > 0:
                spx[x, y] = (0, 0, 0, a)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(silhouette, ((size - art.width) // 2,
                                        (size - art.height) // 2))

    for px_size, fname in [(16, "MenuBarIcon.png"), (32, "MenuBarIcon@2x.png")]:
        canvas.resize((px_size, px_size), Image.LANCZOS).save(OUT / fname)
    print("已生成菜单栏模板图标 MenuBarIcon.png / MenuBarIcon@2x.png")


if __name__ == "__main__":
    theme = os.environ.get("PLATE_COLOR", DEFAULT_THEME)
    if theme not in PLATE_THEMES:
        raise SystemExit(f"未知配色 '{theme}'，可选: {list(PLATE_THEMES)}")
    print(f"底板配色: {theme}")
    export(render(theme), "WinKey")
    export_menu_bar()
