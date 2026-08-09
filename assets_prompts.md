# A1 - Style Anchor Prompt Package (gpt-image-1.5)

Goal: pick ONE style before any batch generation (Gate 1 in assets_spec.md).
Generate the anchor trio (chicken, lion, parrot) in 3 style variants, compare
the 3 resulting sheets, pick one, freeze. ~9-12 generations, then STOP and
review.

## API settings for every call
- model: gpt-image-1.5
- size: 1024x1024
- background: transparent
- one subject per image, one image per call

## The style block (paste verbatim, then append ONE subject line)

### Variant A - "Flat Cel" (the Style Bible baseline)
A cute [SUBJECT]. 3/4 top-down view as in cozy farming games, character seen
slightly from above, facing slightly left. Flat cel shading with at most two
shadow tones, no gradients, no photorealism, no painterly texture. Thick
rounded dark warm-brown outline (#3A2E28) with uniform weight. Warm cozy
palette built on cream, wood brown and leaf green. Soft key light from the
top left. Big simple readable silhouette, no fine details. Single subject
centered, filling about 80% of the canvas height, feet resting on a level
ground line at about 88% of canvas height. No text, no watermark, no
background elements, no cast shadow on the ground. Transparent background.

### Variant B - "Chunky Sticker"
Same block as A, but replace the first two sentences with:
A cute [SUBJECT] in a chunky die-cut sticker style with extra-thick rounded
outline and very simplified rounded shapes. 3/4 top-down view, facing
slightly left.

### Variant C - "Soft Storybook"
Same block as A, but replace "Flat cel shading with at most two shadow
tones" with:
Soft storybook shading with gentle color transitions and rounded volumes,
still cleanly outlined.

## Anchor subjects (use for all 3 variants)
1. [SUBJECT] = chicken with a small red comb, plump round body
2. [SUBJECT] = lion lying down calmly, large fluffy mane
3. [SUBJECT] = parrot standing upright, bright green and red feathers, large curved beak

## Selection checklist (judge each 3-sprite sheet as a SET)
- Do the three read as one game? (outline weight, shading, palette)
- Silhouette still readable when scaled to 64 px?
- Transparent edge clean - no white halo pixels?
- Would you proudly show this sheet at the wedding?

## After the anchor is picked
- Freeze the winning style block; note the variant letter in assets_spec.md.
- Every batch generation attaches ONE approved anchor image as a reference
  image in addition to the text prompt.
- Batch subject lines (full roster, farm pets updated):
  - chicken: (already have from anchor)
  - dog: small fluffy Maltese dog, white coat with dark patches, happy
    expression, tail up  <-- confirm patch placement against a photo if possible
  - cat: [COLORING TBD - ask the couple] shorthair cat sitting upright,
    tail curled around its paws
  - parrot: (already have from anchor)
  - monkey: small monkey sitting, long curled tail visible, holding one hand up
  - penguin: plump penguin standing upright, flippers slightly out
  - lion: (already have from anchor)
  - elephant: young elephant, trunk raised slightly, big friendly ears
- Icons (12, per assets_spec.md section 4) are generated AFTER the anchor,
  same style block with: "flat game icon of [ICON], single glyph" as subject.