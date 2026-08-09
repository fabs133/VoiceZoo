extends Control
## THE STUDIO SCREEN (plan section 3b): the full grid of animals x loop steps.
## Rows are animals, columns are the eight steps of the bar, a cell means "this
## animal sings on this step". The playhead highlights the current column in
## time with the engine, which is what makes the mechanic legible - you SEE the
## beat move and HEAR the sounds fire on it.
##
## Built entirely in code, no scene file (same as record_dialog).
##
## Dependencies are injected via setup():
## - zoo_state: the animals to show, and the rhythm engine to read the playhead
##   and the voice-cap situation from.
## - rhythm_player: fires the immediate preview when a cell is tapped, so a
##   placed beat is heard through exactly the path it will play through.
## - config: anything with get_entity_config(type_id) -> Dictionary.

## Emitted on every cell tap. R5's tutorial waits for this ("beat_toggled").
signal beat_toggled(entity: EntityData)
## A row asked to record. main.gd owns the dialog and the save wiring; this
## screen only says which animal. Recording from the Studio is the common case:
## you hear a part, you want to change it.
signal record_requested(entity: EntityData)
signal closed()

const _RhythmEngine = preload("res://core/rhythm_engine.gd")

## Section 3b's space budget. 1080 wide, minus 300 for the row label and the
## margins, leaves ~93px per cell at 8 steps - above the 88px touch minimum.
## At 16 steps it would be ~47px, which is exactly why V1 is one 8-step bar.
const ROW_LABEL_WIDTH := 300.0
const MIN_TOUCH_SIZE := 88.0
const GRID_MARGIN := 16.0
const ROW_HEIGHT := 96.0
## The row label area is split three ways: a thumbnail that previews, the name
## (which is also the in_song toggle), and a mic button. Thumbnail and mic stay
## full touch targets, so the name takes what is left (~116px) and clips - the
## whole label is on the tooltip.
const ROW_ACTION_SIZE := 88.0

## Mirrors data/ui_theme.json (accent / accent_gold / disabled). These are set
## per cell at runtime, which a static theme.tres cannot express.
const CELL_ON := Color("#E9718F")
const CELL_OFF := Color("#D8CFC0")
## On, but the voice cap drops it - visibly "playing but not heard".
const CELL_CAPPED := Color("#E9718F", 0.35)
const PLAYHEAD_COLOR := Color("#F2B138", 0.28)
const PARKED_ROW_ALPHA := 0.45

var _zoo_state
var _rhythm_player
var _config

var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _grid_area: Control
var _playhead: ColorRect
var _header_labels: Array[Label] = []
var _empty_label: Label
var _legend: Label

## One entry per visible row: {entity, root, label_button, cells: Array[Button]}
var _rows: Array[Dictionary] = []
var _cell_width: float = MIN_TOUCH_SIZE
var _last_step: int = -1
var _last_entity_count: int = -1
var _focus_entity_id: String = ""


func setup(zoo_state, rhythm_player, config) -> void:
	_zoo_state = zoo_state
	_rhythm_player = rhythm_player
	_config = config


func _ready() -> void:
	build()


## Builds the static chrome (title, column header, scroll area, playhead).
## Separate from _ready and idempotent because a Control that is never added to
## a scene tree never gets _ready - which is exactly how the tests drive it.
func build() -> void:
	if _rows_box != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_chrome()
	visible = false


## Opens the Studio. Pass an entity id to scroll to that animal and mark its
## row - that is the link-through from the entity info panel.
func open(focus_entity_id: String = "") -> void:
	_focus_entity_id = focus_entity_id
	visible = true
	_rebuild_rows()
	_scroll_to_focus()


func close() -> void:
	visible = false
	closed.emit()


## Repaint after something OUTSIDE the Studio changed an animal - saving a
## recording renames that row and sorts it to the top. No-op while closed.
func refresh() -> void:
	if visible:
		_rebuild_rows()


func _process(_delta: float) -> void:
	if not visible or _zoo_state == null:
		return
	# Buying an animal or recording a sound while the Studio is open changes
	# the grid. Cheap to check, and rebuilding is the honest response.
	if _zoo_state.entities.size() != _last_entity_count:
		_rebuild_rows()
	_update_playhead()


# --- Pure helpers (static so the rules are testable without building the UI) ---

## Cell width for a given screen width. Not clamped: the raw number is what
## section 3b's budget is about, and the caller clamps to MIN_TOUCH_SIZE.
static func cell_width_for(total_width: float, steps: int) -> float:
	var usable := total_width - ROW_LABEL_WIDTH - GRID_MARGIN * 2.0
	return usable / float(maxi(steps, 1))


## Row order: animals with a user recording first (the interesting voices stay
## on top), then by type, then by id. No grouping by type - patterns are
## per-animal because they rotate, so a type row would lie about what plays.
static func sort_rows(entities: Array) -> Array:
	var rows: Array = []
	for e in entities:
		rows.append(e)
	rows.sort_custom(_compare_rows)
	return rows


static func _compare_rows(a, b) -> bool:
	var a_recorded := 1 if a.sound_ref != "" else 0
	var b_recorded := 1 if b.sound_ref != "" else 0
	if a_recorded != b_recorded:
		return a_recorded > b_recorded
	if a.type_id != b.type_id:
		return a.type_id < b.type_id
	if a.id.to_int() != b.id.to_int():
		return a.id.to_int() < b.id.to_int()
	return a.id < b.id


## entity_id -> 1-based ordinal among its own type, in entity order. Computed
## at display time, so there is nothing to migrate and nothing to keep in sync.
static func ordinals_by_id(entities: Array) -> Dictionary:
	var counts: Dictionary = {}
	var ordinals: Dictionary = {}
	for e in entities:
		var n: int = int(counts.get(e.type_id, 0)) + 1
		counts[e.type_id] = n
		ordinals[e.id] = n
	return ordinals


## What a row is called. An animal with a recording shows that sound's own
## label - it is the reason the player made it. Everything else shows
## "<Name> <n>", its ordinal among its own type, because a dozen rows all
## reading "Huhn" is exactly what the R4 listen test tripped over.
static func row_label(entity, ordinal: int, type_name: String, sound_label: String) -> String:
	if entity.sound_ref != "" and sound_label.strip_edges() != "":
		return sound_label
	return "%s %d" % [type_name, ordinal]


## Makes a set of row names unique. Sound labels come from PEOPLE, so they are
## not unique by construction: two guests both recording "Wuff" is the expected
## case, not the exceptional one, and a zoo saved before R4.5 has several rows
## reading "Sound fuer Katze". Every member of a colliding group gets its
## ordinal appended - numbering only the later ones reads like a mistake.
static func unique_labels(base_labels: Array, ordinals: Array) -> Array:
	var counts: Dictionary = {}
	for label in base_labels:
		counts[str(label)] = int(counts.get(str(label), 0)) + 1
	var used: Dictionary = {}
	var out: Array = []
	for i in base_labels.size():
		var label := str(base_labels[i])
		if int(counts[label]) > 1:
			label = "%s %d" % [label, int(ordinals[i])]
		# Belt and braces: a hand-typed label could equal another row's numbered
		# form. Rare enough to deserve a marker rather than a scheme.
		while used.has(label):
			label += " ·"
		used[label] = true
		out.append(label)
	return out


## The distinguishing name for one animal, without needing the grid. main.gd
## hands it to the record dialog, so a stored sound is labelled with the animal
## it came from and that row stays distinguishable once the recording exists.
static func display_name(entity, entities: Array, type_name: String) -> String:
	return "%s %d" % [type_name, int(ordinals_by_id(entities).get(entity.id, 1))]


## "Singt auf Takt 1, 5" — the one-line, read-only version of a row, used by
## the entity info panel. Steps are 1-based because the player counts bars,
## not array indices. Lives here rather than in entity_info because this module
## is deliberately free of the Config autoload and so can be loaded in tests.
static func beat_summary(entity, steps_per_loop: int) -> String:
	if not entity.in_song:
		return "Pausiert – singt gerade nicht mit"
	var steps := _RhythmEngine.steps_from_pattern(entity.beat_pattern, steps_per_loop)
	if steps.is_empty():
		return "Singt auf keinem Takt"
	var human: Array[String] = []
	for s in steps:
		human.append(str(s + 1))
	return "Singt auf Takt %s" % ", ".join(human)


## True when an animal sings somewhere but loses the cap on EVERY step it is
## on: correct behaviour, but it never makes a sound, and section 3b says the
## grid has to say so rather than let the player conclude their new chicken is
## broken. A parked animal is a different state and is marked differently.
static func is_fully_capped(entity, capped_by_step: Dictionary, steps: int) -> bool:
	if not entity.in_song:
		return false
	var sings := false
	for step in steps:
		if not _RhythmEngine.plays_on(entity.beat_pattern, step):
			continue
		sings = true
		var dropped: Dictionary = capped_by_step.get(step, {})
		if not dropped.has(entity.id):
			return false
	return sings


# --- Building ---

func _build_chrome() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(GRID_MARGIN))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	vbox.add_child(_build_title_row())
	vbox.add_child(_build_column_header())

	_grid_area = Control.new()
	_grid_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_grid_area)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_area.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows_box)

	_empty_label = Label.new()
	_empty_label.text = "Noch keine Tiere – kauf dir eins im Shop!"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	_rows_box.add_child(_empty_label)

	# On top of the rows, not behind them: the cells have opaque backgrounds,
	# so a playhead underneath would be invisible.
	_playhead = ColorRect.new()
	_playhead.color = PLAYHEAD_COLOR
	_playhead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_area.add_child(_playhead)

	_legend = Label.new()
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_legend)


func _build_title_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Studio"
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var done := Button.new()
	done.text = "Fertig"
	done.custom_minimum_size = Vector2(160, MIN_TOUCH_SIZE)
	done.pressed.connect(close)
	row.add_child(done)
	return row


func _build_column_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0)
	row.add_child(spacer)

	_header_labels.clear()
	for step in _steps():
		var lbl := Label.new()
		# 1-based for humans: the player counts "Takt 1", not "step 0".
		lbl.text = str(step + 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(_cell_width, 0)
		row.add_child(lbl)
		_header_labels.append(lbl)
	return row


func _rebuild_rows() -> void:
	if _zoo_state == null:
		return
	_cell_width = maxf(cell_width_for(_screen_width(), _steps()), MIN_TOUCH_SIZE)
	for lbl in _header_labels:
		lbl.custom_minimum_size = Vector2(_cell_width, 0)

	for row in _rows:
		var old: Node = row["root"]
		_rows_box.remove_child(old)
		old.queue_free()
	_rows.clear()

	for entity in sort_rows(_zoo_state.entities):
		_rows.append(_build_row(entity))

	_last_entity_count = _zoo_state.entities.size()
	_empty_label.visible = _rows.is_empty()
	_refresh_cells()


func _build_row(entity) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	_rows_box.add_child(root)

	var label_area := HBoxContainer.new()
	label_area.add_theme_constant_override("separation", 4)
	label_area.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, ROW_HEIGHT)
	root.add_child(label_area)

	# Thumbnail: tap to HEAR the row, without editing it. Hearing an animal is
	# the fastest identity check there is.
	var thumb_button := Button.new()
	thumb_button.custom_minimum_size = Vector2(ROW_ACTION_SIZE, ROW_ACTION_SIZE)
	thumb_button.expand_icon = true
	thumb_button.tooltip_text = "Anhören"
	var cfg: Dictionary = _config.get_entity_config(entity.type_id) if _config != null else {}
	var sprite_path: String = cfg.get("sprite", "")
	if sprite_path != "":
		var tex = load(sprite_path)
		if tex != null:
			thumb_button.icon = tex
	thumb_button.pressed.connect(_on_thumb_pressed.bind(entity))
	label_area.add_child(thumb_button)

	# The name IS the in_song toggle (section 3b) - one tap parks an animal
	# without deleting it.
	var label_button := Button.new()
	label_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_button.clip_text = true
	label_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label_button.pressed.connect(_on_row_label_pressed.bind(entity))
	label_area.add_child(label_button)

	# Record for this animal without leaving the Studio.
	var mic_button := Button.new()
	mic_button.custom_minimum_size = Vector2(ROW_ACTION_SIZE, ROW_ACTION_SIZE)
	mic_button.text = "🎤"
	mic_button.tooltip_text = "Sound aufnehmen"
	mic_button.pressed.connect(_on_mic_pressed.bind(entity))
	label_area.add_child(mic_button)

	var cells: Array[Button] = []
	for step in _steps():
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(_cell_width, ROW_HEIGHT)
		cell.pressed.connect(_on_cell_pressed.bind(entity, step))
		root.add_child(cell)
		cells.append(cell)

	return {
		"entity": entity,
		"root": root,
		"label_button": label_button,
		"thumb_button": thumb_button,
		"mic_button": mic_button,
		"cells": cells,
	}


# --- Refreshing ---

## Repaints every cell and row label from the current patterns and the current
## voice-cap situation. Called on open and after any edit - NOT per frame: the
## cap query walks every entity for every step.
func _refresh_cells() -> void:
	var capped_by_step := _compute_capped()
	var names := _row_names()
	for i in _rows.size():
		var row := _rows[i]
		var entity = row["entity"]
		var fully_capped := is_fully_capped(entity, capped_by_step, _steps())
		var cells: Array = row["cells"]
		for step in cells.size():
			var cell: Button = cells[step]
			if not _RhythmEngine.plays_on(entity.beat_pattern, step):
				cell.self_modulate = CELL_OFF
			elif capped_by_step.get(step, {}).has(entity.id):
				cell.self_modulate = CELL_CAPPED
			else:
				cell.self_modulate = CELL_ON
		_refresh_row_label(row, fully_capped, str(names[i]))
	_refresh_legend()


## The display name of every row, in row order, already de-collided.
func _row_names() -> Array:
	# Ordinals come from the ENTITY order, not the row order: "Huhn 3" has to
	# mean the same animal however the grid happens to be sorted today.
	var ordinals := ordinals_by_id(_zoo_state.entities) if _zoo_state != null else {}
	var base: Array = []
	var row_ordinals: Array = []
	for row in _rows:
		var entity = row["entity"]
		var cfg: Dictionary = _config.get_entity_config(entity.type_id) if _config != null else {}
		var sound_label := ""
		if _zoo_state != null and entity.sound_ref != "":
			sound_label = _zoo_state.sound_bank.get_label(entity.sound_ref)
		var ordinal := int(ordinals.get(entity.id, 1))
		base.append(row_label(entity, ordinal, cfg.get("name", entity.type_id), sound_label))
		row_ordinals.append(ordinal)
	return unique_labels(base, row_ordinals)


func _refresh_row_label(row: Dictionary, fully_capped: bool, name: String) -> void:
	var entity = row["entity"]
	var text := name
	# The name button is ~116px and clips; the tooltip carries the whole thing.
	row["label_button"].tooltip_text = text
	if not entity.in_song:
		text += "  (pausiert)"
	elif fully_capped:
		text += "  (übertönt)"
	if entity.id == _focus_entity_id:
		text = "▸ " + text
	var button: Button = row["label_button"]
	button.text = text
	var root: Control = row["root"]
	root.modulate.a = PARKED_ROW_ALPHA if not entity.in_song else 1.0


func _refresh_legend() -> void:
	var cap: int = _zoo_state.rhythm.voice_cap if _zoo_state != null else 0
	_legend.text = "Blasse Felder: vom Stimmen-Limit übertönt (max. %d gleichzeitig)" % cap


## step -> {entity_id: true} for everyone the voice cap drops.
func _compute_capped() -> Dictionary:
	var capped: Dictionary = {}
	if _zoo_state == null:
		return capped
	for step in _steps():
		var dropped: Dictionary = {}
		for id in _zoo_state.rhythm.capped_out_ids(step):
			dropped[id] = true
		capped[step] = dropped
	return capped


func _update_playhead() -> void:
	var step: int = _zoo_state.rhythm.current_step()
	if step == _last_step:
		return
	_last_step = step
	_playhead.position = Vector2(ROW_LABEL_WIDTH + float(step) * (_cell_width + 4.0), 0.0)
	_playhead.size = Vector2(_cell_width, _grid_area.size.y)


## Which row an animal ended up in after sorting, or -1 if it is not shown.
func row_index_of(entity_id: String) -> int:
	for i in _rows.size():
		if _rows[i]["entity"].id == entity_id:
			return i
	return -1


func _scroll_to_focus() -> void:
	if _focus_entity_id == "" or _scroll == null:
		return
	var index := row_index_of(_focus_entity_id)
	if index >= 0:
		_scroll.scroll_vertical = int(float(index) * (ROW_HEIGHT + 4.0))


## The width the grid divides between the row labels and the cells. Falls back
## to the project's portrait width when there is no viewport, which is the case
## for a detached view in the tests.
func _screen_width() -> float:
	var vp := get_viewport()
	if vp != null:
		return vp.get_visible_rect().size.x
	return float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080))


func _steps() -> int:
	if _zoo_state == null:
		return _RhythmEngine.DEFAULT_STEPS_PER_LOOP
	return _zoo_state.rhythm.effective_steps()


# --- Input ---

func _on_cell_pressed(entity, step: int) -> void:
	entity.beat_pattern = _RhythmEngine.toggle_step(entity.beat_pattern, step)
	# An edit changes who the cap drops, so the whole grid is repainted.
	_refresh_cells()
	# Section 3b: you must hear what you just placed, on this tap and not on
	# the next loop. Turning a step OFF has nothing to preview.
	if _RhythmEngine.plays_on(entity.beat_pattern, step):
		_preview(entity)
	beat_toggled.emit(entity)


func _on_row_label_pressed(entity) -> void:
	entity.in_song = not entity.in_song
	_refresh_cells()
	if entity.in_song:
		_preview(entity)


## Hearing a row is an identity check, not an edit - nothing changes.
func _on_thumb_pressed(entity) -> void:
	_preview(entity)


func _on_mic_pressed(entity) -> void:
	record_requested.emit(entity)


func _preview(entity) -> void:
	if _rhythm_player == null:
		return
	_rhythm_player.preview(entity.id, _RhythmEngine.pitch_scale_from_offset(entity.pitch_offset))
