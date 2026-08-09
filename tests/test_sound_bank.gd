extends "res://tests/helpers/base_test.gd"
## Tests for SoundBank - registry semantics and both serialization contracts.

var _bank


func before_each() -> void:
	_bank = SoundBank.new()


func _wav(rate: int = 22050) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(200)
	return WavUtils.build_wav(pcm, rate, 1)


# --- Capture chain (prepare_take) ---

## A raw take: `lead` silent frames then `body` frames at `amp`.
func _take(rate: int, channels: int, lead: int, body: int, amp: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize((lead + body) * channels * 2)
	for i in body:
		for c in channels:
			pcm.encode_s16(((lead + i) * channels + c) * 2, amp)
	return WavUtils.build_wav(pcm, rate, channels)


func test_prepare_take_canonicalizes_a_48k_stereo_recording() -> void:
	# 400ms of room silence then 200ms of quiet sound - the realistic bad take.
	var out = SoundBank.prepare_take(_take(48000, 2, 19200, 9600, 3000))
	var h = WavUtils.parse_header(out)
	assert_true(WavUtils.is_valid_wav(out), "valid WAV out")
	assert_eq(h["channels"], 1, "downmixed to mono")
	assert_eq(h["sample_rate"], SoundBank.CANONICAL_SAMPLE_RATE, "canonical rate")
	assert_lt(WavUtils.duration_seconds(out), 0.3, "the dead air is trimmed off")
	assert_gt(WavUtils.duration_seconds(out), 0.19, "the sound itself survives")
	assert_almost_eq(WavUtils.get_peak(out), 0.9, 0.02, "and it is normalized")


func test_prepare_take_output_is_accepted_by_the_bank() -> void:
	var id = _bank.add_sound(SoundBank.prepare_take(_take(48000, 2, 4800, 4800, 5000)), "take")
	assert_ne(id, "", "a prepared take enters the bank")
	assert_eq(_bank.get_sample_rate(id), SoundBank.CANONICAL_SAMPLE_RATE, "stored at the canonical rate")


func test_prepare_take_never_loses_a_take() -> void:
	var garbage := PackedByteArray()
	garbage.resize(50)
	assert_eq(SoundBank.prepare_take(garbage), garbage, "unconvertible input comes back unchanged")


func test_prepare_take_of_an_already_canonical_take() -> void:
	# mono, canonical rate, tight, already loud: every step is a no-op.
	var raw = _take(22050, 1, 0, 11025, 30000)
	assert_eq(SoundBank.prepare_take(raw), raw, "nothing to do, nothing changed")


func test_add_and_get() -> void:
	var id = _bank.add_sound(_wav(), "Bark", 123.0)
	assert_eq(id, "snd_1", "first id")
	assert_true(_bank.has_sound(id), "registered")
	assert_eq(_bank.get_bytes(id).size(), 244, "bytes stored (44 header + 200 pcm)")
	assert_eq(_bank.get_label(id), "Bark", "label")
	assert_eq(_bank.get_sample_rate(id), 22050, "rate from header")
	assert_eq(_bank.size(), 1, "size")


func test_ids_increment() -> void:
	assert_eq(_bank.add_sound(_wav()), "snd_1", "first")
	assert_eq(_bank.add_sound(_wav()), "snd_2", "second")


func test_invalid_rejected() -> void:
	var garbage := PackedByteArray()
	garbage.resize(50)
	assert_eq(_bank.add_sound(garbage), "", "garbage rejected")
	var huge := PackedByteArray()
	huge.resize(SoundBank.MAX_SOUND_BYTES + 1)
	assert_eq(_bank.add_sound(huge), "", "oversized rejected")
	assert_eq(_bank.size(), 0, "nothing stored")


func test_remove() -> void:
	var id = _bank.add_sound(_wav())
	assert_true(_bank.remove_sound(id), "removed")
	assert_false(_bank.has_sound(id), "gone")
	assert_false(_bank.remove_sound("snd_99"), "unknown remove is false")


func test_working_save_is_metadata_only() -> void:
	_bank.add_sound(_wav(), "Meow", 5.0)
	var d = _bank.to_dict()
	assert_eq(d["sounds"].size(), 1, "one entry")
	assert_false(d["sounds"][0].has("data_b64"), "no bytes in working save")
	assert_false(d["sounds"][0].has("bytes"), "no raw bytes either")

	var restored = SoundBank.new()
	restored.from_dict(d)
	assert_true(restored.has_sound("snd_1"), "metadata restored")
	assert_eq(restored.get_bytes("snd_1").size(), 0, "bytes empty until store loads")
	assert_eq(restored.get_label("snd_1"), "Meow", "label restored")
	assert_eq(restored.add_sound(_wav()), "snd_2", "next_id survives roundtrip")


func test_set_bytes_validates() -> void:
	_bank.add_sound(_wav(), "x", 0.0)
	var restored = SoundBank.new()
	restored.from_dict(_bank.to_dict())
	var garbage := PackedByteArray()
	garbage.resize(30)
	assert_false(restored.set_bytes("snd_1", garbage), "invalid bytes rejected")
	assert_false(restored.set_bytes("snd_99", _wav()), "unknown id rejected")
	assert_true(restored.set_bytes("snd_1", _wav()), "valid bytes accepted")
	assert_eq(restored.get_bytes("snd_1").size(), 244, "bytes filled")


func test_export_roundtrip_carries_bytes() -> void:
	var id = _bank.add_sound(_wav(44100), "Roar", 9.0)
	var snapshot = _bank.to_export_dict()
	assert_true(snapshot["sounds"][0].has("data_b64"), "export embeds base64")

	var imported = SoundBank.new()
	assert_eq(imported.from_export_dict(snapshot), 1, "one imported")
	assert_eq(imported.get_bytes(id), _bank.get_bytes(id), "bytes identical")
	assert_eq(imported.get_sample_rate(id), 44100, "rate re-derived from bytes")


func test_export_skips_tampered_entries() -> void:
	_bank.add_sound(_wav(), "good")
	var snapshot = _bank.to_export_dict()
	snapshot["sounds"][0]["data_b64"] = "bm90IGEgd2F2"  # "not a wav"
	var imported = SoundBank.new()
	assert_eq(imported.from_export_dict(snapshot), 0, "tampered entry skipped")
	assert_eq(imported.size(), 0, "nothing kept")

# --- Dirty tracking (the autosave must not rewrite unchanged audio) ---

func test_new_sound_is_dirty_until_written() -> void:
	var id = _bank.add_sound(_wav(), "x")
	assert_true(_bank.is_dirty(id), "a fresh recording needs writing")
	_bank.mark_clean(id)
	assert_false(_bank.is_dirty(id), "clean once the store has written it")


func test_loaded_metadata_is_not_dirty() -> void:
	_bank.add_sound(_wav(), "x")
	var restored = SoundBank.new()
	restored.from_dict(_bank.to_dict())
	assert_false(restored.is_dirty("snd_1"), "bytes already on disk - nothing to write")
	restored.set_bytes("snd_1", _wav())
	assert_false(restored.is_dirty("snd_1"), "loading bytes off disk does not dirty them")


func test_imported_sounds_are_dirty() -> void:
	_bank.add_sound(_wav(), "x")
	var imported = SoundBank.new()
	imported.from_export_dict(_bank.to_export_dict())
	assert_true(imported.is_dirty("snd_1"), "imported bytes have never reached the disk")


func test_removed_sound_is_no_longer_dirty() -> void:
	var id = _bank.add_sound(_wav(), "x")
	_bank.remove_sound(id)
	assert_false(_bank.is_dirty(id), "nothing to write for a deleted sound")
