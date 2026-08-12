extends PanelContainer
## Shop panel — shows buyable entity types with costs.
## Shows locked types grayed out with unlock hints.

signal entity_purchased(type_id: String, entity: EntityData, sprite_node: Node2D)
signal entity_tapped(entity_data: EntityData)
## The panel closed itself. main.gd owns the save, so it persists the new state.
signal closed()

## Every interactive control is at least this tall. The viewport is 1080 wide
## against a ~390pt phone screen, so a project pixel is about 0.36pt: the old
## 60px buttons landed near 22pt, half of Apple's 44pt minimum, and four-device
## testing found them genuinely hard to hit.
const MIN_TOUCH_SIZE := 120.0

var _zoo_state: ZooState
var _zoo_map: Node2D
var _buttons: Dictionary = {}  # type_id → Button
var _locked_labels: Dictionary = {}  # type_id → Label

const EntitySpriteScene = preload("res://scenes/entity_sprite.tscn")

@onready var _close_button: Button = $VBoxContainer/HeaderRow/CloseButton
## The one child of the list that _rebuild_shop must never remove.
@onready var _header_row: HBoxContainer = $VBoxContainer/HeaderRow


func _ready() -> void:
	_close_button.pressed.connect(close)


func setup(zoo_state: ZooState, zoo_map: Node2D) -> void:
	_zoo_state = zoo_state
	_zoo_map = zoo_map
	_rebuild_shop()


func open() -> void:
	visible = true
	# Hidden panels skip their refresh, so catch up before being seen rather
	# than showing one frame of stale prices.
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	# A hidden shop still had a Control in the tree ticking every frame, walking
	# every buyable type and every locked milestone to recompute text nobody was
	# looking at. Cheap per frame, pointless while closed.
	if not visible:
		return
	_refresh()


func _refresh() -> void:
	if _zoo_state == null:
		return
	_update_button_states()
	_update_locked_labels()


func _rebuild_shop() -> void:
	var container = $VBoxContainer
	# Detach IMMEDIATELY, then free. queue_free() alone is deferred to the end of
	# the frame, and the replacement rows are added in this same frame - so the
	# old node is still attached when its replacement arrives, Godot resolves the
	# name clash by renaming the NEW node, and the name it picks is "@Label@3".
	# That does not begin with "Locked_", so the next rebuild's name check no
	# longer recognised it and it was never removed. Every unlock after the first
	# therefore left a stale, frozen copy of the locked list above the buy
	# buttons - which is why the shop showed each animal twice with different
	# numbers, and why the buy buttons appeared in the middle rather than on top.
	#
	# Identity, not names: everything except the header row is ours to remove.
	for child in container.get_children():
		if child == _header_row:
			continue
		container.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_locked_labels.clear()

	# Unlocked types — buyable
	for type_id in _zoo_state.unlocks:
		var cfg = Config.get_entity_config(type_id)
		if cfg.is_empty():
			continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, MIN_TOUCH_SIZE)
		btn.pressed.connect(_on_buy_pressed.bind(type_id))
		btn.button_down.connect(_on_button_down.bind(btn))
		btn.button_up.connect(_on_button_up.bind(btn))
		container.add_child(btn)
		_buttons[type_id] = btn

	# Locked types — show hints sorted by threshold
	var milestones = Config.get_progression_milestones()
	for m in milestones:
		var type_id: String = m["unlock_type"]
		if type_id in _zoo_state.unlocks:
			continue
		var cfg = Config.get_entity_config(type_id)
		if cfg.is_empty():
			continue
		var lbl = Label.new()
		lbl.name = "Locked_%s" % type_id
		lbl.custom_minimum_size = Vector2(0, 40)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		container.add_child(lbl)
		_locked_labels[type_id] = {"label": lbl, "threshold": m["threshold"]}


func _update_button_states() -> void:
	for type_id in _buttons:
		var btn: Button = _buttons[type_id]
		var cfg = Config.get_entity_config(type_id)
		var owned = _zoo_state.get_entity_count(type_id)
		var cost = Economy.calculate_cost(type_id, owned, Config)
		var name_str: String = cfg.get("name", type_id)
		var income: float = cfg.get("base_income", 0.0)

		btn.text = "%s kaufen — %d Münzen (+%s/s)" % [name_str, int(cost), _format_income(income)]
		btn.disabled = _zoo_state.coins < cost


func _update_locked_labels() -> void:
	for type_id in _locked_labels:
		var info: Dictionary = _locked_labels[type_id]
		var lbl: Label = info["label"]
		var threshold: float = info["threshold"]
		var cfg = Config.get_entity_config(type_id)
		var name_str: String = cfg.get("name", type_id)
		var remaining = threshold - _zoo_state.lifetime_coins
		if remaining > 0:
			lbl.text = "🔒 %s — noch %d Münzen verdienen" % [name_str, int(remaining)]
		else:
			lbl.text = "🔒 %s — bald verfügbar!" % name_str


func _on_buy_pressed(type_id: String) -> void:
	var owned = _zoo_state.get_entity_count(type_id)
	var cost = Economy.calculate_cost(type_id, owned, Config)

	if _zoo_state.coins < cost:
		return

	_zoo_state.coins -= cost

	var zone = _zoo_map.get_zone_for_type(type_id)
	if not _zoo_map.is_zone_unlocked(zone):
		_zoo_state.coins += cost
		return
	var cell = _zoo_map.get_first_free_cell(zone)
	if cell == Vector2i(-1, -1):
		_zoo_state.coins += cost
		return

	var cfg = Config.get_entity_config(type_id)
	var sound = cfg.get("default_sound", "")
	var entity = _zoo_state.add_entity(type_id, cell, sound)

	var sprite_node = _spawn_entity_sprite(entity, cell)
	entity_purchased.emit(type_id, entity, sprite_node)


func _spawn_entity_sprite(entity: EntityData, cell: Vector2i) -> Node2D:
	var world_pos = _zoo_map.grid_to_world(cell)
	_zoo_map.occupy_cell(cell, entity.id)

	var sprite_node = EntitySpriteScene.instantiate()
	_zoo_map.get_node("Entities").add_child(sprite_node)
	sprite_node.setup(entity, world_pos)
	sprite_node.tapped.connect(_on_entity_tapped.bind(entity))
	return sprite_node


func _on_entity_tapped(sprite_node: Node2D, entity: EntityData) -> void:
	entity_tapped.emit(entity)


func refresh_unlocks() -> void:
	_rebuild_shop()


func _on_button_down(btn: Button) -> void:
	var tween = btn.create_tween()
	tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)


func _on_button_up(btn: Button) -> void:
	var tween = btn.create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08).set_ease(Tween.EASE_OUT)


static func _format_income(value: float) -> String:
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	elif value >= 1:
		return str(int(value))
	else:
		return "%.1f" % value
