extends PanelContainer
## HUD — displays coins, income rate, and next unlock goal.

## The Studio is opened from here (plan section 3b) — it is a full screen, not
## a bottom sheet, so main.gd owns the view and the HUD only asks for it.
signal studio_requested()
## The shop is closable, so it needs a way back. main.gd owns the panel and the
## save; the HUD only asks.
signal shop_requested()

## See ShopPanel.MIN_TOUCH_SIZE - a project pixel is about 0.36pt on a phone,
## so anything under this is below Apple's 44pt touch guideline.
const MIN_TOUCH_SIZE := 120.0

var _zoo_state: ZooState
var _displayed_coins: float = 0.0

@onready var coins_label: Label = $VBoxContainer/TopRow/CoinsLabel
@onready var income_label: Label = $VBoxContainer/TopRow/IncomeLabel
@onready var boost_label: Label = $VBoxContainer/TopRow/BoostLabel
@onready var goal_label: Label = $VBoxContainer/GoalLabel
var studio_button: Button
var shop_button: Button


func _ready() -> void:
	# Code-built so the scene file stays untouched (same as entity_info's
	# record button).
	shop_button = Button.new()
	shop_button.text = "Shop"
	shop_button.custom_minimum_size = Vector2(0, MIN_TOUCH_SIZE)
	shop_button.pressed.connect(func(): shop_requested.emit())
	$VBoxContainer/TopRow.add_child(shop_button)

	studio_button = Button.new()
	studio_button.text = "🎵 Studio"
	studio_button.theme_type_variation = "AccentButton"
	studio_button.custom_minimum_size = Vector2(0, MIN_TOUCH_SIZE)
	studio_button.pressed.connect(func(): studio_requested.emit())
	$VBoxContainer/TopRow.add_child(studio_button)


func setup(zoo_state: ZooState) -> void:
	_zoo_state = zoo_state
	_displayed_coins = zoo_state.coins


func _process(delta: float) -> void:
	if _zoo_state == null:
		return

	_displayed_coins = lerpf(_displayed_coins, _zoo_state.coins, minf(10.0 * delta, 1.0))

	coins_label.text = "%s Münzen" % FormatUtils.format_number(_displayed_coins)
	var ips = _zoo_state.get_income_per_second(Config)
	income_label.text = "+%s/s" % FormatUtils.format_number(ips)

	# Interaction boost indicator
	var any_boost = false
	for e in _zoo_state.entities:
		if _zoo_state.interaction_engine.get_income_multiplier(e.id) > 1.0:
			any_boost = true
			break
	boost_label.visible = any_boost
	if any_boost:
		boost_label.text = "BOOST!"

	# Next unlock goal
	var next = _get_next_milestone()
	if next.is_empty():
		goal_label.text = "Alle Tiere freigeschaltet!"
	else:
		var remaining = next["threshold"] - _zoo_state.lifetime_coins
		var cfg = Config.get_entity_config(next["unlock_type"])
		var name_str: String = cfg.get("name", next["unlock_type"])
		goal_label.text = "Nächstes Ziel: %s (noch %s)" % [name_str, FormatUtils.format_number(remaining)]


func _get_next_milestone() -> Dictionary:
	var milestones = Config.get_progression_milestones()
	for m in milestones:
		if m["unlock_type"] not in _zoo_state.unlocks:
			return m
	return {}
