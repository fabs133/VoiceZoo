extends "res://tests/helpers/base_test.gd"
## Tests for KeeperData, ZooState keeper CRUD, Economy keeper bonus.

const KD = preload("res://core/keeper_data.gd")

var _mock_config: MockConfig


func before_each() -> void:
	_mock_config = MockConfig.new()


# --- KeeperData Serialization ---

func test_keeper_data_roundtrip() -> void:
	var k = KD.new()
	k.id = "7"
	k.name = "Hans"
	k.face_texture_ref = "res://faces/hans.png"
	k.body_type = "tall"
	k.personality = "strict"
	k.assigned_entity_id = "42"

	var d = k.to_dict()
	var k2 = KD.from_dict(d)

	assert_eq(k2.id, "7", "id preserved")
	assert_eq(k2.name, "Hans", "name preserved")
	assert_eq(k2.face_texture_ref, "res://faces/hans.png", "face_texture_ref preserved")
	assert_eq(k2.body_type, "tall", "body_type preserved")
	assert_eq(k2.personality, "strict", "personality preserved")
	assert_eq(k2.assigned_entity_id, "42", "assigned_entity_id preserved")


func test_keeper_data_defaults() -> void:
	var k = KD.from_dict({"id": "1", "name": "Test"})

	assert_eq(k.face_texture_ref, "", "face defaults to empty")
	assert_eq(k.body_type, "default", "body defaults to default")
	assert_eq(k.personality, "friendly", "personality defaults to friendly")
	assert_eq(k.assigned_entity_id, "", "assigned defaults to empty")


func test_keeper_data_empty_dict() -> void:
	var k = KD.from_dict({})

	assert_eq(k.id, "", "id defaults to empty")
	assert_eq(k.name, "", "name defaults to empty")
	assert_eq(k.body_type, "default", "body_type defaults")


# --- ZooState Keeper CRUD ---

func test_add_keeper() -> void:
	var state = ZooState.new()
	var k = state.add_keeper("Hans", "tall", "strict")

	assert_eq(k.id, "0", "first keeper id is 0")
	assert_eq(k.name, "Hans", "name set")
	assert_eq(k.body_type, "tall", "body_type set")
	assert_eq(k.personality, "strict", "personality set")
	assert_eq(state.keepers.size(), 1, "1 keeper in state")


func test_add_keeper_increments_id() -> void:
	var state = ZooState.new()
	var k1 = state.add_keeper("Hans")
	var k2 = state.add_keeper("Greta")

	assert_eq(k1.id, "0", "first id 0")
	assert_eq(k2.id, "1", "second id 1")
	assert_eq(state.keepers.size(), 2, "2 keepers")


func test_assign_keeper() -> void:
	var state = ZooState.new()
	var e = state.add_entity("chicken", Vector2i(0, 0))
	var k = state.add_keeper("Hans")

	var result = state.assign_keeper(k.id, e.id)

	assert_true(result, "assign succeeds")
	assert_eq(k.assigned_entity_id, e.id, "keeper assigned to entity")


func test_assign_keeper_invalid_entity() -> void:
	var state = ZooState.new()
	var k = state.add_keeper("Hans")

	var result = state.assign_keeper(k.id, "nonexistent")

	assert_false(result, "assign fails for invalid entity")
	assert_eq(k.assigned_entity_id, "", "keeper remains unassigned")


func test_assign_keeper_replaces_existing() -> void:
	var state = ZooState.new()
	var e = state.add_entity("chicken", Vector2i(0, 0))
	var k1 = state.add_keeper("Hans")
	var k2 = state.add_keeper("Greta")

	state.assign_keeper(k1.id, e.id)
	state.assign_keeper(k2.id, e.id)

	assert_eq(k1.assigned_entity_id, "", "old keeper unassigned")
	assert_eq(k2.assigned_entity_id, e.id, "new keeper assigned")


func test_get_keeper_for_entity() -> void:
	var state = ZooState.new()
	var e = state.add_entity("chicken", Vector2i(0, 0))
	var k = state.add_keeper("Hans")
	state.assign_keeper(k.id, e.id)

	var found = state.get_keeper_for_entity(e.id)
	assert_not_null(found, "found keeper")
	assert_eq(found.name, "Hans", "correct keeper")

	var none = state.get_keeper_for_entity("nonexistent")
	assert_eq(none, null, "no keeper for unknown entity")


func test_remove_keeper() -> void:
	var state = ZooState.new()
	var k = state.add_keeper("Hans")
	assert_eq(state.keepers.size(), 1, "1 keeper before remove")

	state.remove_keeper(k.id)
	assert_eq(state.keepers.size(), 0, "0 keepers after remove")


func test_get_keeper() -> void:
	var state = ZooState.new()
	var k = state.add_keeper("Hans")

	var found = state.get_keeper(k.id)
	assert_not_null(found, "keeper found")
	assert_eq(found.name, "Hans", "correct keeper")

	var none = state.get_keeper("999")
	assert_eq(none, null, "null for unknown id")


# --- Serialization with Keepers ---

func test_zoo_state_keepers_roundtrip() -> void:
	var state = ZooState.new()
	var e = state.add_entity("chicken", Vector2i(0, 0))
	var k = state.add_keeper("Hans", "tall", "strict")
	state.assign_keeper(k.id, e.id)

	var d = state.to_dict()
	var state2 = ZooState.new()
	state2.from_dict(d)

	assert_eq(state2.keepers.size(), 1, "1 keeper roundtripped")
	assert_eq(state2.keepers[0].name, "Hans", "name preserved")
	assert_eq(state2.keepers[0].assigned_entity_id, e.id, "assignment preserved")

	# next_keeper_id continues correctly
	var k2 = state2.add_keeper("Greta")
	assert_eq(k2.id, "1", "next_keeper_id continues after roundtrip")


func test_backward_compat_no_keepers_in_save() -> void:
	var state = ZooState.new()
	# Simulate old save without keepers key
	state.from_dict({"coins": 100.0, "entities": [], "unlocks": ["chicken"]})

	assert_eq(state.keepers.size(), 0, "no keepers from old save")
	assert_almost_eq(state.coins, 100.0, 0.001, "coins loaded")


# --- Economy Keeper Bonus ---

func test_economy_no_keepers_unchanged() -> void:
	var state = ZooState.new()
	state.add_entity("chicken", Vector2i(0, 0))

	var income = Economy.calculate_income(state.entities, _mock_config)
	assert_almost_eq(income, 1.0, 0.001, "no keepers = base income")


func test_economy_keeper_bonus() -> void:
	var state = ZooState.new()
	var e = state.add_entity("chicken", Vector2i(0, 0))
	var k = state.add_keeper("Hans")
	state.assign_keeper(k.id, e.id)

	var income = Economy.calculate_income(state.entities, _mock_config, state.keepers)
	assert_almost_eq(income, 1.5, 0.001, "keeper gives +50% = 1.5")


func test_economy_keeper_mixed_assigned() -> void:
	var state = ZooState.new()
	var e1 = state.add_entity("chicken", Vector2i(0, 0))  # 1.0 base
	state.add_entity("pig", Vector2i(1, 0))                # 3.0 base, no keeper
	var k = state.add_keeper("Hans")
	state.assign_keeper(k.id, e1.id)

	var income = Economy.calculate_income(state.entities, _mock_config, state.keepers)
	# chicken: 1.0 * 1.5 = 1.5, pig: 3.0 = 3.0 → total 4.5
	assert_almost_eq(income, 4.5, 0.001, "mixed: 1.5 + 3.0 = 4.5")


func test_economy_keeper_bonus_stacks_with_level() -> void:
	var state = ZooState.new()
	var e = state.add_entity("chicken", Vector2i(0, 0))
	e.level = 3  # 1.0 * 3 = 3.0 base
	var k = state.add_keeper("Hans")
	state.assign_keeper(k.id, e.id)

	var income = Economy.calculate_income(state.entities, _mock_config, state.keepers)
	# 1.0 * 3 * 1.5 = 4.5
	assert_almost_eq(income, 4.5, 0.001, "level 3 + keeper = 4.5")


func test_tick_with_keeper_bonus() -> void:
	var state = ZooState.new()
	state.coins = 0.0
	var e = state.add_entity("chicken", Vector2i(0, 0))
	var k = state.add_keeper("Hans")
	state.assign_keeper(k.id, e.id)

	state.tick(1.0, _mock_config)
	assert_almost_eq(state.coins, 1.5, 0.001, "tick with keeper: 1.0 * 1.5 = 1.5")


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
