extends "res://tests/helpers/base_test.gd"
## Tests for Economy pure functions.
## Uses a mock config to avoid autoload dependency.

const KD = preload("res://core/keeper_data.gd")

var _mock_config: MockConfig


func before_each() -> void:
	_mock_config = MockConfig.new()


func test_income_empty_zoo() -> void:
	var entities: Array[EntityData] = []
	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 0.0, 0.001, "empty zoo = 0 income")


func test_income_single_entity() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)

	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 1.0, 0.001, "1 chicken lvl 1 = 1.0 income")


func test_income_scaled_by_level() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.type_id = "chicken"
	e.level = 5
	entities.append(e)

	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 5.0, 0.001, "1 chicken lvl 5 = 5.0 income")


func test_income_multiple_entities() -> void:
	var entities: Array[EntityData] = []
	for i in range(3):
		var e = EntityData.new()
		e.type_id = "chicken"
		e.level = 1
		entities.append(e)

	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 3.0, 0.001, "3 chickens = 3.0 income")


func test_income_mixed_types() -> void:
	var entities: Array[EntityData] = []
	var c = EntityData.new()
	c.type_id = "chicken"
	c.level = 1
	entities.append(c)
	var p = EntityData.new()
	p.type_id = "pig"
	p.level = 1
	entities.append(p)

	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 4.0, 0.001, "chicken(1) + pig(3) = 4.0")


func test_cost_first_is_base() -> void:
	var cost = Economy.calculate_cost("chicken", 0, _mock_config)
	assert_almost_eq(cost, 10.0, 0.001, "first chicken = base_cost 10")


func test_cost_escalation() -> void:
	var cost0 = Economy.calculate_cost("chicken", 0, _mock_config)
	var cost1 = Economy.calculate_cost("chicken", 1, _mock_config)
	var cost5 = Economy.calculate_cost("chicken", 5, _mock_config)

	assert_gt(cost1, cost0, "2nd costs more than 1st")
	assert_gt(cost5, cost1, "6th costs more than 2nd")
	assert_almost_eq(cost1, 10.0 * pow(1.15, 1), 0.01, "follows exponent formula")


func test_upgrade_cost_scales_with_level() -> void:
	var e = EntityData.new()
	e.type_id = "chicken"
	e.level = 1
	var cost1 = Economy.calculate_upgrade_cost(e, _mock_config)

	e.level = 3
	var cost3 = Economy.calculate_upgrade_cost(e, _mock_config)

	assert_gt(cost3, cost1, "lvl 3 upgrade costs more than lvl 1")


func test_upgrade_cost_formula() -> void:
	var e = EntityData.new()
	e.type_id = "chicken"
	e.level = 4
	var cost = Economy.calculate_upgrade_cost(e, _mock_config)
	# base_cost(10) * level(4) * 2.0 = 80
	assert_almost_eq(cost, 80.0, 0.01, "upgrade cost = base * level * 2")


func test_income_unknown_type_skipped() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.type_id = "unicorn"
	e.level = 1
	entities.append(e)

	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 0.0, 0.001, "unknown type yields 0 income")


func test_cost_unknown_type_zero() -> void:
	var cost = Economy.calculate_cost("unicorn", 0, _mock_config)
	assert_almost_eq(cost, 0.0, 0.001, "unknown type cost is 0")


func test_upgrade_cost_unknown_type_zero() -> void:
	var e = EntityData.new()
	e.type_id = "unicorn"
	e.level = 5
	var cost = Economy.calculate_upgrade_cost(e, _mock_config)
	assert_almost_eq(cost, 0.0, 0.001, "unknown type upgrade cost is 0")


func test_cost_high_owned_count() -> void:
	# Verify cost escalation at high quantities
	var cost50 = Economy.calculate_cost("chicken", 50, _mock_config)
	var expected = 10.0 * pow(1.15, 50)
	assert_almost_eq(cost50, expected, 0.1, "cost follows formula at 50 owned")
	assert_gt(cost50, 1000.0, "50 chickens costs over 1000")


func test_income_high_level_entity() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.type_id = "pig"
	e.level = 100
	entities.append(e)

	var income = Economy.calculate_income(entities, _mock_config)
	assert_almost_eq(income, 300.0, 0.001, "pig lvl 100 = 3 * 100 = 300")


# --- Keeper income bonus (config-driven) ---

func test_keeper_bonus_read_from_config() -> void:
	var config = MockConfigWithKeeperBonus.new()  # income_bonus = 1.0
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)
	var k = KD.new()
	k.assigned_entity_id = "0"

	var income = Economy.calculate_income(entities, config, [k])
	assert_almost_eq(income, 2.0, 0.001, "bonus 1.0 from config = 2x income")


func test_keeper_bonus_fallback_without_config_method() -> void:
	# MockConfig has no get_keeper_config() -> DEFAULT_KEEPER_INCOME_BONUS (0.5)
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)
	var k = KD.new()
	k.assigned_entity_id = "0"

	var income = Economy.calculate_income(entities, _mock_config, [k])
	assert_almost_eq(income, 1.5, 0.001, "fallback bonus 0.5 = 1.5x income")


# --- Offline income ---

func test_offline_income_happy_path() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)

	var earned = Economy.calculate_offline_income(entities, _mock_config, [], 600.0)
	assert_almost_eq(earned, 600.0, 0.001, "10 min at 1/s = 600 coins")


func test_offline_income_capped_at_8h() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)

	var earned = Economy.calculate_offline_income(entities, _mock_config, [], 86400.0)
	assert_almost_eq(earned, 28800.0, 0.1, "24h elapsed capped to 8h of income")


func test_offline_income_zero_elapsed() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)

	var earned = Economy.calculate_offline_income(entities, _mock_config, [], 0.0)
	assert_almost_eq(earned, 0.0, 0.001, "zero elapsed = zero income")


func test_offline_income_negative_elapsed() -> void:
	# Clock rolled backwards between sessions - must not charge the player
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)

	var earned = Economy.calculate_offline_income(entities, _mock_config, [], -500.0)
	assert_almost_eq(earned, 0.0, 0.001, "negative elapsed = zero income")


func test_offline_income_includes_keeper_bonus() -> void:
	var entities: Array[EntityData] = []
	var e = EntityData.new()
	e.id = "0"
	e.type_id = "chicken"
	e.level = 1
	entities.append(e)
	var k = KD.new()
	k.assigned_entity_id = "0"

	var earned = Economy.calculate_offline_income(entities, _mock_config, [k], 100.0)
	assert_almost_eq(earned, 150.0, 0.001, "passive keeper bonus applies offline")


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

	func get_entity_config(type_id: String) -> Dictionary:
		if type_id not in _configs:
			return {}
		return _configs[type_id]

class MockConfigWithKeeperBonus:
	extends MockConfig

	func get_keeper_config() -> Dictionary:
		return {"income_bonus": 1.0}

