class_name VirtualJoystick
extends Control
## Плавающий джойстик: появляется там, где палец коснулся левой части экрана.
## Слушает _input, а не _gui_input, чтобы работать поверх игрового мира при мультитаче;
## правая часть экрана оставлена под кнопки. Мышь работает через emulate_touch_from_mouse.

const BASE_RADIUS_DEFAULT := 110.0
const KNOB_RADIUS_DEFAULT := 46.0
const DEADZONE := 0.12
const ZONE_WIDTH_FRACTION := 0.48
const ZONE_TOP := 170.0

var output := Vector2.ZERO
var BASE_RADIUS := BASE_RADIUS_DEFAULT
var KNOB_RADIUS := KNOB_RADIUS_DEFAULT

var _touch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var _batch := PolyBatch.new()
## Точка поверх кнопки интерфейса (навык, рывок, слоты) — не наша: стик можно сдвинуть к кнопкам.
var blocker: Callable


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE


func owns(touch_index: int) -> bool:
	return _touch_index == touch_index


func in_zone(point: Vector2) -> bool:
	return _in_zone(get_global_transform().affine_inverse() * point)


func is_active() -> bool:
	return _touch_index != -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_reset()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var point := get_global_transform().affine_inverse() * touch.position
		if touch.canceled and touch.index == _touch_index:
			_reset()
			return
		if touch.pressed and _in_zone(point) and _touch_index != -1 and touch.index != _touch_index:
			_reset()
		if touch.pressed and _touch_index == -1 and _in_zone(point):
			var scale := float(Controls.get_value("joystick_scale")) * float(Controls.element("move")["s"])
			BASE_RADIUS = BASE_RADIUS_DEFAULT * scale
			KNOB_RADIUS = KNOB_RADIUS_DEFAULT * scale
			_touch_index = touch.index
			_base = _hint_position() if bool(Controls.get_value("joystick_fixed")) else point
			_knob = point
			_update_output()
		elif not touch.pressed and touch.index == _touch_index:
			_reset()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_knob = get_global_transform().affine_inverse() * drag.position
			_update_output()


func _in_zone(point: Vector2) -> bool:
	if point.y <= ZONE_TOP:
		return false
	if blocker.is_valid() and bool(blocker.call(get_global_transform() * point)):
		return false
	return Controls.touch_is_move(point, size)


## «Дом» джойстика — двигается в редакторе управления.
func _hint_position() -> Vector2:
	return Controls.stick_home("move", size)


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
		var hint_scale := float(Controls.get_value("joystick_scale")) * float(Controls.element("move")["s"])
		BASE_RADIUS = BASE_RADIUS_DEFAULT * hint_scale
		KNOB_RADIUS = KNOB_RADIUS_DEFAULT * hint_scale
		var hint := _hint_position()
		_batch.arc(hint, BASE_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.1), 4.0)
		_batch.circle(hint, KNOB_RADIUS, Color(1, 1, 1, 0.06))
		_batch.flush(self)
		return
	_batch.circle(_base, BASE_RADIUS, Color(0.05, 0.02, 0.1, 0.35))
	_batch.arc(_base, BASE_RADIUS, 0.0, TAU, 48, Color(UiStyle.NEON, 0.55), 5.0)
	_batch.circle(_knob, KNOB_RADIUS + 4.0, UiStyle.OUTLINE)
	_batch.circle(_knob, KNOB_RADIUS, Color(UiStyle.NEON, 0.75))
	_batch.circle(_knob + Vector2(-12, -12), KNOB_RADIUS * 0.3, Color(1, 1, 1, 0.35))
	_batch.flush(self)
