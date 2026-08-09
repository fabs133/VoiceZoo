extends Node2D
## Visual representation of a keeper — body + face composite.
## Follows assigned entity sprite via smooth lerp. Idle bob animation.

var keeper_data  # KeeperData — untyped for headless compat
var _target_entity_sprite: Node2D
var _follow_offset: Vector2 = Vector2(40, 0)
var _default_follow_offset: Vector2 = Vector2(40, 0)
var _bob_time: float = 0.0
var _reaction_tween: Tween

@onready var body_sprite: Sprite2D = $BodySprite
@onready var face_sprite: Sprite2D = $FaceSprite
@onready var reaction_sprite: Sprite2D = $ReactionSprite


func setup(data, entity_sprite: Node2D) -> void:
	keeper_data = data
	_target_entity_sprite = entity_sprite

	# Load body texture from config
	var keeper_cfg = Config.get_keeper_config()
	var body_types: Dictionary = keeper_cfg.get("body_types", {})
	var body_info: Dictionary = body_types.get(data.body_type, body_types.get("default", {}))

	var body_tex = load(body_info.get("sprite", ""))
	if body_tex:
		body_sprite.texture = body_tex

	# Load face texture
	if data.face_texture_ref != "":
		var face_tex = load(data.face_texture_ref)
		if face_tex:
			face_sprite.texture = face_tex
	else:
		# Pick a random face from config
		var faces: Array = keeper_cfg.get("faces", [])
		if faces.size() > 0:
			var idx = hash(data.id) % faces.size()
			var face_tex = load(faces[idx])
			if face_tex:
				face_sprite.texture = face_tex

	# Position face relative to body
	var head_offset = body_info.get("head_offset", [0, -48])
	face_sprite.position = Vector2(head_offset[0], head_offset[1])
	var head_scale = body_info.get("head_scale", [1.4, 1.4])
	face_sprite.scale = Vector2(head_scale[0], head_scale[1])

	# Hide reaction sprite until needed
	reaction_sprite.visible = false

	# Position next to entity
	if _target_entity_sprite:
		position = _target_entity_sprite.position + _follow_offset

	# Spawn animation
	_play_spawn_animation()


func _process(delta: float) -> void:
	if keeper_data == null:
		return

	# Follow assigned entity smoothly
	if _target_entity_sprite and is_instance_valid(_target_entity_sprite):
		var target_pos = _target_entity_sprite.position + _follow_offset
		position = position.lerp(target_pos, 3.0 * delta)

	# Idle bob
	_bob_time += delta
	body_sprite.position.y = sin(_bob_time * 2.0) * 2.0
	face_sprite.position.y += sin(_bob_time * 2.0) * 1.5 - sin((_bob_time - delta) * 2.0) * 1.5


func set_target_entity_sprite(entity_sprite: Node2D) -> void:
	_target_entity_sprite = entity_sprite
	if entity_sprite:
		position = entity_sprite.position + _follow_offset


func play_interaction(interaction_config: Dictionary) -> void:
	# Move closer to entity during interaction
	_follow_offset = _default_follow_offset * 0.5

	# Show reaction sprite with action-specific texture
	var action = interaction_config.get("keeper_action", "feed")
	var tex_path = "res://assets/placeholder_sprites/reaction_%s.png" % action
	var tex = load(tex_path)
	if tex:
		reaction_sprite.texture = tex

	reaction_sprite.modulate.a = 0.0
	reaction_sprite.visible = true

	# Fade in + gentle bob loop on reaction sprite
	if _reaction_tween and _reaction_tween.is_valid():
		_reaction_tween.kill()
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(reaction_sprite, "modulate:a", 1.0, 0.3)
	_reaction_tween.tween_property(reaction_sprite, "position:y", -85.0, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_reaction_tween.tween_property(reaction_sprite, "position:y", -75.0, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_reaction_tween.set_loops()


func stop_interaction() -> void:
	_follow_offset = _default_follow_offset

	if _reaction_tween and _reaction_tween.is_valid():
		_reaction_tween.kill()

	reaction_sprite.visible = false
	reaction_sprite.position.y = -80.0
	reaction_sprite.modulate.a = 1.0


func _play_spawn_animation() -> void:
	scale = Vector2(0.0, 0.0)
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_IN_OUT)
