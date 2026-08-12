#!/usr/bin/env python3
"""Report every non-ASCII character the UI draws that no shipped font can draw.

    pip install fonttools
    python tools/glyph_audit.py

This exists because the same bug has now happened three times, and each time it
was only caught by looking at a screenshot: a decorative character is picked for
a button or a marker, the editor draws it from a system font, and the deployed
web build - which has no system fonts to borrow - renders a tofu box. It cost a
mute button ("‖" and "▶"), and the Studio's focus marker ("▸").

Baloo 2 covers Latin and the umlauts. NotoEmoji-subset covers exactly the
codepoints tools/build_emoji_font.py found, and its ranges deliberately exclude
Geometric Shapes and Misc Technical - so arrows, bars and boxes from those
blocks are precisely the trap.

Only string LITERALS in shipped code are scanned. Comments are stripped first -
a comment explaining which character broke is not itself a bug - and tests/ is
skipped, since a test asserting a character's ABSENCE still contains it.
Anything built from a runtime-computed string is invisible here, which is why
the output lists what it checked rather than just printing a verdict.
"""
import os
import re
import sys
import unicodedata

ROOT = os.path.join(os.path.dirname(__file__), "..")
FONTS = [
    os.path.join(ROOT, "assets", "ui", "fonts", "Baloo2.ttf"),
    os.path.join(ROOT, "assets", "ui", "fonts", "NotoEmoji-subset.ttf"),
]
SKIP_DIRS = {".godot", "export", ".git", "tools", "assets", "tests"}


def strip_comments(line: str) -> str:
    """Drop a trailing `#` comment, ignoring any `#` inside a string.

    Naive truncation at the first `#` would also cut `Color("#E9718F")` in half,
    so the quote state is tracked rather than guessed at.
    """
    out = []
    quote = ""
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = ""
            continue
        if ch in ('"', "'"):
            quote = ch
            out.append(ch)
            continue
        if ch == "#":
            break
        out.append(ch)
    return "".join(out)


def main() -> int:
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        print("fonttools is required:  pip install fonttools", file=sys.stderr)
        return 1

    covered = set()
    for path in FONTS:
        if not os.path.isfile(path):
            print(f"note: {os.path.relpath(path, ROOT)} not found, skipping")
            continue
        font = TTFont(path, fontNumber=0)
        for table in font["cmap"].tables:
            covered |= set(table.cmap.keys())

    found: dict[str, set] = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as f:
                lines = f.read().splitlines()
            for line in lines:
                for literal in re.findall(r'"([^"\n]*)"', strip_comments(line)):
                    for ch in literal:
                        if ord(ch) > 127:
                            found.setdefault(ch, set()).add(os.path.relpath(path, ROOT))

    missing = []
    print(f"{'char':6} {'codepoint':11} {'drawable':9} name")
    for ch in sorted(found, key=ord):
        cp = ord(ch)
        ok = cp in covered
        try:
            name = unicodedata.name(ch)
        except ValueError:
            name = "?"
        print(f"{ch:6} U+{cp:04X}      {'yes' if ok else 'NO  <<<':9} {name}")
        if not ok:
            missing.append(ch)
            for where in sorted(found[ch]):
                print(f"{'':29} used in: {where}")

    print()
    if missing:
        print(f"{len(missing)} character(s) would render as a tofu box on the web build.")
        print("Fix by using words, or add the block to EMOJI_RANGES in")
        print("tools/build_emoji_font.py and rebuild the subset.")
        return 1
    print("every character the UI draws has a glyph in a shipped font")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
