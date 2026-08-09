extends Node
## Autoload singleton — loads game configuration from JSON files.

var _entity_configs: Dictionary = {}
var _progression_milestones: Array[Dictionary] = []
var _keeper_config: Dictionary = {}
var _interaction_configs: Dictionary = {}
var _rhythm_config: Dictionary = {}


func _ready() -> void:
	_load_entities()
	_load_progression()
	_load_keepers()
	_load_interactions()
	_load_rhythm()


func get_entity_config(type_id: String) -> Dictionary:
	if type_id not in _entity_configs:
		push_error("Config: unknown entity type '%s'" % type_id)
		return {}
	return _entity_configs[type_id]


func get_all_entity_types() -> Array[String]:
	var types: Array[String] = []
	for key in _entity_configs:
		types.append(key)
	return types


func get_progression_milestones() -> Array[Dictionary]:
	return _progression_milestones


func get_keeper_config() -> Dictionary:
	return _keeper_config


func get_interaction_configs() -> Dictionary:
	return _interaction_configs


func get_interaction_config(interaction_id: String) -> Dictionary:
	return _interaction_configs.get(interaction_id, {})


## Transport + default patterns for RhythmEngine (see data/rhythm.json).
func get_rhythm_config() -> Dictionary:
	return _rhythm_config


## The three coarse tempo presets; [] if rhythm.json is missing.
func get_tempo_presets() -> Array:
	return _rhythm_config.get("tempo_presets", [])


func _load_entities() -> void:
	var file = FileAccess.open("res://data/entities.json", FileAccess.READ)
	if not file:
		push_error("Config: could not open entities.json")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("Config: entities.json parse error: %s" % json.get_error_message())
		return
	_entity_configs = json.data
	print("Config: loaded %d entity types" % _entity_configs.size())


func _load_progression() -> void:
	var file = FileAccess.open("res://data/progression.json", FileAccess.READ)
	if not file:
		push_warning("Config: progression.json not found, skipping")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("Config: progression.json parse error: %s" % json.get_error_message())
		return
	_progression_milestones = []
	for m in json.data.get("milestones", []):
		_progression_milestones.append(m)
	print("Config: loaded %d progression milestones" % _progression_milestones.size())


func _load_keepers() -> void:
	var file = FileAccess.open("res://data/keepers.json", FileAccess.READ)
	if not file:
		push_warning("Config: keepers.json not found, skipping")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("Config: keepers.json parse error: %s" % json.get_error_message())
		return
	_keeper_config = json.data
	print("Config: loaded keeper config")


func _load_interactions() -> void:
	var file = FileAccess.open("res://data/interactions.json", FileAccess.READ)
	if not file:
		push_warning("Config: interactions.json not found, skipping")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("Config: interactions.json parse error: %s" % json.get_error_message())
		return
	_interaction_configs = json.data
	print("Config: loaded %d interaction types" % _interaction_configs.size())


func _load_rhythm() -> void:
	var file = FileAccess.open("res://data/rhythm.json", FileAccess.READ)
	if not file:
		push_warning("Config: rhythm.json not found, skipping")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK:
		push_error("Config: rhythm.json parse error: %s" % json.get_error_message())
		return
	_rhythm_config = json.data
	print("Config: loaded rhythm config (%d bpm, %d steps)" % [
		int(_rhythm_config.get("bpm", 0)), int(_rhythm_config.get("steps_per_loop", 0)),
	])
