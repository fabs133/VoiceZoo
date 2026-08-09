extends SceneTree
## Focused capture probe: three candidate output devices, generous settle
## time (2s) after each switch, 3s capture from the USB condenser.

const MIC := "Mikrofon (USB Condenser Microphone)"
const OUTPUTS := [
	"Kopfhörer (2- Arctis 7+)",
	"VG248 (NVIDIA High Definition Audio)",
	"Lautsprecher (Steam Streaming Speakers)",
]


func _initialize() -> void:
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

	for out_dev in OUTPUTS:
		var found := false
		for d in AudioServer.get_output_device_list():
			if d == out_dev:
				found = true
		if not found:
			print("OUT [%s]: not present, skipped" % out_dev)
			continue
		AudioServer.output_device = out_dev
		await create_timer(2.0).timeout
		AudioServer.input_device = MIC
		await create_timer(0.5).timeout
		player.play()
		effect.set_recording_active(true)
		await create_timer(3.0).timeout
		effect.set_recording_active(false)
		player.stop()
		var rec: AudioStreamWAV = effect.get_recording()
		if rec == null or rec.data.size() == 0:
			print("OUT [%s]: mix=%d -> NO DATA" % [out_dev, AudioServer.get_mix_rate()])
		else:
			var ch := 2 if rec.stereo else 1
			var wav = WavUtils.build_wav(rec.data, rec.mix_rate, ch)
			print("OUT [%s]: mix=%d peak=%.5f" % [out_dev, AudioServer.get_mix_rate(), WavUtils.get_peak(wav)])
	quit(0)