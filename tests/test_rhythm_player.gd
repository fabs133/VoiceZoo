extends "res://tests/helpers/base_test.gd"
## Tests for RhythmPlayer - presentation-side beat playback.
## Runs headless via duck-typed mock sprites, exactly like test_interaction_player.

const PlayerScript = preload("res://presentation/rhythm_player.gd")

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

var _player
var _entity_sprites: Dictionary
var _engine: MockEngine


func before_each() -> void:
	_player = PlayerScript.new()
	_entity_sprites = {}
	_engine = MockEngine.new()
	_player.setup(_entity_sprites)


func _trigger(entity_id: String, step: int, pitch_scale: float = 1.0) -> Dictionary:
	return {"entity_id": entity_id, "step": step, "pitch_scale": pitch_scale}


# --- Trigger handling ---

func test_trigger_makes_the_animal_sing() -> void:
	_entity_sprites["0"] = MockSprite.new()
	_engine.newly_triggered.append(_trigger("0", 0))
	_player.process_triggers(_engine)
	assert_eq(_entity_sprites["0"].beats.size(), 1, "the animal sang once")


func test_pitch_scale_is_passed_to_the_sprite() -> void:
	_entity_sprites["0"] = MockSprite.new()
	_engine.newly_triggered.append(_trigger("0", 4, 1.5))
	_player.process_triggers(_engine)
	assert_almost_eq(_entity_sprites["0"].beats[0], 1.5, 0.001, "pitch comes from the engine")


func test_missing_pitch_defaults_to_unshifted() -> void:
	_entity_sprites["0"] = MockSprite.new()
	_engine.newly_triggered.append({"entity_id": "0", "step": 0})
	_player.process_triggers(_engine)
	assert_almost_eq(_entity_sprites["0"].beats[0], 1.0, 0.001, "no pitch given = concert pitch")


func test_every_trigger_in_a_frame_fires() -> void:
	for i in 3:
		_entity_sprites[str(i)] = MockSprite.new()
		_engine.newly_triggered.append(_trigger(str(i), i))
	_player.process_triggers(_engine)
	for i in 3:
		assert_eq(_entity_sprites[str(i)].beats.size(), 1, "animal %d sang" % i)


func test_catch_up_fires_the_same_animal_twice() -> void:
	# A long frame crosses several steps; an animal on more than one of them
	# has to sing more than once, or the caught-up beats are silently lost.
	_entity_sprites["0"] = MockSprite.new()
	_engine.newly_triggered.append(_trigger("0", 1))
	_engine.newly_triggered.append(_trigger("0", 2))
	_player.process_triggers(_engine)
	assert_eq(_entity_sprites["0"].beats.size(), 2, "both crossed steps played")


func test_no_triggers_plays_nothing() -> void:
	_entity_sprites["0"] = MockSprite.new()
	_player.process_triggers(_engine)
	assert_eq(_entity_sprites["0"].beats.size(), 0, "a step nobody is on stays silent")
	assert_eq(_player.missed_triggers, 0, "and nothing was missed")


# --- Robustness ---

func test_trigger_for_an_unknown_entity_does_not_crash() -> void:
	_engine.newly_triggered.append(_trigger("ghost", 0))
	_player.process_triggers(_engine)
	assert_eq(_player.missed_triggers, 1, "counted for diagnostics, not crashed")


func test_sprites_spawned_after_setup_are_visible() -> void:
	# main.gd mutates the injected dictionary whenever an animal is bought.
	_engine.newly_triggered.append(_trigger("0", 0))
	_player.process_triggers(_engine)
	assert_eq(_player.missed_triggers, 1, "no sprite yet")
	_entity_sprites["0"] = MockSprite.new()
	_player.process_triggers(_engine)
	assert_eq(_entity_sprites["0"].beats.size(), 1, "a sprite added after setup is seen")


func test_preview_fires_one_animal_outside_the_transport() -> void:
	# The Studio's immediate feedback when a cell is tapped.
	_entity_sprites["0"] = MockSprite.new()
	_player.preview("0", 1.5)
	assert_eq(_entity_sprites["0"].beats.size(), 1, "the animal sang once")
	assert_almost_eq(_entity_sprites["0"].beats[0], 1.5, 0.001, "at the pitch it was given")


func test_preview_of_an_unknown_animal_does_not_crash() -> void:
	_player.preview("ghost")
	assert_eq(_player.missed_triggers, 1, "counted like any other missed trigger")


# --- The real engine driving the player (R3 acceptance, headless) ---

func test_three_animals_sing_on_distinct_beats_in_a_stable_loop() -> void:
	var state = ZooState.new()
	state.rhythm.configure(RHYTHM_CFG)
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("dog", Vector2i(1, 0))
	state.add_entity("cat", Vector2i(2, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)
	for e in state.entities:
		_entity_sprites[e.id] = MockSprite.new()

	var played := _run_loops(state, 2)

	assert_eq(played.get("0", []), [0, 4, 0, 4], "chicken holds the pulse, both bars")
	assert_eq(played.get("1", []), [2, 2], "dog answers offbeat, both bars")
	assert_eq(played.get("2", []), [6, 6], "cat takes step 6, both bars")
	assert_eq(_entity_sprites["0"].beats.size(), 4, "and the sprites really played")


func test_a_parked_animal_drops_out_of_the_loop() -> void:
	var state = ZooState.new()
	state.rhythm.configure(RHYTHM_CFG)
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("dog", Vector2i(1, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)
	state.entities[1].in_song = false
	for e in state.entities:
		_entity_sprites[e.id] = MockSprite.new()

	var played := _run_loops(state, 1)
	assert_eq(played.get("0", []), [0, 4], "chicken still sings")
	assert_eq(played.get("1", []), [], "the parked dog is silent")


func test_muting_stops_the_sprites_but_not_the_transport() -> void:
	var state = ZooState.new()
	state.rhythm.configure(RHYTHM_CFG)
	state.add_entity("chicken", Vector2i(0, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)
	_entity_sprites["0"] = MockSprite.new()
	state.rhythm.muted = true

	_run_loops(state, 1)
	assert_eq(_entity_sprites["0"].beats.size(), 0, "muted zoo plays nothing")
	assert_eq(state.rhythm.current_step(), 7, "but the playhead swept the whole bar")


## Runs the transport through whole loops, half a step at a time, and returns
## {entity_id: [step, ...]} of everything the sprites were told to play.
func _run_loops(state, loops: int) -> Dictionary:
	var played: Dictionary = {}
	var sd: float = state.rhythm.step_duration()
	var start := 500.0
	state.rhythm.advance_to(start)
	_collect(state, played)
	for i in range(1, state.rhythm.effective_steps() * loops):
		state.rhythm.advance_to(start + sd * (float(i) + 0.5))
		_collect(state, played)
	return played


func _collect(state, into: Dictionary) -> void:
	_player.process_triggers(state.rhythm)
	for t in state.rhythm.newly_triggered:
		var steps: Array = into.get(t["entity_id"], [])
		steps.append(t["step"])
		into[t["entity_id"]] = steps


# --- Mocks ---

class MockSprite:
	extends RefCounted
	var beats: Array[float] = []

	func play_beat(pitch_scale: float = 1.0) -> void:
		beats.append(pitch_scale)


class MockEngine:
	extends RefCounted
	var newly_triggered: Array[Dictionary] = []
