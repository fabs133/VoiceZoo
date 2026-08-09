extends RefCounted
## Disk adapter between SoundBank (pure, in-memory) and the filesystem.
## Presentation-side by design: core stays free of I/O; persistence lives on
## the same side of the boundary as main.gd's save.json handling.
##
## Layout: <root>/snd_<n>.wav - one file per bank entry.
## Root is injectable so tests run against a scratch directory.

var _root: String


func _init(root: String = "user://sounds") -> void:
	_root = root


## Writes every sound that has bytes, and deletes orphaned snd_*.wav files
## whose id is no longer in the bank (sync semantics, so remove_sound sticks).
## Returns the number of files written.
func save_all(bank) -> int:
	DirAccess.make_dir_recursive_absolute(_root)
	var written := 0
	var valid_names := {}
	for id in bank.get_ids():
		var bytes: PackedByteArray = bank.get_bytes(id)
		if bytes.size() == 0:
			continue  # metadata-only entry (not loaded); never overwrite with nothing
		valid_names[id + ".wav"] = true
		# Already on disk and unchanged - skip it. The autosave runs every 30s
		# and rewriting every recorded WAV each time is a real cost on a phone.
		if not bank.is_dirty(id) and FileAccess.file_exists(_path(id)):
			continue
		var f = FileAccess.open(_path(id), FileAccess.WRITE)
		if f == null:
			push_error("SoundStore: cannot write %s" % _path(id))
			continue
		f.store_buffer(bytes)
		f.close()
		bank.mark_clean(id)
		written += 1
	# orphan sweep - only ever touches our own naming pattern
	var dir = DirAccess.open(_root)
	if dir != null:
		for file_name in dir.get_files():
			if file_name.begins_with("snd_") and file_name.ends_with(".wav") and not file_name in valid_names:
				if bank.has_sound(file_name.trim_suffix(".wav")):
					continue  # metadata-only entry whose bytes we skipped above
				dir.remove(file_name)
	return written


## Loads bytes from disk for every metadata-only entry in the bank.
## Returns the number of sounds loaded. Missing files are logged, not fatal.
func load_all(bank) -> int:
	var loaded := 0
	for id in bank.get_ids():
		if bank.get_bytes(id).size() > 0:
			continue
		if not FileAccess.file_exists(_path(id)):
			push_warning("SoundStore: missing file for %s" % id)
			continue
		var bytes = FileAccess.get_file_as_bytes(_path(id))
		if bank.set_bytes(id, bytes):
			loaded += 1
		else:
			push_warning("SoundStore: invalid file for %s" % id)
	return loaded


func _path(id: String) -> String:
	return _root.path_join(id + ".wav")