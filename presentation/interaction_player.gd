extends RefCounted
## Sole orchestrator for interaction playback (presentation side).
## Consumes newly_started / newly_finished events from the core
## InteractionEngine each frame and drives sprite reactions, interaction
## sounds (concurrency-capped), and camera nudges. Core decides what
## happens; this class only presents it.
##
## Dependencies are injected via setup():
## - entity_sprites / keeper_sprites: shared Dictionaries owned by main.gd
##   (id -> sprite node). Passed by reference, so sprites spawned later are
##   visible here without re-wiring.
## - camera: anything with nudge_to(pos), or null to disable nudges.
## - config: anything with get_interaction_config(id) -> Dictionary.

const MAX_CONCURRENT_INTERACTION_SOUNDS: int = 3

var _entity_sprites: Dictionary = {}
var _keeper_sprites: Dictionary = {}
var _camera = null
var _config = null
var _sound_slot_owners: Dictionary = {}  # keeper_id -> true


func setup(entity_sprites: Dictionary, keeper_sprites: Dictionary, camera, config) -> void:
	_entity_sprites = entity_sprites
	_keeper_sprites = keeper_sprites
	_camera = camera
	_config = config


func process_events(engine) -> void:
	for event in engine.newly_started:
		_on_interaction_started(event)
	for event in engine.newly_finished:
		_on_interaction_finished(event)


func _on_interaction_started(event: Dictionary) -> void:
	var keeper_id: String = event["keeper_id"]
	var entity_id: String = event["entity_id"]
	var interaction_id: String = event["interaction_id"]

	var interaction_cfg: Dictionary = _config.get_interaction_config(interaction_id)
	if interaction_cfg.is_empty():
		return

	# Keeper plays interaction animation
	if keeper_id in _keeper_sprites:
		_keeper_sprites[keeper_id].play_interaction(interaction_cfg)

	# Entity plays reaction animation + interaction sound (with concurrency limit)
	if entity_id in _entity_sprites:
		var entity_sprite = _entity_sprites[entity_id]
		var reaction_type: String = interaction_cfg.get("entity_reaction", "happy")
		var sound_path := ""
		if _sound_slot_owners.size() < MAX_CONCURRENT_INTERACTION_SOUNDS:
			var action: String = interaction_cfg.get("keeper_action", "feed")
			sound_path = "res://assets/placeholder_sounds/interaction_%s.wav" % action
			_sound_slot_owners[keeper_id] = true
		entity_sprite.play_reaction(reaction_type, sound_path)

		entity_sprite.spawn_interaction_particles()

		if _camera != null:
			_camera.nudge_to(entity_sprite.position)


func _on_interaction_finished(event: Dictionary) -> void:
	var keeper_id: String = event["keeper_id"]
	var entity_id: String = event["entity_id"]

	if keeper_id in _keeper_sprites:
		_keeper_sprites[keeper_id].stop_interaction()

	if entity_id in _entity_sprites:
		_entity_sprites[entity_id].stop_reaction()

	# Release the sound slot only if this keeper actually held one
	_sound_slot_owners.erase(keeper_id)