class_name KeeperData
extends Resource
## Data model for a zoo keeper instance.
## Pure data — no Node dependencies.

@export var id: String = ""
@export var name: String = ""
@export var face_texture_ref: String = ""
@export var sound_ref: String = ""  # SoundBank id (schema v2)
@export var body_type: String = "default"
@export var personality: String = "friendly"
@export var assigned_entity_id: String = ""


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"face_texture_ref": face_texture_ref,
		"sound_ref": sound_ref,
		"body_type": body_type,
		"personality": personality,
		"assigned_entity_id": assigned_entity_id,
	}


static func from_dict(d: Dictionary) -> KeeperData:
	var k = KeeperData.new()
	k.id = d.get("id", "")
	k.name = d.get("name", "")
	k.face_texture_ref = d.get("face_texture_ref", "")
	k.sound_ref = d.get("sound_ref", "")
	k.body_type = d.get("body_type", "default")
	k.personality = d.get("personality", "friendly")
	k.assigned_entity_id = d.get("assigned_entity_id", "")
	return k
