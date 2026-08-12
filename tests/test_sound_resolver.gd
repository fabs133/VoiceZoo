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


## A take shaped like speech: sparse loud transients over a quiet body, giving a
## crest factor near 10 - roughly what a voice measures, and about 3.5x peakier
## than the shipped placeholder sounds.
func _peaky_wav(peak: float, seconds: float = 0.4, rate: int = 22050) -> PackedByteArray:
	var n := int(seconds * float(rate))
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var envelope: float = peak if i % 50 == 0 else peak * 0.05
		var s: float = sin(TAU * 220.0 * float(i) / float(rate)) * envelope
		pcm.encode_s16(i * 2, clampi(int(s * 32767.0), -32768, 32767))
	return WavUtils.build_wav(pcm, rate, 1)


func test_a_recording_is_levelled_to_the_shared_loudness() -> void:
	# The reported problem: recordings sat quietly under the placeholder sounds
	# they replaced, because both were normalized by PEAK and a voice carries far
	# less loudness at the same peak. The resolver levels by RMS on the way out.
	var quiet := _peaky_wav(0.9)
	_entity.sound_ref = _state.sound_bank.add_sound(quiet, "leise")
	var stream = _resolver.resolve_entity_stream(_entity, {"default_sound": PLACEHOLDER})
	var played := WavUtils.build_wav(stream.data, int(stream.mix_rate), 1)
	assert_gt(WavUtils.get_rms(played), WavUtils.get_rms(quiet) * 1.5, "it comes out louder")
	assert_almost_eq(WavUtils.get_rms(played), WavUtils.DEFAULT_TARGET_RMS, 0.03,
		"at the level the placeholder sounds sit at")


func test_levelling_leaves_the_stored_recording_untouched() -> void:
	# The bank keeps what was captured. Levelling happens on the way to playback
	# so the target can be changed later and every existing sound re-levels.
	var original := _peaky_wav(0.9)
	_entity.sound_ref = _state.sound_bank.add_sound(original, "leise")
	_resolver.resolve_entity_stream(_entity, {})
	_resolver.resolve_entity_stream(_entity, {})
	assert_eq(_state.sound_bank.get_bytes(_entity.sound_ref), original,
		"repeated resolves never compound onto the stored bytes")


func test_levelling_can_be_switched_off() -> void:
	var original := _peaky_wav(0.9)
	_entity.sound_ref = _state.sound_bank.add_sound(original, "leise")
	_resolver.target_rms = 0.0
	var stream = _resolver.resolve_entity_stream(_entity, {})
	var played := WavUtils.build_wav(stream.data, int(stream.mix_rate), 1)
	assert_almost_eq(WavUtils.get_rms(played), WavUtils.get_rms(original), 0.001,
		"0 leaves the take exactly as captured")


func test_a_recording_plays_louder_than_a_placeholder() -> void:
	# Levelling the recordings was not enough on a device: the built-in sounds
	# are short aggressive bursts and punched through a spoken phrase carrying
	# the same measured energy. They play under it now.
	var without: float = _resolver.volume_db_for(_entity)
	_entity.sound_ref = _state.sound_bank.add_sound(_peaky_wav(0.9), "meine Stimme")
	var with_recording: float = _resolver.volume_db_for(_entity)
	assert_lt(without, with_recording, "the built-in sound sits below the guest's voice")
	assert_almost_eq(with_recording, 0.0, 0.001, "and the recording plays at full level")


func test_a_metadata_only_entry_counts_as_no_recording() -> void:
	# Bytes not loaded means the placeholder is what will actually play, so it
	# must be trimmed like one rather than left at recording level.
	_state.sound_bank.add_sound(_wav(), "user")
	var restored = ZooState.new()
	restored.from_dict(_state.to_dict())
	var resolver = ResolverScript.new(restored)
	var entity = EntityData.new()
	entity.id = "0"
	entity.type_id = "chicken"
	entity.sound_ref = "snd_1"
	assert_false(resolver.has_user_recording(entity), "a ref without bytes is not a recording")
	assert_almost_eq(resolver.volume_db_for(entity), ResolverScript.PLACEHOLDER_TRIM_DB, 0.001,
		"so it plays at the placeholder level")


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