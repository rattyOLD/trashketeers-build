class_name AimStick
extends Control
## Правый стик стрельбы: палец зажат на свободной правой части экрана — герой стреляет туда, куда тянут палец.
## Слушает _unhandled_input: касания кнопок (навык, рывок, слоты, пауза) забирает интерфейс, сюда приходят только
## касания пустого места. Отпустил палец — стрельба прекращается.

const BASE_RADIUS := 96.0
const KNOB_RADIUS := 40.0
## Палец почти не сдвинулся — стреляем в последнем направлении (или туда, куда смотрит герой).
const DEADZONE := 14.0
const ZONE_WIDTH_FRACTION := 0.5
const ZONE_TOP := 150.0
const ACCENT := Color("#ff6a3d")

var direction := Vector2.ZERO
## Тестовые сцены без сенсорного экрана включают стик вручную.
static var force_touch := false

var _touch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var _batch := PolyBatch.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE


func is_active() -> bool:
	return _touch_index != -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_reset()


func _unhandled_input(event: InputEvent) -> void:
	if not (Platform.is_touch() or force_touch) or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var point := get_global_transform().affine_inverse() * touch.position
		if touch.index == _touch_index and (not touch.pressed or touch.canceled):
			_reset()
		elif touch.pressed and _touch_index == -1 and _in_zone(point):
			_touch_index = touch.index
			_base = point
			_knob = point
			direction = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_knob = get_global_transform().affine_inverse() * drag.position
			var offset := _knob - _base
			if offset.length() > BASE_RADIUS:
				# База едет за пальцем: можно развернуть прицел, не отрывая палец от экрана.
				_base = _knob - offset.limit_length(BASE_RADIUS)
				offset = _knob - _base
			if offset.length() > DEADZONE:
				direction = offset.normalized()
			queue_redraw()
			get_viewport().set_input_as_handled()


func _in_zone(point: Vector2) -> bool:
	if point.y <= ZONE_TOP:
		return false
	if bool(Controls.get_value("left_handed")):
		return point.x < size.x * ZONE_WIDTH_FRACTION
	return point.x > size.x * (1.0 - ZONE_WIDTH_FRACTION)


func _reset() -> void:
	_touch_index = -1
	direction = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not is_active():
		return
	_batch.circle(_base, BASE_RADIUS, Color(0.1, 0.02, 0.02, 0.3))
	_batch.arc(_base, BASE_RADIUS, 0.0, TAU, 48, Color(ACCENT, 0.6), 5.0)
	_batch.circle(_knob, KNOB_RADIUS + 4.0, UiStyle.OUTLINE)
	_batch.circle(_knob, KNOB_RADIUS, Color(ACCENT, 0.8))
	_batch.circle(_knob + Vector2(-10, -10), KNOB_RADIUS * 0.3, Color(1, 1, 1, 0.35))
	_batch.flush(self)
