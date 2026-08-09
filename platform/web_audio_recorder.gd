extends AudioRecorderBase
## Web recorder (Sprint 16.5) - a port of the validated export/web/mic_test.html
## pipeline through JavaScriptBridge:
##   getUserMedia -> AudioContext -> ScriptProcessor -> Float32 chunks
##   -> downsample to 22050 mono -> 16-bit PCM WAV -> base64 -> GDScript
##
## THE TIMING PROBLEM, and how it is answered:
## stop_recording() is synchronous by contract, but everything the browser
## offers for audio setup is asynchronous. The split is therefore:
##   - PERMISSION is async and happens EARLY. request_permission() is called
##     when the record dialog opens; is_available() reports whether the guest
##     has said yes yet. Nothing further blocks on it.
##   - CAPTURE accumulates into a JS-side array. GDScript holds no audio.
##   - STOP is fully synchronous JS: a plain resampling loop, not
##     OfflineAudioContext, which would only hand back a promise.
##
## Downsampling happens in JS, BEFORE the bridge crossing, and that is the
## point: ten seconds at 48 kHz is ~2.4 MB of base64, the same take at 22050
## is ~575 KB. The bridge moves a string, so this is the difference between a
## hitch and a stall on a phone.
##
## The WAV that comes back only has to be VALID - SoundBank.prepare_take still
## runs mono/resample/trim/normalize over it afterwards.

## Mirrors window.__vz_mic.permission on the JS side.
const _PERM_UNKNOWN := 0
const _PERM_PENDING := 1
const _PERM_GRANTED := 2
## The guest refused. Recoverable, but only from the browser's own settings.
const _PERM_DENIED := 3
## No microphone, or a browser/context that cannot record at all (no HTTPS, no
## getUserMedia, no AudioContext). Not the guest's decision, so telling them to
## "allow it in settings" would be a wild goose chase.
const _PERM_UNSUPPORTED := 4

var _bridge_ready := false
var _recording := false
## Permission is polled through the bridge, so it is cached: GRANTED and DENIED
## are terminal until release(), and the UI asks every frame while it waits.
var _permission := _PERM_UNKNOWN

const _JS_BOOTSTRAP := """
window.__vz_mic = window.__vz_mic || (function () {
	var st = {
		ctx: null, stream: null, source: null, proc: null, mute: null,
		chunks: [], total: 0, sampleRate: 0,
		recording: false, permission: 0, error: ''
	};

	st.ensureContext = function () {
		if (!st.ctx) {
			var C = window.AudioContext || window.webkitAudioContext;
			if (!C) { st.error = 'no AudioContext in this browser'; return false; }
			try { st.ctx = new C(); }
			catch (e) { st.error = 'AudioContext: ' + e.message; return false; }
		}
		if (st.ctx.state === 'suspended') { st.ctx.resume(); }
		return true;
	};

	// iOS Safari only creates or resumes an AudioContext inside a REAL user
	// gesture. Godot's frame loop runs in requestAnimationFrame, which does not
	// count as one, so the context is unlocked here from a DOM listener on the
	// first touch. Left installed on purpose: a backgrounded tab suspends the
	// context again and the next tap has to bring it back.
	var unlock = function () { st.ensureContext(); };
	window.addEventListener('touchend', unlock, true);
	window.addEventListener('mousedown', unlock, true);
	window.addEventListener('click', unlock, true);

	st.request = function () {
		if (st.permission === 1 || st.permission === 2) { return; }
		if (!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)) {
			st.permission = 4;
			st.error = 'getUserMedia unavailable - the page must be served over HTTPS';
			return;
		}
		if (!st.ensureContext()) { st.permission = 4; return; }
		st.permission = 1;
		navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
			st.stream = stream;
			st.sampleRate = st.ctx.sampleRate;
			st.permission = 2;
		}).catch(function (err) {
			// Only a refusal is worth telling the guest to go and undo.
			// NotFoundError (no microphone) and the rest are not their doing.
			var refused = (err.name === 'NotAllowedError' || err.name === 'SecurityError');
			st.permission = refused ? 3 : 4;
			st.error = err.name + ': ' + err.message;
		});
	};

	st.stopGraph = function () {
		if (st.proc) { st.proc.onaudioprocess = null; }
		try { if (st.source) { st.source.disconnect(); } } catch (e) {}
		try { if (st.proc) { st.proc.disconnect(); } } catch (e) {}
		try { if (st.mute) { st.mute.disconnect(); } } catch (e) {}
		st.source = null; st.proc = null; st.mute = null;
	};

	st.start = function () {
		if (st.permission !== 2 || st.recording || !st.stream) { return false; }
		if (!st.ensureContext()) { return false; }
		st.chunks = [];
		st.total = 0;
		st.sampleRate = st.ctx.sampleRate;
		try {
			st.source = st.ctx.createMediaStreamSource(st.stream);
			st.proc = st.ctx.createScriptProcessor(4096, 1, 1);
		} catch (e) {
			st.error = 'graph: ' + e.message;
			st.stopGraph();
			return false;
		}
		st.proc.onaudioprocess = function (e) {
			if (!st.recording) { return; }
			var d = e.inputBuffer.getChannelData(0);
			st.chunks.push(new Float32Array(d));
			st.total += d.length;
		};
		// A muted gain node keeps the graph pulling samples without feeding the
		// microphone back out of the speaker.
		st.mute = st.ctx.createGain();
		st.mute.gain.value = 0;
		st.source.connect(st.proc);
		st.proc.connect(st.mute);
		st.mute.connect(st.ctx.destination);
		st.recording = true;
		return true;
	};

	// Synchronous by design: flatten, downsample, encode, base64. No promises
	// anywhere, because the GDScript side cannot wait for one.
	st.stop = function (targetRate) {
		if (!st.recording) { return ''; }
		st.recording = false;
		st.stopGraph();
		var flat = new Float32Array(st.total);
		var off = 0;
		for (var i = 0; i < st.chunks.length; i++) {
			flat.set(st.chunks[i], off);
			off += st.chunks[i].length;
		}
		st.chunks = [];
		st.total = 0;
		var rate = st.sampleRate || targetRate;
		var out = flat;
		if (targetRate > 0 && rate > targetRate) {
			var ratio = rate / targetRate;
			var n = Math.floor(flat.length / ratio);
			out = new Float32Array(n);
			for (var j = 0; j < n; j++) {
				// Average the source window rather than picking one sample out
				// of it - cheap anti-aliasing, and 48k -> 22050 is only 2-3
				// samples per window.
				var s0 = Math.floor(j * ratio);
				var s1 = Math.floor((j + 1) * ratio);
				if (s1 > flat.length) { s1 = flat.length; }
				var sum = 0, cnt = 0;
				for (var k = s0; k < s1; k++) { sum += flat[k]; cnt++; }
				out[j] = cnt > 0 ? sum / cnt : 0;
			}
			rate = targetRate;
		}
		return st.encode(out, rate);
	};

	st.encode = function (samples, rate) {
		var len = samples.length;
		if (len === 0) { return ''; }
		var buffer = new ArrayBuffer(44 + len * 2);
		var view = new DataView(buffer);
		function ws(o, s) { for (var i = 0; i < s.length; i++) { view.setUint8(o + i, s.charCodeAt(i)); } }
		ws(0, 'RIFF'); view.setUint32(4, 36 + len * 2, true); ws(8, 'WAVE');
		ws(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
		view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true);
		view.setUint16(32, 2, true); view.setUint16(34, 16, true);
		ws(36, 'data'); view.setUint32(40, len * 2, true);
		var off = 44;
		for (var i = 0; i < len; i++) {
			var s = Math.max(-1, Math.min(1, samples[i]));
			view.setInt16(off, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
			off += 2;
		}
		// Chunked: String.fromCharCode.apply blows the call stack somewhere
		// around a quarter of a megabyte, and a ten-second take is more.
		var bytes = new Uint8Array(buffer);
		var bin = '';
		var CHUNK = 0x8000;
		for (var p = 0; p < bytes.length; p += CHUNK) {
			bin += String.fromCharCode.apply(null, bytes.subarray(p, Math.min(p + CHUNK, bytes.length)));
		}
		return btoa(bin);
	};

	st.release = function () {
		st.stopGraph();
		if (st.stream) {
			var tracks = st.stream.getTracks();
			for (var i = 0; i < tracks.length; i++) { tracks[i].stop(); }
			st.stream = null;
		}
		st.chunks = [];
		st.total = 0;
		st.recording = false;
		// Back to unknown, not denied: the next open() asks again, and a
		// permission the guest already granted resolves without a second prompt.
		st.permission = 0;
	};

	return st;
})();
"""


func _ready() -> void:
	# PlatformFactory only builds this on web, but a stray instantiation
	# elsewhere must degrade to "unavailable" rather than error.
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(_JS_BOOTSTRAP, true)
	# eval returns null for objects, so the bootstrap is confirmed with a
	# primitive rather than assumed.
	var ok = JavaScriptBridge.eval("typeof window.__vz_mic === 'object'", true)
	_bridge_ready = ok is bool and ok
	if not _bridge_ready:
		push_warning("WebAudioRecorder: JavaScript bridge unavailable")


func is_available() -> bool:
	return _poll_permission() == _PERM_GRANTED


func is_permission_pending() -> bool:
	return _poll_permission() == _PERM_PENDING


func is_permission_denied() -> bool:
	return _poll_permission() == _PERM_DENIED


func is_recording() -> bool:
	return _recording


func request_permission() -> void:
	if not _bridge_ready or _permission == _PERM_GRANTED:
		return
	JavaScriptBridge.eval("window.__vz_mic.request()", true)
	_permission = _PERM_PENDING
	_poll_permission()


func start_recording() -> bool:
	if not _bridge_ready or _recording or not is_available():
		return false
	var ok = JavaScriptBridge.eval("window.__vz_mic.start()", true)
	if not (ok is bool and ok):
		push_warning("WebAudioRecorder: start failed - %s" % last_error())
		return false
	_recording = true
	return true


func stop_recording() -> PackedByteArray:
	if not _bridge_ready or not _recording:
		return PackedByteArray()
	_recording = false
	var b64 = JavaScriptBridge.eval(
		"window.__vz_mic.stop(%d)" % SoundBank.CANONICAL_SAMPLE_RATE, true
	)
	if not (b64 is String) or b64 == "":
		push_warning("WebAudioRecorder: nothing captured - %s" % last_error())
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(b64)
	if not WavUtils.is_valid_wav(bytes):
		push_warning("WebAudioRecorder: JS produced %d bytes that are not a WAV" % bytes.size())
		return PackedByteArray()
	return bytes


func release() -> void:
	_recording = false
	_permission = _PERM_UNKNOWN
	if not _bridge_ready:
		return
	JavaScriptBridge.eval("window.__vz_mic.release()", true)


## Last message from the JS side, for push_warning and the diag tools.
func last_error() -> String:
	if not _bridge_ready:
		return "bridge unavailable"
	var msg = JavaScriptBridge.eval("window.__vz_mic.error || ''", true)
	return str(msg) if msg is String else ""


## Every state except UNKNOWN and PENDING is terminal until release(), so the
## bridge is only crossed while the answer is genuinely still open - the UI
## polls this every frame while it waits.
func _poll_permission() -> int:
	if not _bridge_ready:
		return _PERM_UNKNOWN
	if _permission != _PERM_UNKNOWN and _permission != _PERM_PENDING:
		return _permission
	var state = JavaScriptBridge.eval("window.__vz_mic.permission", true)
	if state != null:
		_permission = int(state)
	return _permission
