extends "res://tests/helpers/base_test.gd"
## Tests for the record dialog's three pre-capture states.
##
## These exist because the web recorder cannot be tested here at all: there is
## no browser. What CAN be pinned is the shape the browser imposes - permission
## arrives asynchronously, so the dialog opens unavailable and has to notice
## when that changes. The mock plays the browser's part.

const DialogScript = preload("res://presentation/ui/record_dialog.gd")
const MockRecorder = preload("res://platform/mock_audio_recorder.gd")

var _dialog
var _rec
var _bank


func before_each() -> void:
	_dialog = DialogScript.new()
	# Built detached: the runner has no scene tree, so _ready never fires.
	_dialog.build()
	_rec = MockRecorder.new()
	_bank = SoundBank.new()


func after_each() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.free()
	_dialog = null
	if _rec != null and is_instance_valid(_rec):
		_rec.free()
	_rec = null


func _open_web() -> void:
	# A recorder that behaves like the browser: nothing until the guest answers.
	_rec.needs_permission = true
	_dialog.open(_rec, _bank, "Huhn 1")


# --- Native path (unchanged behaviour) ---

func test_native_recorder_opens_ready_to_record() -> void:
	_dialog.open(_rec, _bank, "Huhn 1")
	assert_false(_dialog._record_button.disabled, "the button is live immediately")
	assert_true(_dialog._hint_label.text.contains("Halte den Knopf"), "and it says so")


func test_missing_recorder_says_no_microphone() -> void:
	_dialog.open(null, _bank, "Huhn 1")
	assert_true(_dialog._record_button.disabled, "nothing to record with")
	assert_true(_dialog._hint_label.text.contains("Kein Mikrofon"), "stated plainly")


# --- Web path: permission is asynchronous ---

func test_opening_asks_for_permission() -> void:
	# Opening the dialog is the user gesture iOS Safari requires.
	_open_web()
	assert_eq(_rec.permission_requests, 1, "asked once, on open")


func test_web_opens_in_a_waiting_state() -> void:
	_open_web()
	assert_true(_dialog._record_button.disabled, "cannot record before the guest allows it")
	assert_true(_dialog._hint_label.text.contains("Warte"), "waiting, not 'no microphone'")
	assert_false(_dialog._hint_label.text.contains("Kein Mikrofon"), "the wrong message would just be a lie")


func test_granting_permission_unlocks_the_button() -> void:
	_open_web()
	_rec.grant_permission()
	_dialog._process(0.016)  # the poll that would run on the next frame
	assert_false(_dialog._record_button.disabled, "the button comes alive by itself")
	assert_true(_dialog._hint_label.text.contains("Halte den Knopf"), "and the hint catches up")


func test_denied_permission_says_so_and_says_how_to_undo_it() -> void:
	# On iOS the refusal is sticky: nothing in the game will prompt again, so
	# "no microphone available" would leave the guest with no way forward.
	_open_web()
	_rec.deny_permission()
	_dialog._process(0.016)
	assert_true(_dialog._record_button.disabled, "still cannot record")
	assert_true(_dialog._hint_label.text.contains("abgelehnt"), "names what actually happened")
	assert_true(_dialog._hint_label.text.contains("Browser"), "and points at the browser settings")
	assert_true(_dialog._hint_label.text.contains("neu laden"), "and says to reload afterwards")
	assert_false(_dialog._hint_label.text.contains("Kein Mikrofon"), "not the wrong diagnosis")


func test_no_microphone_is_not_reported_as_a_refusal() -> void:
	# NotFoundError, or a browser that cannot record at all. Unavailable, but
	# nothing the guest can fix in their settings.
	_open_web()
	_rec.report_no_device()
	_dialog._process(0.016)
	assert_true(_dialog._record_button.disabled, "cannot record")
	assert_true(_dialog._hint_label.text.contains("Kein Mikrofon"), "stated as a missing device")
	assert_false(_dialog._hint_label.text.contains("abgelehnt"), "and not blamed on the guest")


func test_no_device_and_no_recorder_do_not_share_one_message() -> void:
	# These two printed the same string, so a phone reporting it could not tell
	# us whether the platform had failed to build a recorder at all or the
	# browser had refused to produce a microphone. That ambiguity cost a whole
	# debugging round on a device with no reachable console.
	_dialog.open(null, _bank, "Huhn 1")
	var missing_recorder: String = _dialog._hint_label.text
	_open_web()
	_rec.report_no_device()
	_dialog._process(0.016)
	var no_device: String = _dialog._hint_label.text
	assert_true(missing_recorder != no_device, "the two failures read differently")


func test_diagnostic_line_is_absent_by_default() -> void:
	# debug_state() is empty on every platform but web-with-?debug=1, so the
	# guest-facing text stays clean.
	_open_web()
	_rec.report_no_device()
	_dialog._process(0.016)
	assert_false(_dialog._hint_label.text.contains("diag:"), "guests never see the diagnostic")


func test_recovering_from_a_refusal_unlocks_the_button() -> void:
	# The guest allowed it in browser settings and came back.
	_open_web()
	_rec.deny_permission()
	_dialog._process(0.016)
	_dialog._on_discard_pressed()
	_open_web()
	_rec.grant_permission()
	_dialog._process(0.016)
	assert_false(_dialog._record_button.disabled, "a second try after fixing it works")
	assert_true(_dialog._hint_label.text.contains("Halte den Knopf"), "back to the normal prompt")


func test_german_strings_use_real_umlauts() -> void:
	# Section 9: transliteration is for the plan file, not for what a guest sees.
	_dialog.open(_rec, _bank, "Huhn 1")
	assert_true(_dialog._hint_label.text.contains("Geräusch"), "the ready prompt")
	assert_true(_dialog._record_button.text.contains("Gedrückt"), "the record button")
	assert_true(_dialog._play_button.text == "Anhören", "the preview button")
	assert_true(_dialog._title_label.text.begins_with("Sound für"), "the title")


func test_recording_is_refused_while_permission_is_pending() -> void:
	_open_web()
	_dialog._on_record_down()
	assert_false(_rec.is_recording(), "a press during the prompt starts nothing")


func test_polling_stops_once_permission_settles() -> void:
	_open_web()
	_rec.grant_permission()
	_dialog._process(0.016)
	_dialog._hint_label.text = "Aufnahme fast stumm - richtiges Mikrofon gewaehlt?"
	_dialog._process(0.016)
	assert_true(_dialog._hint_label.text.contains("stumm"), "a settled dialog stops overwriting its own messages")


# --- The microphone is handed back ---

func test_saving_releases_the_microphone() -> void:
	_open_web()
	_rec.grant_permission()
	_dialog._process(0.016)
	_dialog._on_record_down()
	_dialog._on_record_up()
	var saved: Array = []
	_dialog.sound_saved.connect(func(id): saved.append(id))
	_dialog._on_save_pressed()

	assert_eq(saved.size(), 1, "the take reached the bank")
	assert_true(_bank.has_sound(saved[0]), "and the bank knows it")
	assert_eq(_bank.get_label(saved[0]), "Huhn 1", "labelled with the animal it came from")
	assert_eq(_rec.release_calls, 1, "and the microphone was handed back")
	assert_false(_dialog.visible, "dialog closed")


func test_discarding_releases_the_microphone() -> void:
	_open_web()
	_rec.grant_permission()
	_dialog._process(0.016)
	_dialog._on_record_down()
	_dialog._on_discard_pressed()
	assert_eq(_rec.release_calls, 1, "released on the way out")
	assert_false(_rec.is_recording(), "and the capture was stopped first")


func test_reopening_asks_again() -> void:
	# release() drops the stream, so the next session has to re-acquire it. An
	# already-granted browser permission resolves without a second prompt.
	_open_web()
	_rec.grant_permission()
	_dialog._on_discard_pressed()
	_open_web()
	assert_eq(_rec.permission_requests, 2, "asked again on the second open")
