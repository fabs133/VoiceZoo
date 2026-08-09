extends Camera2D
## Touch-friendly camera: drag to pan, pinch to zoom, clamped to map bounds.

@export var drag_sensitivity: float = 1.0
@export var zoom_speed: float = 0.1
@export var zoom_min: Vector2 = Vector2(0.5, 0.5)
@export var zoom_max: Vector2 = Vector2(2.0, 2.0)
@export var bounds_padding: float = 64.0
@export var smooth_speed: float = 10.0

var _target_position: Vector2
var _target_zoom: Vector2
var _dragging: bool = false
var _touch_points: Dictionary = {}  # finger index → position
var _nudge_active: bool = false
var _nudge_tween: Tween

const NudgePolicyScript = preload("res://presentation/camera_nudge_policy.gd")
var _nudge_policy = NudgePolicyScript.new()


func _ready() -> void:
	_target_position = position
	_target_zoom = zoom


func _process(delta: float) -> void:
	position = position.lerp(_target_position, smooth_speed * delta)
	zoom = zoom.lerp(_target_zoom, smooth_speed * delta)
	_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	# Touch drag
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
		else:
			_touch_points.erase(event.index)

	elif event is InputEventScreenDrag:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1:
			_on_user_camera_input()
			# Single finger — pan
			_target_position -= event.relative / zoom * drag_sensitivity
		elif _touch_points.size() == 2:
			_on_user_camera_input()
			# Two fingers — pinch zoom
			_handle_pinch(event)

	# Mouse fallback (desktop/browser testing)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = (_target_zoom + Vector2(zoom_speed, zoom_speed)).clamp(zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = (_target_zoom - Vector2(zoom_speed, zoom_speed)).clamp(zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed

	elif event is InputEventMouseMotion and _dragging:
		_on_user_camera_input()
		_target_position -= event.relative / zoom * drag_sensitivity


var _last_pinch_distance: float = 0.0

func _handle_pinch(event: InputEventScreenDrag) -> void:
	var points = _touch_points.values()
	if points.size() < 2:
		return
	var current_distance = points[0].distance_to(points[1])
	if _last_pinch_distance > 0.0:
		var zoom_delta = (current_distance - _last_pinch_distance) * zoom_speed * 0.01
		_target_zoom = (_target_zoom + Vector2(zoom_delta, zoom_delta)).clamp(zoom_min, zoom_max)
	_last_pinch_distance = current_distance


func set_map_bounds(map_rect: Rect2) -> void:
	limit_left = int(map_rect.position.x - bounds_padding)
	limit_top = int(map_rect.position.y - bounds_padding)
	limit_right = int(map_rect.end.x + bounds_padding)
	limit_bottom = int(map_rect.end.y + bounds_padding)


func nudge_to(world_pos: Vector2, duration: float = 2.0) -> void:
	# Only nudge if target is far from current view center
	if position.distance_to(world_pos) < 200.0:
		return
	if _nudge_active:
		return
	if not _nudge_policy.try_nudge(_now_seconds()):
		return

	_nudge_active = true
	var return_pos = _target_position

	if _nudge_tween and _nudge_tween.is_valid():
		_nudge_tween.kill()
	_nudge_tween = create_tween()
	_nudge_tween.tween_property(self, "_target_position", world_pos, duration * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_nudge_tween.tween_interval(duration * 0.4)
	_nudge_tween.tween_property(self, "_target_position", return_pos, duration * 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_nudge_tween.tween_callback(func(): _nudge_active = false)


func _on_user_camera_input() -> void:
	_nudge_policy.record_pan(_now_seconds())
	# User takes over: cancel any running nudge instead of fighting the input
	# (and instead of snapping back to the pre-nudge position afterwards).
	if _nudge_active:
		_cancel_nudge()


func _cancel_nudge() -> void:
	if _nudge_tween and _nudge_tween.is_valid():
		_nudge_tween.kill()
	_nudge_active = false


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _clamp_position() -> void:
	_target_position.x = clamp(_target_position.x, limit_left, limit_right)
	_target_position.y = clamp(_target_position.y, limit_top, limit_bottom)
