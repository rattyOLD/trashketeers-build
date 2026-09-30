class_name DragScroll
extends ScrollContainer
## Прокрутка пальцем/мышью за любое место списка, включая кнопки внутри: обычный ScrollContainer
## их жест не видит, потому что кнопка забирает нажатие себе. Кнопка под пальцем на время жеста глушится,
## чтобы отпускание после прокрутки не считалось нажатием.

const DRAG_START := 14.0
const FRICTION := 5.0

var _pressed_at := Vector2.ZERO
var _tracking := false
var _dragging := false
var _velocity := 0.0
var _muted: Array[BaseButton] = []


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if button.pressed:
			_tracking = get_global_rect().has_point(button.global_position)
			_dragging = false
			_velocity = 0.0
			_pressed_at = button.global_position
		else:
			_tracking = false
			if _dragging:
				_dragging = false
				call_deferred("_unmute")
	elif event is InputEventMouseMotion and _tracking:
		var motion := event as InputEventMouseMotion
		if not _dragging and absf(motion.global_position.y - _pressed_at.y) > DRAG_START:
			_dragging = true
			_mute_pressed(self)
		if _dragging:
			scroll_vertical -= int(motion.relative.y)
			_velocity = -motion.relative.y * 60.0
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _dragging or absf(_velocity) < 8.0:
		_velocity = 0.0
		return
	scroll_vertical += int(_velocity * delta)
	_velocity = move_toward(_velocity, 0.0, absf(_velocity) * FRICTION * delta + 30.0 * delta)


func _mute_pressed(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var b := child as BaseButton
			var mode := b.get_draw_mode()
			if mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED:
				b.disabled = true
				_muted.append(b)
		_mute_pressed(child)


func _unmute() -> void:
	for b in _muted:
		if is_instance_valid(b):
			b.disabled = false
	_muted.clear()
