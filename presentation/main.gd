extends Node2D
## Main scene controller — initializes game state and wires systems together.

@onready var zoo_map: Node2D = $ZooMap
@onready var camera: Camera2D = $Camera2D
@onready var shop_panel: PanelContainer = $UI/ShopPanel
@onready var hud: PanelContainer = $UI/HUD
@onready var entity_info: PanelContainer = $UI/EntityInfo
@onready var unlock_popup: PanelContainer = $UI/UnlockPopup
@onready var keeper_assign_panel: PanelContainer = $UI/KeeperAssignPanel

var zoo_state: ZooState
var _last_unlock_count: int = 0
var _save_timer: float = 0.0
var _entity_sprites: Dictionary = {}  # entity_id → Node2D
var _keeper_sprites: Dictionary = {}  # keeper_id → Node2D
const SAVE_INTERVAL: float = 30.0
const KeeperSpriteScene = preload("res://scenes/keeper_sprite.tscn")
const InteractionPlayerScript = preload("res://presentation/interaction_player.gd")
const SoundStoreScript = preload("res://presentation/sound_store.gd")
const SoundResolverScript = preload("res://presentation/sound_resolver.gd")
const RecordDialogScript = preload("res://presentation/ui/record_dialog.gd")
const RhythmPlayerScript = preload("res://presentation/rhythm_player.gd")
const CompositionViewScript = preload("res://presentation/ui/composition_view.gd")
const StudioHintScript = preload("res://presentation/ui/studio_hint.gd")

var interaction_player  # RefCounted playback orchestrator (see interaction_player.gd)
var rhythm_player  # fires entity sprites on the beat (see rhythm_player.gd)
var sound_store = SoundStoreScript.new()  # disk adapter for SoundBank bytes
var sound_resolver  # entity sound lookup (user recording beats placeholder)
var audio_recorder: AudioRecorderBase  # platform-selected in _ready
var record_dialog  # code-built PanelContainer
var composition_view  # code-built full-screen Studio grid
var studio_hint  # code-built one-shot nudge toward the Studio
var _recording_entity: EntityData  # entity the open record dialog belongs to


func _ready() -> void:
	_apply_dev_audio_override()
	_setup_master_bus()
	zoo_state = ZooState.new()

	# Config BEFORE the save: rhythm.json supplies the loop shape and the caps,
	# the save then overrides the two settings the player owns (tempo, mute).
	zoo_state.rhythm.configure(Config.get_rhythm_config())

	# Try loading saved state
	_load_game()

	# Animals that predate schema v3 (or were just bought) get their type's
	# default part, so a zoo always has something to play.
	zoo_state.apply_rhythm_defaults(Config.get_rhythm_config())

	# Wait one frame for zoo_map to finish _ready() and paint tiles
	await get_tree().process_frame

	# Set camera bounds to match map
	var bounds = zoo_map.get_map_bounds()
	camera.set_map_bounds(bounds)

	# Center camera on map
	camera.position = bounds.get_center()

	# Wire up UI
	hud.setup(zoo_state)
	shop_panel.setup(zoo_state, zoo_map)
	shop_panel.entity_purchased.connect(_on_entity_purchased)
	shop_panel.entity_tapped.connect(_on_entity_tapped)
	# The shop is a bottom sheet that covers the lower third of the zoo, so it
	# opens and closes. The state rides in the save: a guest who closed it should
	# not have it back in their face after a reload.
	shop_panel.closed.connect(_on_shop_closed)
	hud.shop_requested.connect(_on_shop_requested)
	if zoo_state.shop_open:
		shop_panel.open()
	else:
		shop_panel.visible = false
	entity_info.upgrade_purchased.connect(_on_entity_upgraded)
	entity_info.assign_keeper_requested.connect(_on_assign_keeper_requested)
	keeper_assign_panel.keeper_assigned.connect(_on_keeper_assigned)
	keeper_assign_panel.keeper_removed.connect(_on_keeper_removed)
	sound_resolver = SoundResolverScript.new(zoo_state)
	audio_recorder = PlatformFactory.make_audio_recorder()
	add_child(audio_recorder)
	record_dialog = RecordDialogScript.new()
	entity_info.get_parent().add_child(record_dialog)
	record_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	record_dialog.sound_saved.connect(_on_sound_saved)
	entity_info.record_sound_requested.connect(_on_record_sound_requested)

	interaction_player = InteractionPlayerScript.new()
	interaction_player.setup(_entity_sprites, _keeper_sprites, camera, Config)

	rhythm_player = RhythmPlayerScript.new()
	rhythm_player.setup(_entity_sprites)
	# Must run before _respawn_entities: the cap is applied when a sprite is
	# handed its stream, and respawning is where that happens.
	_apply_voice_length_cap()

	# The Studio. Added last so it covers the rest of the UI when open.
	composition_view = CompositionViewScript.new()
	entity_info.get_parent().add_child(composition_view)
	composition_view.setup(zoo_state, rhythm_player, Config)
	hud.studio_requested.connect(_on_studio_requested)
	entity_info.studio_requested.connect(_on_entity_studio_requested)
	# A Studio row can record for its own animal - same dialog, same wiring.
	composition_view.record_requested.connect(_on_record_sound_requested)
	# ...which means the dialog has to sit ABOVE the full-screen Studio. It was
	# added to this layer first, so without this it would open behind it.
	# The one-time nudge toward the Studio. Added to the same layer so it can sit
	# over the HUD, and it never blocks input (see studio_hint.gd).
	studio_hint = StudioHintScript.new()
	entity_info.get_parent().add_child(studio_hint)
	studio_hint.dismissed.connect(_on_studio_hint_dismissed)

	var ui_layer: Node = record_dialog.get_parent()
	ui_layer.move_child(record_dialog, ui_layer.get_child_count() - 1)
	# Persist a composing session when the Studio closes. Per-tap saving would
	# be needless churn; losing an arrangement to a killed tab would not.
	composition_view.closed.connect(_save_game)

	_last_unlock_count = zoo_state.unlocks.size()

	# Unlock zones for already-unlocked types (no animation on load)
	for type_id in zoo_state.unlocks:
		var zone = zoo_map.get_zone_for_type(type_id)
		zoo_map.unlock_zone(zone, false)

	# Respawn saved entities on map
	_respawn_entities()

	# A returning player with animals but no hint yet gets it too, not only
	# someone starting from an empty zoo.
	_maybe_arm_studio_hint()


func _process(delta: float) -> void:
	if zoo_state == null:
		return

	zoo_state.tick(delta, Config)

	# Interaction playback is orchestrated by InteractionPlayer
	interaction_player.process_events(zoo_state.interaction_engine)

	# The zoo sings: advance the one transport, then fire whatever it triggered.
	zoo_state.rhythm.focus_position = zoo_map.world_to_grid(camera.position)
	zoo_state.rhythm.advance_to(_rhythm_now())
	rhythm_player.process_triggers(zoo_state.rhythm)

	# Check if new unlocks happened → rebuild shop + show popup + unlock zones
	if zoo_state.unlocks.size() != _last_unlock_count:
		_last_unlock_count = zoo_state.unlocks.size()
		shop_panel.refresh_unlocks()
		for type_id in zoo_state.newly_unlocked:
			unlock_popup.show_unlock(type_id)
			var zone = zoo_map.get_zone_for_type(type_id)
			zoo_map.unlock_zone(zone)

	# Auto-save timer
	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_save_game()


# --- Rhythm ---

## The transport's clock. MONOTONIC by contract: Time.get_ticks_usec() counts
## from engine start and nothing can move it. get_unix_time_from_system() is
## the wrong call here - an NTP correction, a timezone change or the player
## editing the system clock makes it jump, and a backwards jump silently stalls
## the loop until real time catches up. Microseconds because a double holds
## them exactly for centuries and it costs nothing.
func _rhythm_now() -> float:
	return float(Time.get_ticks_usec()) / 1_000_000.0


## Switches tempo (the three coarse presets from rhythm.json).
## The voice length cap is derived from the step duration, so every already
## resolved stream is stale afterwards - hence the one-time re-resolve sweep.
## This is the ONLY thing that re-resolves; a beat never does.
func set_tempo(bpm: float) -> void:
	if is_equal_approx(zoo_state.rhythm.bpm, bpm):
		return
	zoo_state.rhythm.bpm = bpm
	_apply_voice_length_cap()
	_save_game()  # cheap since SoundStore only writes sounds it has not written


## Phone speakers at a party are the target, and peak normalization alone does
## not get there: a voice recording normalized to 0.9 has loud transients and a
## quiet body, so it measures full-scale and still sounds thin. Compression
## lifts the body, the limiter catches what that pushes over, and the bus gain
## is what actually makes it loud.
##
## Done once on the master bus rather than by raising each source, so recordings,
## placeholders and interaction sounds all benefit and their balance is
## untouched. The ceiling sits below 0 dBFS because six animals landing on the
## same beat would otherwise sum into clipping, which reads as broken, not loud.
func _setup_master_bus() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	# Idempotent: this scene can be reloaded, and the effects would stack.
	if AudioServer.get_bus_effect_count(master) > 0:
		return

	# Gentle. A compressor on a shared bus ducks EVERYTHING when anything on it
	# gets loud, so the earlier -18 dB / 4:1 setting had the placeholders' short
	# aggressive bursts pulling a guest's recording down for a quarter second
	# every time one fired - which is precisely the "the default sounds
	# overshadow my recording" report. Higher threshold, gentler ratio and a
	# quicker recovery keep the glue without the ducking.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 2.0
	comp.attack_us = 20.0
	comp.release_ms = 150.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(master, comp)

	# AudioEffectHardLimiter is the 4.3+ replacement; fall back where it is not
	# compiled in rather than shipping a compressor with nothing catching it.
	var limiter: AudioEffect = null
	if ClassDB.can_instantiate("AudioEffectHardLimiter"):
		limiter = ClassDB.instantiate("AudioEffectHardLimiter")
		limiter.set("ceiling_db", -0.5)
	elif ClassDB.can_instantiate("AudioEffectLimiter"):
		limiter = ClassDB.instantiate("AudioEffectLimiter")
		limiter.set("ceiling_db", -0.5)
	if limiter != null:
		AudioServer.add_bus_effect(master, limiter)

	AudioServer.set_bus_volume_db(master, 3.0)


func _apply_voice_length_cap() -> void:
	sound_resolver.max_voice_seconds = zoo_state.rhythm.voice_length_seconds()
	for entity_id in _entity_sprites:
		_entity_sprites[entity_id].refresh_sound()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save_game()
		get_tree().quit()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
		get_tree().quit()


func _on_entity_purchased(_type_id: String, entity: EntityData, sprite_node: Node2D) -> void:
	# Shop-spawned sprites arrive without the resolver - inject it here or
	# recordings on freshly bought animals silently fall back to placeholders.
	sprite_node.sound_resolver = sound_resolver
	sprite_node.refresh_sound()  # re-resolve now that the resolver (and cap) exist
	_entity_sprites[entity.id] = sprite_node
	# A new animal needs a part in the song, rotated off the ones already owned.
	zoo_state.apply_rhythm_defaults(Config.get_rhythm_config())
	_maybe_arm_studio_hint()


func _on_entity_sprite_tapped(sprite: Node2D) -> void:
	# Adapter: the sprite signal carries the sprite; the info panel wants EntityData.
	_on_entity_tapped(sprite.entity_data)


func _on_shop_requested() -> void:
	# Toggle: the same button that opens it closes it again, so a guest who
	# opened it by accident is not stuck hunting for the way out.
	if shop_panel.is_open():
		shop_panel.close()
		return
	shop_panel.open()
	zoo_state.shop_open = true
	_save_game()


func _on_shop_closed() -> void:
	zoo_state.shop_open = false
	_save_game()


func _on_record_sound_requested(entity: EntityData) -> void:
	_recording_entity = entity
	var cfg = Config.get_entity_config(entity.type_id)
	# Name the take after the individual animal ("Huhn 3"), not its type: the
	# label becomes the Studio row's name, and a dozen rows reading "Huhn"
	# is the problem this is here to solve.
	var subject: String = CompositionViewScript.display_name(
		entity, zoo_state.entities, cfg.get("name", entity.type_id)
	)
	record_dialog.open(audio_recorder, zoo_state.sound_bank, subject)
	record_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _on_sound_saved(sound_id: String) -> void:
	if _recording_entity == null:
		return
	_recording_entity.sound_ref = sound_id
	if _recording_entity.id in _entity_sprites:
		_entity_sprites[_recording_entity.id].refresh_sound()
	_recording_entity = null
	# The new recording renames its Studio row and sorts it to the top.
	composition_view.refresh()
	_save_game()  # persist metadata AND bytes immediately


func _on_entity_tapped(entity: EntityData) -> void:
	entity_info.show_entity(entity, zoo_state)


func _on_studio_requested() -> void:
	# Opening the Studio answers the hint, so it stops nudging.
	if studio_hint != null and studio_hint.is_showing():
		studio_hint.dismiss()
	composition_view.open()


## Three first-time testers all found the idle loop and only one found the
## composer, so a zoo with at least one animal in it earns one nudge toward the
## Studio. The condition is "has an animal and has not been told", NOT "just
## bought their first": anyone already carrying a save - every device tested so
## far - has more than one animal and would otherwise never be shown it.
##
## Not armed when the zoo is empty: the Studio has nothing in it then, and
## "deine Tiere bekommen deine Stimme" promises nothing.
func _maybe_arm_studio_hint() -> void:
	if zoo_state.studio_hint_seen or studio_hint == null:
		return
	if zoo_state.entities.is_empty() or studio_hint.is_armed():
		return
	studio_hint.start(hud.studio_button)


## Shown once per save, whether it was tapped, answered or simply timed out.
func _on_studio_hint_dismissed() -> void:
	zoo_state.studio_hint_seen = true
	_save_game()


## Link-through from the info panel: same screen, scrolled to that animal.
func _on_entity_studio_requested(entity: EntityData) -> void:
	composition_view.open(entity.id)


func _on_entity_upgraded(entity: EntityData) -> void:
	# Update sprite label + play upgrade animation
	if entity.id in _entity_sprites:
		var sprite_node = _entity_sprites[entity.id]
		sprite_node.update_level_display()
		sprite_node.play_upgrade_animation()


func _on_assign_keeper_requested(entity: EntityData) -> void:
	keeper_assign_panel.show_for_entity(entity, zoo_state)


func _on_keeper_assigned(entity_id: String, keeper_id: String) -> void:
	# Remove old keeper sprite if this keeper was reassigned
	if keeper_id in _keeper_sprites:
		_keeper_sprites[keeper_id].queue_free()
		_keeper_sprites.erase(keeper_id)

	# Spawn keeper sprite next to entity
	var entity_sprite = _entity_sprites.get(entity_id)
	if entity_sprite == null:
		return
	var keeper = zoo_state.get_keeper(keeper_id)
	if keeper == null:
		return

	_spawn_keeper_sprite(keeper, entity_sprite)


func _on_keeper_removed(entity_id: String, keeper_id: String) -> void:
	if keeper_id in _keeper_sprites:
		_keeper_sprites[keeper_id].queue_free()
		_keeper_sprites.erase(keeper_id)


# --- Save / Load ---

## Dev-only: user://dev_audio.txt overrides audio devices. Line 1 = output
## device substring, line 2 (optional) = input device substring. Substring
## matching survives Windows USB re-enumeration renames ("2- Arctis 7+").
## Works around the 96kHz WASAPI capture-silence issue on the dev machine
## (output at 96k forces capture at 96k, mics deliver zeros - see Sprint 16
## notes). No-op in release builds and when the file is absent.
func _apply_dev_audio_override() -> void:
	if not OS.is_debug_build():
		return
	if not FileAccess.file_exists("user://dev_audio.txt"):
		return
	var lines = FileAccess.get_file_as_string("user://dev_audio.txt").split("\n")
	if lines.size() >= 1 and lines[0].strip_edges() != "":
		for d in AudioServer.get_output_device_list():
			if lines[0].strip_edges() in d:
				AudioServer.output_device = d
				print("dev audio override: output -> ", d)
				break
	if lines.size() >= 2 and lines[1].strip_edges() != "":
		for d in AudioServer.get_input_device_list():
			if lines[1].strip_edges() in d:
				AudioServer.input_device = d
				print("dev audio override: input -> ", d)
				break


func _save_game() -> void:
	var data = zoo_state.to_dict(Time.get_unix_time_from_system())
	sound_store.save_all(zoo_state.sound_bank)
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open("user://save.json", FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()


func _load_game() -> void:
	if not FileAccess.file_exists("user://save.json"):
		return

	var file = FileAccess.open("user://save.json", FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("Failed to parse save file")
		return

	zoo_state.from_dict(json.data)
	sound_store.load_all(zoo_state.sound_bank)

	# Credit offline income - formula and cap live in core (Economy.calculate_offline_income)
	var now = Time.get_unix_time_from_system()
	var elapsed = now - zoo_state.last_save_time
	if zoo_state.last_save_time > 0:
		var credited = minf(elapsed, Economy.OFFLINE_CAP_SECONDS)
		var earned = Economy.calculate_offline_income(zoo_state.entities, Config, zoo_state.keepers, elapsed)
		if earned > 0:
			zoo_state.coins += earned
			zoo_state.lifetime_coins += earned
			# Show welcome back message after tree is ready
			call_deferred("_show_offline_popup", earned, credited)


func _show_offline_popup(earned: float, elapsed: float) -> void:
	var minutes = int(elapsed / 60.0)
	var msg: String
	if minutes >= 60:
		var hours = minutes / 60
		msg = "Willkommen zurück!\n%s Münzen in %d Stunden verdient!" % [FormatUtils.format_number(earned), hours]
	else:
		msg = "Willkommen zurück!\n%s Münzen in %d Minuten verdient!" % [FormatUtils.format_number(earned), minutes]
	unlock_popup.message_label.text = msg
	unlock_popup.visible = true
	unlock_popup.scale = Vector2(0.5, 0.5)
	unlock_popup.modulate.a = 0.0
	var tween = unlock_popup.create_tween()
	tween.tween_property(unlock_popup, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(unlock_popup, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(3.0)
	tween.tween_property(unlock_popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): unlock_popup.visible = false)


func _respawn_entities() -> void:
	for entity in zoo_state.entities:
		var cell = entity.grid_position
		var world_pos = zoo_map.grid_to_world(cell)
		zoo_map.occupy_cell(cell, entity.id)

		var sprite_scene = preload("res://scenes/entity_sprite.tscn")
		var sprite_node = sprite_scene.instantiate()
		zoo_map.get_node("Entities").add_child(sprite_node)
		sprite_node.sound_resolver = sound_resolver
		sprite_node.setup(entity, world_pos)
		sprite_node.tapped.connect(_on_entity_sprite_tapped)
		sprite_node.update_level_display()
		_entity_sprites[entity.id] = sprite_node

	# Respawn keeper sprites for assigned keepers
	_respawn_keepers()


func _respawn_keepers() -> void:
	for keeper in zoo_state.keepers:
		if keeper.assigned_entity_id == "":
			continue
		var entity_sprite = _entity_sprites.get(keeper.assigned_entity_id)
		if entity_sprite == null:
			continue
		_spawn_keeper_sprite(keeper, entity_sprite)


func _spawn_keeper_sprite(keeper, entity_sprite: Node2D) -> void:
	var keeper_node = KeeperSpriteScene.instantiate()
	zoo_map.get_node("Entities").add_child(keeper_node)
	keeper_node.setup(keeper, entity_sprite)
	_keeper_sprites[keeper.id] = keeper_node
