extends SceneTree
## Inventory of stored sounds: peak per file + which entity references what.

func _init() -> void:
	print("--- stored sounds ---")
	var dir = DirAccess.open("user://sounds")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".wav"):
				var bytes = FileAccess.get_file_as_bytes("user://sounds/" + f)
				var h = WavUtils.parse_header(bytes)
				var secs := 0.0
				if not h.is_empty():
					secs = float(h["data_size"]) / float(h["sample_rate"] * h["channels"] * 2)
				print("%s: rate=%d ch=%d len=%.1fs peak=%.4f" % [f, h.get("sample_rate", 0), h.get("channels", 0), secs, WavUtils.get_peak(bytes)])
	print("--- entity refs ---")
	var file = FileAccess.open("user://save.json", FileAccess.READ)
	if file != null:
		var data = JSON.parse_string(file.get_as_text())
		for e in data.get("entities", []):
			if e.get("sound_ref", "") != "":
				print("%s (%s) -> %s" % [e["type_id"], e["id"], e["sound_ref"]])
	quit(0)