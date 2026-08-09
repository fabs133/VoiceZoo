extends SceneTree
## Output-device matrix probe: for each render device, switch Godot's output
## to it, report the resulting driver mix rate, and run a capture test on the
## USB condenser mic. Nonzero peak = working capture under that output.

const MIC := "Mikrofon (USB Condenser Microphone)"


func _initialize() -> void:
	print("output devices: ", AudioServer.get_output_device_list())
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
	AudioServer.input_device = MIC

	for out_dev in AudioServer.get_output_device_list():
		AudioServer.output_device = out_dev
		await create_timer(0.6).timeout
		var rate = AudioServer.get_mix_rate()
		player.play()
		effect.set_recording_active(true)
		await create_timer(1.5).timeout
		effect.set_recording_active(false)
		player.stop()
		var rec: AudioStreamWAV = effect.get_recording()
		if rec == null or rec.data.size() == 0:
			print("OUT [%s]: mix=%d -> capture: NO DATA" % [out_dev, rate])
		else:
			var ch := 2 if rec.stereo else 1
			var wav = WavUtils.build_wav(rec.data, rec.mix_rate, ch)
			print("OUT [%s]: mix=%d -> capture rate=%d peak=%.5f" % [out_dev, rate, rec.mix_rate, WavUtils.get_peak(wav)])
	quit(0)