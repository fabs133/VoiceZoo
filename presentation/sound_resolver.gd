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

## Loudness every user recording is matched to before it plays, as RMS.
## 0 disables the matching. See WavUtils.match_loudness for why RMS and not peak.
##
## Applied HERE rather than in prepare_take, for two reasons: it fixes the
## recordings already sitting in people's saves rather than only new ones, and
## the stored bytes stay exactly as they were captured, so changing this number
## later re-levels every existing sound instead of baking a mistake in forever.
## The stored bytes are the input every time, so this never compounds.
var target_rms: float = WavUtils.DEFAULT_TARGET_RMS


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
			# After the cap, so the level is measured over what actually plays
			# rather than over a tail that gets cut off anyway.
			if target_rms > 0.0:
				var levelled := WavUtils.match_loudness(bytes, target_rms)
				if levelled.size() > 0:
					bytes = levelled
			var stream = WavUtils.to_stream(bytes)
			if stream != null:
				return stream
	var path: String = cfg.get("default_sound", "")
	if path == "":
		return null
	return load(path)