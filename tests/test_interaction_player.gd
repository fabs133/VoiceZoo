extends "res://tests/helpers/base_test.gd"
## Tests for InteractionPlayer - presentation-side playback orchestration.
## Runs headless via duck-typed mock sprites, camera, and config.

const PlayerScript = preload("res://presentation/interaction_player.gd")

var _player
var _entity_sprites: Dictionary
var _keeper_sprites: Dictionary
var _camera: MockCamera
var _config: MockConfig


func before_each() -> void:
	_player = PlayerScript.new()
	_entity_sprites = {}
	_keeper_sprites = {}
	_camera = MockCamera.new()
	_config = MockConfig.new()
	_player.setup(_entity_sprites, _keeper_sprites, _camera, _config)


func _add_pair(id: String) -> void:
	_entity_sprites[id] = MockEntitySprite.new()
	_keeper_sprites[id] = MockKeeperSprite.new()


func _start_event(keeper_id: String, entity_id: String) -> Dictionary:
	return {"keeper_id": keeper_id, "entity_id": entity_id, "interaction_id": "feed"}


# --- Event handling ---

func test_started_event_drives_sprites() -> void:
	_add_pair("0")
	_player._on_interaction_started(_start_event("0", "0"))

	assert_eq(_keeper_sprites["0"].play_calls, 1, "keeper animation started")
	assert_eq(_entity_sprites["0"].reactions.size(), 1, "entity reaction played")
	assert_eq(_entity_sprites["0"].reactions[0]["type"], "happy", "reaction type from config")
	assert_ne(_entity_sprites["0"].reactions[0]["sound"], "", "first interaction gets a sound slot")
	assert_eq(_entity_sprites["0"].particle_calls, 1, "particles spawned")
	assert_eq(_camera.nudges, 1, "camera nudged toward entity")


func test_finished_event_stops_sprites() -> void:
	_add_pair("0")
	_player._on_interaction_started(_start_event("0", "0"))
	_player._on_interaction_finished({"keeper_id": "0", "entity_id": "0"})

	assert_eq(_keeper_sprites["0"].stop_calls, 1, "keeper animation stopped")
	assert_eq(_entity_sprites["0"].stop_calls, 1, "entity reaction stopped")


func test_process_events_consumes_engine_arrays() -> void:
	_add_pair("0")
	var engine = MockEngine.new()
	engine.newly_started.append(_start_event("0", "0"))
	_player.process_events(engine)
	assert_eq(_keeper_sprites["0"].play_calls, 1, "started event processed")

	engine.newly_started.clear()
	engine.newly_finished.append({"keeper_id": "0", "entity_id": "0"})
	_player.process_events(engine)
	assert_eq(_keeper_sprites["0"].stop_calls, 1, "finished event processed")


# --- Sound slot management ---

func test_sound_slots_capped_at_three() -> void:
	for i in range(4):
		_add_pair(str(i))
	for i in range(4):
		_player._on_interaction_started(_start_event(str(i), str(i)))

	var with_sound := 0
	for i in range(4):
		if _entity_sprites[str(i)].reactions[0]["sound"] != "":
			with_sound += 1
	assert_eq(with_sound, 3, "only 3 concurrent interaction sounds")


func test_slot_released_only_by_owner() -> void:
	# Regression: a finishing keeper that never held a slot must not free one.
	for i in range(4):
		_add_pair(str(i))
	for i in range(4):
		_player._on_interaction_started(_start_event(str(i), str(i)))
	# keepers 0..2 hold the 3 slots, keeper 3 got none

	_player._on_interaction_finished({"keeper_id": "3", "entity_id": "3"})
	_add_pair("4")
	_player._on_interaction_started(_start_event("4", "4"))
	assert_eq(_entity_sprites["4"].reactions[0]["sound"], "", "non-owner finish frees no slot")

	_player._on_interaction_finished({"keeper_id": "0", "entity_id": "0"})
	_add_pair("5")
	_player._on_interaction_started(_start_event("5", "5"))
	assert_ne(_entity_sprites["5"].reactions[0]["sound"], "", "owner finish frees a slot")


# --- Robustness ---

func test_unknown_ids_do_not_crash() -> void:
	_player._on_interaction_started(_start_event("ghost", "ghost"))
	_player._on_interaction_finished({"keeper_id": "ghost", "entity_id": "ghost"})
	assert_eq(_camera.nudges, 0, "no nudge without an entity sprite")


func test_unknown_interaction_config_ignored() -> void:
	_add_pair("0")
	_player._on_interaction_started({"keeper_id": "0", "entity_id": "0", "interaction_id": "nope"})
	assert_eq(_keeper_sprites["0"].play_calls, 0, "no animation without config")
	assert_eq(_entity_sprites["0"].reactions.size(), 0, "no reaction without config")


func test_null_camera_disables_nudges() -> void:
	_player.setup(_entity_sprites, _keeper_sprites, null, _config)
	_add_pair("0")
	_player._on_interaction_started(_start_event("0", "0"))
	assert_eq(_entity_sprites["0"].reactions.size(), 1, "reaction still plays without camera")


func test_shared_dictionary_sees_later_spawns() -> void:
	# main.gd mutates the injected dictionaries after setup(); the player
	# must observe those additions (reference semantics).
	_player._on_interaction_started(_start_event("0", "0"))  # nothing yet
	_add_pair("0")
	_player._on_interaction_started(_start_event("0", "0"))
	assert_eq(_keeper_sprites["0"].play_calls, 1, "sprite added after setup is visible")


# --- Mocks ---

class MockEntitySprite:
	extends RefCounted
	var position := Vector2(10, 20)
	var reactions: Array[Dictionary] = []
	var stop_calls := 0
	var particle_calls := 0

	func play_reaction(reaction_type: String, sound_path: String = "") -> void:
		reactions.append({"type": reaction_type, "sound": sound_path})

	func spawn_interaction_particles(_color = null) -> void:
		particle_calls += 1

	func stop_reaction() -> void:
		stop_calls += 1


class MockKeeperSprite:
	extends RefCounted
	var play_calls := 0
	var stop_calls := 0

	func play_interaction(_cfg: Dictionary) -> void:
		play_calls += 1

	func stop_interaction() -> void:
		stop_calls += 1


class MockCamera:
	extends RefCounted
	var nudges := 0

	func nudge_to(_pos: Vector2) -> void:
		nudges += 1


class MockConfig:
	extends RefCounted

	func get_interaction_config(interaction_id: String) -> Dictionary:
		if interaction_id == "feed":
			return {
				"keeper_action": "feed",
				"entity_reaction": "happy",
			}
		return {}


class MockEngine:
	extends RefCounted
	var newly_started: Array[Dictionary] = []
	var newly_finished: Array[Dictionary] = []