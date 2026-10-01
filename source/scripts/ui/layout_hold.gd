class_name LayoutHold
extends Control
## Долгое удержание экранной кнопки в бою (около двух секунд) просит открыть правку её положения,
## размера и прозрачности. Событие не перехватывается: обычные нажатия работают как раньше.
## Пока палец держат, вокруг него растёт кольцо, чтобы было понятно, что сейчас откроется правка.

signal requested(id: String)

const HOLD_SEC := 2.0
const RING_FROM := 0.6
const SLOP := 36.0

## id кнопки -> Callable, возвращающий её Control (или null, если кнопки сейчас нет).
var targets: Dictionary = {}

var _index := -1
var _id := ""
var _start := Vector2.ZERO
var _t0 := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 50


func _hit(point: Vector2) -> String:
	for id in targets:
		var control: Control = (targets[id] as Callable).call()
		if control != null and control.is_visible_in_tree() and Rect2(control.get_global_position(), control.size * control.get_global_transform().get_scale()).grow(8.0).has_point(point):
			return str(id)
	return ""


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		_cancel()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _index == -1:
			var id := _hit(touch.position)
			if not id.is_empty():
				_index = touch.index
				_id = id
				_start = touch.position
				_t0 = Time.get_ticks_msec()
		elif not touch.pressed and touch.index == _index:
			_cancel()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _index and drag.position.distance_to(_start) > SLOP:
			_cancel()


func _cancel() -> void:
	if _index != -1:
		_index = -1
		queue_redraw()


func _process(_delta: float) -> void:
	if _index == -1:
		return
	if float(Time.get_ticks_msec() - _t0) / 1000.0 >= HOLD_SEC:
		var id := _id
		_index = -1
		Platform.haptic("heavy")
		requested.emit(id)
	queue_redraw()


func _draw() -> void:
	if _index == -1:
		return
	var t := float(Time.get_ticks_msec() - _t0) / 1000.0
	if t < RING_FROM:
		return
	var progress := clampf((t - RING_FROM) / (HOLD_SEC - RING_FROM), 0.0, 1.0)
	draw_arc(_start, 70.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, UiStyle.GOLD, 8.0, true)
	draw_string(ThemeDB.fallback_font, _start + Vector2(-90, -90), "Держи, откроется правка кнопки", HORIZONTAL_ALIGNMENT_CENTER, 180, 20, Color(1, 1, 1, 0.9))
