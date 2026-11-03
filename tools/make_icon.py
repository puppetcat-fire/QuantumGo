"""Generates the game icon.

Run with the bundled Python (Pillow is available there):

    python tools/make_icon.py

Writes  assets/icon.png  (512x512, project/window icon)
        assets/icon.ico  (16..256, Windows export icon)

Design: two go stones caught mid-superposition inside a quantum orbit, on the
game's deep-space background. Everything is drawn from the QGPalette colours.
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter

BG_DEEP = (11, 16, 32)
BG_PANEL = (20, 27, 46)
VIOLET = (139, 124, 246)
ACCENT = (79, 209, 197)
STONE_BLACK = (22, 24, 29)
STONE_BLACK_EDGE = (60, 66, 80)
STONE_WHITE = (244, 246, 250)
STONE_WHITE_EDGE = (194, 200, 212)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
SIZE = 1024


def rounded_background(size: int) -> Image.Image:
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gradient = Image.new("RGB", (1, size))
    pixels = gradient.load()
    for y in range(size):
        t = y / max(1, size - 1)
        pixels[0, y] = tuple(
            int(BG_DEEP[i] + (BG_PANEL[i] - BG_DEEP[i]) * t) for i in range(3)
        )
    gradient = gradient.resize((size, size))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * 0.19), fill=255
    )
    base.paste(gradient, (0, 0), mask)
    return base


def draw_orbit(image: Image.Image, size: int) -> None:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    box = (
        int(size * 0.09),
        int(size * 0.26),
        int(size * 0.91),
        int(size * 0.74),
    )
    for width, alpha in ((int(size * 0.018), 190), (int(size * 0.007), 110)):
        draw.ellipse(box, outline=(*VIOLET, alpha), width=width)
    layer = layer.rotate(-18, resample=Image.BICUBIC, center=(size / 2, size / 2))
    image.alpha_composite(layer)

    # Faint accent spark on the orbit.
    spark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    spark_draw = ImageDraw.Draw(spark)
    cx, cy, r = size * 0.815, size * 0.315, size * 0.028
    spark_draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*ACCENT, 235))
    spark = spark.filter(ImageFilter.GaussianBlur(size * 0.006))
    image.alpha_composite(spark)


def draw_stone(
    image: Image.Image,
    size: int,
    center: tuple[float, float],
    radius: float,
    fill: tuple[int, int, int],
    edge: tuple[int, int, int],
    ghost: bool = False,
) -> None:
    cx, cy = center
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse(
        (cx - radius * 1.02, cy - radius * 0.92, cx + radius * 1.02, cy + radius * 1.16),
        fill=(0, 0, 0, 120),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius * 0.12))
    image.alpha_composite(shadow)

    alpha = 120 if ghost else 255
    draw.ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius),
        fill=(*fill, alpha),
        outline=(*edge, min(255, alpha + 60)),
        width=int(radius * 0.06),
    )
    image.alpha_composite(layer)

    if ghost:
        # Dashed ring marks a phantom stone inside the match UI.
        ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ring_draw = ImageDraw.Draw(ring)
        dash = 16
        for step in range(0, 360, dash * 2):
            ring_draw.arc(
                (cx - radius * 1.12, cy - radius * 1.12, cx + radius * 1.12, cy + radius * 1.12),
                step,
                step + dash,
                fill=(*VIOLET, 235),
                width=int(radius * 0.07),
            )
        image.alpha_composite(ring)
        return

    # Soft specular highlight.
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    hr = radius * 0.38
    hx, hy = cx - radius * 0.30, cy - radius * 0.34
    tint = (255, 255, 255, 34) if fill == STONE_BLACK else (255, 255, 255, 92)
    highlight_draw.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=tint)
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius * 0.18))
    image.alpha_composite(highlight)


def draw_split_mark(image: Image.Image, size: int) -> None:
    """The violet seam where reality splits into two universes."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = size * 0.5, size * 0.53
    points = []
    for i in range(41):
        t = i / 40.0
        y = cy + (t - 0.5) * size * 0.5
        x = cx + math.sin(t * math.pi * 2.4) * size * 0.016
        points.append((x, y))
    draw.line(points, fill=(*VIOLET, 220), width=int(size * 0.012), joint="curve")
    glow = layer.filter(ImageFilter.GaussianBlur(size * 0.012))
    image.alpha_composite(glow)
    image.alpha_composite(layer)


def build(size: int = SIZE) -> Image.Image:
    image = rounded_background(size)
    draw_orbit(image, size)
    # The seam sits behind the stones so it reads as a tear in space, not a scratch
    # across the pieces.
    draw_split_mark(image, size)
    draw_stone(
        image, size, (size * 0.385, size * 0.565), size * 0.203, STONE_BLACK, STONE_BLACK_EDGE
    )
    draw_stone(
        image, size, (size * 0.625, size * 0.495), size * 0.203, STONE_WHITE, STONE_WHITE_EDGE
    )
    # A phantom echo of the black stone: the icon should read "one stone, two worlds".
    draw_stone(
        image,
        size,
        (size * 0.775, size * 0.765),
        size * 0.098,
        STONE_BLACK,
        VIOLET,
        ghost=True,
    )
    return image


def main() -> None:
    os.makedirs(ASSETS, exist_ok=True)
    icon = build(SIZE)
    png_path = os.path.join(ASSETS, "icon.png")
    icon.resize((512, 512), Image.LANCZOS).save(png_path)
    ico_path = os.path.join(ASSETS, "icon.ico")
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    icon.save(ico_path, format="ICO", sizes=sizes)
    print("wrote", png_path)
    print("wrote", ico_path)


if __name__ == "__main__":
    main()
