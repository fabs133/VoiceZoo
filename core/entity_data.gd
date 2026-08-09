class_name EntityData
extends Resource
## Data model for a single zoo entity instance.
## Pure data — no Node dependencies.

## beat_pattern value meaning "this animal has never been given a part".
## Distinct from 0, which is a real mask meaning "sings on no step" — that is
## what a player leaves behind after clearing a row in the Studio, and it must
## survive. ZooState.apply_rhythm_defaults() only fills in the sentinel.
const UNASSIGNED_PATTERN := -1

@export var id: String
@export var type_id: String
@export var grid_position: Vector2i
@export var sound_ref: String = ""
@export var level: int = 1

## Rhythm (schema v3). beat_pattern is a bitmask over the loop steps:
## bit N set = this animal sings on step N.
@export var beat_pattern: int = UNASSIGNED_PATTERN
## Parks an animal without deleting it (the Studio row label toggles this).
@export var in_song: bool = true
## Semitones; playback uses pitch_scale = pow(2, pitch_offset / 12).
@export var pitch_offset: float = 0.0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type_id": type_id,
		"grid_position": [grid_position.x, grid_position.y],
		"sound_ref": sound_ref,
		"level": level,
		"beat_pattern": beat_pattern,
		"in_song": in_song,
		"pitch_offset": pitch_offset,
	}


static func from_dict(d: Dictionary) -> EntityData:
	var e = EntityData.new()
	e.id = d["id"]
	e.type_id = d["type_id"]
	e.grid_position = Vector2i(d["grid_position"][0], d["grid_position"][1])
	# Migration: pre-v2 saves stored placeholder PATHS in sound_ref; since v2
	# it is a SoundBank id. Strip legacy paths so lookups stay clean.
	var ref: String = d.get("sound_ref", "")
	e.sound_ref = "" if ref.begins_with("res://") else ref
	e.level = d.get("level", 1)
	# Schema v3: pre-v3 saves have no rhythm fields. They load as UNASSIGNED
	# and pick up their type default via ZooState.apply_rhythm_defaults().
	e.beat_pattern = int(d.get("beat_pattern", UNASSIGNED_PATTERN))
	e.in_song = bool(d.get("in_song", true))
	e.pitch_offset = float(d.get("pitch_offset", 0.0))
	return e
