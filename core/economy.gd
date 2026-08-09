class_name Economy
extends RefCounted
## Pure static economy functions - no side effects, no scene tree.

## Fallback when config provides no keeper income bonus.
## The authoritative value lives in data/keepers.json ("income_bonus").
const DEFAULT_KEEPER_INCOME_BONUS := 0.5

## Maximum offline time credited on load (8 hours).
const OFFLINE_CAP_SECONDS := 28800.0


static func calculate_income(entities: Array[EntityData], config, keepers: Array = [], interaction_engine = null) -> float:
	var keeper_bonus := get_keeper_income_bonus(config)
	var total := 0.0
	for e in entities:
		var cfg = config.get_entity_config(e.type_id)
		if cfg.is_empty():
			continue
		var base = cfg["base_income"] * e.level
		if _entity_has_keeper(e.id, keepers):
			if interaction_engine != null and interaction_engine.get_income_multiplier(e.id) > 1.0:
				base *= interaction_engine.get_income_multiplier(e.id)
			else:
				base *= (1.0 + keeper_bonus)
		total += base
	return total


## Pure offline income calculation. Presentation supplies elapsed seconds;
## core owns the cap and the formula. Negative/zero elapsed yields 0.
static func calculate_offline_income(entities: Array[EntityData], config, keepers: Array, elapsed_seconds: float, cap_seconds: float = OFFLINE_CAP_SECONDS) -> float:
	if elapsed_seconds <= 0.0:
		return 0.0
	var credited = minf(elapsed_seconds, cap_seconds)
	return calculate_income(entities, config, keepers) * credited


static func get_keeper_income_bonus(config) -> float:
	if config != null and config.has_method("get_keeper_config"):
		return config.get_keeper_config().get("income_bonus", DEFAULT_KEEPER_INCOME_BONUS)
	return DEFAULT_KEEPER_INCOME_BONUS


static func _entity_has_keeper(entity_id: String, keepers: Array) -> bool:
	for k in keepers:
		if k.assigned_entity_id == entity_id:
			return true
	return false


static func calculate_cost(type_id: String, owned_count: int, config) -> float:
	var cfg = config.get_entity_config(type_id)
	if cfg.is_empty():
		return 0.0
	return cfg["base_cost"] * pow(cfg["cost_exponent"], owned_count)


static func calculate_upgrade_cost(entity: EntityData, config) -> float:
	var cfg = config.get_entity_config(entity.type_id)
	if cfg.is_empty():
		return 0.0
	return cfg["base_cost"] * entity.level * 2.0
