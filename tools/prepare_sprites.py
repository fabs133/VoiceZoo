#!/usr/bin/env python3
"""VoiceZoo sprite post-processing: raw generation -> game-ready sprite.
Steps: thresholded trim (ignores the low-alpha noise floor that gpt-image
transparent exports scatter across the canvas) -> noise cleanup ->
height-normalize -> baseline-align onto a square canvas -> resize.
Usage: python tools/prepare_sprites.py assets/generated/animals assets/sprites/animals [--size 256] [--alpha-floor 24]
"""
import sys, os
from PIL import Image

def process(path, out_path, size=256, alpha_floor=24):
    img = Image.open(path).convert('RGBA')
    px = img.load()
    w, h = img.size
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < alpha_floor:
                if a: px[x, y] = (r, g, b, 0)
                continue
            if x < minx: minx = x
            if x > maxx: maxx = x
            if y < miny: miny = y
            if y > maxy: maxy = y
    if maxx < 0:
        print(f'  SKIP {os.path.basename(path)}: empty after threshold'); return None
    crop = img.crop((minx, miny, maxx + 1, maxy + 1))
    box = size - 16
    scale = min(box / crop.width, box / crop.height)
    nw, nh = max(1, round(crop.width * scale)), max(1, round(crop.height * scale))
    crop = crop.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    baseline = round(size * 0.96)
    canvas.paste(crop, ((size - nw) // 2, baseline - nh), crop)
    canvas.save(out_path)
    print(f'  {os.path.basename(path)}: {w}x{h} -> {size}px (scale {scale:.3f})')
    return out_path

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    in_dir, out_dir = sys.argv[1], sys.argv[2]
    size = int(sys.argv[sys.argv.index('--size')+1]) if '--size' in sys.argv else 256
    floor = int(sys.argv[sys.argv.index('--alpha-floor')+1]) if '--alpha-floor' in sys.argv else 24
    os.makedirs(out_dir, exist_ok=True)
    for f in sorted(os.listdir(in_dir)):
        if f.lower().endswith('.png'):
            process(os.path.join(in_dir, f), os.path.join(out_dir, f), size, floor)

if __name__ == '__main__':
    main()