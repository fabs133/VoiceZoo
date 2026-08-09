extends SceneTree
## Per-device mic probe: records ~1.5s from EVERY input device and reports
## the peak. peak > 0 = that device delivers samples at the current rates.


func _initialize() -> void:
	print("driver mix_rate: ", AudioServer.get_mix_rate())
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

	for device in AudioServer.get_input_device_list():
		AudioServer.input_device = device
		await create_timer(0.3).timeout
		player.play()
		effect.set_recording_active(true)
		await create_timer(1.5).timeout
		effect.set_recording_active(false)
		player.stop()
		var rec: AudioStreamWAV = effect.get_recording()
		if rec == null or rec.data.size() == 0:
			print("DEVICE [%s]: no data" % device)
		else:
			var ch := 2 if rec.stereo else 1
			var wav = WavUtils.build_wav(rec.data, rec.mix_rate, ch)
			print("DEVICE [%s]: rate=%d bytes=%d peak=%.5f" % [device, rec.mix_rate, rec.data.size(), WavUtils.get_peak(wav)])
	quit(0)