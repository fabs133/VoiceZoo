class_name ZooState
extends RefCounted
## Central game state — pure data, no scene tree dependencies.

## Bump when the save format changes; from_dict can branch on it for migrations.
## v1: base game. v2: + sound_bank metadata, + keeper sound_ref. v3: + rhythm
## settings {bpm, steps_per_loop, muted, voice_cap} and the per-entity rhythm
## fields (beat_pattern, in_song, pitch_offset). All load gracefully from older
## saves via .get() defaults - no explicit branch needed. Entities arriving
## without a pattern are filled in by apply_rhythm_defaults().
const SCHEMA_VERSION := 3

const _KeeperData = preload("res://core/keeper_data.gd")
const _InteractionEngine = preload("res://core/interaction_engine.gd")
const _RhythmEngine = preload("res://core/rhythm_engine.gd")

var entities: Array[EntityData] = []
var keepers: Array = []
var coins: float = 25.0
var lifetime_coins: float = 0.0
var unlocks: Array[String] = ["chicken"]
var newly_unlocked: Array[String] = []
var last_save_time: float = 0.0

## User-recorded sounds (metadata + in-memory bytes; disk handled by SoundStore)
var sound_bank = SoundBank.new()
var interaction_engine = _InteractionEngine.new()
## The zoo's conductor. Owned here (like interaction_engine) so its settings
## ride along in the save; presentation only drives it and renders the result.
var rhythm = _RhythmEngine.new()

var _next_id: int = 0
var _next_keeper_id: int = 0


func _init() -> void:
	# The engine reads the live entity array, so this wiring only has to happen
	# once: add_entity appends to it and from_dict clears it IN PLACE, so the
	# instance the engine holds never goes stale. Doing it here rather than in
	# presentation means it cannot be forgotten.
	rhythm.set_entities(entities)


func add_entity(type_id: String, pos: Vector2i, sound: String = "") -> EntityData:
	var e = EntityData.new()
	e.id = str(_next_id)
	_next_id += 1
	e.type_id = type_id
	e.grid_position = pos
	# sound_ref holds a SoundBank id since schema v2. Pre-v2 callers passed
	# placeholder PATHS here - refuse those so the two semantics never mix.
	e.sound_ref = "" if sound.begins_with("res://") else sound
	entities.append(e)
	return e


func get_entity_count(type_id: String) -> int:
	var count := 0
	for e in entities:
		if e.type_id == type_id:
			count += 1
	return count


func get_entity(entity_id: String) -> EntityData:
	for e in entities:
		if e.id == entity_id:
			return e
	return null


# --- Rhythm ---

## Gives every entity that has never had a rhythm part its type default from
## data/rhythm.json, rotated by how many of its type come before it. One
## mechanism covers both cases: an animal just bought, and a pre-v3 save being
## migrated. Entities with a real mask (including a deliberately empty 0) are
## left alone. Returns how many entities were assigned.
func apply_rhythm_defaults(rhythm_config: Dictionary) -> int:
	var copies_seen: Dictionary = {}
	var assigned := 0
	for e in entities:
		var copy_index: int = copies_seen.get(e.type_id, 0)
		copies_seen[e.type_id] = copy_index + 1
		if e.beat_pattern != EntityData.UNASSIGNED_PATTERN:
			continue
		_RhythmEngine.apply_defaults_to(e, copy_index, rhythm_config)
		assigned += 1
	return assigned


# --- Keeper Management ---

func add_keeper(keeper_name: String, body_type: String = "default", personality: String = "friendly"):
	var k = _KeeperData.new()
	k.id = str(_next_keeper_id)
	_next_keeper_id += 1
	k.name = keeper_name
	k.body_type = body_type
	k.personality = personality
	keepers.append(k)
	return k


func assign_keeper(keeper_id: String, entity_id: String) -> bool:
	var entity = get_entity(entity_id)
	if entity == null:
		return false
	# Unassign any existing keeper from this entity
	var existing = get_keeper_for_entity(entity_id)
	if existing != null:
		existing.assigned_entity_id = ""
	# Find and assign the keeper
	for k in keepers:
		if k.id == keeper_id:
			k.assigned_entity_id = entity_id
			return true
	return false


func get_keeper_for_entity(entity_id: String):
	for k in keepers:
		if k.assigned_entity_id == entity_id:
			return k
	return null


func get_keeper(keeper_id: String):
	for k in keepers:
		if k.id == keeper_id:
			return k
	return null


func remove_keeper(keeper_id: String) -> void:
	for i in range(keepers.size() - 1, -1, -1):
		if keepers[i].id == keeper_id:
			keepers.remove_at(i)
			return


# --- Tick ---

## NOTE: this does NOT advance the rhythm transport. The sequencer needs
## absolute monotonic time, so presentation calls rhythm.advance_to(now)
## separately (main.gd::_rhythm_now). Do not drive it from here as well -
## double-advancing would emit every beat twice.
func tick(delta: float, config) -> void:
	interaction_engine.tick(delta, keepers, entities, config)
	var income = Economy.calculate_income(entities, config, keepers, interaction_engine)
	var earned = income * delta
	coins += earned
	lifetime_coins += earned

	# Check for new unlocks
	newly_unlocked.clear()
	var should_unlock = Progression.get_unlocks(lifetime_coins, config)
	for type_id in should_unlock:
		if type_id not in unlocks:
			unlocks.append(type_id)
			newly_unlocked.append(type_id)


func get_income_per_second(config) -> float:
	return Economy.calculate_income(entities, config, keepers, interaction_engine)


# --- Serialization ---

## "now" is the current unix time, supplied by the caller so core stays
## clock-free and serialization is deterministic in tests.
func to_dict(now: float = 0.0) -> Dictionary:
	var entity_list: Array[Dictionary] = []
	for e in entities:
		entity_list.append(e.to_dict())
	var keeper_list: Array[Dictionary] = []
	for k in keepers:
		keeper_list.append(k.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"entities": entity_list,
		"keepers": keeper_list,
		"coins": coins,
		"lifetime_coins": lifetime_coins,
		"unlocks": unlocks,
		"next_id": _next_id,
		"next_keeper_id": _next_keeper_id,
		"last_save_time": now,
		"sound_bank": sound_bank.to_dict(),
		"interactions": interaction_engine.to_dict(),
		"rhythm": rhythm.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	entities.clear()
	for ed in d.get("entities", []):
		entities.append(EntityData.from_dict(ed))
	keepers.clear()
	for kd in d.get("keepers", []):
		keepers.append(_KeeperData.from_dict(kd))
	coins = d.get("coins", 25.0)
	lifetime_coins = d.get("lifetime_coins", 0.0)
	unlocks = []
	for u in d.get("unlocks", ["chicken"]):
		unlocks.append(u)
	_next_id = d.get("next_id", 0)
	_next_keeper_id = d.get("next_keeper_id", 0)
	last_save_time = d.get("last_save_time", 0.0)
	sound_bank = SoundBank.new()
	sound_bank.from_dict(d.get("sound_bank", {}))
	interaction_engine.from_dict(d.get("interactions", {}))
	rhythm.from_dict(d.get("rhythm", {}))

