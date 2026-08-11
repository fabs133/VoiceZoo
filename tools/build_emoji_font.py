"""Builds assets/ui/fonts/NotoEmoji-subset.ttf: Noto Emoji cut down to only the
emoji this project actually draws.

    pip install fonttools
    python tools/build_emoji_font.py

Why this exists: the UI theme pins Baloo 2 on every control, and Baloo 2 has no
emoji glyphs. On desktop Godot can borrow a system emoji font; a web export has
none to borrow, so every emoji rendered as a tofu box on the deployed build.
The fix is a fallback font - but shipping all of Noto Emoji costs ~1.9 MB for
four glyphs, which guests would pay for over mobile data. Subsetting makes it a
rounding error.

The codepoints are DISCOVERED from the .gd sources rather than hardcoded, so
adding an emoji to the UI and rerunning this keeps the font in sync. Anything
built from a runtime-computed string would be missed - the script prints what it
found so that is visible rather than silent.

Noto Emoji is OFL-1.1 with no Reserved Font Name, so subsetting is permitted;
assets/ui/fonts/NotoEmoji-OFL.txt ships alongside it to satisfy the licence.
"""

import io
import pathlib
import re
import sys
import urllib.request

FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf"
LICENSE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoemoji/OFL.txt"

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "ui" / "fonts"
OUT_FONT = OUT_DIR / "NotoEmoji-subset.ttf"
OUT_LICENSE = OUT_DIR / "NotoEmoji-OFL.txt"

# Ranges worth treating as "needs the emoji font". Deliberately narrow: Latin
# text and the German umlauts are Baloo 2's job and must not be pulled in here.
EMOJI_RANGES = [
    (0x1F300, 0x1FAFF),  # pictographs, symbols, supplemental
    (0x2600, 0x27BF),    # misc symbols and dingbats
    (0x2B00, 0x2BFF),    # arrows and geometric shapes
    (0xFE0E, 0xFE0F),    # variation selectors (text vs emoji presentation)
]


def wanted(cp: int) -> bool:
    return any(lo <= cp <= hi for lo, hi in EMOJI_RANGES)


def discover() -> dict[int, list[str]]:
    """Codepoint -> the source lines that use it."""
    found: dict[int, list[str]] = {}
    for path in sorted(ROOT.rglob("*.gd")):
        if ".godot" in path.parts or "export" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for ch in line:
                if wanted(ord(ch)):
                    found.setdefault(ord(ch), []).append(
                        f"{path.relative_to(ROOT)}:{lineno}"
                    )
    return found


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


def main() -> int:
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError:
        print("fonttools is required:  pip install fonttools", file=sys.stderr)
        return 1

    found = discover()
    if not found:
        print("no emoji found in the .gd sources - nothing to build")
        return 0

    print(f"{len(found)} emoji in use:")
    for cp in sorted(found):
        where = ", ".join(sorted(set(found[cp]))[:3])
        print(f"  U+{cp:04X}  {chr(cp)}  {where}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"\ndownloading {FONT_URL.rsplit('/', 1)[-1]} ...")
    raw = fetch(FONT_URL)
    print(f"  source font: {len(raw):,} bytes")

    # Pin the variable axis first: a static font has no fvar/gvar machinery to
    # carry around, and Godot has no use for a weight axis on four glyphs.
    font = instancer.instantiateVariableFont(TTFont(io.BytesIO(raw)), {"wght": 400})

    options = subset.Options()
    options.layout_features = []
    options.hinting = False
    options.desubroutinize = True
    options.drop_tables += ["DSIG"]
    options.notdef_outline = False
    options.recalc_bounds = True
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=sorted(found))
    subsetter.subset(font)
    font.save(OUT_FONT)

    OUT_LICENSE.write_bytes(fetch(LICENSE_URL))

    size = OUT_FONT.stat().st_size
    print(f"\nwrote {OUT_FONT.relative_to(ROOT)}  {size:,} bytes "
          f"({size / len(raw):.2%} of the original)")
    print(f"wrote {OUT_LICENSE.relative_to(ROOT)}")
    print("\nNow run:  godot --headless --import")
    print("     and:  godot --headless --script tools/build_theme.gd")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
