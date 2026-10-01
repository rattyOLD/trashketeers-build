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
	if _index == -1 or not targets.has(_id):
		return
	var t := float(Time.get_ticks_msec() - _t0) / 1000.0
	if t < RING_FROM:
		return
	var control: Control = (targets[_id] as Callable).call()
	if control == null:
		return
	var rect := Rect2(control.get_global_position(), control.size * control.get_global_transform().get_scale()).grow(8.0)
	var progress := clampf((t - RING_FROM) / (HOLD_SEC - RING_FROM), 0.0, 1.0)
	var ratio := maxf(rect.size.x, rect.size.y) / maxf(minf(rect.size.x, rect.size.y), 1.0)
	if ratio < 1.5:
		var radius := maxf(rect.size.x, rect.size.y) * 0.5
		draw_arc(rect.get_center(), radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, UiStyle.GOLD, 8.0, true)
	else:
		var points := PackedVector2Array()
		var top := rect.position.x + rect.size.x * 0.5
		var corners := [Vector2(top, rect.position.y), Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position, Vector2(top, rect.position.y)]
		var lengths: Array[float] = []
		var total := 0.0
		for i in corners.size() - 1:
			var seg := (corners[i] as Vector2).distance_to(corners[i + 1])
			lengths.append(seg)
			total += seg
		var left := total * progress
		points.append(corners[0])
		for i in lengths.size():
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[i + 1]
			if left >= lengths[i]:
				points.append(b)
				left -= lengths[i]
			else:
				points.append(a.lerp(b, left / maxf(lengths[i], 1.0)))
				break
		if points.size() > 1:
			draw_polyline(points, UiStyle.GOLD, 8.0, true)
	var font := ThemeDB.fallback_font
	var caption := "Держи, откроется правка"
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
	var x := clampf(rect.get_center().x - width * 0.5, 8.0, maxf(size.x - width - 8.0, 8.0))
	var y := rect.position.y - 12.0 if rect.position.y > 40.0 else rect.end.y + 28.0
	draw_string_outline(font, Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, 6, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 1, 0.95))
