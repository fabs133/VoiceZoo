extends "res://tests/helpers/base_test.gd"
## Tests for Progression pure functions.

var _mock_config: MockConfig


func before_each() -> void:
	_mock_config = MockConfig.new()


func test_initial_unlock() -> void:
	var unlocks = Progression.get_unlocks(0.0, _mock_config)
	assert_eq(unlocks.size(), 1, "only chicken at 0 coins")
	assert_eq(unlocks[0], "chicken", "chicken is first unlock")


func test_pig_unlock() -> void:
	var unlocks = Progression.get_unlocks(200.0, _mock_config)
	assert_true(unlocks.has("chicken"), "chicken unlocked")
	assert_true(unlocks.has("pig"), "pig unlocked at 200")
	assert_eq(unlocks.size(), 2, "exactly 2 unlocks")


func test_threshold_exact() -> void:
	var unlocks = Progression.get_unlocks(200.0, _mock_config)
	assert_true(unlocks.has("pig"), "pig unlocks at exactly 200")


func test_below_threshold() -> void:
	var unlocks = Progression.get_unlocks(199.99, _mock_config)
	assert_false(unlocks.has("pig"), "pig NOT unlocked at 199.99")


func test_multiple_unlocks() -> void:
	var unlocks = Progression.get_unlocks(1200.0, _mock_config)
	assert_true(unlocks.has("chicken"), "chicken")
	assert_true(unlocks.has("pig"), "pig")
	assert_true(unlocks.has("cow"), "cow at 1000")
	assert_eq(unlocks.size(), 3, "3 unlocks at 1200 coins")


func test_all_unlocks() -> void:
	var unlocks = Progression.get_unlocks(300000.0, _mock_config)
	assert_eq(unlocks.size(), 8, "all 8 types unlocked at 300000")
	assert_true(unlocks.has("elephant"), "elephant is last unlock")


func test_unlock_order_preserved() -> void:
	var unlocks = Progression.get_unlocks(999999.0, _mock_config)
	assert_eq(unlocks[0], "chicken", "first is chicken")
	assert_eq(unlocks[1], "pig", "second is pig")
	assert_eq(unlocks[7], "elephant", "last is elephant")


# --- Mock Config ---

class MockConfig:
	extends RefCounted

	var _milestones: Array[Dictionary] = [
		{"threshold": 0,      "unlock_type": "chicken"},
		{"threshold": 200,    "unlock_type": "pig"},
		{"threshold": 1000,   "unlock_type": "cow"},
		{"threshold": 4000,   "unlock_type": "parrot"},
		{"threshold": 12000,  "unlock_type": "monkey"},
		{"threshold": 35000,  "unlock_type": "penguin"},
		{"threshold": 100000, "unlock_type": "lion"},
		{"threshold": 300000, "unlock_type": "elephant"},
	]

	func get_progression_milestones() -> Array[Dictionary]:
		return _milestones
