#!/usr/bin/env python3
"""Render the Safari Bridge's extension icons.

- extension-<n>.png: AUV's own icon (Assets/AppIcon.png), with the glass
  squircle cut out on a transparent background. The source is opaque to its
  edges, so used as it is Safari would show a lavender square.
- toolbar-<n>.png: a gauge glyph drawn for the toolbar, not the app icon made
  small: ring, ticks, needle and hub in AUV's blue on a transparent background.
  Its geometry is drawn on a 32-unit grid and snapped per size, so it stays
  crisp at 16 and 19 points, and with @2x at 32 and 38 pixels.

Usage: render_safari_bridge_icons.py <repo-root> [<contact-sheet.png>]
Requires Pillow.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

BLUE = (48, 124, 255, 255)
EXTENSION_SIZES = (48, 96, 128, 256, 512)
TOOLBAR_SIZES = (16, 19, 32, 38, 48)
# Measured on the 1254-pixel Assets/AppIcon.png: the glass squircle's edge,
# taken a few pixels inside its soft outer glow, and its corner radius.
SQUIRCLE_BOX = (50, 50, 1204, 1204)
SQUIRCLE_RADIUS = 268
SUPERSAMPLE = 8


def extension_icon(source, size):
    big = source.convert("RGBA")
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(SQUIRCLE_BOX, SQUIRCLE_RADIUS, fill=255)
    big.putalpha(mask)
    squircle = big.crop(SQUIRCLE_BOX)
    # A small margin keeps the rim off the edge of the tile Safari draws it in.
    side = round(squircle.width / 0.94)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    offset = (side - squircle.width) // 2
    canvas.paste(squircle, (offset, offset), squircle)
    return canvas.resize((size, size), Image.LANCZOS)


def toolbar_glyph(size):
    s = SUPERSAMPLE
    px = size * s
    unit = size / 32.0
    image = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def at(value):
        return value * unit * s

    center = px / 2
    # The ring's stroke is at least 1.5 device pixels, so it never turns to fog.
    stroke = max(3.0 * unit, 1.5) * s
    outer = at(14.5)
    draw.ellipse(
        (center - outer, center - outer, center + outer, center + outer),
        outline=BLUE, width=round(stroke),
    )
    # Small sizes keep three ticks; larger ones get the app icon's five.
    small = size < 32
    # No tick at half past one, where the needle points.
    angles = (180, 270, 0) if small else (180, 225, 270, 0)
    tick_radius = at(8.2) if small else at(8.8)
    dot = 0.78 * s if small else at(1.35)
    for degrees in angles:
        radians = math.radians(degrees)
        x = center + tick_radius * math.cos(radians)
        y = center + tick_radius * math.sin(radians)
        draw.ellipse((x - dot, y - dot, x + dot, y + dot), fill=BLUE)
    # The needle points to half past one, between two ticks, as in AUV's icon.
    needle = math.radians(-42)
    tip = at(10.8) if small else at(10.2)
    base = 1.05 * s if small else at(1.25)
    tx, ty = center + tip * math.cos(needle), center + tip * math.sin(needle)
    nx, ny = -math.sin(needle), math.cos(needle)
    draw.polygon(
        [(center + nx * base, center + ny * base), (tx, ty), (center - nx * base, center - ny * base)],
        fill=BLUE,
    )
    hub = max(at(2.5), 1.5 * s)
    draw.ellipse((center - hub, center - hub, center + hub, center + hub), fill=BLUE)
    return image.resize((size, size), Image.BOX)


def contact_sheet(toolbar, extension, path):
    backgrounds = (("light", (246, 246, 246, 255)), ("dark", (40, 40, 42, 255)))
    zoom = 8
    rows = []
    for _, color in backgrounds:
        tiles = []
        for size in TOOLBAR_SIZES:
            icon = toolbar[size]
            actual = Image.new("RGBA", (64, 64), color)
            actual.alpha_composite(icon, ((64 - size) // 2, (64 - size) // 2))
            enlarged = Image.new("RGBA", (size * zoom, size * zoom), color)
            enlarged.alpha_composite(icon.resize((size * zoom, size * zoom), Image.NEAREST))
            tiles.append((actual, enlarged))
        for size in (48, 128):
            icon = extension[size]
            actual = Image.new("RGBA", (size + 16, size + 16), color)
            actual.alpha_composite(icon, (8, 8))
            tiles.append((actual, None))
        rows.append((color, tiles))
    width = 24 + sum(max(a.width, e.width if e else 0) + 24 for a, e in rows[0][1])
    height = 24 + sum(max(a.height + (e.height + 12 if e else 0) for a, e in tiles) + 24 for _, tiles in rows)
    sheet = Image.new("RGBA", (width, height), (128, 128, 128, 255))
    y = 24
    for color, tiles in rows:
        row_height = max(a.height + (e.height + 12 if e else 0) for a, e in tiles)
        band = Image.new("RGBA", (width, row_height + 24), color)
        sheet.alpha_composite(band, (0, y - 12))
        x = 24
        for actual, enlarged in tiles:
            sheet.alpha_composite(actual, (x, y))
            if enlarged:
                sheet.alpha_composite(enlarged, (x, y + actual.height + 12))
            x += max(actual.width, enlarged.width if enlarged else 0) + 24
        y += row_height + 24
    sheet.convert("RGB").save(path)


def main():
    root = Path(sys.argv[1])
    out = root / "BrowserExtension/Safari/icons"
    out.mkdir(parents=True, exist_ok=True)
    source = Image.open(root / "Assets/AppIcon.png")
    extension = {size: extension_icon(source, size) for size in EXTENSION_SIZES}
    toolbar = {size: toolbar_glyph(size) for size in TOOLBAR_SIZES}
    for size, image in extension.items():
        image.save(out / f"extension-{size}.png", optimize=True)
    for size, image in toolbar.items():
        image.save(out / f"toolbar-{size}.png", optimize=True)
    if len(sys.argv) > 2:
        contact_sheet(toolbar, extension, sys.argv[2])


if __name__ == "__main__":
    main()
