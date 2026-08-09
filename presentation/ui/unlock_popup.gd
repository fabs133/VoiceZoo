extends PanelContainer
## Brief celebration popup when a new entity type unlocks.

@onready var message_label: Label = $MarginContainer/MessageLabel


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func show_unlock(type_id: String) -> void:
	var cfg = Config.get_entity_config(type_id)
	var name_str: String = cfg.get("name", type_id)
	message_label.text = "Neues Tier freigeschaltet!\n%s" % name_str
	visible = true

	var tween = create_tween()
	# Fade in + scale up
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Hold
	tween.tween_interval(2.0)
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_hide)


func _hide() -> void:
	visible = false
