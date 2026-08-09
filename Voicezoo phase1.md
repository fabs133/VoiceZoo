# VoiceZoo — Phase 1: Core Game
# Claude Code Development Plan

> **Place this file at:** `.claude/plans/voicezoo-phase1.md`
> **Estimated effort:** ~60–70h across Milestones 1.1–1.5
> **Engine:** Godot 4.x, GDScript, Web + Android export targets

---

## Project Bootstrap

Before starting any milestone, set up the project skeleton:

```
voicezoo/
├── .claude/
│   └── plans/
│       └── voicezoo-phase1.md        # This file
├── project.godot
├── core/                              # Pure simulation — NO nodes, NO UI
│   ├── zoo_state.gd
│   ├── entity_data.gd
│   ├── economy.gd
│   ├── progression.gd
│   └── config.gd
├── presentation/                      # Everything that renders
│   ├── zoo_map.gd
│   ├── zoo_camera.gd
│   ├── entity_sprite.gd
│   ├── audio_manager.gd
│   └── ui/
│       ├── hud.gd
│       ├── shop_panel.gd
│       └── entity_info.gd
├── data/
│   ├── entities.json
│   ├── progression.json
│   └── asset_packs/
│       └── default/
│           ├── pack.json
│           ├── sprites/
│           └── sounds/
├── scenes/
│   ├── main.tscn
│   ├── zoo_map.tscn
│   └── ui/
│       ├── hud.tscn
│       └── shop_panel.tscn
├── tests/
│   ├── test_runner.gd
│   ├── test_economy.gd
│   ├── test_progression.gd
│   └── test_zoo_state.gd
├── export/
│   ├── web/
│   └── android/
└── assets/
    ├── placeholder_sprites/
    ├── placeholder_sounds/
    └── tiles/
```

### Architecture Rules (enforce throughout all milestones)

1. **`core/` has ZERO dependencies on Godot scene tree.** All classes in `core/` are either `RefCounted` or `Resource`. They must never extend `Node`, `Node2D`, `Control`, or any scene-tree class. They must never call `get_tree()`, `get_node()`, or emit signals that assume a scene context. This is what makes headless testing possible.

2. **`presentation/` reads from `core/`, never writes game logic.** Presentation nodes hold a reference to `ZooState` and read from it every frame. User inputs in presentation call methods on `core/` objects. Presentation never computes income, costs, or progression directly.

3. **All balancing data lives in `data/`.** No magic numbers in GDScript. Entity stats, costs, income rates, progression thresholds — all loaded from JSON at startup. `config.gd` is the single loader.

4. **Serialization is first-class.** `ZooState` and `EntityData` implement `to_dict()` and `from_dict()` from day one. Every test uses these methods. This is the foundation for save/load and the later export/import system.

---

## Milestone 1.1 — Empty Playfield

**Goal:** Godot project compiles, TileMap renders, camera moves via touch.

### Tasks

1. **Create Godot 4 project** with the folder structure above. Set up `project.godot` with:
   - Display: 1080x1920 portrait (mobile-first)
   - Stretch mode: `canvas_items`, aspect: `expand`
   - Renderer: Compatibility (required for web export)

2. **Create `zoo_map.tscn`:**
   - Root: `Node2D`
   - Child: `TileMapLayer` with a simple placeholder tileset (colored squares: grass=green, path=beige, water=blue)
   - Map size: 20x20 tiles minimum, tile size: 64x64px
   - Create a basic zoo layout: grass field with paths, a few water tiles, fenced areas for later entity placement

3. **Create `zoo_camera.gd`:**
   - Extends `Camera2D`
   - Touch drag: single finger moves camera (track `InputEventScreenDrag`)
   - Pinch zoom: two-finger gesture scales between `zoom_min` (Vector2(0.5, 0.5)) and `zoom_max` (Vector2(2.0, 2.0))
   - Clamp camera to map bounds so you can't scroll into void
   - Smooth movement with lerp, not instant jumps
   - Export vars for sensitivity, zoom speed, bounds padding

4. **Create `main.tscn`:**
   - Loads `zoo_map.tscn` as child
   - Initializes `ZooState` (empty for now)
   - This is the entry scene in project.godot

5. **Verify exports:**
   - Web export: loads in browser, touch/mouse input works
   - Android export: deploy via USB, touch input works

### Acceptance Criteria

```
[ ] Project opens in Godot Editor without errors
[ ] TileMap renders a visible zoo layout with placeholder tiles
[ ] Camera pans with touch drag on mobile
[ ] Camera zooms with pinch gesture on mobile
[ ] Camera is clamped to map bounds
[ ] Mouse drag + scroll wheel work as fallback (desktop/browser testing)
[ ] Web export loads and runs at 60fps on mobile Chrome
[ ] Android APK installs and runs via USB deploy
```

---

## Milestone 1.2 — First Entity

**Goal:** Buy an entity, see it on the map, hear its placeholder sound.

### Tasks

1. **Create `core/entity_data.gd`:**
   ```
   class_name EntityData
   extends Resource

   @export var id: String              # unique instance ID (uuid or counter)
   @export var type_id: String         # reference to entities.json key
   @export var grid_position: Vector2i # position on tile grid
   @export var sound_ref: String       # path to audio file
   @export var level: int = 1

   func to_dict() -> Dictionary:
       return {
           "id": id,
           "type_id": type_id,
           "grid_position": [grid_position.x, grid_position.y],
           "sound_ref": sound_ref,
           "level": level
       }

   static func from_dict(d: Dictionary) -> EntityData:
       var e = EntityData.new()
       e.id = d["id"]
       e.type_id = d["type_id"]
       e.grid_position = Vector2i(d["grid_position"][0], d["grid_position"][1])
       e.sound_ref = d.get("sound_ref", "")
       e.level = d.get("level", 1)
       return e
   ```

2. **Create `core/zoo_state.gd`:**
   ```
   class_name ZooState
   extends RefCounted

   var entities: Array[EntityData] = []
   var coins: float = 100.0            # starting coins
   var lifetime_coins: float = 0.0
   var unlocks: Array[String] = ["chicken"]  # first entity type free

   var _next_id: int = 0

   func add_entity(type_id: String, pos: Vector2i, sound: String = "") -> EntityData:
       var e = EntityData.new()
       e.id = str(_next_id)
       _next_id += 1
       e.type_id = type_id
       e.grid_position = pos
       e.sound_ref = sound
       return e  # caller adds to entities after cost check

   func to_dict() -> Dictionary:
       # full serialization
       ...

   func from_dict(d: Dictionary) -> void:
       # full deserialization
       ...
   ```

3. **Create `data/entities.json`:**
   ```json
   {
     "chicken": {
       "name": "Huhn",
       "base_income": 1.0,
       "base_cost": 10.0,
       "cost_exponent": 1.15,
       "sound_interval": 5.0,
       "sprite": "res://assets/placeholder_sprites/chicken.png",
       "default_sound": "res://assets/placeholder_sounds/chicken.ogg"
     }
   }
   ```

4. **Create `core/config.gd`:**
   - Singleton (autoload) that loads `entities.json` on `_ready()`
   - Provides: `get_entity_config(type_id: String) -> Dictionary`
   - Validates JSON structure on load, prints clear errors

5. **Create `presentation/entity_sprite.gd`:**
   - Extends `Node2D`
   - Receives `EntityData` reference
   - Displays placeholder sprite (colored circle/square with label is fine)
   - Simple movement: wander randomly within a small radius of `grid_position`, using a timer + tween
   - `AudioStreamPlayer2D` child: plays `sound_ref` every `sound_interval` seconds (with small random jitter)

6. **Create basic Shop UI:**
   - `shop_panel.gd` / `shop_panel.tscn`: a button at the bottom of the screen "Buy Chicken — 10 coins"
   - On press: deduct cost from `ZooState.coins`, create `EntityData`, add to `ZooState.entities`, spawn `entity_sprite` on map
   - Button is disabled when `coins < cost`
   - Placement: for now, auto-place on first free grid cell (no manual placement yet)

7. **Create placeholder assets:**
   - At least one sprite: 64x64 colored shape with text label
   - At least one sound: any short .ogg file (can be a beep or generated tone)

### Acceptance Criteria

```
[ ] EntityData serializes and deserializes correctly (to_dict/from_dict roundtrip)
[ ] Tapping "Buy" deducts coins and spawns entity on map
[ ] Entity sprite is visible and wanders slightly
[ ] Entity plays placeholder sound at regular intervals
[ ] Button is disabled when insufficient coins
[ ] No crashes when buying multiple entities
[ ] entities.json is loaded correctly, config values match
```

---

## Milestone 1.3 — Idle Loop

**Goal:** Entities generate passive income. Core gameplay loop works: earn → buy → earn more.

### Tasks

1. **Create `core/economy.gd`:**
   ```
   class_name Economy
   extends RefCounted

   # Returns total income per second for the entire zoo
   static func calculate_income(entities: Array[EntityData], config: Node) -> float:
       var total := 0.0
       for e in entities:
           var cfg = config.get_entity_config(e.type_id)
           total += cfg["base_income"] * e.level
       return total

   # Returns cost for next entity of this type
   static func calculate_cost(type_id: String, owned_count: int, config: Node) -> float:
       var cfg = config.get_entity_config(type_id)
       return cfg["base_cost"] * pow(cfg["cost_exponent"], owned_count)

   # Returns cost for upgrading an entity to next level
   static func calculate_upgrade_cost(entity: EntityData, config: Node) -> float:
       var cfg = config.get_entity_config(entity.type_id)
       return cfg["base_cost"] * entity.level * 2.0
   ```
   **Important:** All methods are static and pure — they take data in, return results, have no side effects. This is what makes them testable without scene tree.

2. **Add `tick()` to `ZooState`:**
   ```
   func tick(delta: float) -> void:
       var income = Economy.calculate_income(entities, Config)
       var earned = income * delta
       coins += earned
       lifetime_coins += earned
   ```
   - `tick()` is called from presentation layer's `_process(delta)`
   - It is ALSO callable in tests with synthetic delta values

3. **Create HUD (`presentation/ui/hud.gd`):**
   - Coins display: top of screen, updates every frame from `ZooState.coins`
   - Income rate display: "X coins/sec"
   - Format large numbers nicely: 1,234 → "1.2K", 1,234,567 → "1.2M"

4. **Update Shop Panel:**
   - Cost updates dynamically based on how many of that type are owned
   - Show income-per-second this entity would add
   - Buy button shows current cost

5. **Add entity tap → upgrade flow:**
   - Tap entity on map → show `entity_info` popup
   - Shows: type name, current level, current income contribution
   - "Upgrade" button: costs `upgrade_cost`, increments `entity.level`
   - Close button to dismiss

6. **Implement offline income:**
   - On `ZooState.to_dict()`: include `"last_save_time": Time.get_unix_time_from_system()`
   - On load: calculate `elapsed = now - last_save_time`, capped at 28800 (8 hours)
   - Call `tick(elapsed)` once to grant offline earnings
   - Show "Welcome back! You earned X coins while away" popup

7. **Auto-save:**
   - Save `ZooState.to_dict()` as JSON to `user://save.json` every 30 seconds
   - Save on `NOTIFICATION_WM_GO_BACK` and `NOTIFICATION_WM_CLOSE_REQUEST`
   - Load on startup if file exists

### Acceptance Criteria

```
[ ] Coins increment visibly while entities are on map
[ ] Income rate scales correctly with number and level of entities
[ ] Cost escalation feels right: 3rd chicken costs more than 1st
[ ] Upgrade works: tap entity → upgrade → income increases
[ ] Buy button cost updates after each purchase
[ ] Save/load roundtrip preserves full state (entities, coins, levels, positions)
[ ] Offline income: close app, wait 60s, reopen → coins increased
[ ] Economy.calculate_income is a pure function with no side effects
[ ] Economy.calculate_cost is a pure function with no side effects
[ ] 5 minutes of play feels like a satisfying loop: always something to buy or upgrade
```

---

## Milestone 1.4 — Progression & Unlocks

**Goal:** New entity types unlock as player progresses. Zoo expands.

### Tasks

1. **Create `core/progression.gd`:**
   ```
   class_name Progression
   extends RefCounted

   # Returns list of type_ids that should be unlocked at given lifetime_coins
   static func get_unlocks(lifetime_coins: float, config: Node) -> Array[String]:
       var result: Array[String] = []
       var milestones = config.get_progression_milestones()
       for m in milestones:
           if lifetime_coins >= m["threshold"]:
               result.append(m["unlock_type"])
       return result
   ```
   **Pure function.** Takes a number, returns a list. No state mutation.

2. **Create `data/progression.json`:**
   ```json
   {
     "milestones": [
       { "threshold": 0,      "unlock_type": "chicken",   "zone": "farm" },
       { "threshold": 100,    "unlock_type": "pig",       "zone": "farm" },
       { "threshold": 500,    "unlock_type": "cow",       "zone": "farm" },
       { "threshold": 2000,   "unlock_type": "parrot",    "zone": "tropical" },
       { "threshold": 5000,   "unlock_type": "monkey",    "zone": "tropical" },
       { "threshold": 15000,  "unlock_type": "penguin",   "zone": "arctic" },
       { "threshold": 50000,  "unlock_type": "lion",      "zone": "savanna" },
       { "threshold": 150000, "unlock_type": "elephant",  "zone": "savanna" }
     ]
   }
   ```

3. **Expand `data/entities.json`** with all 8 entity types. Each with:
   - Increasing `base_income` and `base_cost`
   - Unique `sound_interval` values
   - Unique placeholder sprite (different colored shapes are fine)
   - Unique placeholder sound (different tones/pitches)

4. **Add zones to map:**
   - `zoo_map.tscn`: divide the TileMap into zones (farm, tropical, arctic, savanna)
   - Zones are visually distinct (different tile colors)
   - Locked zones have a visual overlay (dimmed, with a lock icon or "?" text)
   - Unlocking a zone: when first entity of that zone unlocks, overlay fades away

5. **Update Shop Panel:**
   - Show all unlocked entity types, not just chicken
   - Locked types show as grayed out with "Earn X more coins to unlock"
   - Sort by unlock order

6. **Unlock notification:**
   - When `ZooState.unlocks` grows after a `tick()`: show a brief celebration popup
   - "New animal unlocked: Pig!"
   - Keep it simple — a label + tween animation is enough

7. **Check unlocks on every tick:**
   - In `ZooState.tick()`, after updating `lifetime_coins`:
   ```
   var should_unlock = Progression.get_unlocks(lifetime_coins, Config)
   for type_id in should_unlock:
       if type_id not in unlocks:
           unlocks.append(type_id)
           newly_unlocked.append(type_id)  # presentation reads this
   ```

### Acceptance Criteria

```
[ ] Starting zoo has only "chicken" available
[ ] Earning coins progressively unlocks new entity types
[ ] Shop panel updates in real-time as new types unlock
[ ] Zones on map unlock visually when relevant entity type unlocks
[ ] At least 8 entity types defined with escalating stats
[ ] Progression curve: ~2min to first unlock, ~30min to reach lion/elephant tier
[ ] Progression.get_unlocks is a pure function, testable without scene tree
[ ] Player always has a visible "next goal" (next unlock threshold shown in UI)
```

---

## Milestone 1.5 — Tests & Polish

**Goal:** Core simulation is tested, balancing is tuned, no crashes.

### Tasks

1. **Create `tests/test_runner.gd`:**
   - Autoload or main scene for test runs
   - Discovers and runs all `test_*.gd` files
   - Reports pass/fail counts
   - Can run headless: `godot --headless --script tests/test_runner.gd`
   - Exit code 0 on all pass, 1 on any fail

2. **Create `tests/test_economy.gd`:**
   ```
   Tests to implement:
   - test_income_empty_zoo: 0 entities → 0 income
   - test_income_single_entity: 1 chicken level 1 → base_income
   - test_income_scaled_by_level: 1 chicken level 5 → base_income * 5
   - test_income_multiple_entities: 3 chickens → 3 * base_income
   - test_income_mixed_types: chicken + pig → sum of their base_incomes
   - test_cost_escalation: cost for Nth entity follows base_cost * 1.15^N
   - test_cost_first_is_base: first entity costs exactly base_cost
   - test_upgrade_cost_scales_with_level: level 3 upgrade costs more than level 2
   ```

3. **Create `tests/test_progression.gd`:**
   ```
   Tests to implement:
   - test_initial_unlock: 0 lifetime coins → only "chicken"
   - test_pig_unlock: 100 lifetime coins → chicken + pig
   - test_all_unlocks: 150000 lifetime coins → all 8 types
   - test_unlock_order_preserved: unlocks appear in correct order
   - test_threshold_exact: exactly 100 coins → pig unlocks (boundary)
   - test_below_threshold: 99.99 coins → pig NOT unlocked (boundary)
   ```

4. **Create `tests/test_zoo_state.gd`:**
   ```
   Tests to implement:
   - test_serialization_roundtrip: create state → to_dict → from_dict → compare
   - test_serialization_with_entities: state with 5 entities survives roundtrip
   - test_tick_accumulates_coins: tick(1.0) with known entities → expected coins
   - test_tick_triggers_unlock: tick enough to pass threshold → unlock appears
   - test_offline_income_capped: elapsed time > 8h → only 8h worth of income
   - test_buy_entity_insufficient_coins: coins=0, buy → fails, no entity added
   - test_empty_zoo_no_crash: tick on empty zoo → 0 income, no error
   ```

5. **Balancing pass:**
   - Play a full 30-minute session start to finish
   - Log the progression curve: time-to-unlock for each milestone
   - Target curve:
     - Chicken → Pig: ~2 minutes
     - Pig → Cow: ~4 minutes
     - Cow → Parrot: ~6 minutes
     - Parrot → Monkey: ~5 minutes
     - Monkey → Penguin: ~5 minutes
     - Penguin → Lion: ~5 minutes
     - Lion → Elephant: ~5 minutes
   - Adjust `base_income`, `base_cost`, `cost_exponent`, and `progression.json` thresholds
   - The game should never feel stuck — always within ~30sec of affording something

6. **Polish items:**
   - Coin counter animates when coins increase (counting up effect)
   - Entity spawn has a brief pop/grow animation
   - Upgrade has a brief flash/scale animation
   - Sound playback has volume falloff based on camera distance (AudioStreamPlayer2D handles this)
   - Touch feedback: brief visual response when tapping buy/upgrade buttons
   - Handle back button on Android (save and confirm exit)
   - Handle window resize / orientation change gracefully

7. **Usability test:**
   - Give the game to someone who doesn't know the project
   - Watch without explaining
   - They should understand within 30 seconds: buy animals → earn coins → buy more
   - Note any confusion points → fix them

### Acceptance Criteria

```
[ ] All tests pass via: godot --headless --script tests/test_runner.gd
[ ] Zero crashes during 30-minute play session
[ ] Progression curve matches target (±1min per milestone)
[ ] No "dead zones" where player waits >30sec with nothing to do
[ ] Usability test: uninstructed player understands the loop within 30 seconds
[ ] Save/load works across app restart (Android) and page reload (Web)
[ ] Back button on Android saves and exits cleanly
[ ] No visual glitches on screen rotation or resize
```

---

## Decision Log

| Decision | Choice | Rationale |
|---|---|---|
| View perspective | Top-down | Simpler than isometric. No depth sorting. Can upgrade later without changing core/ |
| Grid system | Discrete grid (Vector2i) | Simplifies placement, serialization, pathfinding. Avoids floating-point collision |
| Language | GDScript | Best web export support, existing game-factory pipeline, no Mono overhead |
| Renderer | Compatibility | Required for web export. Fine for 2D |
| State architecture | RefCounted (not Node) | Enables headless testing, no scene tree dependency |
| Balancing data | JSON files | Editable without recompile, versionable, foundation for asset-pack system |
| Offline income | Calculate-on-load | Simple, deterministic, testable. No background service needed |
| Entity placement | Auto-place on grid | Manual placement is polish, not core. Add in Phase 5 if time allows |
| Test framework | Custom minimal runner | Godot has no built-in test framework. GdUnit4 is an option but adds dep. Minimal runner is <100 lines and sufficient |
| Number formatting | Custom helper | K/M/B suffixes. No external dependency needed |

---

## Constraints for Claude Code

- **Never put game logic in presentation/.** If you find yourself computing income, costs, or progression in a Node script, stop and move it to core/.
- **Every function in core/ must be testable without a scene tree.** If a function needs `get_tree()` or `get_node()`, it belongs in presentation/.
- **No magic numbers.** If a value affects gameplay, it goes in entities.json or progression.json.
- **to_dict() / from_dict() on every data class.** Non-negotiable. This is the foundation for save/load and export.
- **Placeholder assets are fine.** Colored shapes and generated tones. Never block on art.
- **Mobile-first.** Test touch input early. If it doesn't feel good on a phone, it doesn't count as done.
- **Commit after each milestone.** Each milestone is a self-contained, working state.

---

## Addendum 2026-07-02 - Sprint 12/13 reality, core hygiene, web spike findings

### As implemented (supersedes 1.8/1.9 text above)
Interactions are keeper-initiated timed actions with per-keeper cooldowns and an
income multiplier that REPLACES the passive 1.5x keeper bonus while active (not
sound-triggered event chains as originally worded). InteractionEngine is core
(RefCounted, injectable RNG via `engine.rng.seed`). Playback is orchestrated by
`presentation/interaction_player.gd` (RefCounted, dependency-injected, headless-
tested) - main.gd is a composition root. Interaction sounds capped at 3
concurrent; slots are keyed by keeper_id and released only by their owner.

### Core hygiene (all headless-tested)
- Offline income is a pure core function: `Economy.calculate_offline_income`
  (8h cap in core, negative elapsed = 0). Presentation only supplies elapsed.
- Keeper income bonus is read from data/keepers.json ("income_bonus"); the
  GDScript constant is only a fallback for configs without get_keeper_config().
- Saves carry `schema_version` (currently 1). `ZooState.to_dict(now)` takes the
  timestamp as a parameter - core never reads the system clock.
- Deliberately deferred to tuning: upgrade-cost factor (2.0) and personality
  weight (3.0) remain GDScript constants.
- Accepted risk: offline income trusts the device clock (players can
  time-travel for coins - irrelevant for a gift game).

### Validation loop (upgraded)
`.\run_checks.ps1` = unit tests + headless boot smoke test
(`--quit-after 10 --verbose`, grep SCRIPT ERROR). Rationale: two main.gd
parse errors were invisible to the 200+ unit tests because the runner only
loads core/. The smoke test caught both. Always run both.

### Web export spike (guest tier) - findings
- export_presets.cfg created: Web preset, `variant/thread_support=false`.
  Verified in output: GODOT_THREADS_ENABLED = false -> no SharedArrayBuffer,
  no COOP/COEP headers needed. This is the iOS-Safari-compatible variant.
- Payload: index.wasm 35.9 MB raw -> 9.0 MB gzip (~7.5 MB brotli est. on
  Cloudflare). Game data (pck) is only 0.15 MB gzip - the engine dominates;
  adding Phase 1 content is nearly free, the ~9 MB floor is fixed.
- Platform harness `export/web/mic_test.html` (THROWAWAY - delete before the
  real deploy) validates the exact Sprint 16 primitives: getUserMedia ->
  AudioContext/ScriptProcessor -> 16-bit mono WAV (no MediaRecorder
  dependency; Safari only offers audio/mp4 there), gesture-gated playback,
  selfie -> 128x128 oval crop.
- Desktop Chrome results: all green. Oval crop 0.2 ms (target <50 ms).
- KEY FINDING: AudioContext sampleRate varies by device (96000 Hz observed on
  dev PC; phones typically 44.1/48k). DECISION: SoundBank canonical format is
  22050 Hz mono 16-bit WAV; capture resamples via OfflineAudioContext in the
  JS layer before crossing into Godot. ~430 KB per 10s clip (~575 KB base64).
- OPEN (blocked on device access): iPhone Safari test - iOS mic permission UX,
  real load time of ~9 MB on cellular, playback quirks, wasm boot time on
  older devices. Nothing on the current critical path depends on these.

### Camera nudge discipline (Sprint 14)
Automatic nudges are gated by `presentation/camera_nudge_policy.gd`:
suppressed within 3.0s of user camera input, min 8.0s between nudges (tunable
vars), and user input cancels a running nudge instead of snapping back.
