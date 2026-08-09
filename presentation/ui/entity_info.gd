extends PanelContainer
## Popup panel shown when tapping an entity on the map.
## Shows type, level, income, and upgrade button.

signal upgrade_purchased(entity: EntityData)
signal assign_keeper_requested(entity: EntityData)
signal record_sound_requested(entity: EntityData)
## Link-through to the Studio, scrolled to this animal. Editing happens there,
## on the grid - this panel only reports what the animal currently sings.
signal studio_requested(entity: EntityData)

## The read-only rhythm line is worded in the Studio module, so the panel and
## the grid can never disagree about what an animal sings.
const _CompositionView = preload("res://presentation/ui/composition_view.gd")

var _entity: EntityData
var _zoo_state: ZooState

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var level_label: Label = $VBoxContainer/LevelLabel
@onready var income_label: Label = $VBoxContainer/IncomeLabel
@onready var keeper_label: Label = $VBoxContainer/KeeperLabel
@onready var upgrade_button: Button = $VBoxContainer/UpgradeButton
@onready var keeper_button: Button = $VBoxContainer/KeeperButton
@onready var close_button: Button = $VBoxContainer/CloseButton
var record_button: Button
var beat_label: Label
var studio_button: Button


func _ready() -> void:
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	keeper_button.pressed.connect(_on_keeper_pressed)
	close_button.pressed.connect(_on_close_pressed)
	# Record button is code-built so the scene file stays untouched (Sprint 16)
	record_button = Button.new()
	record_button.text = "Sound aufnehmen"
	record_button.pressed.connect(_on_record_pressed)
	var vbox = close_button.get_parent()
	vbox.add_child(record_button)
	vbox.move_child(record_button, close_button.get_index())
	# Read-only rhythm line + the way into the Studio (plan section 1)
	beat_label = Label.new()
	vbox.add_child(beat_label)
	vbox.move_child(beat_label, record_button.get_index())
	studio_button = Button.new()
	studio_button.text = "Im Studio öffnen"
	studio_button.pressed.connect(_on_studio_pressed)
	vbox.add_child(studio_button)
	vbox.move_child(studio_button, close_button.get_index())
	visible = false


func show_entity(entity: EntityData, zoo_state: ZooState) -> void:
	_entity = entity
	_zoo_state = zoo_state
	_refresh()
	visible = true
	# Pop-in animation
	scale = Vector2(0.8, 0.8)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _process(_delta: float) -> void:
	if not visible or _entity == null:
		return
	_refresh()


func _refresh() -> void:
	var cfg = Config.get_entity_config(_entity.type_id)
	var name_str: String = cfg.get("name", _entity.type_id)
	var income: float = cfg.get("base_income", 0.0) * _entity.level
	var upgrade_cost = Economy.calculate_upgrade_cost(_entity, Config)

	name_label.text = name_str
	level_label.text = "Level %d" % _entity.level
	income_label.text = "Einkommen: %d/s" % int(income)
	upgrade_button.text = "Upgrade — %d Münzen" % int(upgrade_cost)
	upgrade_button.disabled = _zoo_state.coins < upgrade_cost

	beat_label.text = _CompositionView.beat_summary(_entity, _zoo_state.rhythm.effective_steps())

	# Keeper info
	var keeper = _zoo_state.get_keeper_for_entity(_entity.id)
	if keeper:
		keeper_label.text = "Pfleger: %s (+50%%)" % keeper.name
		keeper_button.text = "Pfleger ändern"
	else:
		keeper_label.text = "Kein Pfleger"
		keeper_button.text = "Pfleger zuweisen"


func _on_studio_pressed() -> void:
	if _entity == null:
		return
	studio_requested.emit(_entity)
	visible = false


func _on_upgrade_pressed() -> void:
	if _entity == null or _zoo_state == null:
		return
	var cost = Economy.calculate_upgrade_cost(_entity, Config)
	if _zoo_state.coins < cost:
		return
	_zoo_state.coins -= cost
	_entity.level += 1
	upgrade_purchased.emit(_entity)
	_refresh()


func _on_keeper_pressed() -> void:
	if _entity == null:
		return
	assign_keeper_requested.emit(_entity)
	visible = false


func _on_record_pressed() -> void:
	if _entity == null:
		return
	record_sound_requested.emit(_entity)
	visible = false


func _on_close_pressed() -> void:
	visible = false
	_entity = null
