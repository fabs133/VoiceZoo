extends AudioRecorderBase
## Test double: honors the full recorder contract and fabricates a valid WAV
## on stop. Keeps every consumer of the recorder headless-testable.

var fake_sample_rate := 22050
var fake_pcm_bytes := 2000
var fail_start := false

## Set to simulate the web path, where permission is an async browser prompt:
## the recorder starts unavailable and only becomes available once the guest
## answers. grant_permission() / deny_permission() play the answer.
var needs_permission := false
var permission_requests := 0
var release_calls := 0

var _recording := false
var _pending := false
var _granted := false
var _denied := false


func is_available() -> bool:
	if needs_permission:
		return _granted
	return true


func is_permission_pending() -> bool:
	return _pending


func is_permission_denied() -> bool:
	return _denied


func request_permission() -> void:
	permission_requests += 1
	if needs_permission and not _granted:
		_pending = true
		_denied = false


## Test hook: the guest tapped "allow".
func grant_permission() -> void:
	_pending = false
	_granted = true
	_denied = false


## Test hook: the guest tapped "don't allow".
func deny_permission() -> void:
	_pending = false
	_granted = false
	_denied = true


## Test hook: unavailable but NOT refused - no microphone, or a browser that
## cannot record. Looks the same to is_available(), reads differently to a guest.
func report_no_device() -> void:
	_pending = false
	_granted = false
	_denied = false


func release() -> void:
	release_calls += 1
	_recording = false
	_pending = false
	_granted = false
	_denied = false


func is_recording() -> bool:
	return _recording


func start_recording() -> bool:
	if fail_start or _recording or not is_available():
		return false
	_recording = true
	return true


func stop_recording() -> PackedByteArray:
	if not _recording:
		return PackedByteArray()
	_recording = false
	var pcm := PackedByteArray()
	pcm.resize(fake_pcm_bytes)
	return WavUtils.build_wav(pcm, fake_sample_rate, 1)