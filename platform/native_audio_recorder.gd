extends AudioRecorderBase
## Native capture via AudioEffectRecord - Windows desktop AND Android use this
## identical path. Requires ProjectSettings "audio/driver/enable_input".
##
## Setup follows the official Godot mic-record recipe: a dedicated muted bus
## carrying an AudioEffectRecord, fed by an AudioStreamPlayer playing
## AudioStreamMicrophone. Muting the bus prevents mic-to-speaker feedback;
## the record effect still receives the signal.

const RECORD_BUS_NAME := "VoiceZooRecord"

var _effect: AudioEffectRecord
var _mic_player: AudioStreamPlayer
var _recording := false


func _ready() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		push_warning("NativeAudioRecorder: audio input disabled in project settings")
		return
	var bus_idx = AudioServer.get_bus_index(RECORD_BUS_NAME)
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, RECORD_BUS_NAME)
		AudioServer.set_bus_mute(bus_idx, true)
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var e = AudioServer.get_bus_effect(bus_idx, i)
		if e is AudioEffectRecord:
			_effect = e
			break
	if _effect == null:
		_effect = AudioEffectRecord.new()
		_effect.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(bus_idx, _effect)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = RECORD_BUS_NAME
	add_child(_mic_player)


func is_available() -> bool:
	return _effect != null


func is_recording() -> bool:
	return _recording


func start_recording() -> bool:
	if _effect == null or _recording:
		return false
	_mic_player.play()
	_effect.set_recording_active(true)
	_recording = true
	return true


func stop_recording() -> PackedByteArray:
	if _effect == null or not _recording:
		return PackedByteArray()
	_effect.set_recording_active(false)
	_mic_player.stop()
	_recording = false
	var rec: AudioStreamWAV = _effect.get_recording()
	if rec == null or rec.data.size() == 0:
		return PackedByteArray()
	if rec.format != AudioStreamWAV.FORMAT_16_BITS:
		push_warning("NativeAudioRecorder: unexpected format %d" % rec.format)
		return PackedByteArray()
	var channels := 2 if rec.stereo else 1
	return WavUtils.build_wav(rec.data, rec.mix_rate, channels)