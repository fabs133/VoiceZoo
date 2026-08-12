extends "res://tests/helpers/base_test.gd"
## Tests for ZooState and EntityData serialization + core logic.

var _mock_config: MockConfig


func before_each() -> void:
	_mock_config = MockConfig.new()


func test_entity_data_roundtrip() -> void:
	var e = EntityData.new()
	e.id = "42"
	e.type_id = "chicken"
	e.grid_position = Vector2i(5, 10)
	e.sound_ref = "snd_3"  # bank id since schema v2 - paths get migrated away
	e.level = 3

	var d = e.to_dict()
	var e2 = EntityData.from_dict(d)

	assert_eq(e2.id, "42", "id preserved")
	assert_eq(e2.type_id, "chicken", "type_id preserved")
	assert_eq(e2.grid_position, Vector2i(5, 10), "grid_position preserved")
	assert_eq(e2.sound_ref, "snd_3", "sound_ref preserved")
	assert_eq(e2.level, 3, "level preserved")


func test_entity_data_defaults() -> void:
	var d = {"id": "1", "type_id": "pig", "grid_position": [0, 0]}
	var e = EntityData.from_dict(d)

	assert_eq(e.sound_ref, "", "sound_ref defaults to empty")
	assert_eq(e.level, 1, "level defaults to 1")


## --- Persisted UI state ---

func test_a_fresh_zoo_starts_with_the_shop_closed() -> void:
	# The zoo should be the first thing a new guest sees, not the store - the
	# shop panel covers the lower third of the map.
	var state = ZooState.new()
	assert_false(state.shop_open, "closed on a fresh save")
	assert_false(state.studio_hint_seen, "and the Studio hint has not been used up")


func test_shop_and_hint_state_survive_a_save() -> void:
	var state = ZooState.new()
	state.shop_open = true
	state.studio_hint_seen = true
	var restored = ZooState.new()
	restored.from_dict(state.to_dict())
	assert_true(restored.shop_open, "a guest who left the shop open gets it back")
	assert_true(restored.studio_hint_seen, "and is not nudged toward the Studio twice")


func test_a_save_written_before_these_existed_still_loads() -> void:
	# Every save on a device right now predates both fields.
	var state = ZooState.new()
	var old_save: Dictionary = state.to_dict()
	old_save.erase("shop_open")
	old_save.erase("studio_hint_seen")
	var restored = ZooState.new()
	restored.from_dict(old_save)
	assert_false(restored.shop_open, "an older save opens on the zoo")
	assert_false(restored.studio_hint_seen, "and is still offered the hint once")


func test_zoo_state_empty_roundtrip() -> void:
	var state = ZooState.new()
	var d = state.to_dict()
	var state2 = ZooState.new()
	state2.from_dict(d)

	assert_eq(state2.coins, 25.0, "starting coins preserved")
	assert_eq(state2.entities.size(), 0, "no entities")
	assert_eq(state2.unlocks.size(), 1, "one unlock (chicken)")
	assert_eq(state2.unlocks[0], "chicken", "chicken is default unlock")


func test_zoo_state_with_entities_roundtrip() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(1, 1))
	state.add_entity("chicken", Vector2i(2, 2))
	state.add_entity("pig", Vector2i(3, 3))
	state.coins = 250.5
	state.lifetime_coins = 500.0
	state.unlocks.clear()
	state.unlocks.append("chicken")
	state.unlocks.append("pig")

	var d = state.to_dict()
	var state2 = ZooState.new()
	state2.from_dict(d)

	assert_eq(state2.entities.size(), 3, "3 entities preserved")
	assert_almost_eq(state2.coins, 250.5, 0.01, "coins preserved")
	assert_almost_eq(state2.lifetime_coins, 500.0, 0.01, "lifetime_coins preserved")
	assert_eq(state2.unlocks.size(), 2, "2 unlocks preserved")
	assert_eq(state2.entities[0].type_id, "chicken", "first entity type")
	assert_eq(state2.entities[2].type_id, "pig", "third entity type")
	assert_eq(state2.entities[1].grid_position, Vector2i(2, 2), "position preserved")


func test_add_entity_increments_id() -> void:
	var state = ZooState.new()
	var e1 = state.add_entity("chicken", Vector2i(0, 0))
	var e2 = state.add_entity("chicken", Vector2i(1, 0))

	assert_eq(e1.id, "0", "first entity id is 0")
	assert_eq(e2.id, "1", "second entity id is 1")
	assert_eq(state.entities.size(), 2, "2 entities in state")


func test_get_entity_count() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("chicken", Vector2i(1, 0))
	state.add_entity("pig", Vector2i(2, 0))

	assert_eq(state.get_entity_count("chicken"), 2, "2 chickens")
	assert_eq(state.get_entity_count("pig"), 1, "1 pig")
	assert_eq(state.get_entity_count("cow"), 0, "0 cows")


func test_next_id_preserved_after_roundtrip() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("chicken", Vector2i(1, 0))

	var d = state.to_dict()
	var state2 = ZooState.new()
	state2.from_dict(d)

	var e3 = state2.add_entity("pig", Vector2i(2, 0))
	assert_eq(e3.id, "2", "next_id continues from 2 after roundtrip")


func test_offline_income_capped() -> void:
	# Offline income now lives in core - state integration check
	var state = ZooState.new()
	state.coins = 0.0
	state.add_entity("chicken", Vector2i(0, 0))  # 1.0/s

	# 24h elapsed - core caps at 8h (28800s)
	var earned = Economy.calculate_offline_income(state.entities, _mock_config, state.keepers, 86400.0)
	state.coins += earned

	assert_almost_eq(state.coins, 28800.0, 1.0, "capped at 8h of income")


func test_to_dict_includes_schema_version() -> void:
	var state = ZooState.new()
	var d = state.to_dict()
	assert_eq(d["schema_version"], ZooState.SCHEMA_VERSION, "schema version present in save")


func test_to_dict_stores_supplied_time() -> void:
	var state = ZooState.new()
	var d = state.to_dict(1234567.0)
	assert_almost_eq(d["last_save_time"], 1234567.0, 0.1, "caller-supplied now stored")

	var state2 = ZooState.new()
	state2.from_dict(d)
	assert_almost_eq(state2.last_save_time, 1234567.0, 0.1, "last_save_time roundtrips")


func test_buy_entity_insufficient_coins() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	var cost = Economy.calculate_cost("chicken", 0, _mock_config)
	assert_true(state.coins < cost, "cannot afford")
	# Simulating the shop check — no entity should be added
	var count_before = state.entities.size()
	if state.coins >= cost:
		state.add_entity("chicken", Vector2i(0, 0))
	assert_eq(state.entities.size(), count_before, "no entity added when broke")


# --- Tick Tests ---

func test_tick_empty_zoo_no_crash() -> void:
	var state = ZooState.new()
	state.tick(1.0, _mock_config)
	assert_almost_eq(state.coins, 25.0, 0.001, "no income with 0 entities")
	assert_almost_eq(state.lifetime_coins, 0.0, 0.001, "no lifetime coins earned")


func test_tick_accumulates_coins() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	state.add_entity("chicken", Vector2i(0, 0))  # 1.0 income/sec

	state.tick(1.0, _mock_config)
	assert_almost_eq(state.coins, 1.0, 0.001, "1 sec = 1 coin from chicken")
	assert_almost_eq(state.lifetime_coins, 1.0, 0.001, "lifetime tracks")

	state.tick(5.0, _mock_config)
	assert_almost_eq(state.coins, 6.0, 0.001, "6 total after 6 sec")


func test_tick_multiple_entities_income() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	state.add_entity("chicken", Vector2i(0, 0))  # 1.0
	state.add_entity("chicken", Vector2i(1, 0))  # 1.0
	state.add_entity("pig", Vector2i(2, 0))       # 3.0

	state.tick(2.0, _mock_config)
	# (1+1+3) * 2 = 10
	assert_almost_eq(state.coins, 10.0, 0.001, "5 income/sec * 2 sec = 10")


func test_tick_triggers_unlock() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	state.lifetime_coins = 190.0
	state.add_entity("chicken", Vector2i(0, 0))

	# tick enough to cross pig threshold (200)
	state.tick(15.0, _mock_config)  # earns 15 coins → lifetime = 205
	assert_true(state.unlocks.has("pig"), "pig unlocked at 200 lifetime coins")
	assert_true(state.newly_unlocked.has("pig"), "pig in newly_unlocked")


func test_tick_no_duplicate_unlocks() -> void:
	var state = ZooState.new()
	state.lifetime_coins = 200.0
	state.unlocks.append("pig")
	state.add_entity("chicken", Vector2i(0, 0))

	state.tick(1.0, _mock_config)
	var pig_count = 0
	for u in state.unlocks:
		if u == "pig":
			pig_count += 1
	assert_eq(pig_count, 1, "pig not duplicated")


func test_get_income_per_second() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("pig", Vector2i(1, 0))

	var ips = state.get_income_per_second(_mock_config)
	assert_almost_eq(ips, 4.0, 0.001, "chicken(1) + pig(3) = 4")


func test_from_dict_missing_fields_uses_defaults() -> void:
	var state = ZooState.new()
	state.from_dict({})

	assert_almost_eq(state.coins, 25.0, 0.001, "default coins 25")
	assert_almost_eq(state.lifetime_coins, 0.0, 0.001, "default lifetime 0")
	assert_eq(state.entities.size(), 0, "no entities")
	assert_eq(state.unlocks.size(), 1, "default unlock")
	assert_eq(state.unlocks[0], "chicken", "default is chicken")


func test_from_dict_preserves_last_save_time() -> void:
	var state = ZooState.new()
	state.from_dict({"last_save_time": 1234567.0})
	assert_almost_eq(state.last_save_time, 1234567.0, 0.1, "last_save_time preserved")


func test_add_entity_with_sound() -> void:
	var state = ZooState.new()
	# paths are legacy semantics and get refused; bank ids pass through
	var e = state.add_entity("chicken", Vector2i(5, 5), "res://sounds/cluck.wav")
	assert_eq(e.sound_ref, "", "legacy path refused")
	var e2 = state.add_entity("chicken", Vector2i(6, 5), "snd_9")
	assert_eq(e2.sound_ref, "snd_9", "bank id stored")
	assert_eq(e.grid_position, Vector2i(5, 5), "position set")


func test_tick_large_delta() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	state.add_entity("chicken", Vector2i(0, 0))

	# Simulate 1000 seconds at once
	state.tick(1000.0, _mock_config)
	assert_almost_eq(state.coins, 1000.0, 0.01, "1000s * 1/s = 1000 coins")
	assert_almost_eq(state.lifetime_coins, 1000.0, 0.01, "lifetime tracks large delta")


func test_tick_zero_delta() -> void:
	var state = ZooState.new()
	state.coins = 50.0
	state.add_entity("chicken", Vector2i(0, 0))

	state.tick(0.0, _mock_config)
	assert_almost_eq(state.coins, 50.0, 0.001, "zero delta = no change")


func test_multiple_ticks_accumulate() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	state.add_entity("chicken", Vector2i(0, 0))

	for i in range(100):
		state.tick(0.016, _mock_config)  # ~60fps

	# 100 * 0.016 = 1.6 seconds of income at 1/s = 1.6 coins
	assert_almost_eq(state.coins, 1.6, 0.01, "100 ticks at 16ms each")


func test_entity_data_level_affects_serialization() -> void:
	var e = EntityData.new()
	e.id = "99"
	e.type_id = "lion"
	e.grid_position = Vector2i(15, 20)
	e.level = 10

	var d = e.to_dict()
	assert_eq(d["level"], 10, "level in dict")

	var e2 = EntityData.from_dict(d)
	assert_eq(e2.level, 10, "level roundtrips")


func test_get_entity_count_after_many_adds() -> void:
	var state = ZooState.new()
	for i in range(20):
		state.add_entity("chicken", Vector2i(i, 0))
	for i in range(5):
		state.add_entity("pig", Vector2i(i, 1))

	assert_eq(state.get_entity_count("chicken"), 20, "20 chickens")
	assert_eq(state.get_entity_count("pig"), 5, "5 pigs")
	assert_eq(state.entities.size(), 25, "25 total")


# --- Mock Config ---

class MockConfig:
	extends RefCounted

	var _configs: Dictionary = {
		"chicken": {
			"name": "Huhn",
			"base_income": 1.0,
			"base_cost": 10.0,
			"cost_exponent": 1.15,
		},
		"pig": {
			"name": "Schwein",
			"base_income": 3.0,
			"base_cost": 50.0,
			"cost_exponent": 1.15,
		},
	}

	var _milestones: Array[Dictionary] = [
		{"threshold": 0, "unlock_type": "chicken"},
		{"threshold": 200, "unlock_type": "pig"},
	]

	func get_entity_config(type_id: String) -> Dictionary:
		if type_id not in _configs:
			return {}
		return _configs[type_id]

	func get_progression_milestones() -> Array[Dictionary]:
		return _milestones

	func get_interaction_configs() -> Dictionary:
		return {}

	func get_interaction_config(_interaction_id: String) -> Dictionary:
		return {}

# --- Schema v2: sound bank + keeper sound_ref ---

func _make_wav() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(200)
	return WavUtils.build_wav(pcm, 22050, 1)


func test_v2_roundtrip_carries_sound_metadata() -> void:
	var state = ZooState.new()
	var id = state.sound_bank.add_sound(_make_wav(), "Wuff", 1.0)
	var d = state.to_dict()
	assert_eq(d["schema_version"], ZooState.SCHEMA_VERSION, "save carries the current schema")
	assert_eq(d["sound_bank"]["sounds"].size(), 1, "sound metadata in save")

	var restored = ZooState.new()
	restored.from_dict(d)
	assert_true(restored.sound_bank.has_sound(id), "sound metadata restored")
	assert_eq(restored.sound_bank.get_bytes(id).size(), 0, "no bytes in working save")


func test_v1_save_loads_with_empty_bank() -> void:
	# a v1 save has no sound_bank key and no keeper sound_ref
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	var d = state.to_dict()
	d.erase("sound_bank")
	d["schema_version"] = 1

	var restored = ZooState.new()
	restored.from_dict(d)
	assert_eq(restored.sound_bank.size(), 0, "v1 loads with empty bank")
	assert_eq(restored.entities.size(), 1, "entities unaffected")


func test_keeper_sound_ref_roundtrips() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	var keeper = state.add_keeper("Bob", "default", "friendly")  # returns the object
	keeper.sound_ref = "snd_7"
	var restored = ZooState.new()
	restored.from_dict(state.to_dict())
	assert_eq(restored.keepers[0].sound_ref, "snd_7", "keeper sound_ref survives")

func test_legacy_path_sound_refs_are_migrated() -> void:
	# pre-v2 saves stored placeholder PATHS in sound_ref
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0), "res://assets/placeholder_sounds/chicken.wav")
	assert_eq(state.entities[0].sound_ref, "", "add_entity refuses path refs")

	var d = state.to_dict()
	d["entities"][0]["sound_ref"] = "res://assets/placeholder_sounds/chicken.wav"
	var restored = ZooState.new()
	restored.from_dict(d)
	assert_eq(restored.entities[0].sound_ref, "", "from_dict strips legacy path refs")
	d["entities"][0]["sound_ref"] = "snd_5"
	restored.from_dict(d)
	assert_eq(restored.entities[0].sound_ref, "snd_5", "real bank ids pass through")


# --- Schema v3: rhythm settings + per-entity rhythm fields ---

const _RE = preload("res://core/rhythm_engine.gd")

## Stand-in for data/rhythm.json.
const RHYTHM_CFG := {
	"bpm": 90.0,
	"steps_per_loop": 8,
	"voice_cap": 6,
	"pitch_rotation": [0.0, 3.0, 5.0, 7.0, 12.0],
	"default_patterns": {"chicken": [0, 4], "dog": [2]},
	"fallback_pattern": [0],
}


func test_schema_is_v3() -> void:
	assert_eq(ZooState.SCHEMA_VERSION, 3, "rhythm bumped the schema to v3")


func test_entity_rhythm_fields_roundtrip() -> void:
	var e = EntityData.new()
	e.id = "7"
	e.type_id = "dog"
	e.grid_position = Vector2i(1, 2)
	e.beat_pattern = _RE.pattern_from_steps([2, 6], 8)
	e.in_song = false
	e.pitch_offset = 5.0

	var restored = EntityData.from_dict(e.to_dict())
	assert_eq(restored.beat_pattern, _RE.pattern_from_steps([2, 6], 8), "beat_pattern preserved")
	assert_false(restored.in_song, "in_song preserved")
	assert_almost_eq(restored.pitch_offset, 5.0, 0.001, "pitch_offset preserved")


func test_pre_v3_entity_loads_as_unassigned() -> void:
	var e = EntityData.from_dict({"id": "1", "type_id": "chicken", "grid_position": [0, 0]})
	assert_eq(e.beat_pattern, EntityData.UNASSIGNED_PATTERN, "no pattern yet")
	assert_true(e.in_song, "animals sing by default")
	assert_almost_eq(e.pitch_offset, 0.0, 0.001, "no pitch shift by default")


func test_rhythm_engine_sees_the_live_entity_list() -> void:
	# Wired in ZooState._init so presentation cannot forget it, and it must
	# survive both add_entity (appends) and from_dict (clears in place).
	var state = ZooState.new()
	state.rhythm.configure(RHYTHM_CFG)
	state.add_entity("chicken", Vector2i(0, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)
	state.rhythm.advance_to(0.0)
	assert_eq(state.rhythm.newly_triggered.size(), 1, "an animal bought after _init sings")

	var restored = ZooState.new()
	restored.rhythm.configure(RHYTHM_CFG)
	restored.from_dict(state.to_dict())
	restored.rhythm.advance_to(0.0)
	assert_eq(restored.rhythm.newly_triggered.size(), 1, "and so does one loaded from a save")


func test_rhythm_settings_roundtrip() -> void:
	var state = ZooState.new()
	state.rhythm.bpm = 110.0
	state.rhythm.muted = true

	var restored = ZooState.new()
	restored.from_dict(state.to_dict())
	assert_almost_eq(restored.rhythm.bpm, 110.0, 0.001, "tempo survives the save")
	assert_true(restored.rhythm.muted, "mute survives the save")


func test_v2_save_loads_with_default_rhythm() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	var d = state.to_dict()
	d.erase("rhythm")
	for ed in d["entities"]:
		ed.erase("beat_pattern")
		ed.erase("in_song")
		ed.erase("pitch_offset")
	d["schema_version"] = 2

	var restored = ZooState.new()
	restored.from_dict(d)
	assert_almost_eq(restored.rhythm.bpm, 90.0, 0.001, "v2 save gets the default tempo")
	assert_eq(restored.entities.size(), 1, "entities unaffected")
	assert_eq(restored.entities[0].beat_pattern, EntityData.UNASSIGNED_PATTERN, "awaits its type default")


func test_apply_rhythm_defaults_assigns_type_patterns() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("dog", Vector2i(1, 0))

	var assigned = state.apply_rhythm_defaults(RHYTHM_CFG)
	assert_eq(assigned, 2, "both animals got a part")
	assert_eq(state.entities[0].beat_pattern, _RE.pattern_from_steps([0, 4], 8), "chicken pulse")
	assert_eq(state.entities[1].beat_pattern, _RE.pattern_from_steps([2], 8), "dog offbeat")


func test_apply_rhythm_defaults_rotates_duplicates() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("chicken", Vector2i(1, 0))
	state.add_entity("chicken", Vector2i(2, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)

	assert_eq(state.entities[0].beat_pattern, _RE.pattern_from_steps([0, 4], 8), "first chicken")
	assert_eq(state.entities[1].beat_pattern, _RE.pattern_from_steps([1, 5], 8), "second rotates by 1")
	assert_eq(state.entities[2].beat_pattern, _RE.pattern_from_steps([2, 6], 8), "third rotates by 2")
	assert_almost_eq(state.entities[1].pitch_offset, 3.0, 0.001, "duplicates also spread in pitch")


func test_apply_rhythm_defaults_leaves_edited_patterns_alone() -> void:
	var state = ZooState.new()
	var edited = state.add_entity("chicken", Vector2i(0, 0))
	var cleared = state.add_entity("chicken", Vector2i(1, 0))
	edited.beat_pattern = _RE.pattern_from_steps([3], 8)
	cleared.beat_pattern = 0  # player emptied the row in the Studio

	var assigned = state.apply_rhythm_defaults(RHYTHM_CFG)
	assert_eq(assigned, 0, "nothing to assign")
	assert_eq(edited.beat_pattern, _RE.pattern_from_steps([3], 8), "hand-edited pattern kept")
	assert_eq(cleared.beat_pattern, 0, "a deliberately silent row is not refilled")


func test_apply_rhythm_defaults_only_touches_new_arrivals() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)
	state.add_entity("chicken", Vector2i(1, 0))

	var assigned = state.apply_rhythm_defaults(RHYTHM_CFG)
	assert_eq(assigned, 1, "only the new chicken is assigned")
	assert_eq(state.entities[1].beat_pattern, _RE.pattern_from_steps([1, 5], 8), "and it rotates off the first")


func test_rhythm_defaults_survive_save_load() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))
	state.add_entity("chicken", Vector2i(1, 0))
	state.apply_rhythm_defaults(RHYTHM_CFG)

	var restored = ZooState.new()
	restored.from_dict(state.to_dict())
	assert_eq(restored.entities[1].beat_pattern, _RE.pattern_from_steps([1, 5], 8), "pattern survives")
	assert_almost_eq(restored.entities[1].pitch_offset, 3.0, 0.001, "pitch survives")
	assert_eq(restored.apply_rhythm_defaults(RHYTHM_CFG), 0, "a loaded zoo needs no reassignment")
