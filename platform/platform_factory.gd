class_name PlatformFactory
extends RefCounted
## Selects platform implementations once at startup (see plan: platform layer).


static func make_audio_recorder() -> AudioRecorderBase:
	if OS.has_feature("web"):
		return load("res://platform/web_audio_recorder.gd").new()
	return load("res://platform/native_audio_recorder.gd").new()