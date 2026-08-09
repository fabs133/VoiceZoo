extends SceneTree
## Playback diagnostic: loads the newest user sound and plays it twice -
## (1) plain AudioStreamPlayer (non-positional), (2) AudioStreamPlayer2D
## configured exactly like entity_sprite (attenuation 1.5, max 800, -3db).

func _initialize() -> void:
	var dir = DirAccess.open("user://sounds")
	if dir == null:
		print("RESULT: no sounds directory")
		quit(1)
		return
	var newest := ""
	for f in dir.get_files():
		if f.ends_with(".wav"):
			newest = f
	if newest == "":
		print("RESULT: no wav files")
		quit(1)
		return
	var bytes = FileAccess.get_file_as_bytes("user://sounds/" + newest)
	var h = WavUtils.parse_header(bytes)
	print("FILE: %s bytes=%d header=%s peak=%.4f" % [newest, bytes.size(), str(h), WavUtils.get_peak(bytes)])
	var stream = WavUtils.to_stream(bytes)
	if stream == null:
		print("RESULT: to_stream returned NULL")
		quit(1)
		return
	print("STREAM: mix_rate=%d stereo=%s length=%.2fs" % [stream.mix_rate, str(stream.stereo), stream.get_length()])

	print("PLAY 1: plain AudioStreamPlayer (you should hear your recording)")
	var p1 := AudioStreamPlayer.new()
	root.add_child(p1)
	p1.stream = stream
	p1.play()
	await create_timer(stream.get_length() + 0.5).timeout

	print("PLAY 2: AudioStreamPlayer2D, entity_sprite settings, at screen center")
	var p2 := AudioStreamPlayer2D.new()
	p2.max_distance = 800.0
	p2.attenuation = 1.5
	p2.volume_db = -3.0
	root.add_child(p2)
	p2.position = get_root().get_visible_rect().size / 2.0
	p2.stream = stream
	p2.play()
	await create_timer(stream.get_length() + 0.5).timeout
	print("RESULT: both playbacks attempted - which did you hear?")
	quit(0)