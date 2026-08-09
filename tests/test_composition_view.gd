extends "res://tests/helpers/base_test.gd"
## Tests for CompositionView - the Studio grid (plan section 3b).
##
## Two halves: the pure static rules (layout budget, row order, cap marking),
## and REAL integration coverage - the view is instantiated in the runner's
## scene tree and driven through its actual buttons, so a mis-bound signal is
## caught here rather than by a human tapping the screen.

const ViewScript = preload("res://presentation/ui/composition_view.gd")
const RE = preload("res://core/rhythm_engine.gd")

## Stand-in for data/rhythm.json.
const RHYTHM_CFG := {
	"bpm": 90.0,
	"steps_per_loop": 8,
	"voice_cap": 6,
	"voice_length_steps": 2.0,
	"pitch_rotation": [0.0, 3.0, 5.0, 7.0, 12.0],
	"default_patterns": {"chicken": [0, 4], "dog": [2], "cat": [6]},
	"fallback_pattern": [0],
}

var _state: ZooState
var _player: MockRhythmPlayer
var _config: MockConfig
var _view


func before_each() -> void:
	_state = ZooState.new()
	_state.rhythm.configure(RHYTHM_CFG)
	_player = MockRhythmPlayer.new()
	_config = MockConfig.new()
	_view = ViewScript.new()
	# Built detached: the runner has no scene tree to add to, so _ready never
	# fires and build() is called directly. Everything below then drives the
	# real buttons through their real signals.
	_view.build()
	_view.setup(_state, _player, _config)


func after_each() -> void:
	# Freed here, not at the end of the file: leaking Node mocks across a whole
	# suite is exactly what bit test_audio_recorder.
	if _view != null and is_instance_valid(_view):
		_view.free()
	_view = null


func _add(type_id: String, id_hint: String = "") -> EntityData:
	var e = _state.add_entity(type_id, Vector2i(_state.entities.size(), 0))
	_state.apply_rhythm_defaults(RHYTHM_CFG)
	if id_hint != "":
		e.id = id_hint
	return e


# --- Space budget (section 3b) ---

func test_cells_clear_the_touch_minimum_at_eight_steps() -> void:
	var width := ViewScript.cell_width_for(1080.0, 8)
	assert_gt(width, ViewScript.MIN_TOUCH_SIZE, "8 cells fit above the 88px touch minimum")
	assert_lt(width, 120.0, "and the budget is not wildly generous either")


func test_sixteen_steps_would_break_the_touch_minimum() -> void:
	# The reason V1 is one 8-step bar. If this ever passes, the grid needs
	# horizontal scrolling or landscape before steps_per_loop can be raised.
	assert_lt(ViewScript.cell_width_for(1080.0, 16), ViewScript.MIN_TOUCH_SIZE, "16 cells do not fit in portrait")


# --- Row order ---

func test_recorded_animals_sort_first() -> void:
	var plain = _add("chicken")
	var recorded = _add("chicken")
	recorded.sound_ref = "snd_1"
	var rows = ViewScript.sort_rows(_state.entities)
	assert_eq(rows[0].id, recorded.id, "the animal with a voice is on top")
	assert_eq(rows[1].id, plain.id, "the placeholder one is below it")


func test_sort_falls_back_to_type_then_numeric_id() -> void:
	var dog = _add("dog")
	var chicken_ten = _add("chicken")
	chicken_ten.id = "10"
	var chicken_two = _add("chicken")
	chicken_two.id = "2"
	var rows = ViewScript.sort_rows(_state.entities)
	assert_eq(rows[0].type_id, "chicken", "chicken sorts before dog")
	assert_eq(rows[0].id, "2", "id 2 before id 10 - numeric, not lexicographic")
	assert_eq(rows[1].id, "10", "then 10")
	assert_eq(rows[2].id, dog.id, "dog last")


# --- Row identity (section 3b, added after the R4 listen test) ---

func test_ordinals_count_within_each_type() -> void:
	_add("chicken")
	_add("dog")
	_add("chicken")
	var ordinals := ViewScript.ordinals_by_id(_state.entities)
	assert_eq(ordinals[_state.entities[0].id], 1, "first chicken is 1")
	assert_eq(ordinals[_state.entities[1].id], 1, "the dog counts on its own")
	assert_eq(ordinals[_state.entities[2].id], 2, "second chicken is 2")


func test_row_label_without_a_recording_is_name_plus_ordinal() -> void:
	var e = _add("chicken")
	assert_eq(ViewScript.row_label(e, 3, "Huhn", ""), "Huhn 3", "the third chicken says so")


func test_row_label_prefers_the_sounds_own_label() -> void:
	var e = _add("chicken")
	e.sound_ref = "snd_1"
	assert_eq(ViewScript.row_label(e, 3, "Huhn", "Opas Lachen"), "Opas Lachen", "the recording names the row")


func test_row_label_falls_back_when_the_sound_has_no_label() -> void:
	var e = _add("chicken")
	e.sound_ref = "snd_1"
	assert_eq(ViewScript.row_label(e, 2, "Huhn", "   "), "Huhn 2", "a blank label is not an identity")


func test_display_name_is_the_ordinal_form() -> void:
	_add("chicken")
	var second = _add("chicken")
	assert_eq(ViewScript.display_name(second, _state.entities, "Huhn"), "Huhn 2", "what the record dialog is told")


func test_every_row_of_the_same_type_is_distinguishable() -> void:
	# The ACCEPTS for this subsection, in miniature.
	for i in 5:
		_add("chicken")
	_view.open()
	var seen := {}
	for row in _view._rows:
		var text: String = row["label_button"].text
		assert_false(seen.has(text), "row label '%s' is unique" % text)
		seen[text] = true


func test_a_recorded_row_shows_its_sound_label() -> void:
	var e = _add("chicken")
	var pcm := PackedByteArray()
	pcm.resize(200)
	e.sound_ref = _state.sound_bank.add_sound(WavUtils.build_wav(pcm, 22050, 1), "Opas Lachen")
	_view.open()
	assert_eq(_view._rows[0]["label_button"].text, "Opas Lachen", "the row is named by its recording")
	assert_eq(_view._rows[0]["label_button"].tooltip_text, "Opas Lachen", "and the full text is on the tooltip")


func test_unique_labels_numbers_a_colliding_group() -> void:
	# Two guests both recording "Wuff" is the expected case, not the odd one.
	var out := ViewScript.unique_labels(["Wuff", "Muh", "Wuff"], [1, 1, 2])
	assert_eq(out, ["Wuff 1", "Muh", "Wuff 2"], "both Wuffs numbered, Muh untouched")


func test_unique_labels_guarantees_uniqueness_even_when_numbering_collides() -> void:
	# A hand-typed label can equal another row's numbered form.
	var out := ViewScript.unique_labels(["Wuff", "Wuff", "Wuff 1"], [1, 2, 1])
	var seen := {}
	for label in out:
		assert_false(seen.has(label), "'%s' appears once" % label)
		seen[label] = true


func test_two_animals_sharing_a_sound_label_stay_distinguishable() -> void:
	# What a pre-R4.5 save looks like: several rows reading "Sound fuer Katze".
	var pcm := PackedByteArray()
	pcm.resize(200)
	var wav := WavUtils.build_wav(pcm, 22050, 1)
	var first = _add("cat")
	var second = _add("cat")
	first.sound_ref = _state.sound_bank.add_sound(wav, "Sound fuer Katze")
	second.sound_ref = _state.sound_bank.add_sound(wav, "Sound fuer Katze")
	_view.open()
	var a: String = _view._rows[0]["label_button"].text
	var b: String = _view._rows[1]["label_button"].text
	assert_ne(a, b, "the two rows do not read the same")
	assert_true(a.begins_with("Sound fuer Katze"), "both still carry the label the player gave")
	assert_true(b.begins_with("Sound fuer Katze"), "and so does the other one")


func test_mic_button_asks_for_a_recording() -> void:
	_add("chicken")
	var target = _add("dog")
	var asked: Array = []
	_view.record_requested.connect(func(e): asked.append(e))
	_view.open()
	var row: int = _view.row_index_of(target.id)
	_view._rows[row]["mic_button"].pressed.emit()
	assert_eq(asked.size(), 1, "one request per tap")
	assert_eq(asked[0].id, target.id, "for the animal whose row it is")


func test_mic_button_does_not_edit_anything() -> void:
	var chicken = _add("chicken")
	var before: int = chicken.beat_pattern
	_view.open()
	_view._rows[0]["mic_button"].pressed.emit()
	assert_eq(chicken.beat_pattern, before, "recording is not an edit")
	assert_true(chicken.in_song, "and it does not park the animal either")


func test_thumbnail_previews_without_editing() -> void:
	var chicken = _add("chicken")
	chicken.pitch_offset = 12.0
	var before: int = chicken.beat_pattern
	_view.open()
	_view._rows[0]["thumb_button"].pressed.emit()
	assert_eq(_player.previews.size(), 1, "you hear the row")
	assert_almost_eq(_player.previews[0]["pitch"], 2.0, 0.001, "at its own pitch")
	assert_eq(chicken.beat_pattern, before, "and nothing changed")


func test_refresh_picks_up_a_recording_made_elsewhere() -> void:
	# main.gd calls this after the record dialog saves.
	var e = _add("chicken")
	_add("chicken")
	_view.open()
	assert_eq(_view._rows[0]["label_button"].text, "Huhn 1", "unrecorded to start with")
	var pcm := PackedByteArray()
	pcm.resize(200)
	e.sound_ref = _state.sound_bank.add_sound(WavUtils.build_wav(pcm, 22050, 1), "Wuff")
	_view.refresh()
	assert_eq(_view._rows[0]["label_button"].text, "Wuff", "renamed and sorted to the top")


func test_refresh_while_closed_does_nothing() -> void:
	_add("chicken")
	_view.refresh()
	assert_eq(_view._rows.size(), 0, "a closed Studio has no rows to repaint")


func test_row_actions_are_full_touch_targets() -> void:
	_add("chicken")
	_view.open()
	var thumb: Button = _view._rows[0]["thumb_button"]
	var mic: Button = _view._rows[0]["mic_button"]
	assert_gt(thumb.custom_minimum_size.x, ViewScript.MIN_TOUCH_SIZE - 1.0, "the thumbnail is tappable")
	assert_gt(mic.custom_minimum_size.y, ViewScript.MIN_TOUCH_SIZE - 1.0, "so is the mic button")


func test_row_actions_still_leave_room_for_the_cells() -> void:
	# Thumbnail + name + mic have to fit inside the 300px label budget, or the
	# cells drop under the touch minimum and section 3b's budget is broken.
	var name_width := ViewScript.ROW_LABEL_WIDTH - ViewScript.ROW_ACTION_SIZE * 2.0
	assert_gt(name_width, 100.0, "the name still gets a readable slice")
	assert_gt(ViewScript.cell_width_for(1080.0, 8), ViewScript.MIN_TOUCH_SIZE, "and the cells are untouched")


# --- Capped-out marking (section 3b: dropped rows must be visible) ---

func test_fully_capped_animal_is_detected() -> void:
	var e = _add("chicken")
	var capped := {0: {e.id: true}, 4: {e.id: true}}
	assert_true(ViewScript.is_fully_capped(e, capped, 8), "dropped on both its steps = never heard")


func test_animal_audible_on_one_step_is_not_fully_capped() -> void:
	var e = _add("chicken")  # steps 0 and 4
	var capped := {0: {e.id: true}}
	assert_false(ViewScript.is_fully_capped(e, capped, 8), "still heard on step 4")


func test_parked_animal_is_not_reported_as_capped() -> void:
	var e = _add("chicken")
	e.in_song = false
	assert_false(ViewScript.is_fully_capped(e, {}, 8), "parked is a different state, marked differently")


func test_silent_pattern_is_not_reported_as_capped() -> void:
	var e = _add("chicken")
	e.beat_pattern = 0
	assert_false(ViewScript.is_fully_capped(e, {}, 8), "an empty row is not being drowned out")


# --- The read-only summary the entity info panel shows ---

func test_summary_lists_steps_one_based() -> void:
	# The player counts "Takt 1", not "step 0".
	var e = _add("chicken")  # steps 0 and 4
	assert_eq(ViewScript.beat_summary(e, 8), "Singt auf Takt 1, 5", "steps 0 and 4 read as 1 and 5")


func test_summary_of_a_single_step() -> void:
	var e = _add("dog")  # step 2
	assert_eq(ViewScript.beat_summary(e, 8), "Singt auf Takt 3", "no stray separator")


func test_summary_of_a_cleared_pattern() -> void:
	var e = _add("chicken")
	e.beat_pattern = 0
	assert_eq(ViewScript.beat_summary(e, 8), "Singt auf keinem Takt", "an emptied row says so")


func test_summary_of_an_unassigned_pattern() -> void:
	# The sentinel must not read as "sings on all eight".
	var e = _state.add_entity("chicken", Vector2i(0, 0))
	assert_eq(ViewScript.beat_summary(e, 8), "Singt auf keinem Takt", "no part yet reads as silent")


func test_summary_of_a_parked_animal() -> void:
	var e = _add("chicken")
	e.in_song = false
	assert_true(ViewScript.beat_summary(e, 8).contains("Pausiert"), "parking wins over the step list")


# --- The real grid ---

func test_grid_builds_one_row_per_animal() -> void:
	_add("chicken")
	_add("dog")
	_view.open()
	assert_eq(_view._rows.size(), 2, "one row per animal")
	assert_eq(_view._rows[0]["cells"].size(), 8, "eight step cells per row")


func test_grid_reflects_the_live_patterns() -> void:
	var chicken = _add("chicken")  # steps 0 and 4
	_view.open()
	var cells: Array = _view._rows[0]["cells"]
	assert_eq(cells[0].self_modulate, ViewScript.CELL_ON, "step 1 is on")
	assert_eq(cells[1].self_modulate, ViewScript.CELL_OFF, "step 2 is off")
	assert_eq(cells[4].self_modulate, ViewScript.CELL_ON, "step 5 is on")
	assert_eq(chicken.beat_pattern, RE.pattern_from_steps([0, 4], 8), "and the data says the same")


func test_empty_zoo_shows_a_hint() -> void:
	_view.open()
	assert_eq(_view._rows.size(), 0, "no rows")
	assert_true(_view._empty_label.visible, "an empty grid explains itself")


# --- Editing ---

func test_tapping_a_cell_turns_a_step_on() -> void:
	var chicken = _add("chicken")
	_view.open()
	_view._rows[0]["cells"][2].pressed.emit()
	assert_true(RE.plays_on(chicken.beat_pattern, 2), "step 3 is now on")
	assert_eq(_view._rows[0]["cells"][2].self_modulate, ViewScript.CELL_ON, "and the cell shows it")


func test_tapping_an_on_cell_turns_it_off() -> void:
	var chicken = _add("chicken")  # steps 0 and 4
	_view.open()
	_view._rows[0]["cells"][0].pressed.emit()
	assert_false(RE.plays_on(chicken.beat_pattern, 0), "step 1 is off again")
	assert_true(RE.plays_on(chicken.beat_pattern, 4), "step 5 is untouched")


func test_tapping_an_unassigned_animal_gives_it_exactly_one_step() -> void:
	# The sentinel trap: -1 already has every bit set, so a naive OR would make
	# the animal sing on all eight steps at once.
	var e = _state.add_entity("chicken", Vector2i(0, 0))
	assert_eq(e.beat_pattern, EntityData.UNASSIGNED_PATTERN, "starts with no part at all")
	_view.open()
	_view._rows[0]["cells"][3].pressed.emit()
	assert_eq(RE.steps_from_pattern(e.beat_pattern, 8), [3] as Array[int], "exactly one step, not all eight")


func test_placing_a_beat_previews_it_immediately() -> void:
	var chicken = _add("chicken")
	chicken.pitch_offset = 12.0
	_view.open()
	_view._rows[0]["cells"][2].pressed.emit()
	assert_eq(_player.previews.size(), 1, "you hear what you just placed, on this tap")
	assert_eq(_player.previews[0]["id"], chicken.id, "and it is that animal")
	assert_almost_eq(_player.previews[0]["pitch"], 2.0, 0.001, "at its own pitch")


func test_clearing_a_beat_does_not_preview() -> void:
	_add("chicken")  # steps 0 and 4
	_view.open()
	_view._rows[0]["cells"][0].pressed.emit()  # turn step 1 off
	assert_eq(_player.previews.size(), 0, "nothing to hear when a step is removed")


func test_cell_tap_emits_beat_toggled() -> void:
	# R5's tutorial advances on this event.
	var chicken = _add("chicken")
	var seen: Array = []
	_view.beat_toggled.connect(func(e): seen.append(e))
	_view.open()
	_view._rows[0]["cells"][1].pressed.emit()
	assert_eq(seen.size(), 1, "one event per tap")
	assert_eq(seen[0].id, chicken.id, "carrying the animal that changed")


func test_toggling_never_restarts_the_loop() -> void:
	_add("chicken")
	var sd: float = _state.rhythm.step_duration()
	_state.rhythm.advance_to(100.0)
	_state.rhythm.advance_to(100.0 + sd * 3.5)
	_view.open()
	_view._rows[0]["cells"][1].pressed.emit()
	assert_eq(_state.rhythm.current_step(), 3, "the transport is free-running, the edit did not touch it")


func test_edits_made_in_the_studio_survive_save_and_load() -> void:
	var chicken = _add("chicken")
	_view.open()
	_view._rows[0]["cells"][6].pressed.emit()       # add step 7
	_view._rows[0]["label_button"].pressed.emit()   # park it
	var edited_pattern: int = chicken.beat_pattern

	var restored = ZooState.new()
	restored.rhythm.configure(RHYTHM_CFG)
	restored.from_dict(_state.to_dict())

	assert_eq(restored.entities[0].beat_pattern, edited_pattern, "the edited pattern is in the save")
	assert_true(RE.plays_on(restored.entities[0].beat_pattern, 6), "including the step just added")
	assert_false(restored.entities[0].in_song, "and the row stays parked")
	assert_eq(restored.apply_rhythm_defaults(RHYTHM_CFG), 0, "a hand-edited zoo is never re-defaulted")


func test_row_label_parks_and_unparks_the_animal() -> void:
	var chicken = _add("chicken")
	_view.open()
	_view._rows[0]["label_button"].pressed.emit()
	assert_false(chicken.in_song, "the row label IS the mute button")
	assert_true(_view._rows[0]["label_button"].text.contains("pausiert"), "and the row says so")
	_view._rows[0]["label_button"].pressed.emit()
	assert_true(chicken.in_song, "tapping again brings it back")
	assert_eq(_player.previews.size(), 1, "un-parking previews, parking does not")


func test_parked_row_is_dimmed() -> void:
	var chicken = _add("chicken")
	chicken.in_song = false
	_view.open()
	var root: Control = _view._rows[0]["root"]
	assert_almost_eq(root.modulate.a, ViewScript.PARKED_ROW_ALPHA, 0.001, "a parked row is visibly out of the song")


# --- Capped rows in the real grid ---

func test_cells_dropped_by_the_voice_cap_are_faded() -> void:
	_state.rhythm.voice_cap = 2
	for i in 4:
		_add("chicken")
	# All four on step 0, so two of them lose the cap.
	for e in _state.entities:
		e.beat_pattern = RE.pattern_from_steps([0], 8)
	_view.open()

	var faded := 0
	var solid := 0
	for row in _view._rows:
		var cell: Button = row["cells"][0]
		if cell.self_modulate == ViewScript.CELL_CAPPED:
			faded += 1
		elif cell.self_modulate == ViewScript.CELL_ON:
			solid += 1
	assert_eq(solid, 2, "two voices get through the cap of 2")
	assert_eq(faded, 2, "and the two that do not are marked, not silently dead")


func test_a_never_heard_row_says_so() -> void:
	_state.rhythm.voice_cap = 1
	var loud = _add("chicken")
	loud.sound_ref = "snd_1"  # recorded voices win the tiebreak
	var quiet = _add("chicken")
	for e in _state.entities:
		e.beat_pattern = RE.pattern_from_steps([0], 8)
	_view.open()

	var quiet_row: int = _view.row_index_of(quiet.id)
	var label: Button = _view._rows[quiet_row]["label_button"]
	assert_true(label.text.contains("übertönt"), "the drowned-out animal is labelled, not left looking broken")
	var loud_label: Button = _view._rows[_view.row_index_of(loud.id)]["label_button"]
	assert_false(loud_label.text.contains("übertönt"), "the audible one is not")


func test_legend_names_the_voice_cap() -> void:
	_state.rhythm.voice_cap = 4
	_add("chicken")
	_view.open()
	assert_true(_view._legend.text.contains("4"), "the legend states the actual cap")


# --- Playhead ---

func test_playhead_tracks_the_engine() -> void:
	_add("chicken")
	_view.open()
	var sd: float = _state.rhythm.step_duration()
	_state.rhythm.advance_to(0.0)
	_view._update_playhead()
	var at_step_0: float = _view._playhead.position.x
	_state.rhythm.advance_to(sd * 2.5)
	_view._update_playhead()
	var at_step_2: float = _view._playhead.position.x
	assert_eq(_state.rhythm.current_step(), 2, "engine moved to step 3")
	assert_gt(at_step_2, at_step_0, "and the playhead moved right with it")


func test_playhead_starts_after_the_row_labels() -> void:
	_add("chicken")
	_view.open()
	_state.rhythm.advance_to(0.0)
	_view._update_playhead()
	assert_gt(_view._playhead.position.x, ViewScript.ROW_LABEL_WIDTH - 1.0, "the playhead is over the grid, not the labels")


# --- Link-through and live updates ---

func test_open_marks_the_animal_it_was_opened_for() -> void:
	_add("chicken")
	var target = _add("dog")
	_view.open(target.id)
	var index: int = _view.row_index_of(target.id)
	assert_gt(float(index), -1.0, "the animal has a row")
	var label: Button = _view._rows[index]["label_button"]
	assert_true(label.text.begins_with("▸"), "and it is marked so the scroll target is obvious")


func test_row_index_of_unknown_animal_is_minus_one() -> void:
	_add("chicken")
	_view.open()
	assert_eq(_view.row_index_of("nope"), -1, "unknown ids do not crash the link-through")


func test_buying_an_animal_while_the_studio_is_open_adds_a_row() -> void:
	_add("chicken")
	_view.open()
	assert_eq(_view._rows.size(), 1, "one row to start")
	_add("dog")
	_view._process(0.016)
	assert_eq(_view._rows.size(), 2, "the new animal appears without closing the Studio")


# --- Mocks ---

class MockRhythmPlayer:
	extends RefCounted
	var previews: Array[Dictionary] = []

	func preview(entity_id: String, pitch_scale: float = 1.0) -> void:
		previews.append({"id": entity_id, "pitch": pitch_scale})


class MockConfig:
	extends RefCounted

	var _names := {"chicken": "Huhn", "dog": "Hund", "cat": "Katze"}

	func get_entity_config(type_id: String) -> Dictionary:
		# No sprite path: the grid must build without loading textures.
		return {"name": _names.get(type_id, type_id), "sprite": ""}
