#!/usr/bin/env python3
"""Build a review sheet for the ground tiles and the animal sprites.

Every tile is drawn REPEATED 4x4, which is the whole point of the exercise: a
texture can look perfectly good on its own and show an obvious grid the moment
it is tiled across a zone. Judging a single 64px square tells you nothing about
that. Seams, repeated highlights and any directional feature all show up in the
repeat and nowhere else.

Sprites are drawn on a checkerboard so the alpha edge is visible, at 256 (the
prepared size) and at 64 (roughly what a phone shows).

Usage:
  python tools/contact_sheet.py                       # assets/tiles + the cat
  python tools/contact_sheet.py --sprites cat,dog     # more sprites
  python tools/contact_sheet.py --out some/path.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
TILE_DIR = os.path.join(ROOT, "assets", "tiles")
SPRITE_DIR = os.path.join(ROOT, "assets", "sprites", "animals")
DEFAULT_OUT = os.path.join(ROOT, "tools", ".review", "contact_sheet.png")
FONT_PATH = os.path.join(ROOT, "assets", "ui", "fonts", "Baloo2.ttf")

# The order zoo_map.gd declares them in, so the sheet reads like the tileset.
TILE_ORDER = ["grass", "grass2", "path", "water", "fence", "sand", "snow", "savanna"]
# Not generated in this pass - shown for context, labelled so it is not mistaken
# for a new asset.
DEFERRED = {"fence"}

REPEAT = 4
CELL = 256
PAD = 18
LABEL_H = 30
COLS = 4
BG = (34, 30, 28)
INK = (245, 238, 226)
MUTED = (150, 140, 130)


def font(size: int):
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except Exception:  # noqa: BLE001 - cosmetic only, never worth failing over
        return ImageFont.load_default()


def checkerboard(size: int, square: int = 16) -> Image.Image:
    img = Image.new("RGB", (size, size), (70, 64, 60))
    d = ImageDraw.Draw(img)
    for y in range(0, size, square):
        for x in range(0, size, square):
            if (x // square + y // square) % 2 == 0:
                d.rectangle([x, y, x + square - 1, y + square - 1], fill=(92, 85, 80))
    return img


def tiled(path: str) -> Image.Image:
    """One tile repeated REPEAT x REPEAT, at its native pixel size."""
    src = Image.open(path).convert("RGB")
    step = CELL // REPEAT
    src = src.resize((step, step), Image.NEAREST)
    out = Image.new("RGB", (CELL, CELL))
    for gy in range(REPEAT):
        for gx in range(REPEAT):
            out.paste(src, (gx * step, gy * step))
    return out


def missing_cell(text: str) -> Image.Image:
    img = Image.new("RGB", (CELL, CELL), (58, 46, 46))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, CELL - 1, CELL - 1], outline=(120, 90, 90), width=2)
    d.text((CELL // 2, CELL // 2), text, fill=(200, 150, 150), anchor="mm", font=font(20))
    return img


def main() -> None:
    args = sys.argv[1:]
    out_path = args[args.index("--out") + 1] if "--out" in args else DEFAULT_OUT
    sprites = (args[args.index("--sprites") + 1].split(",")
               if "--sprites" in args else ["cat"])

    cells = []
    for name in TILE_ORDER:
        path = os.path.join(TILE_DIR, name + ".png")
        if os.path.isfile(path):
            src_px = Image.open(path).size[0]
            label = f"{name}  {src_px}px"
            if name in DEFERRED:
                label += "  (deferred)"
            cells.append((label, tiled(path), name in DEFERRED))
        else:
            cells.append((f"{name}  MISSING", missing_cell("not generated"), True))

    for sid in sprites:
        path = os.path.join(SPRITE_DIR, sid + ".png")
        if not os.path.isfile(path):
            cells.append((f"{sid}  MISSING", missing_cell("not generated"), True))
            continue
        sprite = Image.open(path).convert("RGBA")
        # 256 and 64 side by side on one checkerboard cell.
        cell = checkerboard(CELL)
        big = sprite.resize((CELL - 96, CELL - 96), Image.LANCZOS)
        cell.paste(big, (8, CELL - 96 - 8), big)
        small = sprite.resize((64, 64), Image.LANCZOS)
        cell.paste(small, (CELL - 72, CELL - 72), small)
        cells.append((f"{sid}  256px + 64px", cell, False))

    rows = (len(cells) + COLS - 1) // COLS
    width = COLS * CELL + (COLS + 1) * PAD
    height = rows * (CELL + LABEL_H) + (rows + 1) * PAD + 52
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((PAD, 16), "VoiceZoo - tiles shown 4x4 to expose seams and repeats",
              fill=INK, font=font(26))

    for i, (label, img, dim) in enumerate(cells):
        col, row = i % COLS, i // COLS
        x = PAD + col * (CELL + PAD)
        y = 52 + PAD + row * (CELL + LABEL_H + PAD)
        sheet.paste(img, (x, y))
        draw.rectangle([x, y, x + CELL - 1, y + CELL - 1], outline=(90, 82, 76))
        draw.text((x, y + CELL + 6), label, fill=(MUTED if dim else INK), font=font(20))

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    sheet.save(out_path)
    print(f"wrote {os.path.abspath(out_path)}  ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()
