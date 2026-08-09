# Claude Design Prompt Package - HUD Mockup (input for A2)

Goal: get a visual spec (mockups + style tokens) for the Godot HUD theme.
Design outputs web-native artifacts - that is fine, we transcribe the TOKENS
into theme.tres by hand. We are buying design decisions, not files.

## Step 1 - Prepare uploads

1. SCREENSHOT of the running game: launch the game windowed in portrait
   (project is 1080x1920), get a state with 3-4 animals + 2 keepers visible
   and the shop panel OPEN. Capture with Win+Shift+S. One extra screenshot
   with the entity info panel open.
2. REFERENCES: 2-4 images of rounded/cozy casual game UI (the direction
   already picked: chunky rounded panels, warm palette, thick friendly
   buttons). Dribbble/Behance searches like "cozy game UI" or "casual game
   HUD concept" - pick ones YOU like; they steer the whole theme.

## Step 2 - The prompt (paste into Claude Design, attach uploads)

---

I am skinning the HUD of an EXISTING 2D cozy zoo idle game built in the
Godot engine, portrait 1080x1920, for mobile touch. This is NOT a website
and NOT an app landing page - I need game HUD overlay designs on top of the
attached gameplay screenshots. The game world (map, animals, keepers) stays
as-is underneath; only the UI layer is being designed.

Style direction: cozy, rounded, warm - see attached reference images. Base
palette family: cream / wood brown / leaf green, with one wedding-accent
color (blush/gold family). Chunky readable buttons sized for thumbs, thick
rounded panel corners, friendly and celebratory but not childish. It is a
personalized wedding gift.

Deliverables, in this order:
1. Mockup: main HUD over screenshot 1 - coin counter with coin icon,
   income-per-second readout, shop button. Top bar or corner cluster, must
   not cover the map center.
2. Mockup: shop panel (bottom sheet style) - scrollable list of animals with
   name, cost, buy button; locked entries visibly locked.
3. Mockup: entity info panel - name, level, income, upgrade button with
   cost, assign-keeper button, close.
4. Mockup: a celebration popup (unlock/welcome-back) - short text, one
   confirm button, confetti-adjacent but tasteful.
5. STYLE TOKEN SHEET (most important deliverable): exact hex colors
   (background, panel, panel-border, text primary/secondary, accent,
   positive/buy, disabled), corner radius scale in px, border widths,
   spacing scale, button states (normal/pressed/disabled), font
   recommendation limited to OFL Google Fonts (suggest 2-3, show the coin
   counter rendered in each), and icon style guidance.

Constraints: no gradients heavier than subtle, no glassmorphism, no thin
elegant serif UI, minimum touch target 88x88 px at 1080 width, text must
stay readable over a busy colorful map (panels need enough opacity).

---

## Step 3 - What we do with the output

- Token sheet -> theme.tres (StyleBoxFlat panels/buttons, colors, corners,
  font) - mechanical transcription, then font .ttf into the project.
- Mockups -> layout adjustments to the existing panels (positions, sizes).
- Icons are NOT taken from the mockup - they are generated separately per
  assets_spec.md section 4 so they match the sprite style bible.

## Notes

- If the mockups drift toward "website" (nav bars, footers, hero sections),
  reply with: "game HUD overlay only - no page structure" and re-anchor on
  the screenshot.
- Iterate on deliverable 5 hardest; a beautiful mockup with vague tokens is
  not actionable, vague mockups with precise tokens are.