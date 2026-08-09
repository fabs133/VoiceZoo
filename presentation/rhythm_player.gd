extends RefCounted
## Sole orchestrator for rhythm playback (presentation side).
## Consumes newly_triggered from the core RhythmEngine each frame and tells the
## entity sprites to sing. The engine decides WHEN and WHO, SoundResolver
## decides WHAT, this class only fires it. Deliberately the same shape as
## InteractionPlayer.
##
## Dependencies are injected via setup():
## - entity_sprites: the shared Dictionary owned by main.gd (id -> sprite node).
##   Passed by reference, so animals bought later are visible here without
##   re-wiring.
##
## Firing a beat must stay nearly free: the stream is resolved and
## length-capped once, when it is assigned to the sprite, so play_beat() only
## sets a pitch and calls play(). Nothing in this path allocates.

var _entity_sprites: Dictionary = {}

## Beats that found no sprite, for diagnostics. A trigger for an animal that
## was just sold is normal; a permanently rising count is a wiring bug.
var missed_triggers: int = 0


func setup(entity_sprites: Dictionary) -> void:
	_entity_sprites = entity_sprites


func process_triggers(engine) -> void:
	for trigger in engine.newly_triggered:
		_play_trigger(trigger)


## Fires one animal outside the transport - the Studio's immediate preview when
## a cell is tapped. Deliberately the same path as a real trigger, so what you
## hear when you place a beat is exactly what you will hear when it plays.
func preview(entity_id: String, pitch_scale: float = 1.0) -> void:
	_play_trigger({"entity_id": entity_id, "pitch_scale": pitch_scale})


func _play_trigger(trigger: Dictionary) -> void:
	var sprite = _entity_sprites.get(trigger["entity_id"])
	if sprite == null:
		missed_triggers += 1
		return
	sprite.play_beat(trigger.get("pitch_scale", 1.0))
