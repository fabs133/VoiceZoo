extends "res://tests/helpers/base_test.gd"
## Tests for RhythmEngine — transport, step sequencer, default patterns.
## Time is always supplied by the test; the engine never reads a clock.

const RE = preload("res://core/rhythm_engine.gd")

## Stand-in for data/rhythm.json.
const CFG := {
	"bpm": 90.0,
	"steps_per_loop": 8,
	"voice_cap": 6,
	"voice_length_steps": 2.0,
	"pitch_rotation": [0.0, 3.0, 5.0, 7.0, 12.0],
	"default_patterns": {
		"chicken": [0, 4],
		"dog": [2],
		"parrot": [1, 5],
	},
	"fallback_pattern": [0],
}

## Sings on every step of an 8-step bar — makes "did a step fire?" a size check.
const EVERY_STEP := 255

var _engine: RefCounted


func before_each() -> void:
	_engine = RE.new()


# --- Construction / configuration ---

func test_new_engine_defaults() -> void:
	assert_almost_eq(_engine.bpm, 90.0, 0.001, "default bpm 90")
	assert_eq(_engine.steps_per_loop, 8, "default 8 steps")
	assert_false(_engine.muted, "not muted")
	assert_eq(_engine.voice_cap, 6, "default voice cap 6")
	assert_eq(_engine.current_step(), 0, "starts at step 0")
	assert_almost_eq(_engine.loop_progress(), 0.0, 0.001, "no progress before start")
	assert_eq(_engine.newly_triggered.size(), 0, "nothing triggered yet")


func test_step_and_loop_duration() -> void:
	assert_almost_eq(_engine.step_duration(), 0.6667, 0.001, "90 bpm = 0.667s per step")
	assert_almost_eq(_engine.loop_duration(), 5.3333, 0.001, "8 steps = 5.33s loop")


func test_configure_reads_json_shape() -> void:
	_engine.configure(CFG)
	assert_almost_eq(_engine.bpm, 90.0, 0.001, "bpm from config")
	assert_eq(_engine.steps_per_loop, 8, "steps from config")
	assert_eq(_engine.voice_cap, 6, "voice cap from config")


func test_voice_length_follows_the_tempo() -> void:
	_engine.configure(CFG)  # 90 bpm, two steps per voice
	assert_almost_eq(_engine.voice_length_seconds(), 1.3333, 0.001, "two steps at 90 bpm")
	_engine.bpm = 45.0
	assert_almost_eq(_engine.voice_length_seconds(), 2.6667, 0.001, "half the tempo, twice the voice")


func test_voice_length_steps_is_configurable() -> void:
	_engine.configure({"bpm": 120.0, "voice_length_steps": 1.0})
	assert_almost_eq(_engine.voice_length_seconds(), 0.5, 0.001, "one step at 120 bpm")
	_engine.configure({"voice_length_steps": 0.0})
	assert_almost_eq(_engine.voice_length_seconds(), 0.0, 0.001, "zero disables the cap downstream")


func test_configure_keeps_current_value_for_missing_keys() -> void:
	_engine.bpm = 110.0
	_engine.configure({"voice_cap": 2})
	assert_almost_eq(_engine.bpm, 110.0, 0.001, "bpm untouched by partial config")
	assert_eq(_engine.voice_cap, 2, "voice cap applied")


func test_zero_bpm_cannot_divide_by_zero() -> void:
	_engine.bpm = 0.0
	assert_gt(_engine.step_duration(), 0.0, "step duration stays positive")


func test_steps_per_loop_clamped() -> void:
	_engine.steps_per_loop = 0
	assert_eq(_engine.effective_steps(), 1, "at least one step")
	_engine.steps_per_loop = 999
	assert_eq(_engine.effective_steps(), RE.MAX_STEPS_PER_LOOP, "clamped to bitmask width")


# --- Transport ---

func test_first_advance_emits_the_downbeat() -> void:
	_engine.set_entities(_singers(1))
	_engine.advance_to(1234.5)
	assert_eq(_engine.newly_triggered.size(), 1, "downbeat fires on the first advance")
	assert_eq(_engine.newly_triggered[0]["step"], 0, "and it is step 0")
	assert_eq(_engine.current_step(), 0, "transport sits on step 0")


func test_advance_within_the_same_step_emits_nothing() -> void:
	_engine.set_entities(_singers(1))
	_engine.advance_to(0.0)
	_engine.advance_to(_engine.step_duration() * 0.9)
	assert_eq(_engine.newly_triggered.size(), 0, "no second trigger inside one step")
	assert_eq(_engine.current_step(), 0, "still step 0")


func test_consecutive_steps_arrive_in_order() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	var seen: Array[int] = []
	for i in range(1, 5):
		_engine.advance_to(sd * (float(i) + 0.1))
		assert_eq(_engine.newly_triggered.size(), 1, "exactly one step per frame")
		seen.append(_engine.newly_triggered[0]["step"])
	assert_eq(seen, [1, 2, 3, 4] as Array[int], "steps 1..4 in order")


func test_multi_step_catchup_emits_all_crossed_steps() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	# One long frame spanning three step boundaries.
	_engine.advance_to(sd * 3.4)
	assert_eq(_engine.newly_triggered.size(), 3, "no beat silently dropped")
	assert_eq(_engine.newly_triggered[0]["step"], 1, "first crossed step")
	assert_eq(_engine.newly_triggered[1]["step"], 2, "second crossed step")
	assert_eq(_engine.newly_triggered[2]["step"], 3, "third crossed step")
	assert_eq(_engine.current_step(), 3, "transport ends on step 3")


func test_step_index_wraps_at_the_end_of_the_loop() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	_engine.advance_to(sd * 8.2)
	assert_eq(_engine.newly_triggered.size(), 8, "a full loop of steps crossed")
	assert_eq(_engine.newly_triggered[7]["step"], 0, "step 8 wraps back to 0")
	assert_eq(_engine.current_step(), 0, "loop wrapped")


func test_exactly_one_missed_loop_still_emits_every_step() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	_engine.advance_to(sd * 8.9)
	assert_eq(_engine.newly_triggered.size(), 8, "one whole loop is caught up, not resynced")
	assert_eq(_engine.newly_triggered[0]["step"], 1, "starting at the step after the downbeat")


func test_one_step_past_a_full_loop_resyncs() -> void:
	# The exact boundary of the catch-up rule: 8 pending steps are played,
	# 9 are too stale to be worth hearing.
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	_engine.advance_to(sd * 9.1)
	assert_eq(_engine.newly_triggered.size(), 1, "resync instead of a burst")
	assert_eq(_engine.newly_triggered[0]["step"], 1, "step 9 % 8 = 1")


func test_more_than_one_missed_loop_resyncs() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	# Backgrounded tab: 100 loops go by.
	_engine.advance_to(sd * 800.5)
	assert_eq(_engine.newly_triggered.size(), 1, "resync fires only the current step")
	assert_eq(_engine.newly_triggered[0]["step"], 0, "which is step 800 % 8 = 0")
	assert_eq(_engine.current_step(), 0, "transport is at the present, not in the past")


func test_resync_keeps_the_phase_of_the_wall_clock() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	_engine.advance_to(sd * 803.5)
	assert_eq(_engine.current_step(), 3, "step 803 % 8 = 3")
	_engine.advance_to(sd * 804.5)
	assert_eq(_engine.newly_triggered.size(), 1, "normal stepping resumes after resync")
	assert_eq(_engine.current_step(), 4, "and continues at 4")


func test_time_going_backwards_emits_nothing() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(100.0)
	_engine.advance_to(100.0 + sd * 2.5)
	_engine.advance_to(100.0)
	assert_eq(_engine.newly_triggered.size(), 0, "no triggers when time moves backwards")
	assert_eq(_engine.current_step(), 2, "transport holds its position")


func test_no_drift_over_ten_simulated_minutes() -> void:
	# bpm 120 -> 0.5s per step, exactly representable in binary, so the
	# expected step count is exact rather than "about right".
	_engine.bpm = 120.0
	_engine.set_entities(_singers(1))
	var start := 1000.0
	_engine.advance_to(start)
	var emitted: int = _engine.newly_triggered.size()
	var expected_step := 0
	var order_ok := true
	# 10 minutes at 60fps, absolute time derived from a frame counter.
	for frame in range(1, 36001):
		_engine.advance_to(start + float(frame) / 60.0)
		for t in _engine.newly_triggered:
			expected_step = posmod(expected_step + 1, 8)
			if t["step"] != expected_step:
				order_ok = false
			emitted += 1
	assert_true(order_ok, "steps arrive in unbroken 0..7 order for 10 minutes")
	assert_eq(emitted, 1201, "600s at 0.5s/step = steps 0..1200 inclusive")
	assert_eq(_engine.current_step(), 0, "1200 % 8 = 0 exactly, no drift")


func test_loop_progress_tracks_position_in_the_bar() -> void:
	_engine.set_entities(_singers(1))
	var loop: float = _engine.loop_duration()
	_engine.advance_to(50.0)
	assert_almost_eq(_engine.loop_progress(), 0.0, 0.001, "downbeat is 0.0")
	_engine.advance_to(50.0 + loop * 0.25)
	assert_almost_eq(_engine.loop_progress(), 0.25, 0.001, "a quarter through the bar")
	_engine.advance_to(50.0 + loop * 1.5)
	assert_almost_eq(_engine.loop_progress(), 0.5, 0.001, "wraps at the loop boundary")


func test_tempo_change_keeps_the_loop_continuous() -> void:
	_engine.set_entities(_singers(1))
	var old_sd: float = _engine.step_duration()
	var change_time: float = 100.0 + old_sd * 1.5
	_engine.advance_to(100.0)
	_engine.advance_to(change_time)
	assert_eq(_engine.current_step(), 1, "on step 1, half a step in")

	_engine.bpm = 45.0  # half speed
	var new_sd: float = _engine.step_duration()
	_engine.advance_to(change_time)
	assert_eq(_engine.newly_triggered.size(), 0, "changing tempo alone emits nothing")
	assert_eq(_engine.current_step(), 1, "and does not jump the transport")

	# The remaining half step now takes half of the NEW step duration.
	_engine.advance_to(change_time + new_sd * 0.49)
	assert_eq(_engine.newly_triggered.size(), 0, "boundary not reached yet")
	_engine.advance_to(change_time + new_sd * 0.51)
	assert_eq(_engine.newly_triggered.size(), 1, "one step crossed, none skipped")
	assert_eq(_engine.current_step(), 2, "the next step is 2")


func test_reset_restarts_the_transport() -> void:
	_engine.set_entities(_singers(1))
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	_engine.advance_to(sd * 3.0)
	assert_eq(_engine.current_step(), 3, "advanced to step 3")
	_engine.reset()
	assert_eq(_engine.current_step(), 0, "reset returns to step 0")
	_engine.advance_to(9999.0)
	assert_eq(_engine.newly_triggered.size(), 1, "next advance is a fresh downbeat")
	assert_eq(_engine.newly_triggered[0]["step"], 0, "at step 0")


# --- Sequencer ---

func test_only_entities_on_this_step_trigger() -> void:
	var list: Array[EntityData] = []
	list.append(_entity("a", "chicken", RE.pattern_from_steps([0, 4], 8)))
	list.append(_entity("b", "dog", RE.pattern_from_steps([2], 8)))
	_engine.set_entities(list)
	var sd: float = _engine.step_duration()

	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 1, "only the chicken on step 0")
	assert_eq(_engine.newly_triggered[0]["entity_id"], "a", "chicken sings the pulse")

	_engine.advance_to(sd * 2.1)
	assert_eq(_engine.newly_triggered.size(), 1, "only the dog on step 2")
	assert_eq(_engine.newly_triggered[0]["entity_id"], "b", "dog answers offbeat")

	_engine.advance_to(sd * 4.1)
	assert_eq(_engine.newly_triggered[0]["entity_id"], "a", "chicken again on step 4")


func test_parked_entity_is_silent() -> void:
	var list: Array[EntityData] = []
	var e := _entity("a", "chicken", EVERY_STEP)
	e.in_song = false
	list.append(e)
	_engine.set_entities(list)
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 0, "in_song = false parks the animal")


func test_unassigned_pattern_is_silent() -> void:
	var list: Array[EntityData] = []
	list.append(_entity("a", "chicken", EntityData.UNASSIGNED_PATTERN))
	_engine.set_entities(list)
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 0, "an animal with no part yet stays quiet")


func test_empty_pattern_is_silent() -> void:
	var list: Array[EntityData] = []
	list.append(_entity("a", "chicken", 0))
	_engine.set_entities(list)
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 0, "a cleared row sings on no step")


func test_muted_emits_nothing_but_the_transport_runs() -> void:
	_engine.set_entities(_singers(1))
	_engine.muted = true
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	_engine.advance_to(sd * 3.1)
	assert_eq(_engine.newly_triggered.size(), 0, "muted = no triggers")
	assert_eq(_engine.current_step(), 3, "but the playhead keeps sweeping")
	_engine.muted = false
	_engine.advance_to(sd * 4.1)
	assert_eq(_engine.newly_triggered.size(), 1, "unmuting resumes in place")


func test_trigger_carries_pitch_scale() -> void:
	var list: Array[EntityData] = []
	var high := _entity("a", "chicken", 1)
	high.pitch_offset = 12.0
	var low := _entity("b", "dog", 1)
	low.pitch_offset = -12.0
	list.append(high)
	list.append(low)
	_engine.set_entities(list)
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 2, "both sing on step 0")
	assert_almost_eq(_engine.newly_triggered[0]["pitch_scale"], 2.0, 0.0001, "+12 semitones = 2x")
	assert_almost_eq(_engine.newly_triggered[1]["pitch_scale"], 0.5, 0.0001, "-12 semitones = 0.5x")


func test_pattern_edits_take_effect_without_re_registering() -> void:
	var list: Array[EntityData] = []
	var e := _entity("a", "chicken", 0)
	list.append(e)
	_engine.set_entities(list)
	var sd: float = _engine.step_duration()
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 0, "silent to start with")
	e.beat_pattern = RE.pattern_from_steps([1], 8)  # Studio tap
	_engine.advance_to(sd * 1.1)
	assert_eq(_engine.newly_triggered.size(), 1, "the edit plays on the next step")


# --- Voice cap ---

func test_voice_cap_limits_simultaneous_triggers() -> void:
	_engine.voice_cap = 3
	_engine.set_entities(_singers(10))
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 3, "28-animal wall of noise is capped")


func test_under_the_cap_everyone_sings() -> void:
	_engine.voice_cap = 6
	_engine.set_entities(_singers(4))
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 4, "no trimming below the cap")


func test_voice_cap_prefers_recorded_voices() -> void:
	_engine.voice_cap = 2
	var list := _singers(10)
	list[7].sound_ref = "snd_1"
	list[9].sound_ref = "snd_2"
	_engine.set_entities(list)
	_engine.advance_to(0.0)
	var ids := _triggered_ids()
	assert_eq(ids.size(), 2, "capped at 2")
	assert_true(ids.has("7"), "recorded animal 7 survives the cap")
	assert_true(ids.has("9"), "recorded animal 9 survives the cap")


func test_voice_cap_then_prefers_closest_to_focus() -> void:
	_engine.voice_cap = 2
	_engine.focus_position = Vector2i(9, 0)
	_engine.set_entities(_singers(10))  # laid out along x = 0..9
	_engine.advance_to(0.0)
	var ids := _triggered_ids()
	assert_true(ids.has("9"), "nearest animal kept")
	assert_true(ids.has("8"), "second nearest kept")


func test_voice_cap_selection_is_deterministic() -> void:
	_engine.voice_cap = 3
	_engine.set_entities(_singers(10))
	_engine.advance_to(0.0)
	var first := _triggered_ids()
	var second_engine = RE.new()
	second_engine.voice_cap = 3
	second_engine.set_entities(_singers(10))
	second_engine.advance_to(555.0)
	var second: Array[String] = []
	for t in second_engine.newly_triggered:
		second.append(t["entity_id"])
	assert_eq(first, second, "the same overloaded step drops the same animals")


func test_capped_out_ids_is_empty_under_the_cap() -> void:
	_engine.voice_cap = 6
	_engine.set_entities(_singers(4))
	assert_eq(_engine.capped_out_ids(0).size(), 0, "nobody is dropped below the cap")


func test_capped_out_ids_names_the_dropped_animals() -> void:
	# Section 3b: the Studio marks these rows, so they must be exactly the ones
	# _select_voices leaves out - same candidates, same sort.
	_engine.voice_cap = 3
	_engine.set_entities(_singers(10))
	_engine.advance_to(0.0)

	var playing: Array[String] = []
	for t in _engine.newly_triggered:
		playing.append(t["entity_id"])
	var dropped: Array[String] = _engine.capped_out_ids(0)

	assert_eq(dropped.size(), 7, "ten want the step, three get it")
	for id in playing:
		assert_false(dropped.has(id), "no animal is both playing and marked dropped")


func test_capped_out_ids_never_drops_a_recorded_voice() -> void:
	_engine.voice_cap = 1
	var list := _singers(5)
	list[3].sound_ref = "snd_1"
	_engine.set_entities(list)
	var dropped: Array[String] = _engine.capped_out_ids(0)
	assert_eq(dropped.size(), 4, "one voice survives")
	assert_false(dropped.has("3"), "and it is the recorded one")


func test_capped_out_ids_ignores_parked_animals() -> void:
	_engine.voice_cap = 1
	var list := _singers(3)
	list[0].in_song = false
	_engine.set_entities(list)
	var dropped: Array[String] = _engine.capped_out_ids(0)
	assert_eq(dropped.size(), 1, "two candidates, one cap slot, one dropped")
	assert_false(dropped.has("0"), "a parked animal is not 'drowned out', it is switched off")


func test_voice_cap_of_zero_still_plays_one() -> void:
	_engine.voice_cap = 0
	_engine.set_entities(_singers(5))
	_engine.advance_to(0.0)
	assert_eq(_engine.newly_triggered.size(), 1, "a cap of 0 must not mute the zoo")


# --- Pattern helpers ---

func test_pattern_from_steps() -> void:
	assert_eq(RE.pattern_from_steps([0, 4], 8), 0b00010001, "chicken pulse mask")
	assert_eq(RE.pattern_from_steps([2], 8), 0b00000100, "dog offbeat mask")
	assert_eq(RE.pattern_from_steps([], 8), 0, "no steps = silent mask")


func test_pattern_from_steps_wraps_out_of_range_steps() -> void:
	assert_eq(RE.pattern_from_steps([9], 8), 0b00000010, "step 9 wraps to 1 in an 8-step bar")


func test_steps_from_pattern_roundtrips() -> void:
	var mask := RE.pattern_from_steps([1, 5], 8)
	assert_eq(RE.steps_from_pattern(mask, 8), [1, 5] as Array[int], "mask -> steps")
	assert_eq(RE.steps_from_pattern(0, 8), [] as Array[int], "empty mask")
	assert_eq(RE.steps_from_pattern(EntityData.UNASSIGNED_PATTERN, 8), [] as Array[int], "sentinel is not all-steps")


func test_plays_on() -> void:
	var mask := RE.pattern_from_steps([0, 4], 8)
	assert_true(RE.plays_on(mask, 0), "sings on 0")
	assert_false(RE.plays_on(mask, 1), "silent on 1")
	assert_true(RE.plays_on(mask, 4), "sings on 4")
	assert_false(RE.plays_on(EntityData.UNASSIGNED_PATTERN, 3), "sentinel never sings")


func test_rotate_pattern_wraps_around_the_bar() -> void:
	var mask := RE.pattern_from_steps([0, 4], 8)
	assert_eq(RE.rotate_pattern(mask, 1, 8), RE.pattern_from_steps([1, 5], 8), "rotate by 1")
	assert_eq(RE.rotate_pattern(mask, 5, 8), RE.pattern_from_steps([1, 5], 8), "5 wraps past the end")
	assert_eq(RE.rotate_pattern(mask, 8, 8), mask, "a full bar of rotation is identity")
	assert_eq(RE.rotate_pattern(0, 3, 8), 0, "rotating silence stays silent")


func test_toggle_step_turns_a_step_on_and_off() -> void:
	var mask := RE.pattern_from_steps([0, 4], 8)
	var with_two := RE.toggle_step(mask, 2)
	assert_eq(RE.steps_from_pattern(with_two, 8), [0, 2, 4] as Array[int], "step 2 added")
	assert_eq(RE.steps_from_pattern(RE.toggle_step(with_two, 2), 8), [0, 4] as Array[int], "and removed again")


func test_toggle_step_spends_the_unassigned_sentinel() -> void:
	# -1 has every bit set: toggling a step on it must NOT mean "sings on all
	# eight". Tapping a cell is a deliberate assignment, so it starts at silence.
	var toggled := RE.toggle_step(EntityData.UNASSIGNED_PATTERN, 3)
	assert_eq(RE.steps_from_pattern(toggled, 8), [3] as Array[int], "exactly the tapped step")


func test_toggle_step_ignores_a_step_outside_the_bitmask() -> void:
	var mask := RE.pattern_from_steps([1], 8)
	assert_eq(RE.toggle_step(mask, -1), mask, "negative step changes nothing")
	assert_eq(RE.toggle_step(mask, 99), mask, "and neither does one past the mask width")


func test_pitch_scale_from_offset() -> void:
	assert_almost_eq(RE.pitch_scale_from_offset(0.0), 1.0, 0.0001, "0 semitones = unchanged")
	assert_almost_eq(RE.pitch_scale_from_offset(12.0), 2.0, 0.0001, "an octave up")
	assert_almost_eq(RE.pitch_scale_from_offset(7.0), 1.4983, 0.001, "a fifth up")


# --- Defaults from data/rhythm.json ---

func test_default_pattern_per_type() -> void:
	assert_eq(RE.default_pattern_for("chicken", 0, CFG), RE.pattern_from_steps([0, 4], 8), "chicken is the pulse")
	assert_eq(RE.default_pattern_for("dog", 0, CFG), RE.pattern_from_steps([2], 8), "dog answers offbeat")
	assert_eq(RE.default_pattern_for("parrot", 0, CFG), RE.pattern_from_steps([1, 5], 8), "parrot fills 1 and 5")


func test_default_pattern_of_first_two_types_is_a_two_part_groove() -> void:
	# The demo song: chicken and dog must not collide before any recording.
	var chicken := RE.default_pattern_for("chicken", 0, CFG)
	var dog := RE.default_pattern_for("dog", 0, CFG)
	assert_eq(chicken & dog, 0, "the starter pair never lands on the same step")


func test_duplicate_copies_rotate_around_the_bar() -> void:
	var first := RE.default_pattern_for("chicken", 0, CFG)
	var second := RE.default_pattern_for("chicken", 1, CFG)
	var third := RE.default_pattern_for("chicken", 2, CFG)
	assert_eq(second, RE.pattern_from_steps([1, 5], 8), "second chicken shifts one step")
	assert_eq(third, RE.pattern_from_steps([2, 6], 8), "third chicken shifts two")
	assert_eq(first & second, 0, "duplicates spread instead of stacking")


func test_ninth_copy_wraps_back_to_the_first_pattern() -> void:
	assert_eq(
		RE.default_pattern_for("chicken", 8, CFG),
		RE.default_pattern_for("chicken", 0, CFG),
		"rotation wraps after a full bar"
	)


func test_unknown_type_uses_the_fallback_pattern() -> void:
	assert_eq(RE.default_pattern_for("dragon", 0, CFG), RE.pattern_from_steps([0], 8), "unknown type lands on the downbeat")


func test_default_pattern_with_empty_config() -> void:
	assert_eq(RE.default_pattern_for("chicken", 0, {}), RE.pattern_from_steps([0], 8), "no config still yields a playable part")


func test_default_pitch_rotates_over_a_pentatonic_set() -> void:
	assert_almost_eq(RE.default_pitch_for(0, CFG), 0.0, 0.001, "first copy at concert pitch")
	assert_almost_eq(RE.default_pitch_for(1, CFG), 3.0, 0.001, "second copy a minor third up")
	assert_almost_eq(RE.default_pitch_for(4, CFG), 12.0, 0.001, "fifth copy an octave up")
	assert_almost_eq(RE.default_pitch_for(5, CFG), 0.0, 0.001, "the set wraps")


func test_apply_defaults_to_sets_both_fields() -> void:
	var e := _entity("a", "chicken", EntityData.UNASSIGNED_PATTERN)
	RE.apply_defaults_to(e, 1, CFG)
	assert_eq(e.beat_pattern, RE.pattern_from_steps([1, 5], 8), "pattern assigned and rotated")
	assert_almost_eq(e.pitch_offset, 3.0, 0.001, "pitch assigned from the rotation")


# --- data/rhythm.json contract (the real file, not a fixture) ---

func _rhythm_json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/rhythm.json"))


func test_tempo_presets_are_five_coarse_steps() -> void:
	# Decision 8.3: presets, never a free slider. Five of them since R4.5.
	var presets: Array = _rhythm_json().get("tempo_presets", [])
	assert_eq(presets.size(), 5, "five presets")
	var bpms: Array = []
	for p in presets:
		bpms.append(float(p["bpm"]))
	assert_eq(bpms, [60.0, 75.0, 90.0, 105.0, 120.0], "60 to 120 in even 15 bpm steps")


func test_tempo_presets_are_labelled_in_german() -> void:
	var labels: Array = []
	for p in _rhythm_json().get("tempo_presets", []):
		labels.append(str(p["label"]))
		assert_true(str(p["label"]).strip_edges() != "", "every preset has a label for its button")
	assert_true(labels.has("Gemütlich"), "and the umlauts survived the file")


func test_tempo_presets_are_all_playable() -> void:
	var engine = RE.new()
	for p in _rhythm_json().get("tempo_presets", []):
		engine.bpm = float(p["bpm"])
		assert_gt(engine.bpm, RE.MIN_BPM, "%s is above the engine floor" % p["id"])
		assert_gt(engine.voice_length_seconds(), 0.0, "%s yields a usable voice length" % p["id"])


func test_the_boot_tempo_is_one_of_the_presets() -> void:
	# Otherwise the tempo control boots with no button matching the tempo.
	var cfg := _rhythm_json()
	var bpms: Array = []
	for p in cfg["tempo_presets"]:
		bpms.append(float(p["bpm"]))
	assert_true(bpms.has(float(cfg["bpm"])), "the default bpm is selectable")


# --- Serialization ---

func test_player_settings_roundtrip() -> void:
	_engine.bpm = 110.0
	_engine.muted = true

	var restored = RE.new()
	restored.from_dict(_engine.to_dict())

	assert_almost_eq(restored.bpm, 110.0, 0.001, "tempo preserved")
	assert_true(restored.muted, "mute preserved")


func test_config_values_are_not_saved() -> void:
	# The loop shape and the caps come from rhythm.json on every boot. If an
	# old save pinned them, tuning that file would do nothing for the couple.
	_engine.configure(CFG)
	var saved: Dictionary = _engine.to_dict()
	assert_false(saved.has("steps_per_loop"), "loop shape is config, not save data")
	assert_false(saved.has("voice_cap"), "voice cap is config, not save data")

	var retuned = RE.new()
	retuned.configure({"steps_per_loop": 16, "voice_cap": 9, "voice_length_steps": 1.5})
	retuned.from_dict(saved)
	assert_eq(retuned.steps_per_loop, 16, "a retuned loop shape survives an old save")
	assert_eq(retuned.voice_cap, 9, "so does a retuned voice cap")
	assert_almost_eq(retuned.voice_length_steps, 1.5, 0.001, "and the retuned length cap")


func test_from_dict_missing_keys_keep_current_values() -> void:
	_engine.configure({"bpm": 75.0})
	_engine.from_dict({})
	assert_almost_eq(_engine.bpm, 75.0, 0.001, "a save with no opinion keeps the configured tempo")
	assert_false(_engine.muted, "and the current mute state")


func test_transport_phase_is_not_persisted() -> void:
	_engine.set_entities(_singers(1))
	_engine.advance_to(_engine.step_duration() * 5.0)
	var restored = RE.new()
	restored.from_dict(_engine.to_dict())
	assert_eq(restored.current_step(), 0, "a loaded save starts its own downbeat")


# --- Helpers ---

func _entity(id: String, type_id: String, pattern: int, pos := Vector2i.ZERO) -> EntityData:
	var e = EntityData.new()
	e.id = id
	e.type_id = type_id
	e.grid_position = pos
	e.beat_pattern = pattern
	return e


## n animals that all sing on every step, laid out along x = 0..n-1.
func _singers(n: int) -> Array[EntityData]:
	var list: Array[EntityData] = []
	for i in n:
		list.append(_entity(str(i), "chicken", EVERY_STEP, Vector2i(i, 0)))
	return list


func _triggered_ids() -> Array[String]:
	var ids: Array[String] = []
	for t in _engine.newly_triggered:
		ids.append(t["entity_id"])
	return ids
