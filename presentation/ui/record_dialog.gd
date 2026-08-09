extends PanelContainer
## Hold-to-record dialog (Sprint 16). Built entirely in code - no scene file.
## Flow: hold button -> record (max 10s, auto-stop) -> preview -> save/discard.
## The dialog captures and previews; the CALLER owns what the sound is for
## (assigning sound_ref, persisting). Emits sound_saved(sound_id) on success.

signal sound_saved(sound_id: String)

const MAX_SECONDS := 10.0

var _recorder: AudioRecorderBase
var _bank
var _pending := PackedByteArray()
var _elapsed := 0.0
## What the caller called this animal, e.g. "Huhn 3". Stored as the SOUND's
## label so a Studio row can identify itself by its recording afterwards.
var _subject_name := ""
## On web, microphone permission is an async browser prompt: the dialog opens
## before the guest has answered. While this is true the dialog polls and shows
## a waiting state, rather than the flatly wrong "no microphone available".
var _awaiting_permission := false

var _title_label: Label
var _hint_label: Label
var _record_button: Button
var _play_button: Button
var _save_button: Button
var _discard_button: Button
var _preview: AudioStreamPlayer
var _mic_picker: OptionButton


func _ready() -> void:
	build()


## Builds the dialog. Separate from _ready and idempotent so the tests can
## drive it detached - a Control that never enters a scene tree never gets
## _ready, and the permission states below have no browser to be tested in.
func build() -> void:
	if _record_button != null:
		return
	custom_minimum_size = Vector2(560, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.theme_type_variation = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint_label)

	# Microphone picker - with several inputs connected, the OS default is
	# often the wrong one; recording silence must be a solvable problem in-UI.
	var mic_row := HBoxContainer.new()
	mic_row.add_theme_constant_override("separation", 8)
	mic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(mic_row)
	var mic_label := Label.new()
	mic_label.text = "Mikrofon:"
	mic_row.add_child(mic_label)
	_mic_picker = OptionButton.new()
	_mic_picker.item_selected.connect(_on_mic_selected)
	mic_row.add_child(_mic_picker)

	_record_button = Button.new()
	_record_button.text = "Gedrückt halten zum Aufnehmen"
	_record_button.theme_type_variation = "AccentButton"
	_record_button.button_down.connect(_on_record_down)
	_record_button.button_up.connect(_on_record_up)
	vbox.add_child(_record_button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	_play_button = Button.new()
	_play_button.text = "Anhören"
	_play_button.pressed.connect(_on_play_pressed)
	row.add_child(_play_button)

	_save_button = Button.new()
	_save_button.text = "Speichern"
	_save_button.pressed.connect(_on_save_pressed)
	row.add_child(_save_button)

	_discard_button = Button.new()
	_discard_button.text = "Abbrechen"
	_discard_button.theme_type_variation = "GhostButton"
	_discard_button.pressed.connect(_on_discard_pressed)
	row.add_child(_discard_button)

	_preview = AudioStreamPlayer.new()
	add_child(_preview)

	visible = false


func open(recorder: AudioRecorderBase, bank, subject_name: String) -> void:
	_recorder = recorder
	_bank = bank
	_pending = PackedByteArray()
	_elapsed = 0.0
	_subject_name = subject_name
	_title_label.text = "Sound für %s" % subject_name
	# Opening the dialog is a user gesture, which is the one moment iOS Safari
	# will let the microphone be asked for at all.
	if _recorder != null:
		_recorder.request_permission()
	_refresh_availability()
	_refresh_mic_list()
	_update_buttons()
	visible = true


func _process(delta: float) -> void:
	if _recorder != null and _recorder.is_recording():
		_elapsed += delta
		_hint_label.text = "Aufnahme... %.1fs" % _elapsed
		if _elapsed >= MAX_SECONDS:
			_finish_recording()
		return
	if visible and _awaiting_permission:
		_refresh_availability()


## The four states the dialog can be in before anything is recorded: ready,
## waiting on the browser, refused, or nothing to record with. Native platforms
## go straight to ready; web can sit in "waiting" for as long as the guest takes
## to answer, and "refused" is a dead end until they change it themselves.
func _refresh_availability() -> void:
	_awaiting_permission = false
	_record_button.disabled = true
	if _recorder == null:
		_hint_label.text = "Kein Mikrofon verfügbar"
		return
	if _recorder.is_available():
		_hint_label.text = "Halte den Knopf und mach ein Geräusch!"
		_record_button.disabled = false
		return
	if _recorder.is_permission_pending():
		_awaiting_permission = true
		_hint_label.text = "Warte auf Mikrofon-Freigabe..."
		return
	if _recorder.is_permission_denied():
		# The only one of the failure states the guest can undo - and on iOS
		# the refusal is sticky, so nothing here will ever prompt again. Say
		# where to fix it instead of pretending there is no microphone.
		_hint_label.text = "Mikrofon-Zugriff abgelehnt.\nIm Browser erlauben und die Seite neu laden."
		return
	_hint_label.text = "Kein Mikrofon verfügbar"


func _on_record_down() -> void:
	if _recorder == null or not _recorder.is_available():
		return
	_pending = PackedByteArray()
	_elapsed = 0.0
	if _recorder.start_recording():
		_hint_label.text = "Aufnahme..."
	else:
		_hint_label.text = "Aufnahme konnte nicht starten"
	_update_buttons()


func _on_record_up() -> void:
	if _recorder != null and _recorder.is_recording():
		_finish_recording()


func _finish_recording() -> void:
	_pending = _recorder.stop_recording()
	if _pending.size() > 0:
		var peak = WavUtils.get_peak(_pending)
		if peak < 0.02:
			_hint_label.text = "Aufnahme fast stumm - richtiges Mikrofon gewählt?"
		else:
			_hint_label.text = "%.1fs aufgenommen - anhören oder speichern" % _elapsed
	else:
		_hint_label.text = "Aufnahme fehlgeschlagen - nochmal versuchen"
	_update_buttons()


func _on_play_pressed() -> void:
	var stream = WavUtils.to_stream(_pending)
	if stream != null:
		_preview.stream = stream
		_preview.play()


func _on_save_pressed() -> void:
	# The capture chain (mono -> canonical rate -> trim -> normalize) lives in
	# SoundBank: it owns what shape sounds enter the bank in, and every capture
	# path has to agree on it.
	var canonical := SoundBank.prepare_take(_pending)
	# The label is the SUBJECT, not the dialog's title text: the Studio shows it
	# as the row's name, and "Sound für Huhn" on a dozen rows says nothing.
	var id: String = _bank.add_sound(canonical, _subject_name, Time.get_unix_time_from_system())
	if id == "":
		_hint_label.text = "Speichern fehlgeschlagen - nochmal aufnehmen"
		_update_buttons()
		return
	_close()
	sound_saved.emit(id)


func _on_discard_pressed() -> void:
	if _recorder != null and _recorder.is_recording():
		_recorder.stop_recording()
	_close()


## Hands the microphone back on the way out. On web that is what turns the
## browser's recording indicator off - holding the stream open for the rest of
## the session looks like the game is listening.
func _close() -> void:
	visible = false
	_awaiting_permission = false
	if _recorder != null:
		_recorder.release()


func _refresh_mic_list() -> void:
	_mic_picker.clear()
	var devices = AudioServer.get_input_device_list()
	var current = AudioServer.input_device
	for i in devices.size():
		_mic_picker.add_item(devices[i])
		if devices[i] == current:
			_mic_picker.select(i)
	_mic_picker.visible = devices.size() > 1


func _on_mic_selected(index: int) -> void:
	AudioServer.input_device = _mic_picker.get_item_text(index)


func _update_buttons() -> void:
	var has_take := _pending.size() > 0
	_play_button.disabled = not has_take
	_save_button.disabled = not has_take