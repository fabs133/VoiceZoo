extends Node2D
## Visual representation of a zoo entity.
## Displays sprite, wanders near grid position, sings when the rhythm engine
## says so. It has NO timer of its own: since Sprint R the zoo has one
## conductor, and the old per-entity random ambient timer was deleted rather
## than gated (two sound models is twice the surface for no gain).

signal tapped(entity_sprite: Node2D)

## Fallback for a type with no "sprite_size" in entities.json. The processed
## art is 256px square against a 64px tile grid, so it always has to be scaled;
## the authoritative per-type values live in that file.
const DEFAULT_SPRITE_SIZE := 96.0
## Gap between the bottom of the sprite and the name label, and the label's own
## height. The scene file's fixed offsets were written for 64px placeholders.
const LABEL_GAP := 6.0
const LABEL_HEIGHT := 20.0
## A tap target is never smaller than this, however small the animal is drawn.
const MIN_TAP_RADIUS := 40.0

var entity_data: EntityData
var sound_resolver = null  # injected by main; user recordings win over placeholders
var _home_position: Vector2
var _wander_radius: float = 20.0
var _tap_radius: float = 40.0
var _is_reacting: bool = false
var _wander_tween: Tween
var _reaction_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D
## Interaction and reaction sounds. Kept separate from the beat voice below so
## a keeper feeding an animal cannot silence its part in the song.
##
## NOT positional. The whole zoo fits on one screen, so there is no meaningful
## distance to model - and AudioStreamPlayer2D does not attenuate past
## max_distance, it MUTES, which is how animals ended up silent rather than
## quiet twice (see rhythm_tutorial_plan.md). A non-positional player cannot
## have that bug at all.
@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var label: Label = $Label

## The animal's own voice, played on the beat. Built in code rather than in the
## scene so the two players cannot be confused for one another.
var _beat_audio: AudioStreamPlayer


func _ready() -> void:
	_beat_audio = AudioStreamPlayer.new()
	_beat_audio.name = "BeatAudio"
	# The singing voice is the point of the game, so it runs at unity. Loudness
	# is managed once, on the master bus (main.gd), instead of by trimming each
	# source - and there is no falloff left to inherit by accident.
	_beat_audio.volume_db = 0.0
	add_child(_beat_audio)


func setup(data: EntityData, world_pos: Vector2) -> void:
	entity_data = data
	_home_position = world_pos
	position = world_pos

	var cfg = Config.get_entity_config(data.type_id)
	if cfg.is_empty():
		return

	# Load sprite texture, then size it to the world (see _apply_sprite_size)
	var tex = load(cfg.get("sprite", ""))
	if tex:
		sprite.texture = tex
	_apply_sprite_size(float(cfg.get("sprite_size", DEFAULT_SPRITE_SIZE)))

	# Load sound - user recording wins over placeholder (via SoundResolver)
	_apply_resolved_sound(cfg)

	# Set label
	label.text = cfg.get("name", data.type_id)

	# Spawn pop animation
	_play_spawn_animation()

	# Start first wander
	_start_wander()


## Scales the sprite to `target` pixels on its longest edge and moves the name
## label clear of it. Source art is 256px and the tile grid is 64, so drawing it
## unscaled would cover four tiles; the placeholders are 64px and would stay
## tiny next to it. Scaling from the texture's real size rather than an assumed
## 256 keeps both paths, and any future re-export, correct.
func _apply_sprite_size(target: float) -> void:
	if sprite == null or sprite.texture == null or target <= 0.0:
		return
	var longest := float(maxi(sprite.texture.get_width(), sprite.texture.get_height()))
	if longest <= 0.0:
		return
	sprite.scale = Vector2.ONE * (target / longest)
	# Bigger animals get a bigger tap target; small ones keep a usable floor.
	_tap_radius = maxf(target * 0.5, MIN_TAP_RADIUS)
	if label != null:
		# The sprite is centred on the node origin, so its bottom edge is half
		# the target below it.
		label.offset_top = target * 0.5 + LABEL_GAP
		label.offset_bottom = label.offset_top + LABEL_HEIGHT


## Sings one beat. Called by RhythmPlayer, which owns the timing.
## Deliberately trivial: the stream was resolved and length-capped when it was
## assigned, so this allocates nothing and can run for six animals in a frame.
func play_beat(pitch_scale: float = 1.0) -> void:
	if _beat_audio == null or _beat_audio.stream == null:
		return
	_beat_audio.pitch_scale = maxf(pitch_scale, 0.01)
	_beat_audio.play()


func _start_wander() -> void:
	_wander_to_random_point()


func _wander_to_random_point() -> void:
	if _is_reacting:
		return
	var offset = Vector2(
		randf_range(-_wander_radius, _wander_radius),
		randf_range(-_wander_radius, _wander_radius)
	)
	var target = _home_position + offset
	var duration = randf_range(1.5, 3.0)

	_wander_tween = create_tween()
	_wander_tween.tween_property(self, "position", target, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_wander_tween.tween_callback(_wander_to_random_point)


func _unhandled_input(event: InputEvent) -> void:
	if entity_data == null:
		return
	if event is InputEventScreenTouch and event.pressed:
		_check_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_check_tap(event.position)


func _check_tap(screen_pos: Vector2) -> void:
	var world_pos = get_canvas_transform().affine_inverse() * screen_pos
	if world_pos.distance_to(position) <= _tap_radius:
		tapped.emit(self)


func refresh_sound() -> void:
	## Re-resolve after a recording was assigned to this entity.
	if entity_data == null:
		return
	_apply_resolved_sound(Config.get_entity_config(entity_data.type_id))


func _apply_resolved_sound(cfg: Dictionary) -> void:
	if _beat_audio == null:
		return
	var snd: AudioStream = null
	if sound_resolver != null:
		snd = sound_resolver.resolve_entity_stream(entity_data, cfg)
	else:
		var path: String = cfg.get("default_sound", "")
		if path != "":
			snd = load(path)
	if snd:
		_beat_audio.stream = snd


func update_level_display() -> void:
	if entity_data and label:
		var cfg = Config.get_entity_config(entity_data.type_id)
		var name_str = cfg.get("name", entity_data.type_id)
		if entity_data.level > 1:
			label.text = "%s Lv%d" % [name_str, entity_data.level]
		else:
			label.text = name_str


func play_upgrade_animation() -> void:
	var tween = create_tween()
	# Flash white then back
	tween.tween_property(self, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)
	# Quick scale bounce
	tween.parallel().tween_property(self, "scale", Vector2(1.3, 1.3), 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)


func play_reaction(reaction_type: String, interaction_sound_path: String = "") -> void:
	_is_reacting = true

	# Pause wandering
	if _wander_tween and _wander_tween.is_valid():
		_wander_tween.kill()

	# Play interaction sound if provided. This uses the interaction player, not
	# the beat voice, so the animal keeps its part in the song while it is fed.
	if interaction_sound_path != "":
		var snd = load(interaction_sound_path)
		if snd:
			audio.stream = snd
			audio.volume_db = -6.0
			audio.play()

	# Reaction animation based on type
	if _reaction_tween and _reaction_tween.is_valid():
		_reaction_tween.kill()
	_reaction_tween = create_tween()

	match reaction_type:
		"happy":
			_reaction_tween.tween_property(self, "scale", Vector2(1.2, 0.9), 0.15)
			_reaction_tween.tween_property(self, "scale", Vector2(0.9, 1.1), 0.15)
			_reaction_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
		"excited":
			_reaction_tween.tween_property(self, "position:y", _home_position.y - 15.0, 0.2).set_trans(Tween.TRANS_BACK)
			_reaction_tween.tween_property(self, "position:y", _home_position.y, 0.3)
		"focused":
			_reaction_tween.tween_property(self, "rotation", 0.1, 0.1)
			_reaction_tween.tween_property(self, "rotation", -0.1, 0.1)
			_reaction_tween.tween_property(self, "rotation", 0.0, 0.1)
		"relaxed":
			_reaction_tween.tween_property(self, "scale", Vector2(1.05, 0.95), 0.3).set_ease(Tween.EASE_IN_OUT)
			_reaction_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_IN_OUT)
		"curious":
			_reaction_tween.tween_property(self, "rotation", 0.15, 0.2).set_ease(Tween.EASE_OUT)
			_reaction_tween.tween_interval(0.5)
			_reaction_tween.tween_property(self, "rotation", 0.0, 0.2).set_ease(Tween.EASE_IN)
		_:
			_reaction_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.15)
			_reaction_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)


func spawn_interaction_particles(color: Color = Color.YELLOW) -> void:
	var particles = CPUParticles2D.new()
	particles.amount = 8
	particles.lifetime = 1.0
	particles.one_shot = true
	particles.emitting = true
	particles.direction = Vector2(0, -1)
	particles.spread = 45.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 60.0
	particles.gravity = Vector2(0, 98)
	particles.color = color
	add_child(particles)
	# Auto-cleanup after emission
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)


func stop_reaction() -> void:
	_is_reacting = false

	if _reaction_tween and _reaction_tween.is_valid():
		_reaction_tween.kill()

	# Reset visual state
	scale = Vector2(1.0, 1.0)
	rotation = 0.0

	# No sound to restore: the beat voice was never touched by the interaction,
	# and re-resolving here would rebuild the capped WAV for nothing.

	# Resume wandering
	_wander_to_random_point()


func _play_spawn_animation() -> void:
	scale = Vector2(0.0, 0.0)
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_IN_OUT)
