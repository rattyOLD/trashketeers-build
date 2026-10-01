class_name VirtualJoystick
extends Control
## Плавающий джойстик: появляется там, где палец коснулся левой части экрана.
## Слушает _input, а не _gui_input, чтобы работать поверх игрового мира при мультитаче;
## правая часть экрана оставлена под кнопки. Мышь работает через emulate_touch_from_mouse.

const BASE_RADIUS_DEFAULT := 110.0
const KNOB_RADIUS_DEFAULT := 46.0
const DEADZONE := 0.12
const ZONE_WIDTH_FRACTION := 0.62
const ZONE_TOP := 170.0

var output := Vector2.ZERO
var BASE_RADIUS := BASE_RADIUS_DEFAULT
var KNOB_RADIUS := KNOB_RADIUS_DEFAULT

var _touch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE


func owns(touch_index: int) -> bool:
	return _touch_index == touch_index


func in_zone(point: Vector2) -> bool:
	return _in_zone(point)


func is_active() -> bool:
	return _touch_index != -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_reset()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.canceled and touch.index == _touch_index:
			_reset()
			return
		if touch.pressed and _in_zone(touch.position) and _touch_index != -1 and touch.index != _touch_index:
			_reset()
		if touch.pressed and _touch_index == -1 and _in_zone(touch.position):
			var scale := float(Controls.get_value("joystick_scale"))
			BASE_RADIUS = BASE_RADIUS_DEFAULT * scale
			KNOB_RADIUS = KNOB_RADIUS_DEFAULT * scale
			_touch_index = touch.index
			_base = _hint_position() if bool(Controls.get_value("joystick_fixed")) else touch.position
			_knob = touch.position
			_update_output()
		elif not touch.pressed and touch.index == _touch_index:
			_reset()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_knob = drag.position
			_update_output()


func _in_zone(point: Vector2) -> bool:
	if point.y <= ZONE_TOP:
		return false
	if bool(Controls.get_value("left_handed")):
		return point.x > size.x * (1.0 - ZONE_WIDTH_FRACTION)
	return point.x < size.x * ZONE_WIDTH_FRACTION


func _hint_position() -> Vector2:
	var x := size.x * (0.76 if bool(Controls.get_value("left_handed")) else 0.24)
	return Vector2(x, size.y - 340.0)


func _update_output() -> void:
	var offset := (_knob - _base).limit_length(BASE_RADIUS)
	_knob = _base + offset
	var strength := offset.length() / BASE_RADIUS
	output = offset.normalized() * inverse_lerp(DEADZONE, 1.0, strength) if strength > DEADZONE else Vector2.ZERO
	queue_redraw()


func _reset() -> void:
	_touch_index = -1
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not is_active():
		var hint := _hint_position()
		draw_arc(hint, BASE_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.1), 4.0)
		draw_circle(hint, KNOB_RADIUS, Color(1, 1, 1, 0.06))
		return
	draw_circle(_base, BASE_RADIUS, Color(0.05, 0.02, 0.1, 0.35))
	draw_arc(_base, BASE_RADIUS, 0.0, TAU, 48, Color(UiStyle.NEON, 0.55), 5.0)
	draw_circle(_knob, KNOB_RADIUS + 4.0, UiStyle.OUTLINE)
	draw_circle(_knob, KNOB_RADIUS, Color(UiStyle.NEON, 0.75))
	draw_circle(_knob + Vector2(-12, -12), KNOB_RADIUS * 0.3, Color(1, 1, 1, 0.35))
