extends SceneTree
## Diagnostic: what does the runtime actually resolve for theme fonts?

func _init() -> void:
	print("--- project setting ---")
	print("gui/theme/custom = ", ProjectSettings.get_setting("gui/theme/custom", "<UNSET>"))

	print("--- direct load of theme.tres ---")
	var th = load("res://assets/ui/theme.tres")
	print("loaded: ", th != null)
	if th != null:
		print("has (font,Label): ", th.has_font("font", "Label"))
		print("(font_size,Label): ", th.get_font_size("font_size", "Label"))
		var f = th.get_font("font", "Label")
		print("(font,Label) resource: ", f)
		if f is FontVariation:
			print("  base_font: ", f.base_font)
			print("  coords: ", f.variation_opentype)
			if f.base_font != null:
				print("  base name: ", f.base_font.get_font_name())

	print("--- what a real Label in the tree resolves ---")
	var l := Label.new()
	root.add_child(l)
	var rf = l.get_theme_font("font")
	print("resolved font: ", rf)
	if rf != null:
		print("resolved font name: ", rf.get_font_name())
	print("resolved font_size: ", l.get_theme_font_size("font_size"))
	quit(0)