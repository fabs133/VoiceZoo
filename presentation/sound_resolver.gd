extends RefCounted
## Resolves which AudioStream an entity plays: a user-recorded sound
## (entity.sound_ref present in the SoundBank with loaded bytes) wins over
## the placeholder default from config. Holds the ZooState, not the bank -
## from_dict() swaps the bank instance on load and this must not go stale.
##
## Rhythm decides WHEN an entity sings, this decides WHAT it sings with.
## The length cap below applies to user recordings only; placeholders are
## imported resources and are already short enough for the loop.

var _zoo_state

## Length cap for user recordings, in seconds; 0 disables it. main.gd sets it
## from rhythm.voice_length_seconds() - a recording longer than two steps
## smears across the following beats.
##
## The cap is applied HERE, once, when a sprite is handed its stream. It slices
## the PCM and rebuilds the WAV, so doing it per trigger would copy tens of KB
## on every beat for every animal - six of those in one frame is a real hitch
## on a phone browser. The cost is that the cap moves with the tempo: whoever
## changes the tempo must re-resolve every sprite's stream (main.set_tempo).
var max_voice_seconds: float = 0.0


func _init(zoo_state) -> void:
	_zoo_state = zoo_state


func resolve_entity_stream(entity, cfg: Dictionary) -> AudioStream:
	if entity != null and entity.sound_ref != "" and _zoo_state != null:
		var bytes: PackedByteArray = _zoo_state.sound_bank.get_bytes(entity.sound_ref)
		if bytes.size() > 0:
			if max_voice_seconds > 0.0:
				var capped := WavUtils.cap_length(bytes, max_voice_seconds)
				if capped.size() > 0:
					bytes = capped
			var stream = WavUtils.to_stream(bytes)
			if stream != null:
				return stream
	var path: String = cfg.get("default_sound", "")
	if path == "":
		return null
	return load(path)