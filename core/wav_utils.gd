class_name WavUtils
extends RefCounted
## Pure static helpers for 16-bit PCM WAV byte blobs. No I/O, no side effects.
## Used by SoundBank (validation), playback (to_stream), and tests (build_wav).

## Amplitude below which a frame counts as silence when trimming (0..1).
## Matches the "almost stumm" warning level in record_dialog - anything under
## this is noise floor, not a sound.
## Trim level as a FRACTION OF THE TAKE'S OWN PEAK, not an absolute level.
## An absolute threshold cuts a quiet recording to pieces: a take peaking at
## 0.046 (a real measurement from this project) judged against 0.02 loses
## everything below 43%% of its own peak - attack and release included.
const DEFAULT_TRIM_RATIO := 0.05
## Material kept on either side of the sound when trimming. A cut placed
## exactly on the transient clips the attack and clicks.
const DEFAULT_TRIM_LEAD_MS := 10.0
## Fade applied at a length cap so the cut lands as an ending, not a click.
const DEFAULT_FADE_MS := 30.0


## Parses RIFF/fmt/data chunks. Returns {} if the blob is not a WAV.
## Result keys: channels, sample_rate, bits, format, data_offset, data_size.
static func parse_header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 44:
		return {}
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var pos := 12
	var fmt := {}
	var data_offset := -1
	var data_size := 0
	while pos + 8 <= bytes.size():
		var chunk_id = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size = _u32(bytes, pos + 4)
		if chunk_id == "fmt ":
			if pos + 8 + 16 > bytes.size():
				return {}
			fmt = {
				"format": _u16(bytes, pos + 8),
				"channels": _u16(bytes, pos + 10),
				"sample_rate": _u32(bytes, pos + 12),
				"bits": _u16(bytes, pos + 22),
			}
		elif chunk_id == "data":
			data_offset = pos + 8
			data_size = chunk_size
		pos += 8 + chunk_size + (chunk_size & 1)  # chunks are word-aligned
	if fmt.is_empty() or data_offset < 0:
		return {}
	if data_offset + data_size > bytes.size():
		# Tolerate a truncated size field; clamp to what is actually there
		data_size = bytes.size() - data_offset
	return {
		"channels": fmt["channels"],
		"sample_rate": fmt["sample_rate"],
		"bits": fmt["bits"],
		"format": fmt["format"],
		"data_offset": data_offset,
		"data_size": data_size,
	}


## True for the formats the game accepts: PCM (format 1), 16-bit, mono/stereo.
static func is_valid_wav(bytes: PackedByteArray) -> bool:
	var h = parse_header(bytes)
	if h.is_empty():
		return false
	return h["format"] == 1 and h["bits"] == 16 and (h["channels"] == 1 or h["channels"] == 2)


## Converts a WAV blob to a playable AudioStreamWAV. Null if invalid.
static func to_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	if not is_valid_wav(bytes):
		return null
	var h = parse_header(bytes)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = h["sample_rate"]
	stream.stereo = h["channels"] == 2
	stream.data = bytes.slice(h["data_offset"], h["data_offset"] + h["data_size"])
	return stream


## Builds a minimal valid 16-bit PCM WAV from raw sample bytes.
## Production path for native recording later; also the test fixture factory.
static func build_wav(pcm16: PackedByteArray, sample_rate: int, channels: int = 1) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(44)
	_write_ascii(out, 0, "RIFF")
	out.encode_u32(4, 36 + pcm16.size())
	_write_ascii(out, 8, "WAVE")
	_write_ascii(out, 12, "fmt ")
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)  # PCM
	out.encode_u16(22, channels)
	out.encode_u32(24, sample_rate)
	out.encode_u32(28, sample_rate * channels * 2)  # byte rate
	out.encode_u16(32, channels * 2)  # block align
	out.encode_u16(34, 16)  # bits
	_write_ascii(out, 36, "data")
	out.encode_u32(40, pcm16.size())
	out.append_array(pcm16)
	return out


## Downmixes a stereo 16-bit PCM WAV to mono by averaging channels.
## Mono input is returned unchanged. Invalid input returns an empty array.
static func to_mono(bytes: PackedByteArray) -> PackedByteArray:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16 or h["format"] != 1:
		return PackedByteArray()
	if h["channels"] == 1:
		return bytes
	if h["channels"] != 2:
		return PackedByteArray()
	var off: int = h["data_offset"]
	var frames: int = h["data_size"] / 4
	var out := PackedByteArray()
	out.resize(frames * 2)
	for i in frames:
		var left := _s16(bytes, off + i * 4)
		var right := _s16(bytes, off + i * 4 + 2)
		out.encode_s16(i * 2, (left + right) / 2)
	return build_wav(out, h["sample_rate"], 1)


## Resamples 16-bit PCM WAV to target_rate (linear interpolation, channels
## preserved). Same-rate input is returned unchanged; invalid input returns
## an empty array. Note: GDScript-speed - a 10s clip takes noticeable time;
## acceptable for one-shot save actions, not for per-frame use.
static func resample_wav(bytes: PackedByteArray, target_rate: int) -> PackedByteArray:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16 or h["format"] != 1:
		return PackedByteArray()
	var src_rate: int = h["sample_rate"]
	if src_rate == target_rate:
		return bytes
	var ch: int = h["channels"]
	var frame_bytes := ch * 2
	var src_frames: int = h["data_size"] / frame_bytes
	if src_frames < 2:
		return PackedByteArray()
	var dst_frames := int(floor(float(src_frames) * float(target_rate) / float(src_rate)))
	var out := PackedByteArray()
	out.resize(dst_frames * frame_bytes)
	var ratio := float(src_rate) / float(target_rate)
	var off: int = h["data_offset"]
	for i in dst_frames:
		var pos := float(i) * ratio
		var i0 := int(pos)
		var frac := pos - float(i0)
		var i1: int = mini(i0 + 1, src_frames - 1)
		for c in ch:
			var s0 := _s16(bytes, off + (i0 * ch + c) * 2)
			var s1 := _s16(bytes, off + (i1 * ch + c) * 2)
			out.encode_s16((i * ch + c) * 2, int(roundf(lerpf(float(s0), float(s1), frac))))
	return build_wav(out, target_rate, ch)


static func _s16(b: PackedByteArray, o: int) -> int:
	var u = b[o] | (b[o + 1] << 8)
	return u - 65536 if u >= 32768 else u


## Strips leading and trailing silence so the sound STARTS on its transient.
## A prerequisite for rhythm, not polish: 400ms of leading silence means the
## animal audibly misses its beat no matter how exact the sequencer is.
##
## threshold: amplitude (0..1) at or above which a frame counts as sound.
## max_lead_ms: how much material to keep BEFORE the first transient - and
## after the last one, so the release is not clipped either.
##
## A take with nothing above the threshold is returned UNCHANGED. Trimming
## runs before normalize (see record_dialog), so a quiet-but-real recording
## must survive to be boosted rather than come back empty.
static func trim_silence(bytes: PackedByteArray, threshold_ratio: float = DEFAULT_TRIM_RATIO, max_lead_ms: float = DEFAULT_TRIM_LEAD_MS) -> PackedByteArray:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16 or h["format"] != 1:
		return PackedByteArray()
	var ch: int = h["channels"]
	var frame_bytes := ch * 2
	var frames: int = h["data_size"] / frame_bytes
	if frames <= 0:
		return bytes
	var off: int = h["data_offset"]
	# Scaled to this take's own peak, so loud and quiet recordings are trimmed
	# with equal precision. Floor of 1 keeps an all-silent take from matching
	# every frame (which would then trim nothing and return it whole - correct).
	var limit := maxi(1, int(get_peak(bytes) * maxf(threshold_ratio, 0.0) * 32768.0))

	var first := -1
	for i in frames:
		if _frame_peak(bytes, off + i * frame_bytes, ch) >= limit:
			first = i
			break
	if first < 0:
		return bytes

	var last := frames - 1
	while last > first and _frame_peak(bytes, off + last * frame_bytes, ch) < limit:
		last -= 1

	var pad := int(maxf(max_lead_ms, 0.0) / 1000.0 * float(h["sample_rate"]))
	var start := maxi(first - pad, 0)
	var end := mini(last + 1 + pad, frames)
	if start == 0 and end == frames:
		return bytes
	return build_wav(bytes.slice(off + start * frame_bytes, off + end * frame_bytes), h["sample_rate"], ch)


## Truncates to max_seconds with a short fade-out at the cut. For the RHYTHM
## VOICE only: a 4-second recording fired every 0.67s turns the loop into mush.
## The full recording stays in the SoundBank untouched - this shortens a copy
## on its way to playback. Shorter input is returned unchanged.
static func cap_length(bytes: PackedByteArray, max_seconds: float, fade_ms: float = DEFAULT_FADE_MS) -> PackedByteArray:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16 or h["format"] != 1:
		return PackedByteArray()
	if max_seconds <= 0.0:
		return bytes
	var ch: int = h["channels"]
	var frame_bytes := ch * 2
	var frames: int = h["data_size"] / frame_bytes
	var rate: int = h["sample_rate"]
	var keep := int(max_seconds * float(rate))
	if keep <= 0 or frames <= keep:
		return bytes

	var off: int = h["data_offset"]
	var pcm := bytes.slice(off, off + keep * frame_bytes)
	var fade := mini(int(maxf(fade_ms, 0.0) / 1000.0 * float(rate)), keep)
	for i in fade:
		var frame := keep - fade + i
		var gain := 1.0 - float(i + 1) / float(fade)
		for c in ch:
			var o := (frame * ch + c) * 2
			pcm.encode_s16(o, int(roundf(float(_s16(pcm, o)) * gain)))
	return build_wav(pcm, rate, ch)


## Playing time in seconds; 0.0 for anything that is not a readable WAV.
static func duration_seconds(bytes: PackedByteArray) -> float:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16:
		return 0.0
	var frame_bytes: int = h["channels"] * 2
	if frame_bytes <= 0 or h["sample_rate"] <= 0:
		return 0.0
	return float(h["data_size"] / frame_bytes) / float(h["sample_rate"])


## Loudest channel of one frame, as a positive 16-bit magnitude.
static func _frame_peak(b: PackedByteArray, offset: int, channels: int) -> int:
	var peak := 0
	for c in channels:
		var v := absi(_s16(b, offset + c * 2))
		if v > peak:
			peak = v
	return peak


## Scales PCM so the peak hits target_peak. Recordings arrive at wildly
## different levels (mic distance, device gain) - normalizing at the capture
## edge makes every animal audible in-world. Near-silence is returned as-is
## (boosting it only amplifies noise), gain is capped at 30x, and samples are
## clamped (get_peak strides, so a few true peaks may exceed the estimate).
static func normalize_wav(bytes: PackedByteArray, target_peak: float = 0.9) -> PackedByteArray:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16 or h["format"] != 1:
		return PackedByteArray()
	var peak := get_peak(bytes)
	if peak < 0.001:
		return bytes
	var gain: float = minf(target_peak / peak, 30.0)
	if gain <= 1.02:
		return bytes
	var out := bytes.duplicate()
	var pos: int = h["data_offset"]
	var end: int = h["data_offset"] + h["data_size"] - 1
	while pos < end:
		var v := int(roundf(float(_s16(bytes, pos)) * gain))
		out.encode_s16(pos, clampi(v, -32768, 32767))
		pos += 2
	return out


## Peak amplitude of the PCM data, 0.0..1.0. Used to detect near-silent
## recordings (wrong microphone, muted input) right after capture.
## Samples every 4th frame - plenty for a loudness sanity check.
static func get_peak(bytes: PackedByteArray) -> float:
	var h = parse_header(bytes)
	if h.is_empty() or h["bits"] != 16:
		return 0.0
	var peak := 0
	var pos: int = h["data_offset"]
	var end: int = h["data_offset"] + h["data_size"] - 1
	while pos < end:
		var u = bytes[pos] | (bytes[pos + 1] << 8)
		if u >= 32768:
			u = 65536 - u
		if u > peak:
			peak = u
		pos += 8
	return float(peak) / 32768.0


static func _write_ascii(buf: PackedByteArray, offset: int, s: String) -> void:
	var ascii = s.to_ascii_buffer()
	for i in ascii.size():
		buf[offset + i] = ascii[i]


static func _u16(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


static func _u32(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)