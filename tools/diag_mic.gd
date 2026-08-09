extends SceneTree
## Microphone capture diagnostic. Run WITHOUT --headless (needs a real
## audio driver): godot --script tools/diag_mic.gd
## Records ~4s from the current input device, reports bytes + peak.
## Interpretation: peak EXACTLY 0.0 = capture path broken; small nonzero
## peak = capture works (room noise floor).


func _initialize() -> void:
	print("--- mic diagnostic ---")
	print("enable_input: ", ProjectSettings.get_setting("audio/driver/enable_input", false))
	print("project mix_rate: ", ProjectSettings.get_setting("audio/driver/mix_rate", 44100))
	print("driver mix_rate: ", AudioServer.get_mix_rate())
	print("input devices: ", AudioServer.get_input_device_list())
	print("current input: ", AudioServer.input_device)

	var idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "DiagRecord")
	AudioServer.set_bus_mute(idx, true)
	var effect := AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(idx, effect)
	var player := AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = "DiagRecord"
	root.add_child(player)

	await create_timer(0.5).timeout
	player.play()
	effect.set_recording_active(true)
	print("recording 4s ...")
	await create_timer(4.0).timeout
	effect.set_recording_active(false)
	player.stop()
	var rec: AudioStreamWAV = effect.get_recording()
	if rec == null:
		print("RESULT: get_recording() returned NULL")
	elif rec.data.size() == 0:
		print("RESULT: recording has ZERO bytes")
	else:
		print("RESULT: format=%d mix_rate=%d stereo=%s bytes=%d" % [rec.format, rec.mix_rate, str(rec.stereo), rec.data.size()])
		var ch := 2 if rec.stereo else 1
		var wav = WavUtils.build_wav(rec.data, rec.mix_rate, ch)
		print("RESULT: peak=%.5f" % WavUtils.get_peak(wav))
	quit(0)