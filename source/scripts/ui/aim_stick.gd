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
## Пока игрок ни разу не стрелял стиком, справа мерцает подсказка «зажми и тяни».
var _hint := false
var _hint_time := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_hint = (Platform.is_touch() or force_touch) and not bool(SaveService.data.get("aim_learned", false))
	set_process(_hint)


func _process(delta: float) -> void:
	_hint_time += delta
	queue_redraw()


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
			if _hint:
				_hint = false
				set_process(false)
				SaveService.set_flag("aim_learned", true)
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
		if _hint:
			_draw_hint()
		return
	_batch.circle(_base, BASE_RADIUS, Color(0.1, 0.02, 0.02, 0.3))
	_batch.arc(_base, BASE_RADIUS, 0.0, TAU, 48, Color(ACCENT, 0.6), 5.0)
	_batch.circle(_knob, KNOB_RADIUS + 4.0, UiStyle.OUTLINE)
	_batch.circle(_knob, KNOB_RADIUS, Color(ACCENT, 0.8))
	_batch.circle(_knob + Vector2(-10, -10), KNOB_RADIUS * 0.3, Color(1, 1, 1, 0.35))
	_batch.flush(self)


func _draw_hint() -> void:
	var left := bool(Controls.get_value("left_handed"))
	var at := Vector2(size.x * (0.4 if left else 0.6), size.y * 0.66)
	var pulse := 0.5 + 0.5 * sin(_hint_time * 4.0)
	var drift := Vector2.from_angle(-0.5) * (BASE_RADIUS * 0.55) * fmod(_hint_time * 0.8, 1.0)
	_batch.arc(at, BASE_RADIUS, 0.0, TAU, 48, Color(ACCENT, 0.25 + 0.3 * pulse), 4.0)
	_batch.circle(at + drift, KNOB_RADIUS * 0.8, Color(ACCENT, 0.35 + 0.25 * pulse))
	_batch.flush(self)
	var font := ThemeDB.fallback_font
	var caption := "ЗАЖМИ И ТЯНИ — ОГОНЬ"
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x
	var pos := Vector2(at.x - width * 0.5, at.y + BASE_RADIUS + 30.0)
	draw_string_outline(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, 6, Color(0, 0, 0, 0.8))
	draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(1, 1, 1, 0.75 + 0.25 * pulse))
