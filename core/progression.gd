class_name Progression
extends RefCounted
## Pure static progression functions — no side effects, no scene tree.


static func get_unlocks(lifetime_coins: float, config) -> Array[String]:
	var result: Array[String] = []
	var milestones = config.get_progression_milestones()
	for m in milestones:
		if lifetime_coins >= m["threshold"]:
			result.append(m["unlock_type"])
	return result
