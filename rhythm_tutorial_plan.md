# VoiceZoo - Rhythm & Onboarding Plan (Sprint R)

Status: PROPOSAL for review | Target: V1 wedding build
Implementation vehicle: Claude Code, staged R1..R6 below.
NOTE: German UI copy in this document is written with ue/ae/oe transliteration
to survive tooling. Use PROPER UMLAUTS in the actual data/strings files.

---

## 0. Why this exists (read first)

The current sound model is per-entity random timers with jitter
(entity_sprite.gd: _sound_timer / _next_sound_at). That is ambience. It is
structurally incapable of producing coordinated sound, because there is no
shared clock - every animal is its own island.

The fun of this game is the zoo singing TOGETHER: sounds landing on beats,
combining into patterns, eventually into a song. That requires one conductor
and a step sequencer. This plan replaces the random timers with a global
rhythm engine and teaches the mechanic through a short guided tutorial.

Guiding principle: THE ZOO MUST SOUND GOOD WITH ZERO INPUT. Defaults do the
musical work; editing is the depth layer for players who want it.

---

## 1. Architecture

Follows the existing core/presentation split and mirrors the
InteractionEngine + InteractionPlayer pattern exactly (engine returns data,
player renders it).

NEW core (pure, RefCounted, headless-testable):
  core/rhythm_engine.gd    - transport + step sequencer, emits triggers
  core/tutorial_state.gd   - tutorial step machine, pure predicates + events

NEW presentation:
  presentation/rhythm_player.gd      - consumes triggers, plays entity sprites
  presentation/ui/composition_view.gd- THE STUDIO SCREEN: full grid of
                                       animals x steps (see section 3b)
  presentation/ui/tutorial_overlay.gd- spotlight + speech bubble + next step

NEW data:
  data/rhythm.json    - bpm, steps_per_loop, per-type default patterns, pitch
  data/tutorial.json  - ordered steps: text, target, advance condition

CHANGED:
  core/entity_data.gd  - + beat_pattern: int (bitmask), + in_song: bool,
                         + pitch_offset: float (semitones)
  core/zoo_state.gd    - + rhythm settings, + tutorial progress, SCHEMA v3
  presentation/entity_sprite.gd - REMOVE the random _sound_timer path;
                         sounds are triggered externally by RhythmPlayer
  presentation/main.gd - own + wire RhythmEngine/RhythmPlayer/Tutorial
  presentation/ui/entity_info.gd - read-only "singt auf Takt 1, 5" line +
                         a button that opens the Studio scrolled to this animal

---

## 2. Rhythm engine contract

### Transport
- Absolute-time driven: advance_to(now_seconds), NEVER accumulated delta.
  Accumulated delta drifts over minutes; absolute time cannot. This also
  makes frame drops skip-and-recover instead of slowly falling behind.
- Loop: steps_per_loop steps (default 8), step_duration = 60.0 / bpm
  (quarter notes). Defaults: bpm 90 -> step 0.667s -> loop 5.33s.
  Rationale: animal recordings run ~0.5-1.5s; faster steps cause pile-up.
- Crossing multiple steps in one frame emits ALL crossed steps in order
  (never silently drop a beat).
- If more than one loop was missed (tab backgrounded, breakpoint), resync to
  the current position instead of emitting hundreds of stale triggers.

### API (proposed)
    var bpm: float
    var steps_per_loop: int
    var muted: bool
    func advance_to(now: float) -> void      # emits into newly_triggered
    var newly_triggered: Array[Dictionary]   # [{entity_id, step}]
    func current_step() -> int
    func loop_progress() -> float            # 0..1, for UI pulse
    func set_entities(entities: Array) -> void
    func to_dict() / from_dict()

### Per-entity data
- beat_pattern: int, bitmask over steps (bit N set = sings on step N).
  8 steps fits in one int trivially; extending to 16 later costs nothing.
- in_song: bool (default true). Lets a player park an animal without
  deleting it.
- pitch_offset: float, semitones. Playback uses
  pitch_scale = pow(2, pitch_offset / 12).

### Default patterns (the "sounds good for free" rule)
data/rhythm.json defines per TYPE a default pattern, so a purchased animal
lands in a musically sensible slot immediately:
  chicken  -> steps 0, 4      (the pulse)
  dog      -> step  2         (offbeat answer)
  cat      -> step  6
  parrot   -> steps 1, 5
  monkey   -> step  3
  penguin  -> step  7
  lion     -> step  0         (downbeat, low)
  elephant -> step  4
Multiple copies of the same type: rotate the pattern by (owned_count mod
steps) so a zoo full of chickens spreads across the bar instead of stacking.
Default pitch_offset also rotates over a small pentatonic set
(0, +3, +5, +7, +12) so duplicates sound like a chord, not a doubling.

### Voice cap
Hard cap on simultaneous triggers per step (default 6, in rhythm.json).
Selection when over cap: prefer entities WITH user recordings, then closest
to camera. Prevents a 28-animal zoo from becoming a wall of noise.

---

## 3. Interaction with existing systems

- entity_sprite: keep play_reaction / interaction sounds as-is. Remove ONLY
  the ambient random timer. Add play_beat(pitch_scale) used by RhythmPlayer.
- InteractionPlayer sounds and rhythm sounds coexist; interactions are rare
  and short. If they collide audibly in testing, duck rhythm volume by ~3dB
  during an interaction rather than suppressing either.
- SoundResolver is unchanged: it already answers "what stream does this
  entity play". Rhythm decides WHEN, resolver decides WHAT.

---

## 3b. Composition view (the "Studio" screen)

The place the actual fun lives. A per-animal editor lets you TWEAK; a grid
lets you COMPOSE - you cannot arrange parts you cannot see at the same time.
This screen replaces the per-animal beat editor entirely and also absorbs the
"visual beat pulse" idea (the playhead does that job better).

### Layout (portrait 1080x1920)
- Full-screen view, opened from a HUD button ("Studio"). Not a bottom sheet -
  it needs the height.
- Rows = animals. Each row: sprite thumbnail + name + in_song toggle (the row
  label IS the mute button), then 8 step cells.
- Columns = the 8 loop steps, with a column header showing step numbers.
- Cell = tap to toggle. Filled = this animal sings on this step.
- PLAYHEAD: the current step's column is highlighted, sweeping in time with
  the engine (rhythm_engine.current_step()). This is what makes the mechanic
  legible - you SEE the beat move and HEAR sounds fire on it.

### Space budget (this is why V1 is 8 steps)
1080 wide - ~300 for the row label = 780 for cells -> 8 cells at ~97px,
comfortably above the 88px touch minimum. At 16 steps cells drop to ~48px,
which is below the touch minimum in portrait. 16 steps would require
horizontal scrolling or landscape - deliberately out of scope for V1.

### Row count / late-game zoo
A guest has 3-5 animals (perfect). A finished zoo has 28+ (a wall). Rules:
- Vertical scroll, rows sorted: animals WITH user recordings first, then by
  type, then by id. The interesting voices are always on top.
- Per-row in_song toggle parks an animal without deleting it.
- No grouping-by-type: patterns are per-animal (they rotate), so a type row
  would lie about what is actually playing.

### Row identity - ADDED after the R4 listen test (spec gap, not an R4 bug)
Section 3b originally specified rows as "thumbnail + name + in_song toggle".
With 44 animals that produces a dozen rows all labelled "Huhn" and no way to
tell which is which, or which one on the map a row corresponds to. Worse, the
link-through was one-directional: animal -> Studio, never back.

The fix is to stop requiring the round trip at all - a row that can manage its
own sound never needs to be located on the map:

1. ROW SOUND ACTION. Each row gets a mic button that opens the record dialog
   for that entity (the same dialog entity_info uses). Recording from the
   Studio is the common case anyway: you hear a part, you want to change it.
   composition_view emits record_requested(entity); main.gd already owns the
   dialog and the _on_sound_saved wiring.
2. DISTINGUISHABLE LABELS. A row shows the sound's own label when the animal
   has a recording, otherwise "<Name> <n>" where n is the animal's ordinal
   among its type (computed at display time from entity order - deterministic,
   no schema change). Recorded animals already sort first, so the meaningful
   labels sit at the top where they are useful.
3. TAP THE THUMBNAIL TO PREVIEW. Hearing a row is the fastest identity check
   there is. Cell taps already preview on turn-on; the thumbnail previews
   without editing anything.
4. OPTIONAL, ONLY IF CHEAP: a locate action that closes the Studio and centres
   the camera on that animal. Nice for players who do want the map; not
   required once 1-3 exist.

ACCEPTS: with 44 animals, every row is distinguishable from every other row,
and a sound can be recorded or replaced without leaving the Studio.

### Capped-out rows must be visible
The voice cap silently drops the lowest-priority voices on a saturated step.
Measured on a real 44-animal save: every step pegged at the cap of 6, and ten
animals never sang at all. Correct behaviour (the tiebreak protects
user-recorded voices) but it reads as a bug. The grid must mark dropped rows
- dimmed cells or a small cap badge. Without it the first question is
"my new chicken is broken".

### Feedback rules
- Tapping a cell plays that animal's sound IMMEDIATELY (not on the next
  loop). You must hear what you just placed.
- Toggling never restarts the loop - the transport is free-running.

### V1 scope: static timings only
V1 = one 8-step bar, patterns fixed until edited. Known extension paths, NOT
built now:
- Swing/groove: one float in rhythm.json that delays even steps. Purely
  engine-side, no data migration.
- Multi-bar songs: beat_pattern becomes Array[int] (one mask per bar) and the
  grid gains a bar selector. This IS a schema migration (v3 -> v4) but a
  contained one: widen the field, default existing masks to bar 0.
Do not pre-build either. The escape route is known; that is enough.

## 4. Recording quality prerequisites (needed for tight rhythm)

Two additions to core/wav_utils.gd - both are prerequisites, not polish. A
recording with 400ms of leading silence will audibly miss its beat.

R2a. trim_silence(bytes, threshold, max_lead_ms)
     Strips leading/trailing samples below threshold so the sound STARTS on
     the transient. Applied at the capture edge in record_dialog, in the
     existing chain: to_mono -> resample -> trim_silence -> normalize.
R2b. Soft length cap for rhythm use: if a trimmed sound exceeds
     step_duration * 2, apply a short fade-out at the cap. Keeps the loop
     legible without destroying long recordings (full sound still stored;
     the cap applies to the rhythm voice only).

---

## 5. Tutorial design

Data-driven step machine. core/tutorial_state.gd is pure; presentation only
renders the current step and posts events.

### Advance conditions - two kinds
- STATE predicates evaluated against ZooState (entity_count >= 1,
  any_entity_has_recording, ...)
- EVENTS posted by presentation (notify("shop_opened"),
  notify("beat_toggled"), ...)

### Proposed steps (data/tutorial.json)
1. welcome     - "Willkommen in deinem Zoo!"            -> tap anywhere
2. buy_first   - highlight Shop, "Kauf dein erstes Tier" -> entity_count >= 1
3. hear_beat   - "Hoerst du es? Dein Tier singt im Takt" -> 1 full loop plays
4. buy_second  - highlight Shop, "Hol noch eins dazu"    -> entity_count >= 2
5. hear_song   - "Zwei Tiere, zwei Takte - zusammen ein Lied" -> 1 loop
6. record      - highlight animal, "Tippe an und nimm deinen Sound auf"
                 -> any_entity_has_recording
7. studio      - highlight the Studio button, "Hier baust du dein Lied"
                 -> opens Studio; playhead sweeping over 2 animals on
                 different steps is the payoff moment -> event beat_toggled
8. done        - "Viel Spass! Bau deinen Zoo." -> dismiss, set tutorial_done

Rules:
- Skippable at any time ("Ueberspringen"), and never shown again once
  tutorial_done is true (persisted in the save).
- The tutorial must not block play: it highlights and suggests, it does not
  lock input.
- Steps 3 and 5 are the payoff moments; give them a visual beat pulse on the
  animals so the mechanic is SEEN as well as heard.

### Demo song
The first two purchasable types ship with complementary default patterns
(chicken 0,4 / dog 2) so the two-part groove exists BEFORE any recording.
Placeholder sounds already carry it - the game demonstrates itself.

---

## 6. Schema v3

entity: + beat_pattern (int), + in_song (bool), + pitch_offset (float)
zoo_state: + rhythm {bpm, muted}, + tutorial {step_index, done}
All read with .get() defaults so v2 saves load unchanged. On migration,
entities without a pattern receive the type default (rotated by index).

---

## 7. Staged implementation (for Claude Code)

R1 - Core rhythm engine (no UI)
    core/rhythm_engine.gd + data/rhythm.json + schema v3 fields.
    ACCEPTS: engine emits correct steps for synthetic time sequences;
    no drift over a simulated 10 minutes; multi-step catch-up correct;
    loop-skip resync correct; voice cap respected; save roundtrip.
    Fully headless. No presentation changes yet.

R2 - Recording quality (wav_utils)
    trim_silence + fade cap + wire into record_dialog chain.
    ACCEPTS: synthetic WAV with leading silence starts on the transient;
    chain still produces valid canonical WAV; existing tests stay green.

R3 - Rhythm playback (presentation)
    rhythm_player.gd; remove the random timer from entity_sprite;
    add play_beat(pitch_scale); wire in main.gd.
    ACCEPTS: buy 3 animals -> they sound on distinct beats in a stable loop;
    boot smoke clean; manual listen test.

R4 - Composition view (Studio screen)
    composition_view.gd per section 3b: grid, playhead, in_song toggles,
    entity_info link-through. Bigger than a dot row, but it REPLACES the
    beat editor and the beat-pulse item, so net scope is close to even.
    ACCEPTS: grid reflects live patterns; playhead tracks the engine; tapping
    a cell changes the next loop AND previews immediately; sorting puts
    recorded animals first; cells >= 88px; survives save/load; 60fps with
    28 rows on the web export.

R5 - Tutorial
    core/tutorial_state.gd + data/tutorial.json + tutorial_overlay.gd.
    ACCEPTS: fresh save runs all steps in order; skip works; never reappears
    after completion; state machine fully unit-tested with fake events.

R6 - Feel pass
    Beat pulse animation on trigger, tempo control in HUD, mute toggle,
    interaction ducking if needed.
    ACCEPTS: an uninstructed player understands within 30 seconds
    (the original Milestone 1.5 criterion, now actually meaningful).

---

## 8. Decisions - RESOLVED (no open questions remain)

1. Steps per loop: 8 for V1. Hard constraint from the Studio grid space
   budget (section 3b), not a preference. Bitmask keeps 16 open for later.
2. Rhythm REPLACES ambient sound entirely. The per-entity random timer in
   entity_sprite.gd is deleted, not gated. Two sound models is twice the
   surface for no gain, and the ambient one is the unfun one.
3. Tempo: player-adjustable, THREE COARSE PRESETS only
   (gemuetlich ~75 / normal ~90 / Party ~110 bpm). No free slider.
4. Tutorial runs in the guest web build too. It matters MORE there: a guest
   has two minutes and zero context.
5. Snapshot export/import is CUT. Replaced by single-sound sharing: a
   "schick uns deinen Sound" action that hands one WAV to the platform share
   / download. The couple needs the sound, not the guest's whole zoo.
6. Selfie -> keeper-face pipeline is CUT to post-wedding. That removes photo
   capture, the oval-crop face composite, head-anchor measurement, and the
   3 keeper body sprites from V1 scope. Keepers keep their gameplay role
   (income bonus, interactions) with placeholder visuals.

---

## 9. Working agreement for this repo (READ BEFORE CODING)

### Validation loop - run after EVERY change
    .\run_checks.ps1
Three stages: (0) godot --headless --import, (1) unit tests, (2) headless
boot smoke test. All three must pass. Do not skip stage 0: adding any new
class_name script invalidates Godot's global class cache, and stale caches
produce a wall of "Could not find type X" parse errors that look like real
breakage. This has bitten this project three times.

### Test runner - HARDENED in the fix pass, trust it now
The runner used to report a file whose methods died at runtime as
"test_x: 0 passed, 0 failed [PASS]". That is fixed:
- a file that fails to LOAD counts as a failure (was already true),
- a file with no test_* methods counts as a failure,
- a test METHOD that records zero assertions counts as a failure (GDScript
  aborts a method on a runtime error, so "recorded nothing" is the only
  signal available).
Verified by deliberately introducing a zombie test and watching the suite go
red. Still worth glancing at the pass count, but a green run now means what
it says.
BASELINE AFTER THE FIX PASS: 592 tests passing, 0 failed.
### House conventions (follow these, they are load-bearing)
- core/ is pure: RefCounted or Resource only. Never extends Node, never
  get_tree(), never get_node(), never file I/O, never reads the system clock
  (pass "now" in as a parameter). This is what makes headless testing work.
- presentation/ reads state and renders. It never computes income, cost,
  progression, or timing itself.
- platform/ is the ONLY place AudioEffectRecord, JavaScriptBridge or
  getUserMedia may appear.
- All balancing/config data lives in JSON under data/. No magic numbers in
  GDScript.
- Every data class implements to_dict() / from_dict().
- Schema migrations use .get() with defaults rather than version branches
  wherever possible. Bump SCHEMA_VERSION in zoo_state.gd and document what
  changed at the constant.
- Engines return DATA; players render it. Follow the existing
  InteractionEngine / InteractionPlayer split - RhythmEngine / RhythmPlayer
  is deliberately the same shape.
- Dependency injection at boundaries (see interaction_player.setup(...) and
  sound_store's injectable root). Avoid globals beyond the Config autoload.
- Tests: happy path + at least one edge case per unit. Use injectable
  RNG/time for determinism (see interaction_engine.rng).

### Encoding
Write files as UTF-8 without BOM. German UI strings belong in data/ JSON or
GDScript string literals with PROPER UMLAUTS - this plan file transliterates
(ue/ae/oe) only to survive the tooling that produced it.

### Useful existing tools
    tools/diag_theme.gd          - is the UI theme actually applying?
    tools/diag_mic*.gd           - microphone / audio device probes
    tools/diag_playback.gd       - stored sound inspection + playback test
    tools/diag_sound_inventory.gd- what sounds exist, who references them
    tools/build_theme.gd         - regenerate theme.tres from ui_theme.json

---

## 10. Priority order under a TWO WEEK deadline

Wedding is ~2 weeks out. This plan alone does not fit alongside the unbuilt
guest chain, so order matters more than completeness.

TIER 1 - without these there is no gift
  A. Web audio recorder (Sprint 16.5): port the ALREADY VALIDATED
     mic_test.html pipeline through JavaScriptBridge
     (getUserMedia -> AudioContext -> resample 22050 -> 16-bit WAV).
  B. Single-sound sharing (replaces snapshot export).
  C. Deploy to Cloudflare Pages + iPhone Safari test. STILL UNVALIDATED.
     Exclude assets/generated/ from the export preset first.
  D. R1-R3: rhythm engine, recording trim/normalize, rhythm playback.
     A game that is not fun fails regardless of what else ships.

TIER 2 - what makes it feel finished
  E. R4 Studio screen (the compose-a-song payoff).
  F. R5 tutorial.
  G. Wire the 7 processed animal sprites into entities.json.

TIER 3 - only if time remains
  H. R6 feel pass, HUD layout pass, icons, background art, cat sprite.

### Pre-planned degradation path for TIER 1 C
If Godot web recording fails on iOS Safari, DO NOT try to fix it under
deadline. Fall back to: guests get a small standalone HTML page (the
existing mic_test.html pipeline, already proven to work in-browser) that
records and shares one sound, and the full game ships as the couple's
Android build only. This preserves the gift concept at a fraction of the
risk. Decide this the same day the iPhone test happens.

---

## 11. Fix pass (post-R3, pre-R4) - COMPLETE

Six issues found across the R1-R3 reviews, fixed together rather than carried
into R4. All verified green at 592 tests.

1. Beat voice spatial falloff. _beat_audio is built in code and silently
   inherited Godot's defaults (max_distance 2000, attenuation 1.0) instead of
   the scene's tuned 800 / 1.5, making the constantly-firing singing voice
   audible across the entire map. Now copied from the interaction player at
   _ready, so the scene file stays the single source of truth.
2. trim_silence used an ABSOLUTE threshold. A take peaking at 0.046 (a real
   measurement from this project) judged against 0.02 lost everything below
   43% of its own peak - attack and release included. The threshold is now a
   fraction of the take's own peak (DEFAULT_TRIM_RATIO 0.05). Pinned by a
   test that trims one layout at two very different levels and asserts
   identical output length.
3. rotate_pattern laundered UNASSIGNED (-1) into 0, turning "never given a
   part" into "deliberately silent" - the exact distinction the sentinel
   exists to protect, and R4 edits patterns.
4. ZooState.tick() does not advance the rhythm transport (that needs absolute
   monotonic time from presentation). Now documented at the function;
   double-advancing would emit every beat twice.
5. test_audio_recorder leaked Node-derived mocks - created in before_each for
   every test, freed only in the last one. Now freed in after_each.
6. Test runner hardening - see section 9.

Still open, deliberately NOT fixed here:
- The manual listen test (R3 acceptance). Needs human ears.
- trim ratio / lead constants live in GDScript, not JSON. Left alone: a ratio
  is device-independent in a way an absolute threshold was not, so most of
  the tuning pressure that justified moving them is gone.
- No integration coverage on input paths (the signal-arity bug class). Real
  gap, real cost to close, out of scope two weeks out.
