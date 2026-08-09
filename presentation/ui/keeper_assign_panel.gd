extends PanelContainer
## Panel for assigning a keeper to an entity.
## Allows naming, choosing body type, and selecting a face.

signal keeper_assigned(entity_id: String, keeper_id: String)
signal keeper_removed(entity_id: String, keeper_id: String)

var _zoo_state: ZooState
var _entity: EntityData
var _selected_face_idx: int = 0
var _face_buttons: Array[Button] = []

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var name_edit: LineEdit = $VBoxContainer/NameEdit
@onready var body_option: OptionButton = $VBoxContainer/BodyOption
@onready var face_container: HBoxContainer = $VBoxContainer/FaceContainer
@onready var assign_button: Button = $VBoxContainer/AssignButton
@onready var remove_button: Button = $VBoxContainer/RemoveButton
@onready var close_button: Button = $VBoxContainer/CloseButton


func _ready() -> void:
	assign_button.pressed.connect(_on_assign_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	close_button.pressed.connect(_on_close_pressed)
	visible = false

	# Populate body type options
	var keeper_cfg = Config.get_keeper_config()
	var body_types: Dictionary = keeper_cfg.get("body_types", {})
	for bt in body_types:
		body_option.add_item(bt)

	# Create face selection buttons
	var faces: Array = keeper_cfg.get("faces", [])
	for i in range(faces.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(50, 50)
		btn.text = "👤%d" % (i + 1)
		btn.pressed.connect(_on_face_selected.bind(i))
		face_container.add_child(btn)
		_face_buttons.append(btn)

	_update_face_highlight()


func show_for_entity(entity: EntityData, zoo_state: ZooState) -> void:
	_entity = entity
	_zoo_state = zoo_state
	visible = true

	var cfg = Config.get_entity_config(entity.type_id)
	var name_str = cfg.get("name", entity.type_id)

	var existing_keeper = zoo_state.get_keeper_for_entity(entity.id)
	if existing_keeper:
		title_label.text = "Pfleger für %s" % name_str
		name_edit.text = existing_keeper.name
		# Select matching body type
		for i in range(body_option.item_count):
			if body_option.get_item_text(i) == existing_keeper.body_type:
				body_option.selected = i
				break
		remove_button.visible = true
		assign_button.text = "Aktualisieren"
	else:
		title_label.text = "Pfleger zuweisen: %s" % name_str
		name_edit.text = ""
		body_option.selected = 0
		_selected_face_idx = 0
		_update_face_highlight()
		remove_button.visible = false
		assign_button.text = "Zuweisen"

	# Pop-in animation
	scale = Vector2(0.8, 0.8)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _on_face_selected(idx: int) -> void:
	_selected_face_idx = idx
	_update_face_highlight()


func _update_face_highlight() -> void:
	for i in range(_face_buttons.size()):
		if i == _selected_face_idx:
			_face_buttons[i].modulate = Color(1.0, 1.0, 0.6)
		else:
			_face_buttons[i].modulate = Color.WHITE


func _on_assign_pressed() -> void:
	if _entity == null or _zoo_state == null:
		return

	var keeper_name = name_edit.text.strip_edges()
	if keeper_name == "":
		keeper_name = "Pfleger"

	var body_type = body_option.get_item_text(body_option.selected) if body_option.item_count > 0 else "default"

	var keeper_cfg = Config.get_keeper_config()
	var faces: Array = keeper_cfg.get("faces", [])
	var face_ref = faces[_selected_face_idx] if _selected_face_idx < faces.size() else ""

	# Check if entity already has a keeper — update it instead of creating new
	var existing = _zoo_state.get_keeper_for_entity(_entity.id)
	if existing:
		existing.name = keeper_name
		existing.body_type = body_type
		existing.face_texture_ref = face_ref
		keeper_assigned.emit(_entity.id, existing.id)
	else:
		var personalities: Array = keeper_cfg.get("personalities", ["friendly"])
		var personality = personalities[hash(keeper_name) % personalities.size()]
		var keeper = _zoo_state.add_keeper(keeper_name, body_type, personality)
		keeper.face_texture_ref = face_ref
		_zoo_state.assign_keeper(keeper.id, _entity.id)
		keeper_assigned.emit(_entity.id, keeper.id)

	visible = false


func _on_remove_pressed() -> void:
	if _entity == null or _zoo_state == null:
		return

	var existing = _zoo_state.get_keeper_for_entity(_entity.id)
	if existing:
		var keeper_id = existing.id
		_zoo_state.remove_keeper(keeper_id)
		keeper_removed.emit(_entity.id, keeper_id)

	visible = false


func _on_close_pressed() -> void:
	visible = false
	_entity = null
