# VoiceZoo Asset Specification (A0)

Status: DRAFT for review | Date: 2026-07-07 | Target: V1 wedding build (freeze ~2026-08-10)

Scope: everything visual that gets generated or themed for V1. Sounds are NOT in
scope here - animal/keeper sounds come from guests and the couple (Phase 2).
Display names (German) live in data/entities.json and stay unchanged; this spec
keys everything by type_id so finished art lands via file drop + JSON path only.

---

## 1. Style Bible (applies to EVERY generated asset)

These lines are pasted verbatim into every generation prompt. Change them only
by changing this document.

- Perspective: 3/4 top-down view (Stardew Valley-like), same camera angle for
  every sprite. Never pure top-down, never side view.
- Rendering: soft cel shading, two shadow tones max, no photorealism, no
  gradients, no painterly texture noise.
- Outline: thick, rounded, warm dark-brown outline (approx #3A2E28), uniform
  weight (~8 px on a 1024 canvas).
- Palette: warm and cozy - cream, wood brown, leaf green as base family.
  Wedding accent colors: **TBD (fill in after asking the couple / checking
  wedding deco - one accent is enough, e.g. blush or gold)**.
- Lighting: soft key light from top-left, consistent across all assets.
- Mood: cute, rounded, friendly. Big readable silhouettes. No tiny details
  that vanish at 64 px.
- Forbidden in output: any text, watermarks, backgrounds (must be fully
  transparent), drop shadows baked into the sprite (engine adds those),
  multiple subjects per image.
- Canvas: 1024x1024 PNG, transparent background (gpt-image-1.5,
  background: transparent). Subject centered, 75-85% of canvas height,
  feet/base on a consistent baseline at ~88% canvas height.
- Delivery: post-processed to 256x256 working sprites by tools script
  (trim margins -> height-normalize -> baseline-align). Engine scales down;
  256 keeps 2.0x camera zoom crisp.

## 2. Animal roster (8 - unchanged type_ids)

| type_id  | zone     | silhouette / read at 64px               | guest records      |
|----------|----------|------------------------------------------|--------------------|
| chicken  | farm     | round body, small comb, big eye          | clucking           |
| dog      | farm     | small fluffy Maltese, WHITE with dark patches, tail up | barking |
| cat      | farm     | sitting cat, tail curled - coloring TBD (ask couple)   | meow    |
| parrot   | tropical | upright, big curved beak, bright         | squawk / phrase    |
| monkey   | tropical | sitting pose, long tail curled visible   | ooh-ooh screech    |
| penguin  | arctic   | upright teardrop, flippers out           | honk / trumpet     |
| lion     | savanna  | big mane = the silhouette, lying/sitting | roar               |
| elephant | savanna  | mass + trunk raised slightly             | trumpet            |

Rules:
- One pose per animal in V1 (static sprite, no animation frames).
- Poses: idle, calm, slightly angled toward camera-left (consistent facing).
- Per-animal prompt = Style Bible block + one subject line, e.g.:
  "A cute chicken, idle pose, facing slightly left" - subject lines this
  short on purpose; the style block does the heavy lifting.
- RESOLVED 2026-07-07: couple's pets are in - dog (Maltese, white with dark
  patches) and cat replace pig/cow in the FARM zone, so guests meet them within
  the first minutes of a short session. type_ids renamed (dog/cat) in
  entities.json + progression.json; dev save migrated. Placeholder sounds still
  point at the old pig/cow wav files until Phase 2 makes all sounds recorded.
- Personalization option for the couple's build: use the pets' REAL NAMES as
  display names (one string each in entities.json - ask the couple casually).

## 3. Keepers

Bodies (match data/keepers.json exactly - default / tall / small):
- Generated as: cartoon body, NECK-UP EMPTY - no head, no hair. The head is
  the guest's photo, composited at runtime into the head slot.
- THE INVARIANT: after curation, measure each body's head anchor (pixel
  offset from sprite center + scale) and write it into keepers.json
  (head_offset / head_scale - fields already exist). Acceptance test: the
  oval face composite sits correctly on ALL THREE bodies with 4 test faces.
- Clothing: NEUTRAL LIGHT GRAY zookeeper outfit (shirt + shorts/pants +
  boots). Color variety comes free via modulate tinting in-engine.
- Tint palette (6): warm red, leaf green, sky blue, sunflower yellow,
  lavender, coral - **TBD confirm against wedding accent**.
- Personalities (friendly/strict/playful/calm) are behavioral (interactions),
  NOT visual. Do not encode them in the art.

Accessory experiment (go/no-go gate, timeboxed to ~1h):
- Generate 2 accessories (straw hat, neck scarf) as separate transparent
  sprites for the default body. GO if they align on the body without manual
  per-combination fixup; then produce ~4 accessories total.
- NO-GO default: ship bodies x 6 tints only (18 visual variants + unique
  faces on top = plenty for a wedding guest list).

## 4. HUD / UI theme

Approach: Godot Theme resource (theme.tres) carries panels, buttons, colors,
corners, font - resolution-independent, no image slicing. Generated images are
used ONLY for icons. Input for the theme values = Claude Design mockup (see
design_prompt_package.md).

Surfaces to theme (complete inventory from code):
1. Main HUD (coin counter, income/s, shop button)
2. Shop panel (buy list incl. locked entries)
3. Entity info panel (level, income, upgrade button)
4. Keeper assign panel
5. Unlock popup
6. Offline income popup ("Willkommen zurueck")
7. Reserved for Phase 2 (design now, build later): record dialog
   (hold-to-record), selfie dialog

Font: rounded display font, OFL-licensed so it ships in the game.
Candidates: Fredoka, Baloo 2, Quicksand Bold. **TBD: pick after seeing the
Design mockup rendered with each.**

Icon set (gpt-image-1.5, transparent, 512x512, Style Bible applies, single
glyph per image): coin, income-rate (arrow-up-coin), shop (stall), upgrade
(arrow), lock, sound-on, sound-off, microphone (Phase 2), camera (Phase 2),
close (x), checkmark, back-arrow. 12 total.

## 5. Background / map (A5 spec preview)

- ONE map in V1. No teleport, no map switching (cut per decision log).
- Painted 2048x2048 (gpt-image-2, no transparency needed), replaces tile
  RENDERING only - the 20x20 logical grid and all zone/unlock core logic stay
  untouched (acceptance: full test suite green without modification).
- Zone layout must visually match the four logical zones: farm, tropical,
  arctic, savanna + connecting paths. Locked zones get an engine-side fog/dim
  overlay (per-zone rects), NOT baked into the image.
- No text, no animals, no people baked in - sprites live on top.
- Style anchoring: pass 3-4 APPROVED animal sprites as reference images plus
  the Style Bible text. Generate 3 candidates, curate.

## 6. Generation workflow and quality gates

- GATE 1: CLOSED 2026-07-07. ANCHOR = VARIANT A (Flat Cel, chibi-rounded).
  Anchor sprites: chicken, lion, parrot - keep the raw PNGs; every batch
  generation attaches one as a reference image. Pipeline findings baked into
  tools/prepare_sprites.py: transparent exports carry a low-alpha noise floor
  across the whole canvas (trim MUST threshold at alpha>=24), edges have
  clean dark antialiasing (no white halo). Use size 1024x1024 for the batch
  (anchors were 1024x1536 - works, but square is cheaper).
- Candidates: 3-4 per asset. Curation checklist: silhouette readable at
  64 px; outline weight consistent with anchor sheet; baseline correct;
  transparent background actually clean (check semi-transparent halo pixels).
- Directory convention:
  assets/generated/<category>/<id>_v<N>.png   (raw candidates, gitignored ok)
  assets/sprites/<category>/<id>.png          (curated + post-processed, shipped)
  Placeholders in assets/placeholder_sprites/ stay until each swap lands.
- Post-processing: tools/prepare_sprites.py (Pillow): trim -> normalize
  height -> baseline-align -> resize 256. Built in A3, ~50 lines.
- Budget estimate: ~120-160 generations total (anchor 10, animals 32,
  keepers+accessories 20, icons 40, background 6, retries) - low double-digit
  EUR at current API pricing. Negligible; curation time is the real cost.

## 7. Decisions - RESOLVED 2026-07-07

1. Wedding accent: couple has no lead color; keeping the Design-mockup pair -
   blush #E9718F (accent) + gold #F2B138. Already live in data/ui_theme.json.
2. Animal swaps: dog (Maltese, white with dark patches) + cat replace pig/cow
   in the farm zone. Remaining detail: CAT COLORING unknown - ask the couple
   (or get a photo) before the sprite batch.
3. Keeper tint palette: 6-color palette as specified in section 3.
4. Font: Baloo 2, weight 800 via FontVariation (see data/ui_theme.json).
5. Accessory experiment: SKIPPED for V1 (NO-GO default: 3 bodies x 6 tints =
   18 variants + unique guest faces). Revisit post-wedding if variety feels
   thin. Override any time by generating the 2-accessory test per section 3.

Winning Variant: A