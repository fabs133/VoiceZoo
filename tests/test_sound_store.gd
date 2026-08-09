extends "res://tests/helpers/base_test.gd"
## Tests for SoundStore - disk roundtrip against a scratch directory.

const SoundStoreScript = preload("res://presentation/sound_store.gd")
const TEST_ROOT := "user://test_sounds"

var _store


func before_each() -> void:
	_cleanup()
	_store = SoundStoreScript.new(TEST_ROOT)


func _cleanup() -> void:
	var dir = DirAccess.open(TEST_ROOT)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.open("user://").remove(TEST_ROOT.trim_prefix("user://"))


func _wav() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(200)
	return WavUtils.build_wav(pcm, 22050, 1)


func test_save_and_load_roundtrip() -> void:
	var bank = SoundBank.new()
	var id1 = bank.add_sound(_wav(), "a")
	var id2 = bank.add_sound(_wav(), "b")
	assert_eq(_store.save_all(bank), 2, "two files written")
	assert_true(FileAccess.file_exists(TEST_ROOT + "/" + id1 + ".wav"), "file 1 on disk")

	# fresh bank from metadata, then load bytes from disk
	var restored = SoundBank.new()
	restored.from_dict(bank.to_dict())
	assert_eq(restored.get_bytes(id1).size(), 0, "empty before load")
	assert_eq(_store.load_all(restored), 2, "two loaded")
	assert_eq(restored.get_bytes(id1), bank.get_bytes(id1), "bytes identical after roundtrip")
	assert_eq(restored.get_bytes(id2), bank.get_bytes(id2), "second sound too")
	_cleanup()


func test_orphan_sweep_on_save() -> void:
	var bank = SoundBank.new()
	var id1 = bank.add_sound(_wav())
	var id2 = bank.add_sound(_wav())
	_store.save_all(bank)
	bank.remove_sound(id1)
	_store.save_all(bank)
	assert_false(FileAccess.file_exists(TEST_ROOT + "/" + id1 + ".wav"), "removed sound swept from disk")
	assert_true(FileAccess.file_exists(TEST_ROOT + "/" + id2 + ".wav"), "kept sound untouched")
	_cleanup()


func test_metadata_only_entries_never_clobber_disk() -> void:
	var bank = SoundBank.new()
	var id = bank.add_sound(_wav())
	_store.save_all(bank)
	# simulate next session: metadata restored, bytes not yet loaded
	var restored = SoundBank.new()
	restored.from_dict(bank.to_dict())
	assert_eq(_store.save_all(restored), 0, "nothing written for empty-bytes entries")
	assert_true(FileAccess.file_exists(TEST_ROOT + "/" + id + ".wav"), "file survives an early save")
	_cleanup()


func test_missing_file_is_not_fatal() -> void:
	var bank = SoundBank.new()
	bank.add_sound(_wav())
	var restored = SoundBank.new()
	restored.from_dict(bank.to_dict())  # metadata exists, no file on disk
	assert_eq(_store.load_all(restored), 0, "missing file loads nothing")
	assert_eq(restored.get_bytes("snd_1").size(), 0, "entry stays metadata-only")
	_cleanup()

func test_unchanged_sounds_are_not_rewritten() -> void:
	# The 30s autosave must not rewrite every recorded WAV every time.
	var bank = SoundBank.new()
	bank.add_sound(_wav(), "a")
	bank.add_sound(_wav(), "b")
	assert_eq(_store.save_all(bank), 2, "both written the first time")
	assert_eq(_store.save_all(bank), 0, "second save writes nothing")

	bank.add_sound(_wav(), "c")
	assert_eq(_store.save_all(bank), 1, "only the new sound is written")
	_cleanup()


func test_a_missing_file_is_rewritten_even_when_clean() -> void:
	var bank = SoundBank.new()
	var id = bank.add_sound(_wav(), "a")
	_store.save_all(bank)
	DirAccess.open(TEST_ROOT).remove(id + ".wav")
	assert_eq(_store.save_all(bank), 1, "a vanished file is written again")
	assert_true(FileAccess.file_exists(TEST_ROOT + "/" + id + ".wav"), "restored on disk")
	_cleanup()
