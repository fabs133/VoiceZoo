#!/usr/bin/env python3
"""VoiceZoo sprite generation: manifest -> assembled prompts -> gpt-image API.

SECURITY CONTRACT (do not weaken):
- The API key is NEVER read into this program's logic. The OpenAI client
  picks up OPENAI_API_KEY from the environment itself; we only check that
  the variable EXISTS.
- Every error message printed to the console is passed through scrub(),
  which redacts the literal key value and anything shaped like an API key.
- No tracebacks are printed. No log files are written.

Usage:
  python tools/generate_sprites.py --dry-run          # assemble + print prompts, no API calls
  python tools/generate_sprites.py                    # full run (asks for confirmation)
  python tools/generate_sprites.py --only monkey      # subset, e.g. one cheap smoke subject
  python tools/generate_sprites.py --yes              # skip confirmation
  python tools/generate_sprites.py --no-reference     # allow running without the anchor image
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


def main() -> None:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    auto_yes = "--yes" in args
    no_reference = "--no-reference" in args
    only = None
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))

    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    defaults = manifest["defaults"]
    template = manifest["style_template"]
    root = os.path.join(os.path.dirname(__file__), "..")
    out_dir = os.path.join(root, defaults["output_dir"])
    ref_path = os.path.join(root, defaults["reference_image"])

    jobs = []
    for s in manifest["subjects"]:
        if not s.get("enabled", False):
            continue
        if only is not None and s["id"] not in only:
            continue
        prompt = template.replace("{subject}", s["subject"])
        existing = len(glob.glob(os.path.join(out_dir, s["id"] + "_v*.png")))
        missing = max(0, defaults["candidates"] - existing)
        jobs.append({"id": s["id"], "prompt": prompt, "existing": existing, "missing": missing})

    print("Plan:")
    total_calls = 0
    for j in jobs:
        print(f"  {j['id']}: {j['existing']} candidate(s) on disk, {j['missing']} to generate")
        total_calls += j["missing"]
    print(f"  -> {total_calls} API call(s), model {defaults['model']}, size {defaults['size']}")

    if dry_run:
        print("\n--- dry run: assembled prompts ---")
        for j in jobs:
            print(f"\n[{j['id']}]\n{j['prompt']}")
        return
    if total_calls == 0:
        print("Nothing to do - all candidates exist. Delete files to regenerate.")
        return

    if not os.environ.get("OPENAI_API_KEY"):
        fail("OPENAI_API_KEY is not set in this shell. Set it and rerun.")
    use_reference = not no_reference
    if use_reference and not os.path.isfile(ref_path):
        fail(f"Reference anchor missing: {defaults['reference_image']}\n"
             "Drop your approved Variant A anchor PNG there, or rerun with --no-reference.")

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

    for j in jobs:
        for n in range(j["existing"] + 1, j["existing"] + j["missing"] + 1):
            out_path = os.path.join(out_dir, f"{j['id']}_v{n}.png")
            print(f"generating {j['id']}_v{n} ...")
            for attempt in range(1, MAX_ATTEMPTS + 1):
                try:
                    if use_reference:
                        with open(ref_path, "rb") as ref:
                            result = client.images.edit(
                                model=defaults["model"],
                                image=[ref],
                                prompt=j["prompt"],
                                size=defaults["size"],
                                background=defaults["background"],
                            )
                    else:
                        result = client.images.generate(
                            model=defaults["model"],
                            prompt=j["prompt"],
                            size=defaults["size"],
                            background=defaults["background"],
                        )
                    data = base64.b64decode(result.data[0].b64_json)
                    with open(out_path, "wb") as f:
                        f.write(data)
                    print(f"  saved {os.path.relpath(out_path, root)} ({len(data) // 1024} KB)")
                    break
                except Exception as e:  # noqa: BLE001 - scrubbed, no traceback by design
                    print(f"  attempt {attempt}/{MAX_ATTEMPTS} failed ({type(e).__name__}): {scrub(str(e))}")
                    if attempt == MAX_ATTEMPTS:
                        print(f"  giving up on {j['id']}_v{n}, continuing with next")
                    else:
                        time.sleep(5 * attempt)
            time.sleep(1)  # gentle pacing between calls

    print("\nDone. Next: curate, then run:")
    print("  python tools/prepare_sprites.py assets/generated/animals assets/sprites/animals")


if __name__ == "__main__":
    main()