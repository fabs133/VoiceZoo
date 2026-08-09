extends "res://tests/helpers/base_test.gd"
## Contract tests for the recorder interface, exercised via the mock.
## The native implementation is device-dependent and validated manually;
## these tests pin the CONTRACT every consumer relies on.

const MockRecorder = preload("res://platform/mock_audio_recorder.gd")

var _rec


func before_each() -> void:
	_rec = MockRecorder.new()


func after_each() -> void:
	# The recorders extend Node, so they do not refcount away on their own.
	if _rec != null:
		_rec.free()
		_rec = null


func test_lifecycle_produces_valid_wav() -> void:
	assert_true(_rec.is_available(), "mock available")
	assert_false(_rec.is_recording(), "idle initially")
	assert_true(_rec.start_recording(), "start succeeds")
	assert_true(_rec.is_recording(), "recording state")
	var wav = _rec.stop_recording()
	assert_false(_rec.is_recording(), "idle after stop")
	assert_true(WavUtils.is_valid_wav(wav), "output is a valid 16-bit PCM WAV")
	assert_true(SoundBank.new().add_sound(wav) != "", "output is bank-acceptable")


func test_double_start_rejected() -> void:
	assert_true(_rec.start_recording(), "first start")
	assert_false(_rec.start_recording(), "second start rejected")
	_rec.stop_recording()


func test_stop_without_start_is_empty() -> void:
	assert_eq(_rec.stop_recording().size(), 0, "no phantom recording")


func test_failed_start_reported() -> void:
	_rec.fail_start = true
	assert_false(_rec.start_recording(), "start failure surfaces as false")
	assert_false(_rec.is_recording(), "no recording state on failure")


func test_base_class_is_safe_null_object() -> void:
	var base = load("res://platform/audio_recorder.gd").new()
	assert_false(base.is_available(), "base unavailable")
	assert_false(base.start_recording(), "base cannot start")
	assert_eq(base.stop_recording().size(), 0, "base returns empty")
	assert_false(base.is_permission_pending(), "base is not waiting for anything")
	assert_false(base.is_permission_denied(), "and nobody refused it anything")
	base.request_permission()
	base.release()
	assert_false(base.is_available(), "asking changes nothing on the null object")
	base.free()


# --- Async permission (the web path's shape, played through the mock) ---

func test_native_style_recorder_needs_no_permission_step() -> void:
	# Desktop and Android have the microphone at construction. The extra calls
	# exist for web and must be harmless everywhere else.
	assert_true(_rec.is_available(), "available without asking")
	assert_false(_rec.is_permission_pending(), "nothing to wait for")
	_rec.request_permission()
	assert_true(_rec.is_available(), "still available after asking")


func test_permission_starts_pending_and_becomes_available() -> void:
	_rec.needs_permission = true
	assert_false(_rec.is_available(), "web opens unavailable - nobody has said yes yet")
	_rec.request_permission()
	assert_true(_rec.is_permission_pending(), "waiting on the browser prompt")
	assert_false(_rec.is_available(), "and still not available while waiting")
	_rec.grant_permission()
	assert_true(_rec.is_available(), "available once the guest allows it")
	assert_false(_rec.is_permission_pending(), "no longer waiting")


func test_denied_permission_is_not_pending() -> void:
	_rec.needs_permission = true
	_rec.request_permission()
	_rec.deny_permission()
	assert_false(_rec.is_available(), "denied means unavailable")
	assert_false(_rec.is_permission_pending(), "and settled, not still waiting")
	assert_true(_rec.is_permission_denied(), "and reported as a refusal")


func test_refusal_is_distinct_from_a_missing_microphone() -> void:
	# Both are unavailable; only one of them is the guest's to undo.
	_rec.needs_permission = true
	_rec.request_permission()
	_rec.report_no_device()
	assert_false(_rec.is_available(), "no device means unavailable")
	assert_false(_rec.is_permission_denied(), "but nobody refused anything")


func test_asking_again_clears_a_previous_refusal() -> void:
	_rec.needs_permission = true
	_rec.request_permission()
	_rec.deny_permission()
	_rec.request_permission()
	assert_true(_rec.is_permission_pending(), "the new prompt is open")
	assert_false(_rec.is_permission_denied(), "the stale refusal is not still showing")


func test_cannot_record_before_permission_arrives() -> void:
	_rec.needs_permission = true
	_rec.request_permission()
	assert_false(_rec.start_recording(), "no capture while the prompt is open")
	assert_false(_rec.is_recording(), "and no phantom recording state")
	_rec.grant_permission()
	assert_true(_rec.start_recording(), "capture once permission lands")
	assert_true(WavUtils.is_valid_wav(_rec.stop_recording()), "and it still yields a valid WAV")


func test_release_hands_the_microphone_back() -> void:
	_rec.needs_permission = true
	_rec.request_permission()
	_rec.grant_permission()
	_rec.start_recording()
	_rec.release()
	assert_eq(_rec.release_calls, 1, "release reached the platform")
	assert_false(_rec.is_recording(), "recording stopped with it")
	assert_false(_rec.is_available(), "and the permission has to be asked for again")