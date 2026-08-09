class_name InteractionEngine
extends RefCounted
## Manages keeper-entity interactions. Pure logic, no scene tree dependencies.
## Keepers periodically interact with their assigned entity for a temporary
## income boost. Interaction type is selected based on zone + personality.

## Injectable RNG - seed in tests for deterministic interaction selection.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _active_interactions: Dictionary = {}  # keeper_id -> {interaction_id, entity_id, remaining_time, total_duration, income_multiplier}
var _cooldowns: Dictionary = {}  # keeper_id -> float (seconds remaining)

var newly_started: Array[Dictionary] = []
var newly_finished: Array[Dictionary] = []


func tick(delta: float, keepers: Array, entities: Array[EntityData], config) -> void:
	newly_started.clear()
	newly_finished.clear()

	# 1. Decrement cooldowns
	var expired_cooldowns: Array[String] = []
	for keeper_id in _cooldowns:
		_cooldowns[keeper_id] -= delta
		if _cooldowns[keeper_id] <= 0.0:
			expired_cooldowns.append(keeper_id)
	for keeper_id in expired_cooldowns:
		_cooldowns.erase(keeper_id)

	# 2. Advance active interactions
	var finished_keepers: Array[String] = []
	for keeper_id in _active_interactions:
		_active_interactions[keeper_id]["remaining_time"] -= delta
		if _active_interactions[keeper_id]["remaining_time"] <= 0.0:
			finished_keepers.append(keeper_id)

	# 3. Finish completed interactions -> start cooldown
	for keeper_id in finished_keepers:
		var interaction = _active_interactions[keeper_id]
		var cfg = config.get_interaction_config(interaction["interaction_id"])
		_cooldowns[keeper_id] = cfg.get("cooldown", 15.0)
		newly_finished.append({
			"keeper_id": keeper_id,
			"entity_id": interaction["entity_id"],
			"interaction_id": interaction["interaction_id"],
		})
		_active_interactions.erase(keeper_id)

	# 4. Start new interactions for idle, assigned, off-cooldown keepers
	for keeper in keepers:
		if keeper.assigned_entity_id == "":
			continue
		if keeper.id in _active_interactions:
			continue
		if keeper.id in _cooldowns:
			continue
		var entity = _find_entity(keeper.assigned_entity_id, entities)
		if entity == null:
			continue
		var picked = _pick_interaction(keeper, entity, config)
		if picked.is_empty():
			continue
		_active_interactions[keeper.id] = {
			"interaction_id": picked["id"],
			"entity_id": entity.id,
			"remaining_time": picked["duration"],
			"total_duration": picked["duration"],
			"income_multiplier": picked["income_multiplier"],
		}
		newly_started.append({
			"keeper_id": keeper.id,
			"entity_id": entity.id,
			"interaction_id": picked["id"],
		})


func get_active_interaction(keeper_id: String) -> Dictionary:
	return _active_interactions.get(keeper_id, {})


func get_income_multiplier(entity_id: String) -> float:
	for keeper_id in _active_interactions:
		if _active_interactions[keeper_id]["entity_id"] == entity_id:
			return _active_interactions[keeper_id]["income_multiplier"]
	return 1.0


func is_interacting(keeper_id: String) -> bool:
	return keeper_id in _active_interactions


func to_dict() -> Dictionary:
	return {
		"active_interactions": _active_interactions.duplicate(true),
		"cooldowns": _cooldowns.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	_active_interactions = d.get("active_interactions", {}).duplicate(true)
	_cooldowns = d.get("cooldowns", {}).duplicate()


# --- Private ---

func _find_entity(entity_id: String, entities: Array[EntityData]) -> EntityData:
	for e in entities:
		if e.id == entity_id:
			return e
	return null


func _pick_interaction(keeper, entity: EntityData, config) -> Dictionary:
	var entity_cfg = config.get_entity_config(entity.type_id)
	if entity_cfg.is_empty():
		return {}
	var entity_zone = entity_cfg.get("zone", "")

	var interaction_configs = config.get_interaction_configs()
	if interaction_configs.is_empty():
		return {}

	# Build weighted candidate list
	var candidates: Array[Dictionary] = []  # [{id, duration, income_multiplier, weight}]
	var total_weight := 0.0

	for interaction_id in interaction_configs:
		var cfg = interaction_configs[interaction_id]
		var zones: Array = cfg.get("zones", [])
		if entity_zone not in zones:
			continue
		var personalities: Array = cfg.get("personalities", [])
		var weight := 1.0
		if keeper.personality in personalities:
			weight = 3.0
		candidates.append({
			"id": interaction_id,
			"duration": cfg.get("duration", 3.0),
			"income_multiplier": cfg.get("income_multiplier", 1.5),
			"weight": weight,
		})
		total_weight += weight

	if candidates.is_empty() or total_weight <= 0.0:
		return {}

	# Weighted random selection
	var roll = rng.randf() * total_weight
	var cumulative := 0.0
	for candidate in candidates:
		cumulative += candidate["weight"]
		if roll <= cumulative:
			return candidate

	return candidates[candidates.size() - 1]

