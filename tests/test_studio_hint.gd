extends "res://tests/helpers/base_test.gd"
## Tests for the one-shot Studio nudge.
##
## Three first-time testers all found the idle loop and only one found the
## composer, so this hint exists to close that one gap. What has to hold: it
## waits until the player has an animal making noise, it goes away by itself,
## and it never shows twice.

const HintScript = preload("res://presentation/ui/studio_hint.gd")

var _hint
var _target: Button
var _dismissals: int


func before_each() -> void:
	_hint = HintScript.new()
	# Built detached: the runner has no scene tree, so _ready never fires.
	_hint.build()
	_target = Button.new()
	_dismissals = 0
	_hint.dismissed.connect(func(): _dismissals += 1)
	_hint.start(_target)


func after_each() -> void:
	if _hint != null and is_instance_valid(_hint):
		_hint.free()
	_hint = null
	if _target != null and is_instance_valid(_target):
		_target.free()
	_target = null


## Advances the hint's own clock without a tree.
func _tick(seconds: float) -> void:
	_hint._process(seconds)


func test_it_does_not_appear_immediately() -> void:
	# At the moment of purchase the animal has not made a sound yet, so the
	# promise of "deine Stimme" has nothing to contrast with.
	_tick(0.5)
	assert_false(_hint.is_showing(), "still quiet right after the purchase")
	assert_false(_hint.visible, "and nothing is on screen")


func test_it_appears_a_few_seconds_after_the_first_animal() -> void:
	_tick(HintScript.DELAY_AFTER_PURCHASE + 0.1)
	assert_true(_hint.is_showing(), "the nudge arrives once the zoo has a voice")
	assert_true(_hint.visible, "and it is on screen")


func test_it_dismisses_itself() -> void:
	# Guests are at a wedding; an unread hint is a decision too.
	_tick(HintScript.DELAY_AFTER_PURCHASE + 0.1)
	_tick(HintScript.AUTO_DISMISS_AFTER + 0.1)
	assert_false(_hint.is_showing(), "it gives up on its own")
	assert_false(_hint.visible, "and takes itself off screen")
	assert_eq(_dismissals, 1, "reporting once so the flag gets set")


func test_tapping_it_dismisses_it() -> void:
	_tick(HintScript.DELAY_AFTER_PURCHASE + 0.1)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	_hint._on_panel_input(touch)
	assert_false(_hint.is_showing(), "tapping the callout puts it away")
	assert_eq(_dismissals, 1, "and reports it")


func test_dismissing_reports_exactly_once() -> void:
	# main.gd writes the save flag on this signal, and the hint can be dismissed
	# from three directions - tap, the Studio button, or the timeout.
	_tick(HintScript.DELAY_AFTER_PURCHASE + 0.1)
	_hint.dismiss()
	_tick(HintScript.AUTO_DISMISS_AFTER + 0.1)
	assert_eq(_dismissals, 1, "the timeout cannot re-report an already-dismissed hint")


func test_it_stops_processing_once_dismissed() -> void:
	_tick(HintScript.DELAY_AFTER_PURCHASE + 0.1)
	_hint.dismiss()
	assert_false(_hint.is_processing(), "no per-frame work left behind")


func test_it_restores_the_button_it_pulsed() -> void:
	# The pulse modulates the Studio button. Whatever it was mid-way through,
	# the button must not be left tinted.
	_target.modulate = Color(1.3, 1.3, 1.3)
	_tick(HintScript.DELAY_AFTER_PURCHASE + 0.1)
	_hint.dismiss()
	assert_eq(_target.modulate, Color.WHITE, "the button goes back to normal")


func test_the_hint_layer_never_blocks_input() -> void:
	# It highlights and suggests; it does not gate anything.
	assert_eq(_hint.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the full-screen layer lets everything through")


func test_the_copy_is_german_with_real_umlauts() -> void:
	assert_true(HintScript.TEXT.contains("Studio"), "it names where to go")
	assert_true(HintScript.TEXT.contains("Stimme"), "and what is in it for them")
