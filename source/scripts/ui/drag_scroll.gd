class_name DragScroll
extends ScrollContainer
signal tapped
## Прокрутка пальцем/мышью за любое место списка, включая кнопки внутри: обычный ScrollContainer
## их жест не видит, потому что кнопка забирает нажатие себе. Кнопка под пальцем на время жеста глушится,
## чтобы отпускание после прокрутки не считалось нажатием.

const DRAG_START := 14.0
const FRICTION := 5.0
static var _gesture_owner: DragScroll

var _pressed_at := Vector2.ZERO
var _tracking := false
var _dragging := false
var _velocity := 0.0
var _muted: Array[BaseButton] = []
var _touch_index := -1
var _last_motion_ms := 0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index < 0 and _begin_gesture(touch.position):
			_touch_index = touch.index
			_tracking = true
			_dragging = false
			_velocity = 0.0
			_pressed_at = touch.position
		elif not touch.pressed and touch.index == _touch_index:
			if _tracking and not _dragging and get_global_rect().has_point(touch.position):
				tapped.emit()
			if Time.get_ticks_msec() - _last_motion_ms > 100:
				_velocity = 0.0
			_touch_index = -1
			_tracking = false
			_release_gesture()
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
				_unmute.call_deferred()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_index or not _tracking:
			return
		if not _dragging and absf(drag.position.y - _pressed_at.y) > DRAG_START:
			_dragging = true
			_mute_pressed(self)
		if _dragging:
			scroll_vertical -= int(drag.relative.y)
			_velocity = -drag.velocity.y if drag.velocity.length_squared() > 0.0 else -drag.relative.y * 60.0
			_velocity = clampf(_velocity, -2600.0, 2600.0)
			_last_motion_ms = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()
		return
	# Touch also produces emulated mouse input; process each gesture once.
	if _touch_index >= 0 or event.device == -1:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if button.pressed:
			_tracking = _begin_gesture(button.global_position)
			_dragging = false
			_velocity = 0.0
			_pressed_at = button.global_position
		else:
			if _tracking and not _dragging and get_global_rect().has_point(button.global_position):
				tapped.emit()
			if Time.get_ticks_msec() - _last_motion_ms > 100:
				_velocity = 0.0
			_tracking = false
			_release_gesture()
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
			_velocity = clampf(-motion.velocity.y if motion.velocity.length_squared() > 0.0 else -motion.relative.y * 60.0, -2600.0, 2600.0)
			_last_motion_ms = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_tracking = false
		_dragging = false
		_touch_index = -1
		_velocity = 0.0
		_release_gesture()
		_unmute()


func _begin_gesture(point: Vector2) -> bool:
	if not get_global_rect().has_point(point):
		return false
	var parent := get_parent()
	while parent != null:
		if parent is Control and (parent as Control).clip_contents and not (parent as Control).get_global_rect().has_point(point):
			return false
		if parent.has_method("is_top_popup") and not bool(parent.call("is_top_popup")):
			return false
		parent = parent.get_parent()
	if is_instance_valid(_gesture_owner) and _gesture_owner != self:
		if not _gesture_owner.is_ancestor_of(self):
			return false
		_gesture_owner._tracking = false
		_gesture_owner._touch_index = -1
	_gesture_owner = self
	return true


func _release_gesture() -> void:
	if _gesture_owner == self:
		_gesture_owner = null


func _exit_tree() -> void:
	_release_gesture()
	_unmute()


func _process(delta: float) -> void:
	if _dragging:
		return
	if absf(_velocity) < 8.0:
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
