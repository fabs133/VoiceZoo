extends SceneTree
## Builds assets/ui/theme.tres from the design tokens in data/ui_theme.json.
## Run: godot --headless --script tools/build_theme.gd   (after --import if the
## font is new). Rerun whenever tokens change - e.g. the final wedding accent.

func _init() -> void:
	var file = FileAccess.open("res://data/ui_theme.json", FileAccess.READ)
	if file == null:
		push_error("ui_theme.json not found")
		quit(1)
		return
	var tokens: Dictionary = JSON.parse_string(file.get_as_text())
	if tokens == null or tokens.is_empty():
		push_error("ui_theme.json invalid")
		quit(1)
		return

	var c := {}
	for key in tokens["colors"]:
		c[key] = Color(tokens["colors"][key])
	var radius: Dictionary = tokens["radius"]
	var border: Dictionary = tokens["border"]
	var pad := float(tokens["panel_padding"])

	var theme := Theme.new()

	# --- Font ---
	var base_font = load(tokens["font_path"])
	if base_font == null:
		push_error("font not imported yet - run --headless --import first")
		quit(1)
		return
	var font: Font = base_font
	if tokens.has("font_weight"):
		# Baloo 2 is a variable font (wght 400-800); pin an explicit weight
		var fv := FontVariation.new()
		fv.base_font = base_font
		# Numeric OpenType tag, not a string key - string keys are not reliably
		# honored on every load path (editor serializes tags as ints).
		var ts = TextServerManager.get_primary_interface()
		fv.variation_opentype = { ts.name_to_tag("wght"): int(tokens["font_weight"]) }
		font = fv

	# Emoji fallback. Baloo 2 covers no emoji, and a web export has no system
	# font to borrow one from the way the desktop build does, so every emoji in
	# the UI rendered as a tofu box on the deployed game while looking fine in
	# the editor. The fallback is a ~2 KB subset containing only the glyphs the
	# sources actually use - see tools/build_emoji_font.py, which rebuilds it and
	# rediscovers the codepoints.
	var emoji_path: String = str(tokens.get("emoji_font_path", ""))
	if emoji_path != "":
		var emoji_font = load(emoji_path)
		if emoji_font == null:
			push_error("emoji font not imported yet - run --headless --import first")
			quit(1)
			return
		if font is FontVariation:
			font.fallbacks = [emoji_font]
		else:
			# Never write fallbacks onto the imported FontFile itself - that
			# resource is shared, and the change would leak into every other
			# user of it. Wrap it instead.
			var wrapper := FontVariation.new()
			wrapper.base_font = font
			wrapper.fallbacks = [emoji_font]
			font = wrapper

	theme.default_font = font
	theme.default_font_size = int(tokens["font_size_default"])
	# Explicit per-type items: the engine default theme defines ("font", type)
	# and ("font_size", type) for every control, and explicit items beat any
	# theme's default_font fallback. Our theme is first in the chain, so
	# explicit entries here win unconditionally.
	for type in ["Label", "Button", "LineEdit", "OptionButton", "MenuButton", "CheckBox", "PopupMenu", "TooltipLabel"]:
		theme.set_font("font", type, font)
		theme.set_font_size("font_size", type, int(tokens["font_size_default"]))

	# --- Panels ---
	var panel := _box(c["panel"], c["panel_border"], int(border["panel"]), int(radius["panel"]), pad)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var popup := _box(c["panel"], c["panel_border"], int(border["panel"]), int(radius["popup"]), pad)
	theme.set_stylebox("panel", "PopupPanel", popup)
	theme.set_stylebox("panel", "PopupMenu", popup)

	# --- Labels ---
	theme.set_color("font_color", "Label", c["text_primary"])
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", int(tokens["font_size_title"]))
	theme.set_color("font_color", "TitleLabel", c["text_primary"])
	theme.set_type_variation("SubtleLabel", "Label")
	theme.set_color("font_color", "SubtleLabel", c["text_secondary"])

	# --- Buttons: default = positive/buy (green) ---
	_style_button(theme, "Button", c["positive"], c["disabled"], c["text_secondary"], border, radius)
	# Accent variation (pink) for upgrade/celebration actions
	theme.set_type_variation("AccentButton", "Button")
	_style_button(theme, "AccentButton", c["accent"], c["disabled"], c["text_secondary"], border, radius)
	# Ghost variation (neutral) for close/secondary actions
	theme.set_type_variation("GhostButton", "Button")
	_style_button(theme, "GhostButton", c["panel"].darkened(0.06), c["disabled"], c["text_secondary"], border, radius)
	theme.set_color("font_color", "GhostButton", c["text_primary"])
	theme.set_color("font_hover_color", "GhostButton", c["text_primary"])
	theme.set_color("font_pressed_color", "GhostButton", c["text_primary"])

	# --- LineEdit (keeper name input) ---
	var input := _box(Color.WHITE, c["panel_border"], int(border["button"]), int(radius["button"]), 8.0)
	theme.set_stylebox("normal", "LineEdit", input)
	theme.set_color("font_color", "LineEdit", c["text_primary"])

	DirAccess.make_dir_recursive_absolute("res://assets/ui")
	var err = ResourceSaver.save(theme, "res://assets/ui/theme.tres")
	if err == OK:
		print("theme.tres written")
		quit(0)
	else:
		push_error("save failed: %s" % err)
		quit(1)


func _box(bg: Color, border_color: Color, border_w: int, corner: int, pad: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border_color
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(corner)
	box.set_content_margin_all(pad)
	return box


func _style_button(theme: Theme, type: String, base: Color, disabled: Color, disabled_text: Color, border: Dictionary, radius: Dictionary) -> void:
	var r := int(radius["button"])
	var bw := int(border["button"])
	var edge := base.darkened(0.35)
	theme.set_stylebox("normal", type, _box(base, edge, bw, r, 10.0))
	theme.set_stylebox("hover", type, _box(base.lightened(0.07), edge, bw, r, 10.0))
	theme.set_stylebox("pressed", type, _box(base.darkened(0.14), edge, bw, r, 10.0))
	theme.set_stylebox("disabled", type, _box(disabled, disabled.darkened(0.2), bw, r, 10.0))
	theme.set_color("font_color", type, Color.WHITE)
	theme.set_color("font_hover_color", type, Color.WHITE)
	theme.set_color("font_pressed_color", type, Color.WHITE)
	theme.set_color("font_disabled_color", type, disabled_text)