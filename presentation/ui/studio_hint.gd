extends Control
## A single one-shot nudge toward the Studio, shown once per save.
##
## Device testing with three first-time players: all three understood the idle
## loop within seconds, only one found the composer. Recording is the point of
## the gift, so that one gap is worth a hint - and only that one.
##
## Deliberately NOT the tutorial from rhythm_tutorial_plan.md section 5: no state
## machine, no step list, no tutorial.json. A callout, a pulse on the button it
## points at, and a flag in the save.
##
## It never blocks input. The callout itself is tappable (that dismisses it), but
## everything around and beneath it stays live - a hint that gates the game is a
## modal dialog wearing a friendly hat.
##
## Built in code with no scene file, the same way record_dialog and
## composition_view are.

## The player dismissed it, or it timed out. main.gd sets the save flag.
signal dismissed()

const TEXT := "Im Studio bekommen deine Tiere deine Stimme"
## Long enough to have heard the placeholder sound at least once, so "deine
## Stimme" reads as a contrast rather than an abstraction. Not shown at launch:
## the Studio is empty then and the promise means nothing.
const DELAY_AFTER_PURCHASE := 4.0
## Unread after this long is a decision too. Guests are here for a wedding.
const AUTO_DISMISS_AFTER := 15.0
const PULSE_PERIOD := 0.9

var _panel: PanelContainer
var _target: Control
var _pulse_tween: Tween
var _elapsed: float = 0.0
var _showing: bool = false


func _ready() -> void:
	build()


## Idempotent and separate from _ready so the tests can drive it detached - a
## Control that never enters a tree never gets _ready.
func build() -> void:
	if _panel != null:
		return
	# The hint layer covers the screen so the callout can be positioned against
	# the button, but it must never eat a touch aimed at anything else.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	# The callout itself IS tappable - that is one of the ways to dismiss it.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	var label := Label.new()
	label.text = TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrapped against an explicit width: an autowrapping Label reports a ~1px
	# minimum width, and a parent sized to its minimum then stretches it to
	# absurd heights. That bug already cost this project a broken record dialog.
	label.custom_minimum_size = Vector2(520, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(label)

	visible = false


## Starts the countdown. Call once, when the player's first animal is bought.
## target is the Studio button, which gets the pulse.
func start(target: Control) -> void:
	_target = target
	_elapsed = 0.0
	_showing = false
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	if _target == null:
		return
	_elapsed += delta
	if not _showing:
		if _elapsed >= DELAY_AFTER_PURCHASE:
			_show()
		return
	_reposition()
	if _elapsed >= DELAY_AFTER_PURCHASE + AUTO_DISMISS_AFTER:
		dismiss()


func _show() -> void:
	_showing = true
	visible = true
	_reposition()
	_start_pulse()


## Parks the callout just under the Studio button, clamped into the screen so it
## cannot end up half off the edge on a narrow phone.
func _reposition() -> void:
	if _target == null or _panel == null:
		return
	# Detached in the tests, where there is no viewport to measure against.
	if get_viewport() == null:
		return
	var target_rect := _target.get_global_rect()
	var panel_size := _panel.get_combined_minimum_size()
	var x := target_rect.get_center().x - panel_size.x * 0.5
	# Below the button, but never on top of the panel the button lives in: the
	# HUD's goal line sits under the Studio button and was being covered for the
	# full fifteen seconds.
	var y := target_rect.end.y
	var ancestor: Node = _target.get_parent()
	while ancestor != null and not (ancestor is PanelContainer):
		ancestor = ancestor.get_parent()
	if ancestor is PanelContainer:
		y = maxf(y, (ancestor as Control).get_global_rect().end.y)
	y += 16.0
	var screen := get_viewport_rect().size
	x = clampf(x, 16.0, maxf(screen.x - panel_size.x - 16.0, 16.0))
	_panel.position = Vector2(x, y)
	_panel.size = panel_size


## Pulses the BUTTON, not the callout: the callout says what to do, the pulse
## says where. Modulating the button leaves it fully functional throughout.
func _start_pulse() -> void:
	# create_tween() requires the node to be in the tree; it is not in the tests.
	if _target == null or not _target.is_inside_tree():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = _target.create_tween().set_loops()
	_pulse_tween.tween_property(_target, "modulate", Color(1.35, 1.35, 1.35), PULSE_PERIOD * 0.5) \
		.set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_target, "modulate", Color.WHITE, PULSE_PERIOD * 0.5) \
		.set_trans(Tween.TRANS_SINE)


func dismiss() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _target != null:
		# Whatever the tween was mid-way through, the button goes back to normal.
		_target.modulate = Color.WHITE
	_showing = false
	visible = false
	set_process(false)
	dismissed.emit()


func is_showing() -> bool:
	return _showing


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		dismiss()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
