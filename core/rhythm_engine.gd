class_name RhythmEngine
extends RefCounted
## Global transport + step sequencer — the zoo's one conductor.
##
## Pure core: no scene tree, no clock. The caller passes absolute time into
## advance_to(); the engine answers with DATA in newly_triggered and
## presentation/rhythm_player.gd turns that into sound. Deliberately the same
## shape as InteractionEngine / InteractionPlayer.
##
## Why absolute time instead of accumulated delta: accumulated float delta
## drifts audibly over minutes, and a frame drop makes it fall permanently
## behind. Deriving the step index from (now - start) cannot drift, and a
## hitch becomes skip-and-recover.

## Fallbacks for when data/rhythm.json is missing a key. The authoritative
## values live in that file — these only keep a bare RhythmEngine.new() usable.
const DEFAULT_BPM := 90.0
const DEFAULT_STEPS_PER_LOOP := 8
const DEFAULT_VOICE_CAP := 6
## A rhythm voice may sound for this many steps before it is cut off. Longer
## recordings smear across the following beats and the loop stops being legible.
const DEFAULT_VOICE_LENGTH_STEPS := 2.0
const DEFAULT_PITCH_ROTATION := [0.0, 3.0, 5.0, 7.0, 12.0]
const DEFAULT_FALLBACK_PATTERN := [0]

## Guard rails, not balance: bpm 0 would divide by zero, and the pattern
## bitmask has to stay inside a safe int width.
const MIN_BPM := 20.0
const MAX_STEPS_PER_LOOP := 32

var bpm: float = DEFAULT_BPM
var steps_per_loop: int = DEFAULT_STEPS_PER_LOOP
var muted: bool = false
## Hard cap on simultaneous triggers per step — stops a 28-animal zoo from
## becoming a wall of noise.
var voice_cap: int = DEFAULT_VOICE_CAP
## Length cap for one voice, as a multiple of the step (see voice_length_seconds).
var voice_length_steps: float = DEFAULT_VOICE_LENGTH_STEPS

## Grid position the "closest to the camera" voice-cap tiebreak measures from.
## Presentation writes it; core only does arithmetic on it.
var focus_position: Vector2i = Vector2i.ZERO

## Refilled by every advance_to(): [{entity_id, step, pitch_scale}].
## pitch_scale is precomputed here so presentation never does the semitone math.
var newly_triggered: Array[Dictionary] = []

## Held by REFERENCE, so pattern edits in the Studio take effect on the next
## step without re-registering anything.
var _entities: Array = []

var _started := false
var _start_time := 0.0
var _now := 0.0
## Absolute (unwrapped) index of the last emitted step; -1 before the first one.
var _last_step := -1
## Step duration in force at the last advance_to, used to detect tempo changes.
var _last_step_duration := 60.0 / DEFAULT_BPM


## Applies data/rhythm.json. Missing keys keep the current value.
func configure(rhythm_config: Dictionary) -> void:
	bpm = float(rhythm_config.get("bpm", bpm))
	steps_per_loop = int(rhythm_config.get("steps_per_loop", steps_per_loop))
	voice_cap = int(rhythm_config.get("voice_cap", voice_cap))
	voice_length_steps = float(rhythm_config.get("voice_length_steps", voice_length_steps))


func set_entities(entities: Array) -> void:
	_entities = entities


## Quarter notes: one step per beat. bpm 90 -> 0.667s -> an 8-step loop of
## 5.33s, which fits the ~0.5-1.5s animal recordings without pile-up.
func step_duration() -> float:
	return 60.0 / maxf(bpm, MIN_BPM)


func loop_duration() -> float:
	return step_duration() * float(effective_steps())


## steps_per_loop clamped into the range the bitmask can actually represent.
func effective_steps() -> int:
	return clampi(steps_per_loop, 1, MAX_STEPS_PER_LOOP)


## How many seconds a single rhythm voice may sound. SoundResolver applies this
## ONCE, when it hands a sprite its stream — never per trigger, which would
## rebuild the WAV on every beat. It moves with the tempo, so changing the
## tempo means re-resolving every stream (main.gd does one sweep); a beat
## itself stays free.
func voice_length_seconds() -> float:
	return step_duration() * maxf(voice_length_steps, 0.0)


# --- Transport ---

## Advances the transport to absolute time `now` and fills newly_triggered
## with everything that fires in between. Emits ALL crossed steps in order —
## a beat is never silently dropped.
func advance_to(now: float) -> void:
	newly_triggered.clear()
	var sd := step_duration()

	if not _started:
		_started = true
		_start_time = now
		_last_step = -1
	elif not is_equal_approx(sd, _last_step_duration):
		# Tempo changed. Preserve the continuous position in STEP space so the
		# loop neither jumps nor repeats a beat — only the pace changes.
		var position_in_steps := (now - _start_time) / _last_step_duration
		_start_time = now - position_in_steps * sd
	_last_step_duration = sd
	_now = now

	var target := int(floor((now - _start_time) / sd))
	if target <= _last_step:
		return  # still inside the same step, or time went backwards

	# More than a whole loop missed (backgrounded tab, breakpoint): resync to
	# the present instead of firing a burst of stale beats.
	if target - _last_step > effective_steps():
		_last_step = target - 1

	var steps := effective_steps()
	for absolute_step in range(_last_step + 1, target + 1):
		_emit_step(posmod(absolute_step, steps))
	_last_step = target


func current_step() -> int:
	if not _started:
		return 0
	return posmod(_last_step, effective_steps())


## 0..1 through the current loop — for the Studio playhead and UI pulses.
func loop_progress() -> float:
	if not _started:
		return 0.0
	var loop := loop_duration()
	if loop <= 0.0:
		return 0.0
	return fposmod(_now - _start_time, loop) / loop


## Drops the transport back to "not started"; the next advance_to() puts the
## downbeat at whatever time it is given. Settings and entities are kept.
func reset() -> void:
	_started = false
	_last_step = -1
	_now = 0.0
	newly_triggered.clear()


# --- Sequencer ---

## Does this bitmask sing on this step? UNASSIGNED (-1) and 0 are both silent:
## an entity that never got a default has no part yet, and 0 is a deliberate
## "sings on no step".
static func plays_on(pattern: int, step: int) -> bool:
	if pattern <= 0:
		return false
	return (pattern >> step) & 1 == 1


static func pitch_scale_from_offset(semitones: float) -> float:
	return pow(2.0, semitones / 12.0)


func _emit_step(step: int) -> void:
	if muted:
		return  # the transport keeps running, so the playhead still sweeps
	for e in _select_voices(step):
		newly_triggered.append({
			"entity_id": e.id,
			"step": step,
			"pitch_scale": pitch_scale_from_offset(e.pitch_offset),
		})


## The entities singing on this step, already trimmed to the voice cap.
func _select_voices(step: int) -> Array:
	var candidates := _candidates_for(step)
	if candidates.size() > _effective_cap():
		candidates.sort_custom(_compare_voice_priority)
		candidates.resize(_effective_cap())

	var voices: Array = []
	for c in candidates:
		voices.append(c["entity"])
	return voices


## Entity ids that WANT to sing on this step but lose to the voice cap.
## The Studio grid marks these: the behaviour is correct (the tiebreak protects
## user-recorded voices) but a row that never makes a sound reads as a bug.
## Same candidates and same sort as _select_voices, so the marked rows are
## exactly the silent ones.
func capped_out_ids(step: int) -> Array[String]:
	var dropped: Array[String] = []
	var candidates := _candidates_for(step)
	var cap := _effective_cap()
	if candidates.size() <= cap:
		return dropped
	candidates.sort_custom(_compare_voice_priority)
	for i in range(cap, candidates.size()):
		dropped.append(candidates[i]["entity"].id)
	return dropped


## Everyone who wants this step, unsorted, in entity order.
func _candidates_for(step: int) -> Array:
	var candidates: Array = []
	for i in _entities.size():
		var e = _entities[i]
		if e == null or not e.in_song:
			continue
		if not plays_on(e.beat_pattern, step):
			continue
		candidates.append({"entity": e, "index": i})
	return candidates


## A cap of 0 would silently mute the whole zoo, which reads as a bug rather
## than a setting — one voice always gets through.
func _effective_cap() -> int:
	return maxi(voice_cap, 1)


## Cap priority: user-recorded voices first (those are the ones the player came
## for), then closest to the camera, then array order. A total order, so the
## same overloaded step always drops the same animals.
func _compare_voice_priority(a: Dictionary, b: Dictionary) -> bool:
	var a_recorded := 1 if a["entity"].sound_ref != "" else 0
	var b_recorded := 1 if b["entity"].sound_ref != "" else 0
	if a_recorded != b_recorded:
		return a_recorded > b_recorded
	var a_distance := _focus_distance(a["entity"])
	var b_distance := _focus_distance(b["entity"])
	if a_distance != b_distance:
		return a_distance < b_distance
	return a["index"] < b["index"]


func _focus_distance(e) -> int:
	return (e.grid_position - focus_position).length_squared()


# --- Default patterns (the "sounds good for free" rule) ---

## [0, 4] -> 0b00010001. Steps outside the bar wrap rather than vanish.
static func pattern_from_steps(steps: Array, steps_per_bar: int) -> int:
	var bar := clampi(steps_per_bar, 1, MAX_STEPS_PER_LOOP)
	var mask := 0
	for s in steps:
		mask |= 1 << posmod(int(s), bar)
	return mask


## Inverse of pattern_from_steps — for the Studio grid and for readable tests.
static func steps_from_pattern(pattern: int, steps_per_bar: int) -> Array[int]:
	var out: Array[int] = []
	if pattern <= 0:
		return out
	for step in clampi(steps_per_bar, 1, MAX_STEPS_PER_LOOP):
		if plays_on(pattern, step):
			out.append(step)
	return out


## Flips one step on or off — what a Studio cell tap does.
## An animal that never got a part starts from SILENCE, not from the sentinel:
## -1 already has every bit set, so toggling a step on it would otherwise make
## the animal sing on all eight. Tapping a cell is a deliberate assignment, so
## the sentinel is spent here.
static func toggle_step(pattern: int, step: int) -> int:
	var bar := MAX_STEPS_PER_LOOP
	if step < 0 or step >= bar:
		return pattern
	return maxi(pattern, 0) ^ (1 << step)


## Rotates a pattern later in the bar, wrapping around the end.
static func rotate_pattern(pattern: int, shift: int, steps_per_bar: int) -> int:
	# UNASSIGNED (-1) must stay UNASSIGNED: laundering it into 0 would turn
	# "never given a part" into "deliberately silent" and defeat the sentinel.
	if pattern <= 0:
		return pattern
	var bar := clampi(steps_per_bar, 1, MAX_STEPS_PER_LOOP)
	var by := posmod(shift, bar)
	var mask := 0
	for step in bar:
		if plays_on(pattern, step):
			mask |= 1 << posmod(step + by, bar)
	return mask


## The default part for the copy_index-th animal of this type. Copies rotate
## around the bar so a zoo full of chickens spreads across it instead of
## stacking on one beat.
static func default_pattern_for(type_id: String, copy_index: int, rhythm_config: Dictionary) -> int:
	var bar := int(rhythm_config.get("steps_per_loop", DEFAULT_STEPS_PER_LOOP))
	var patterns: Dictionary = rhythm_config.get("default_patterns", {})
	var steps: Array = patterns.get(type_id, rhythm_config.get("fallback_pattern", DEFAULT_FALLBACK_PATTERN))
	return rotate_pattern(pattern_from_steps(steps, bar), copy_index, bar)


## Duplicates also rotate through a small pentatonic set, so they land as a
## chord rather than as one very loud animal.
static func default_pitch_for(copy_index: int, rhythm_config: Dictionary) -> float:
	var rotation: Array = rhythm_config.get("pitch_rotation", DEFAULT_PITCH_ROTATION)
	if rotation.is_empty():
		return 0.0
	return float(rotation[posmod(copy_index, rotation.size())])


## Gives one entity its type default. See ZooState.apply_rhythm_defaults for
## the "who is the copy_index-th of its type" bookkeeping.
static func apply_defaults_to(entity, copy_index: int, rhythm_config: Dictionary) -> void:
	entity.beat_pattern = default_pattern_for(entity.type_id, copy_index, rhythm_config)
	entity.pitch_offset = default_pitch_for(copy_index, rhythm_config)


# --- Serialization ---

## PLAYER settings only (schema v3 "rhythm"). Tempo and mute are chosen in the
## game, so they belong in the save. steps_per_loop, voice_cap and
## voice_length_steps are CONFIG: they come from data/rhythm.json on every
## boot, so tuning that file is never defeated by an old save.
##
## The transport phase is runtime state either way — a loaded save puts its
## downbeat at the moment of the first advance_to().
func to_dict() -> Dictionary:
	return {
		"bpm": bpm,
		"muted": muted,
	}


## Missing keys keep the current value, same rule as configure(). That makes
## the boot order compose: configure(rhythm.json) first, then from_dict(save) —
## the save wins where it has an opinion and the config fills in the rest.
func from_dict(d: Dictionary) -> void:
	bpm = float(d.get("bpm", bpm))
	muted = bool(d.get("muted", muted))
