extends "res://tests/helpers/base_test.gd"
## Tests for InteractionEngine — keeper-entity interaction logic.

const IE = preload("res://core/interaction_engine.gd")
const KD = preload("res://core/keeper_data.gd")

var _mock_config: MockConfig
var _engine: RefCounted


func before_each() -> void:
	_mock_config = MockConfig.new()
	_engine = IE.new()


# --- Construction ---

func test_new_engine_empty() -> void:
	assert_false(_engine.is_interacting("0"), "no interactions on new engine")
	assert_almost_eq(_engine.get_income_multiplier("0"), 1.0, 0.001, "default multiplier is 1.0")
	assert_eq(_engine.newly_started.size(), 0, "no newly started")
	assert_eq(_engine.newly_finished.size(), 0, "no newly finished")


# --- No interaction conditions ---

func test_tick_no_keepers() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	_engine.tick(1.0, [], entities, _mock_config)
	assert_eq(_engine.newly_started.size(), 0, "no interactions without keepers")


func test_tick_unassigned_keeper() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "")

	_engine.tick(1.0, [keeper], entities, _mock_config)
	assert_false(_engine.is_interacting("0"), "unassigned keeper does not interact")


func test_tick_keeper_assigned_to_missing_entity() -> void:
	var entities: Array[EntityData] = []
	var keeper = _make_keeper("0", "friendly", "nonexistent")

	_engine.tick(1.0, [keeper], entities, _mock_config)
	assert_false(_engine.is_interacting("0"), "no interaction with missing entity")


# --- Interaction start ---

func test_auto_start_interaction() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)

	assert_true(_engine.is_interacting("0"), "keeper starts interaction")
	assert_eq(_engine.newly_started.size(), 1, "one interaction started")
	assert_eq(_engine.newly_started[0]["keeper_id"], "0", "correct keeper")
	assert_eq(_engine.newly_started[0]["entity_id"], "0", "correct entity")


func test_double_start_prevented() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	assert_eq(_engine.newly_started.size(), 1, "first start")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	assert_eq(_engine.newly_started.size(), 0, "no second start while active")


# --- Interaction completion ---

func test_interaction_completes() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	assert_true(_engine.is_interacting("0"), "interaction active")

	# Tick past longest possible duration (6.0s for observe)
	_engine.tick(10.0, [keeper], entities, _mock_config)
	assert_eq(_engine.newly_finished.size(), 1, "interaction finished")
	assert_eq(_engine.newly_finished[0]["keeper_id"], "0", "correct keeper finished")


func test_cooldown_prevents_restart() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	# Start and complete interaction
	_engine.tick(0.1, [keeper], entities, _mock_config)
	_engine.tick(10.0, [keeper], entities, _mock_config)
	assert_false(_engine.is_interacting("0"), "interaction ended")

	# Tick a short time — should still be on cooldown
	_engine.tick(1.0, [keeper], entities, _mock_config)
	assert_false(_engine.is_interacting("0"), "cooldown prevents restart")


func test_cooldown_expires() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	# Start, complete, and wait for cooldown (max cooldown is 30s)
	_engine.tick(0.1, [keeper], entities, _mock_config)
	_engine.tick(10.0, [keeper], entities, _mock_config)  # completes interaction
	_engine.tick(35.0, [keeper], entities, _mock_config)   # expires cooldown + starts new

	assert_true(_engine.is_interacting("0"), "new interaction after cooldown")


# --- Income multiplier ---

func test_income_multiplier_active() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	var mult = _engine.get_income_multiplier("0")
	assert_gt(mult, 1.0, "multiplier > 1.0 during interaction")


func test_income_multiplier_inactive() -> void:
	assert_almost_eq(_engine.get_income_multiplier("0"), 1.0, 0.001, "1.0 when no interaction")


func test_income_multiplier_after_completion() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	_engine.tick(10.0, [keeper], entities, _mock_config)  # completes

	assert_almost_eq(_engine.get_income_multiplier("0"), 1.0, 0.001, "1.0 after completion")


# --- Zone filtering ---

func test_zone_filtering_blocks_train() -> void:
	# Train is only available in tropical/savanna. Chicken is farm.
	# So with only "train" available, no interaction should start for chicken.
	var config = MockConfigTrainOnly.new()
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "strict", "0")

	_engine.tick(1.0, [keeper], entities, config)
	assert_false(_engine.is_interacting("0"), "train blocked for farm entity")


func test_zone_filtering_allows_train_tropical() -> void:
	# Parrot is tropical — train should work.
	var config = MockConfigTrainOnly.new()
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "parrot"))
	var keeper = _make_keeper("0", "strict", "0")

	_engine.tick(1.0, [keeper], entities, config)
	assert_true(_engine.is_interacting("0"), "train allowed for tropical entity")


# --- Multiple keepers ---

func test_multiple_keepers_interact_simultaneously() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	entities.append(_make_entity("1", "pig"))
	var k1 = _make_keeper("0", "friendly", "0")
	var k2 = _make_keeper("1", "calm", "1")

	_engine.tick(0.1, [k1, k2], entities, _mock_config)

	assert_true(_engine.is_interacting("0"), "keeper 0 interacting")
	assert_true(_engine.is_interacting("1"), "keeper 1 interacting")
	assert_eq(_engine.newly_started.size(), 2, "2 interactions started")


# --- Serialization ---

func test_serialization_roundtrip() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	assert_true(_engine.is_interacting("0"), "active before save")

	var d = _engine.to_dict()
	var engine2 = IE.new()
	engine2.from_dict(d)

	assert_true(engine2.is_interacting("0"), "active after restore")
	var mult = engine2.get_income_multiplier("0")
	assert_gt(mult, 1.0, "multiplier preserved")


func test_from_dict_empty() -> void:
	_engine.from_dict({})
	assert_false(_engine.is_interacting("0"), "empty dict = no interactions")


func test_serialization_preserves_cooldowns() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	# Start, complete → keeper now on cooldown
	_engine.tick(0.1, [keeper], entities, _mock_config)
	_engine.tick(10.0, [keeper], entities, _mock_config)

	var d = _engine.to_dict()
	var engine2 = IE.new()
	engine2.from_dict(d)

	# Tick a short time — should still be on cooldown
	engine2.tick(1.0, [keeper], entities, _mock_config)
	assert_false(engine2.is_interacting("0"), "cooldown preserved after restore")


# --- Economy integration ---

func test_economy_with_interaction_multiplier() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	var mult = _engine.get_income_multiplier("0")

	var income = Economy.calculate_income(entities, _mock_config, [keeper], _engine)
	# chicken base = 1.0, level 1, interaction multiplier replaces keeper bonus
	assert_almost_eq(income, 1.0 * mult, 0.001, "income uses interaction multiplier")
	assert_gt(income, 1.5, "interaction multiplier > keeper bonus 1.5")


func test_economy_without_engine_backward_compat() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	var income = Economy.calculate_income(entities, _mock_config, [keeper])
	assert_almost_eq(income, 1.5, 0.001, "without engine = normal keeper bonus")


# --- Edge cases ---

func test_zero_delta_no_change() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	var active_before = _engine.get_active_interaction("0").duplicate()

	_engine.tick(0.0, [keeper], entities, _mock_config)
	var active_after = _engine.get_active_interaction("0")

	assert_almost_eq(active_after["remaining_time"], active_before["remaining_time"], 0.001, "zero delta = no change")


func test_large_delta_completes_and_starts_cooldown() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	_engine.tick(100.0, [keeper], entities, _mock_config)

	assert_eq(_engine.newly_finished.size(), 1, "interaction finished with large delta")


func test_newly_events_cleared_each_tick() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	_engine.tick(0.1, [keeper], entities, _mock_config)
	assert_eq(_engine.newly_started.size(), 1, "started event present")

	# Next tick: still interacting, no new events
	_engine.tick(0.1, [keeper], entities, _mock_config)
	assert_eq(_engine.newly_started.size(), 0, "events cleared next tick")
	assert_eq(_engine.newly_finished.size(), 0, "no finished events yet")


# --- RNG determinism ---

func test_seeded_rng_deterministic_selection() -> void:
	var entities: Array[EntityData] = []
	entities.append(_make_entity("0", "chicken"))
	var keeper = _make_keeper("0", "friendly", "0")

	var e1 = IE.new()
	e1.rng.seed = 1337
	e1.tick(0.1, [keeper], entities, _mock_config)

	var e2 = IE.new()
	e2.rng.seed = 1337
	e2.tick(0.1, [keeper], entities, _mock_config)

	assert_eq(e1.newly_started.size(), 1, "engine 1 started an interaction")
	assert_eq(e2.newly_started.size(), 1, "engine 2 started an interaction")
	assert_eq(
		e1.newly_started[0]["interaction_id"],
		e2.newly_started[0]["interaction_id"],
		"same seed = same interaction picked"
	)


func test_personality_weighting_favors_matches() -> void:
	# Calm keeper + farm chicken with MockConfig:
	#   feed -> personalities [friendly, calm] -> weight 3 (match)
	#   play -> personalities [playful, friendly] -> weight 1 (no match)
	#   train -> zone-excluded for farm
	_engine.rng.seed = 42
	var entity = _make_entity("0", "chicken")
	var keeper = _make_keeper("0", "calm", "0")

	var counts := {}
	for i in range(300):
		var picked = _engine._pick_interaction(keeper, entity, _mock_config)
		var id: String = picked["id"]
		counts[id] = counts.get(id, 0) + 1

	assert_gt(
		float(counts.get("feed", 0)),
		float(counts.get("play", 0)),
		"personality-matched interaction picked more often (3:1 weight)"
	)
	assert_gt(float(counts.get("play", 0)), 0.0, "unmatched interaction still possible")


# --- Helpers ---

func _make_entity(id: String, type_id: String) -> EntityData:
	var e = EntityData.new()
	e.id = id
	e.type_id = type_id
	e.grid_position = Vector2i(0, 0)
	e.level = 1
	return e


func _make_keeper(id: String, personality: String, assigned_entity_id: String):
	var k = KD.new()
	k.id = id
	k.name = "Keeper_%s" % id
	k.personality = personality
	k.assigned_entity_id = assigned_entity_id
	return k


# --- Mock Configs ---

class MockConfig:
	extends RefCounted

	var _configs: Dictionary = {
		"chicken": {
			"name": "Huhn",
			"base_income": 1.0,
			"base_cost": 10.0,
			"cost_exponent": 1.15,
			"zone": "farm",
		},
		"pig": {
			"name": "Schwein",
			"base_income": 3.0,
			"base_cost": 50.0,
			"cost_exponent": 1.15,
			"zone": "farm",
		},
		"parrot": {
			"name": "Papagei",
			"base_income": 20.0,
			"base_cost": 800.0,
			"cost_exponent": 1.15,
			"zone": "tropical",
		},
	}

	var _interactions: Dictionary = {
		"feed": {
			"name": "Füttern",
			"duration": 3.0,
			"cooldown": 15.0,
			"income_multiplier": 2.0,
			"keeper_action": "feed",
			"entity_reaction": "happy",
			"personalities": ["friendly", "calm"],
			"zones": ["farm", "tropical", "arctic", "savanna"],
		},
		"play": {
			"name": "Spielen",
			"duration": 4.0,
			"cooldown": 20.0,
			"income_multiplier": 2.5,
			"keeper_action": "play",
			"entity_reaction": "excited",
			"personalities": ["playful", "friendly"],
			"zones": ["farm", "tropical", "arctic", "savanna"],
		},
		"train": {
			"name": "Training",
			"duration": 5.0,
			"cooldown": 25.0,
			"income_multiplier": 3.0,
			"keeper_action": "train",
			"entity_reaction": "focused",
			"personalities": ["strict"],
			"zones": ["tropical", "savanna"],
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

	func get_interaction_configs() -> Dictionary:
		return _interactions

	func get_interaction_config(interaction_id: String) -> Dictionary:
		return _interactions.get(interaction_id, {})

	func get_progression_milestones() -> Array[Dictionary]:
		return _milestones


class MockConfigTrainOnly:
	extends RefCounted

	var _configs: Dictionary = {
		"chicken": {
			"name": "Huhn",
			"base_income": 1.0,
			"base_cost": 10.0,
			"cost_exponent": 1.15,
			"zone": "farm",
		},
		"parrot": {
			"name": "Papagei",
			"base_income": 20.0,
			"base_cost": 800.0,
			"cost_exponent": 1.15,
			"zone": "tropical",
		},
	}

	var _interactions: Dictionary = {
		"train": {
			"name": "Training",
			"duration": 5.0,
			"cooldown": 25.0,
			"income_multiplier": 3.0,
			"keeper_action": "train",
			"entity_reaction": "focused",
			"personalities": ["strict"],
			"zones": ["tropical", "savanna"],
		},
	}

	func get_entity_config(type_id: String) -> Dictionary:
		if type_id not in _configs:
			return {}
		return _configs[type_id]

	func get_interaction_configs() -> Dictionary:
		return _interactions

	func get_interaction_config(interaction_id: String) -> Dictionary:
		return _interactions.get(interaction_id, {})
