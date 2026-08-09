extends "res://tests/helpers/base_test.gd"
## Tests for WavUtils - pure WAV parsing/validation/building.


func _pcm(n: int = 200) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	return b


func test_build_parse_roundtrip() -> void:
	var wav = WavUtils.build_wav(_pcm(400), 22050, 1)
	var h = WavUtils.parse_header(wav)
	assert_false(h.is_empty(), "header parses")
	assert_eq(h["sample_rate"], 22050, "sample rate")
	assert_eq(h["channels"], 1, "mono")
	assert_eq(h["bits"], 16, "16 bit")
	assert_eq(h["data_size"], 400, "data size")


func test_stereo_and_other_rates() -> void:
	var wav = WavUtils.build_wav(_pcm(800), 48000, 2)
	var h = WavUtils.parse_header(wav)
	assert_eq(h["sample_rate"], 48000, "48k kept")
	assert_eq(h["channels"], 2, "stereo")
	assert_true(WavUtils.is_valid_wav(wav), "stereo 16-bit accepted")


func test_garbage_rejected() -> void:
	var garbage := PackedByteArray()
	garbage.resize(100)
	for i in 100:
		garbage[i] = i % 251
	assert_true(WavUtils.parse_header(garbage).is_empty(), "garbage has no header")
	assert_false(WavUtils.is_valid_wav(garbage), "garbage invalid")
	assert_true(WavUtils.parse_header(PackedByteArray()).is_empty(), "empty rejected")


func test_wrong_bit_depth_rejected() -> void:
	var wav = WavUtils.build_wav(_pcm(), 22050, 1)
	wav.encode_u16(34, 8)  # patch bits field to 8
	assert_false(WavUtils.is_valid_wav(wav), "8-bit rejected")


func test_to_stream_fields() -> void:
	var wav = WavUtils.build_wav(_pcm(400), 22050, 1)
	var stream = WavUtils.to_stream(wav)
	assert_ne(stream, null, "stream created")
	assert_eq(stream.mix_rate, 22050, "mix rate")
	assert_false(stream.stereo, "mono stream")
	assert_eq(stream.data.size(), 400, "pcm carried over")
	assert_eq(WavUtils.to_stream(PackedByteArray()), null, "invalid -> null")

# --- Peak analysis (silence diagnosis) ---

func test_peak_of_silence_is_zero() -> void:
	var pcm := PackedByteArray()
	pcm.resize(400)
	var wav = WavUtils.build_wav(pcm, 22050, 1)
	assert_almost_eq(WavUtils.get_peak(wav), 0.0, 0.001, "silence has zero peak")


func test_peak_of_known_amplitude() -> void:
	var pcm := PackedByteArray()
	pcm.resize(400)
	# write value 16384 (= 0.5 peak) into every sample so stride cannot miss it
	var i := 0
	while i < 400:
		pcm.encode_s16(i, 16384)
		i += 2
	var wav = WavUtils.build_wav(pcm, 22050, 1)
	assert_almost_eq(WavUtils.get_peak(wav), 0.5, 0.01, "peak 0.5 detected")


func test_peak_of_garbage_is_zero() -> void:
	var garbage := PackedByteArray()
	garbage.resize(60)
	assert_almost_eq(WavUtils.get_peak(garbage), 0.0, 0.001, "invalid input -> 0")

# --- Downmix + resample ---

func _stereo_wav(rate: int, frames: int, left: int, right: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(frames * 4)
	for i in frames:
		pcm.encode_s16(i * 4, left)
		pcm.encode_s16(i * 4 + 2, right)
	return WavUtils.build_wav(pcm, rate, 2)


func test_to_mono_averages_channels() -> void:
	var wav = _stereo_wav(48000, 100, 1000, 3000)
	var mono = WavUtils.to_mono(wav)
	var h = WavUtils.parse_header(mono)
	assert_eq(h["channels"], 1, "mono output")
	assert_eq(h["data_size"], 200, "frame count preserved")
	assert_eq(WavUtils._s16(mono, h["data_offset"]), 2000, "channels averaged")


func test_to_mono_passthrough_and_garbage() -> void:
	var pcm := PackedByteArray()
	pcm.resize(200)
	var mono_in = WavUtils.build_wav(pcm, 22050, 1)
	assert_eq(WavUtils.to_mono(mono_in), mono_in, "mono passes through unchanged")
	var garbage := PackedByteArray()
	garbage.resize(50)
	assert_eq(WavUtils.to_mono(garbage).size(), 0, "garbage rejected")


func test_resample_halves_frames() -> void:
	var pcm := PackedByteArray()
	pcm.resize(1000 * 2)  # 1000 mono frames
	var wav = WavUtils.build_wav(pcm, 44100, 1)
	var out = WavUtils.resample_wav(wav, 22050)
	var h = WavUtils.parse_header(out)
	assert_eq(h["sample_rate"], 22050, "target rate in header")
	assert_eq(h["data_size"] / 2, 500, "frame count halved")
	assert_true(WavUtils.is_valid_wav(out), "output is valid WAV")


func test_resample_same_rate_passthrough() -> void:
	var pcm := PackedByteArray()
	pcm.resize(400)
	var wav = WavUtils.build_wav(pcm, 22050, 1)
	assert_eq(WavUtils.resample_wav(wav, 22050), wav, "same rate untouched")


func test_capture_edge_chain_48k_stereo_to_canonical() -> void:
	# the exact transformation the record dialog performs on save
	var wav = _stereo_wav(48000, 4800, 800, 1200)  # 0.1s stereo 48k
	var canonical = WavUtils.resample_wav(WavUtils.to_mono(wav), 22050)
	var h = WavUtils.parse_header(canonical)
	assert_eq(h["channels"], 1, "mono")
	assert_eq(h["sample_rate"], 22050, "canonical rate")
	var frames: int = h["data_size"] / 2
	assert_true(frames >= 2200 and frames <= 2206, "~0.1s of frames survive (%d)" % frames)
	assert_eq(WavUtils._s16(canonical, h["data_offset"] + 100), 1000, "averaged amplitude preserved")

func test_normalize_scales_to_target() -> void:
	var pcm := PackedByteArray()
	pcm.resize(400)
	var i := 0
	while i < 400:
		pcm.encode_s16(i, 8192)  # peak 0.25
		i += 2
	var out = WavUtils.normalize_wav(WavUtils.build_wav(pcm, 22050, 1))
	assert_almost_eq(WavUtils.get_peak(out), 0.9, 0.02, "peak raised to ~0.9")


func test_normalize_leaves_silence_alone() -> void:
	var pcm := PackedByteArray()
	pcm.resize(400)
	var wav = WavUtils.build_wav(pcm, 22050, 1)
	assert_eq(WavUtils.normalize_wav(wav), wav, "silence untouched")


func test_normalize_leaves_loud_alone() -> void:
	var pcm := PackedByteArray()
	pcm.resize(400)
	var i := 0
	while i < 400:
		pcm.encode_s16(i, 30000)
		i += 2
	var wav = WavUtils.build_wav(pcm, 22050, 1)
	assert_eq(WavUtils.normalize_wav(wav), wav, "already-loud untouched")


# --- Trim + length cap (rhythm prerequisites) ---

## `lead` silent frames, then `body` frames at `amp`, then `tail` silent frames.
func _wav_with_silence(rate: int, lead: int, body: int, tail: int, amp: int = 8000, channels: int = 1) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize((lead + body + tail) * channels * 2)
	for i in body:
		for c in channels:
			pcm.encode_s16(((lead + i) * channels + c) * 2, amp)
	return WavUtils.build_wav(pcm, rate, channels)


func _frames(wav: PackedByteArray) -> int:
	var h = WavUtils.parse_header(wav)
	return int(h["data_size"]) / (int(h["channels"]) * 2)


func _frame(wav: PackedByteArray, index: int, channel: int = 0) -> int:
	var h = WavUtils.parse_header(wav)
	return WavUtils._s16(wav, int(h["data_offset"]) + (index * int(h["channels"]) + channel) * 2)


func test_trim_starts_the_sound_on_its_transient() -> void:
	# 400ms of room silence, 100ms of sound, 200ms of silence at 22050 Hz.
	var wav = _wav_with_silence(22050, 8820, 2205, 4410)
	var out = WavUtils.trim_silence(wav)
	# 10ms of lead is kept by default: 0.010 * 22050 = 220 frames.
	assert_eq(_frame(out, 219), 0, "silence right up to the kept lead-in")
	assert_eq(_frame(out, 220), 8000, "the sound starts 10ms in, not 400ms in")
	assert_eq(_frames(out), 2645, "220 lead + 2205 body + 220 release")


func test_trim_removes_trailing_silence() -> void:
	var wav = _wav_with_silence(22050, 0, 100, 10000)
	var out = WavUtils.trim_silence(wav)
	assert_eq(_frames(out), 320, "100 body + 220 release, the dead tail is gone")
	assert_eq(_frame(out, 0), 8000, "nothing taken off the front")


func test_trim_keeps_a_lead_shorter_than_the_allowance() -> void:
	var wav = _wav_with_silence(22050, 100, 100, 0)
	assert_eq(WavUtils.trim_silence(wav), wav, "already tight - returned untouched")


func test_trim_lead_allowance_is_configurable() -> void:
	var wav = _wav_with_silence(22050, 8820, 2205, 0)
	var out = WavUtils.trim_silence(wav, WavUtils.DEFAULT_TRIM_RATIO, 0.0)
	assert_eq(_frame(out, 0), 8000, "zero allowance cuts exactly on the transient")
	assert_eq(_frames(out), 2205, "only the sound itself remains")


func test_trim_leaves_an_all_silent_take_alone() -> void:
	var wav = _wav_with_silence(22050, 4410, 0, 0)
	assert_eq(WavUtils.trim_silence(wav), wav, "never hand back an empty clip")


func test_trim_ratio_is_relative_to_the_takes_own_peak() -> void:
	# Identical layout, wildly different levels. The quiet take must be trimmed
	# just as precisely as the loud one - under an absolute threshold it would
	# lose its attack and release, or pass through untrimmed and miss its beat.
	var loud = _wav_with_silence(22050, 4410, 2205, 4410)          # peak 0.244
	var quiet = _wav_with_silence(22050, 4410, 2205, 4410, 300)    # peak 0.009
	var loud_frames := _frames(WavUtils.trim_silence(loud))
	var quiet_frames := _frames(WavUtils.trim_silence(quiet))
	assert_eq(quiet_frames, loud_frames, "same layout trims the same, whatever the level")
	assert_lt(float(quiet_frames), 11025.0, "and the quiet take really was trimmed")


func test_trim_ratio_is_configurable() -> void:
	var wav = _wav_with_silence(22050, 4410, 2205, 0)
	# A ratio above 1.0 puts the bar over the take's own peak: nothing clears
	# it, so the take comes back whole rather than empty.
	assert_eq(WavUtils.trim_silence(wav, 1.5), wav, "nothing clears the bar - returned whole")
	assert_lt(float(_frames(WavUtils.trim_silence(wav, 0.05))), 6615.0, "a sane ratio still trims")


func test_trim_output_is_a_valid_canonical_wav() -> void:
	var wav = _wav_with_silence(22050, 8820, 2205, 4410)
	var out = WavUtils.trim_silence(wav)
	assert_true(WavUtils.is_valid_wav(out), "still a valid WAV")
	var h = WavUtils.parse_header(out)
	assert_eq(h["sample_rate"], 22050, "sample rate preserved")
	assert_eq(h["channels"], 1, "channel count preserved")


func test_trim_preserves_stereo_frames() -> void:
	var wav = _wav_with_silence(48000, 4800, 480, 4800, 6000, 2)
	var out = WavUtils.trim_silence(wav)
	var h = WavUtils.parse_header(out)
	assert_eq(h["channels"], 2, "stays stereo")
	assert_eq(_frames(out), 1440, "480 lead + 480 body + 480 release at 48k")
	assert_eq(_frame(out, 480, 1), 6000, "the right channel is aligned, not shifted")


func test_trim_rejects_garbage() -> void:
	var garbage := PackedByteArray()
	garbage.resize(50)
	assert_eq(WavUtils.trim_silence(garbage).size(), 0, "invalid input rejected")


func test_duration_seconds() -> void:
	var wav = _wav_with_silence(22050, 0, 11025, 0)
	assert_almost_eq(WavUtils.duration_seconds(wav), 0.5, 0.001, "11025 frames at 22050 = 0.5s")
	assert_almost_eq(WavUtils.duration_seconds(PackedByteArray()), 0.0, 0.001, "garbage has no duration")


func test_cap_shortens_a_long_sound() -> void:
	var wav = _wav_with_silence(22050, 0, 66150, 0)  # 3s
	var out = WavUtils.cap_length(wav, 1.0)
	assert_almost_eq(WavUtils.duration_seconds(out), 1.0, 0.001, "capped to one second")
	assert_true(WavUtils.is_valid_wav(out), "still a valid WAV")


func test_cap_leaves_a_short_sound_alone() -> void:
	var wav = _wav_with_silence(22050, 0, 11025, 0)  # 0.5s
	assert_eq(WavUtils.cap_length(wav, 1.33), wav, "under the cap = untouched")


func test_cap_fades_out_at_the_cut() -> void:
	var wav = _wav_with_silence(22050, 0, 44100, 0)  # 2s of steady tone
	var out = WavUtils.cap_length(wav, 1.0)
	var frames := _frames(out)
	# 30ms of fade by default: 0.030 * 22050 = 661 frames.
	assert_eq(_frame(out, frames - 662), 8000, "audio before the fade is untouched")
	assert_eq(_frame(out, frames - 1), 0, "the cut lands on silence, not a click")
	var mid := _frame(out, frames - 331)
	assert_gt(float(mid), 0.0, "the fade is a ramp, not a gate")
	assert_lt(float(mid), 8000.0, "and it is on its way down")


func test_cap_of_zero_seconds_returns_the_input() -> void:
	var wav = _wav_with_silence(22050, 0, 11025, 0)
	assert_eq(WavUtils.cap_length(wav, 0.0), wav, "a nonsense cap must not silence the animal")


func test_cap_rejects_garbage() -> void:
	var garbage := PackedByteArray()
	garbage.resize(50)
	assert_eq(WavUtils.cap_length(garbage, 1.0).size(), 0, "invalid input rejected")


func test_capture_edge_chain_trims_then_normalizes() -> void:
	# The exact chain record_dialog runs on save, on a realistic bad take:
	# 48k stereo, 400ms of room silence, 200ms of quiet sound, 100ms of tail.
	var wav = _wav_with_silence(48000, 19200, 9600, 4800, 3000, 2)
	var canonical = WavUtils.resample_wav(WavUtils.to_mono(wav), 22050)
	var trimmed = WavUtils.trim_silence(canonical)
	var out = WavUtils.normalize_wav(trimmed)

	assert_true(WavUtils.is_valid_wav(out), "chain still produces a valid WAV")
	var h = WavUtils.parse_header(out)
	assert_eq(h["channels"], 1, "mono")
	assert_eq(h["sample_rate"], 22050, "canonical rate")
	assert_lt(WavUtils.duration_seconds(out), 0.3, "the 400ms of dead air is gone")
	assert_gt(WavUtils.duration_seconds(out), 0.19, "the sound itself survives")
	assert_almost_eq(WavUtils.get_peak(out), 0.9, 0.02, "normalized after trimming")
	assert_eq(_frame(out, 0), 0, "a short lead-in is kept ahead of the transient")
	assert_gt(float(absi(_frame(out, 300))), 20000.0, "and the sound is up at full level right after it")
