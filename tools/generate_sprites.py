#!/usr/bin/env python3
"""VoiceZoo asset generation: manifest -> assembled prompts -> gpt-image API.

SECURITY CONTRACT (do not weaken):
- The API key is NEVER read into this program's logic. The OpenAI client
  picks up OPENAI_API_KEY from the environment itself; we only check that
  the variable EXISTS.
- Every error message printed to the console is passed through scrub(),
  which redacts the literal key value and anything shaped like an API key.
- No tracebacks are printed. No log files are written.

Two job types, selected by --tiles:

  SPRITES (default)  gpt-image-1.5, transparent background, one subject per
                     image, written as <id>_v<n>.png so several candidates can
                     be generated and curated by hand before one is promoted.

  TILES (--tiles)    gpt-image-2, which has no transparency support and is
                     better at flat textures, so the manifest omits the
                     background parameter entirely rather than sending a value
                     the model would reject. Written as <id>.png with no
                     candidate suffix, because zoo_map.gd loads tiles by exact
                     filename and there is no curation step to rename them.

Both attach one approved image as a style reference through images.edit, which
is what keeps the palette consistent across separately generated assets.

Usage:
  python tools/generate_sprites.py --dry-run           # assemble + print prompts, no API calls
  python tools/generate_sprites.py                     # sprites (asks for confirmation)
  python tools/generate_sprites.py --tiles             # ground tiles
  python tools/generate_sprites.py --only monkey       # subset, e.g. one cheap smoke subject
  python tools/generate_sprites.py --tiles --only water,path
  python tools/generate_sprites.py --yes               # skip confirmation
  python tools/generate_sprites.py --no-reference      # allow running without the style reference
"""
import base64
import glob
import json
import os
import re
import sys
import time

MANIFEST = os.path.join(os.path.dirname(__file__), "..", "data", "asset_generation.json")
MAX_ATTEMPTS = 3


def scrub(text: str) -> str:
    key = os.environ.get("OPENAI_API_KEY", "")
    if key:
        text = text.replace(key, "[REDACTED]")
    return re.sub(r"sk-[A-Za-z0-9_\-]{8,}", "[REDACTED]", text)


def fail(msg: str) -> None:
    print(scrub(msg))
    sys.exit(1)


def load_group(manifest: dict, tiles: bool) -> dict:
    """The manifest section for the requested job type.

    `versioned` is what separates them: sprites accumulate numbered candidates
    for a human to choose between, tiles are written straight to the filename
    the engine loads.
    """
    if tiles:
        section = manifest.get("tiles")
        if not section:
            fail("The manifest has no 'tiles' section. Nothing to generate with --tiles.")
        return {
            "label": "tile",
            "defaults": section["defaults"],
            "template": section["style_template"],
            "subjects": section["subjects"],
            "versioned": False,
        }
    return {
        "label": "sprite",
        "defaults": manifest["defaults"],
        "template": manifest["style_template"],
        "subjects": manifest["subjects"],
        "versioned": True,
    }


def plan_outputs(group: dict, out_dir: str, subject_id: str) -> tuple:
    """(files already on disk, filenames still to generate) for one subject."""
    if group["versioned"]:
        existing = sorted(glob.glob(os.path.join(out_dir, subject_id + "_v*.png")))
        missing = max(0, group["defaults"].get("candidates", 1) - len(existing))
        start = len(existing) + 1
        return existing, [f"{subject_id}_v{n}.png" for n in range(start, start + missing)]
    # Exact filename, one per subject: regenerating means deleting the file
    # first, the same rule the sprite path uses for its candidates.
    final = os.path.join(out_dir, subject_id + ".png")
    if os.path.isfile(final):
        return [final], []
    return [], [subject_id + ".png"]


def main() -> None:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    auto_yes = "--yes" in args
    no_reference = "--no-reference" in args
    tiles = "--tiles" in args
    only = None
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))

    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    group = load_group(manifest, tiles)
    defaults = group["defaults"]
    root = os.path.join(os.path.dirname(__file__), "..")
    out_dir = os.path.join(root, defaults["output_dir"])
    ref_path = os.path.join(root, defaults["reference_image"])

    jobs = []
    for s in group["subjects"]:
        if not s.get("enabled", False):
            continue
        if only is not None and s["id"] not in only:
            continue
        prompt = group["template"].replace("{subject}", s["subject"])
        existing, pending = plan_outputs(group, out_dir, s["id"])
        jobs.append({"id": s["id"], "prompt": prompt, "existing": existing, "pending": pending})

    print(f"Plan ({group['label']}s):")
    total_calls = 0
    for j in jobs:
        print(f"  {j['id']}: {len(j['existing'])} on disk, {len(j['pending'])} to generate")
        total_calls += len(j["pending"])
    print(f"  -> {total_calls} API call(s), model {defaults['model']}, size {defaults['size']}")
    print(f"  -> output {defaults['output_dir']}, style reference {defaults['reference_image']}")
    if "background" in defaults:
        print(f"  -> background {defaults['background']}")
    else:
        print("  -> background parameter omitted (this model has no transparency)")

    if dry_run:
        print("\n--- dry run: assembled prompts ---")
        for j in jobs:
            print(f"\n[{j['id']}] -> {', '.join(j['pending']) or '(nothing to generate)'}\n{j['prompt']}")
        return
    if total_calls == 0:
        print("Nothing to do - every output already exists. Delete files to regenerate.")
        return

    if not os.environ.get("OPENAI_API_KEY"):
        fail("OPENAI_API_KEY is not set in this shell. Set it and rerun.")
    use_reference = not no_reference
    if use_reference and not os.path.isfile(ref_path):
        fail(f"Style reference missing: {defaults['reference_image']}\n"
             "Point reference_image at an approved asset, or rerun with --no-reference.")

    if not auto_yes:
        answer = input(f"Generate {total_calls} image(s)? [y/N] ").strip().lower()
        if answer != "y":
            print("Aborted.")
            return

    try:
        from openai import OpenAI  # imported late so --dry-run works without the package
    except ModuleNotFoundError:
        fail("The 'openai' package is not installed for THIS interpreter:\n"
             f"  {sys.executable}\n"
             "Fix: run  python -m pip install openai  in this same terminal\n"
             "('-m pip' guarantees the install targets the python you are running).")
    client = OpenAI()
    os.makedirs(out_dir, exist_ok=True)

    # Only the keys the manifest actually declares are sent. gpt-image-2 has no
    # transparency, so its section omits `background` and the parameter never
    # reaches the API rather than being sent as some placeholder value.
    call_kwargs = {"model": defaults["model"], "size": defaults["size"]}
    if "background" in defaults:
        call_kwargs["background"] = defaults["background"]

    for j in jobs:
        for filename in j["pending"]:
            out_path = os.path.join(out_dir, filename)
            print(f"generating {filename} ...")
            for attempt in range(1, MAX_ATTEMPTS + 1):
                try:
                    if use_reference:
                        with open(ref_path, "rb") as ref:
                            result = client.images.edit(
                                image=[ref], prompt=j["prompt"], **call_kwargs
                            )
                    else:
                        result = client.images.generate(prompt=j["prompt"], **call_kwargs)
                    data = base64.b64decode(result.data[0].b64_json)
                    with open(out_path, "wb") as f:
                        f.write(data)
                    print(f"  saved {os.path.relpath(out_path, root)} ({len(data) // 1024} KB)")
                    break
                except Exception as e:  # noqa: BLE001 - scrubbed, no traceback by design
                    print(f"  attempt {attempt}/{MAX_ATTEMPTS} failed ({type(e).__name__}): {scrub(str(e))}")
                    if attempt == MAX_ATTEMPTS:
                        print(f"  giving up on {filename}, continuing with next")
                    else:
                        time.sleep(5 * attempt)
            time.sleep(1)  # gentle pacing between calls

    print("\nDone. Next:")
    if tiles:
        print("  python tools/make_tileable.py assets/generated/tiles assets/tiles")
        print("  (NOT prepare_sprites.py - it trims transparent margins and would wreck a full-bleed texture)")
    else:
        print("  curate the candidates, rename the keeper to <id>.png, then run:")
        print("  python tools/prepare_sprites.py assets/generated/animals assets/sprites/animals")


if __name__ == "__main__":
    main()
