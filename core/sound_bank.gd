class_name SoundBank
extends RefCounted
## ID-addressed registry of user-recorded sounds. Core, pure - no I/O.
##
## Storage contract (decided in the Phase 2 spike):
## - Working saves carry METADATA ONLY (to_dict/from_dict) - never audio bytes.
##   Raw bytes live as files managed by presentation/sound_store.gd.
## - Export snapshots embed bytes as base64 (to_export_dict/from_export_dict)
##   so a zoo can travel as a single JSON file.

## Target rate for recorders (JS layer resamples to this). Not enforced here -
## the bank stores whatever valid WAV it is given and remembers the real rate.
const CANONICAL_SAMPLE_RATE := 22050
## Hard guard against runaway blobs (~45s mono at canonical rate).
const MAX_SOUND_BYTES := 2 * 1024 * 1024

var _sounds: Dictionary = {}  # id -> {label, sample_rate, created_at, bytes}
## Ids whose bytes are not yet on disk. Without this the 30s autosave rewrites
## every recorded WAV every time - megabytes of unchanged audio on a phone.
var _dirty: Dictionary = {}
var _next_id: int = 1


## The shape a recording must be in before it enters the bank: mono, canonical
## rate, starting on its transient, normalized. Every capture path runs this
## one function - the record dialog today, the web recorder later - so the
## chain cannot drift between them, and reordering it cannot regress silently.
##
## Each step keeps the previous result if it fails: a take is never lost to a
## conversion error. Trim runs before normalize so the sound starts on its
## transient (a beat is missed by 400ms of dead air) and so the noise floor
## stays out of the peak estimate.
static func prepare_take(bytes: PackedByteArray) -> PackedByteArray:
	var out := bytes
	var mono := WavUtils.to_mono(out)
	if mono.size() > 0:
		out = mono
	var canonical := WavUtils.resample_wav(out, CANONICAL_SAMPLE_RATE)
	if canonical.size() > 0:
		out = canonical
	var trimmed := WavUtils.trim_silence(out)
	if trimmed.size() > 0:
		out = trimmed
	var normalized := WavUtils.normalize_wav(out)
	if normalized.size() > 0:
		out = normalized
	return out


## Registers a WAV blob. Returns the new id, or "" if the blob is rejected
## (not 16-bit PCM WAV, or over MAX_SOUND_BYTES).
func add_sound(wav_bytes: PackedByteArray, label: String = "", now: float = 0.0) -> String:
	if wav_bytes.size() > MAX_SOUND_BYTES:
		return ""
	if not WavUtils.is_valid_wav(wav_bytes):
		return ""
	var header = WavUtils.parse_header(wav_bytes)
	var id := "snd_%d" % _next_id
	_next_id += 1
	_sounds[id] = {
		"label": label,
		"sample_rate": header["sample_rate"],
		"created_at": now,
		"bytes": wav_bytes,
	}
	_dirty[id] = true
	return id


## True while this sound's bytes still need writing to disk.
func is_dirty(id: String) -> bool:
	return id in _dirty


## Called by the store once the bytes are safely on disk.
func mark_clean(id: String) -> void:
	_dirty.erase(id)


func has_sound(id: String) -> bool:
	return id in _sounds


## Empty array if unknown or not yet loaded from disk.
func get_bytes(id: String) -> PackedByteArray:
	if id in _sounds:
		return _sounds[id]["bytes"]
	return PackedByteArray()


## Fills bytes for a metadata-only entry (used by SoundStore after loading
## a save). Validates; returns false for unknown ids or invalid blobs.
func set_bytes(id: String, wav_bytes: PackedByteArray) -> bool:
	if not id in _sounds:
		return false
	if wav_bytes.size() > MAX_SOUND_BYTES or not WavUtils.is_valid_wav(wav_bytes):
		return false
	_sounds[id]["bytes"] = wav_bytes
	return true


func get_label(id: String) -> String:
	return _sounds[id]["label"] if id in _sounds else ""


func get_sample_rate(id: String) -> int:
	return _sounds[id]["sample_rate"] if id in _sounds else 0


func remove_sound(id: String) -> bool:
	_dirty.erase(id)
	return _sounds.erase(id)


## Sorted for deterministic iteration (plain string sort - fine at this scale).
func get_ids() -> Array:
	var ids := _sounds.keys()
	ids.sort()
	return ids


func size() -> int:
	return _sounds.size()


# --- Serialization: working save (metadata only) ---

func to_dict() -> Dictionary:
	var list := []
	for id in get_ids():
		var s = _sounds[id]
		list.append({
			"id": id,
			"label": s["label"],
			"sample_rate": s["sample_rate"],
			"created_at": s["created_at"],
		})
	return {"sounds": list, "next_id": _next_id}


## Restores metadata; every entry starts with EMPTY bytes. The SoundStore
## loads the actual audio from disk afterwards.
func from_dict(d: Dictionary) -> void:
	_sounds.clear()
	_dirty.clear()  # metadata only; the store loads bytes that are already on disk
	for s in d.get("sounds", []):
		_sounds[s["id"]] = {
			"label": s.get("label", ""),
			"sample_rate": int(s.get("sample_rate", CANONICAL_SAMPLE_RATE)),
			"created_at": float(s.get("created_at", 0.0)),
			"bytes": PackedByteArray(),
		}
	_next_id = int(d.get("next_id", 1))


# --- Serialization: export snapshot (bytes embedded as base64) ---

func to_export_dict() -> Dictionary:
	var list := []
	for id in get_ids():
		var s = _sounds[id]
		list.append({
			"id": id,
			"label": s["label"],
			"sample_rate": s["sample_rate"],
			"created_at": s["created_at"],
			"data_b64": Marshalls.raw_to_base64(s["bytes"]),
		})
	return {"sounds": list, "next_id": _next_id}


## Imports a snapshot. Invalid entries are skipped, valid ones kept.
## Returns the number of sounds imported.
func from_export_dict(d: Dictionary) -> int:
	_sounds.clear()
	_dirty.clear()
	var imported := 0
	for s in d.get("sounds", []):
		var bytes = Marshalls.base64_to_raw(str(s.get("data_b64", "")))
		if bytes.size() == 0 or bytes.size() > MAX_SOUND_BYTES or not WavUtils.is_valid_wav(bytes):
			continue
		var header = WavUtils.parse_header(bytes)
		_sounds[s["id"]] = {
			"label": s.get("label", ""),
			"sample_rate": header["sample_rate"],
			"created_at": float(s.get("created_at", 0.0)),
			"bytes": bytes,
		}
		_dirty[s["id"]] = true  # imported bytes still have to reach the disk
		imported += 1
	_next_id = int(d.get("next_id", 1))
	return imported