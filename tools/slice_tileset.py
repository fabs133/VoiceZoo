#!/usr/bin/env python3
"""Cut named full-bleed ground tiles out of a pixel-art tileset atlas.

An atlas of this kind is an AUTOTILE set: most cells are edge and corner pieces
for terrain transitions, and only a handful are the plain interior fill that a
flat-painted TileMap needs. This lifts those interior cells out by coordinate
and writes them as the individual files zoo_map.gd loads by name.

Scaling is integer and NEAREST on purpose. The art is 32px pixel art and the
game's tile is 64px, so every source pixel becomes exactly a 2x2 block - any
smoothing filter would turn crisp pixel art into mush.

These tiles must NOT go through make_tileable.py. That cross-fades opposite
edges to force a generated texture to wrap, which is exactly wrong here: the
interior cells of an autotile set are already designed to tile, and blending
their edges would smear the pixel grid.

Usage:
  python tools/slice_tileset.py <atlas.png> <out_dir> --cell 32 --scale 2 \
      --map grass=10,1 grass2=12,1 sand=15,2 water=16,5
"""
import os
import sys

from PIL import Image


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 2 or "--map" not in args:
        print(__doc__)
        sys.exit(1)
    atlas_path, out_dir = args[0], args[1]
    cell = int(args[args.index("--cell") + 1]) if "--cell" in args else 32
    scale = int(args[args.index("--scale") + 1]) if "--scale" in args else 2
    keep_alpha = "--keep-alpha" in args
    pairs = args[args.index("--map") + 1:]

    atlas = Image.open(atlas_path).convert("RGBA")
    os.makedirs(out_dir, exist_ok=True)
    for pair in pairs:
        if "=" not in pair:
            continue
        name, coord = pair.split("=", 1)
        cx, cy = (int(v) for v in coord.split(","))
        box = (cx * cell, cy * cell, (cx + 1) * cell, (cy + 1) * cell)
        tile = atlas.crop(box)
        opaque = tile.getchannel("A").getextrema()[0] == 255
        if keep_alpha:
            # Decoration pieces (fences) MUST keep their alpha - they sit on a
            # layer above the ground and the gaps are where the ground shows.
            out = tile
        else:
            if not opaque:
                # A ground fill has to be opaque edge to edge. Anything else is
                # an edge or decoration piece and would leave holes in the map.
                print(f"  WARNING {name} at {cx},{cy} is not fully opaque - not an interior fill")
            out = tile.convert("RGB")
        out = out.resize((cell * scale, cell * scale), Image.NEAREST)
        out_path = os.path.join(out_dir, name + ".png")
        out.save(out_path)
        print(f"  {name}.png  <- cell ({cx},{cy})  {cell}px -> {cell * scale}px")


if __name__ == "__main__":
    main()
