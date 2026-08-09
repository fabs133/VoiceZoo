extends "res://tests/helpers/base_test.gd"
## Tests for SoundResolver - user recording beats placeholder, with graceful
## fallbacks for every degraded state.

const ResolverScript = preload("res://presentation/sound_resolver.gd")
const PLACEHOLDER := "res://assets/placeholder_sounds/interaction_feed.wav"

var _state: ZooState
var _resolver
var _entity: EntityData


func before_each() -> void:
	_state = ZooState.new()
	_resolver = ResolverScript.new(_state)
	_entity = EntityData.new()
	_entity.id = "0"
	_entity.type_id = "chicken"


func _wav(rate: int = 32000) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(200)
	return WavUtils.build_wav(pcm, rate, 1)


func test_user_recording_wins() -> void:
	var id = _state.sound_bank.add_sound(_wav(32000), "user")
	_entity.sound_ref = id
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_ne(stream, null, "stream resolved")
	assert_true(stream is AudioStreamWAV, "user WAV stream")
	assert_eq(stream.mix_rate, 32000, "it is the user sound, not the placeholder")


func test_no_ref_falls_back_to_placeholder() -> void:
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_ne(stream, null, "placeholder loaded")


func test_metadata_only_bank_entry_falls_back() -> void:
	# save loaded but SoundStore has not delivered bytes (or file missing)
	var id = _state.sound_bank.add_sound(_wav(), "user")
	var restored = ZooState.new()
	restored.from_dict(_state.to_dict())
	var resolver = ResolverScript.new(restored)
	_entity.sound_ref = id
	var stream = resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_ne(stream, null, "fallback stream")
	assert_false(stream is AudioStreamWAV and stream.mix_rate == 32000, "not the (unloaded) user sound")


func test_unknown_ref_falls_back() -> void:
	_entity.sound_ref = "snd_999"
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_ne(stream, null, "unknown ref falls back to placeholder")


func test_nothing_available_returns_null() -> void:
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": ""})
	assert_eq(stream, null, "no user sound, no placeholder -> null")


# --- Rhythm voice length cap (applied once, at stream assignment) ---

func _tone_wav(seconds: float, rate: int = 22050) -> PackedByteArray:
	var frames := int(seconds * float(rate))
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		pcm.encode_s16(i * 2, 8000)
	return WavUtils.build_wav(pcm, rate, 1)


func _stream_seconds(stream) -> float:
	return float(stream.data.size() / 2) / 22050.0


func test_cap_shortens_a_long_user_recording() -> void:
	_entity.sound_ref = _state.sound_bank.add_sound(_tone_wav(3.0), "long")
	_resolver.max_voice_seconds = 1.333
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_true(stream is AudioStreamWAV, "the user recording still wins")
	assert_almost_eq(_stream_seconds(stream), 1.333, 0.01, "cut to two steps' worth")


func test_no_cap_by_default() -> void:
	_entity.sound_ref = _state.sound_bank.add_sound(_tone_wav(3.0), "long")
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_almost_eq(_stream_seconds(stream), 3.0, 0.01, "0 = uncapped, the whole take plays")


func test_cap_leaves_a_short_recording_alone() -> void:
	_entity.sound_ref = _state.sound_bank.add_sound(_tone_wav(0.5), "short")
	_resolver.max_voice_seconds = 1.333
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_almost_eq(_stream_seconds(stream), 0.5, 0.01, "already inside the cap")


func test_changing_the_cap_changes_the_next_resolve() -> void:
	# This is what the tempo-change sweep in main.gd relies on: a faster preset
	# means a shorter cap, and re-resolving is what applies it.
	_entity.sound_ref = _state.sound_bank.add_sound(_tone_wav(3.0), "long")
	_resolver.max_voice_seconds = 1.333  # 90 bpm
	var slow = _resolver.resolve_entity_stream(_entity, {})
	_resolver.max_voice_seconds = 1.09   # 110 bpm
	var fast = _resolver.resolve_entity_stream(_entity, {})
	assert_lt(float(fast.data.size()), float(slow.data.size()), "faster tempo, shorter voice")
	assert_almost_eq(_stream_seconds(fast), 1.09, 0.01, "cut to the new cap")


func test_cap_does_not_break_the_placeholder_fallback() -> void:
	_resolver.max_voice_seconds = 1.0
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_ne(stream, null, "an entity with no recording still gets its placeholder")


func test_bank_swap_on_load_does_not_stale_resolver() -> void:
	# from_dict replaces the sound_bank instance; resolver must follow it
	var id = _state.sound_bank.add_sound(_wav(28000), "user")
	_entity.sound_ref = id
	_state.from_dict(_state.to_dict())  # swaps bank (metadata-only now)
	_state.sound_bank.set_bytes(id, _wav(28000))  # store delivers bytes
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	assert_eq(stream.mix_rate, 28000, "resolver sees the NEW bank instance")