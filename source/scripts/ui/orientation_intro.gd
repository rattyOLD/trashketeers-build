class_name OrientationIntro
extends CanvasLayer

const SHOW_SECONDS := 1.8

var _cover: Control


class PhoneIcon:
	extends Control
	var _style := UiStyle.box(UiStyle.PANEL, UiStyle.GOLD, 4, 14)
	var angle := 0.0:
		set(value):
			angle = value
			queue_redraw()

	func _draw() -> void:
		draw_arc(size * 0.5, 96.0, -PI * 0.75, PI * 0.15, 40, Color(UiStyle.GOLD, 0.4), 3.0, true)
		draw_set_transform(size * 0.5, angle)
		draw_style_box(_style, Rect2(-38, -64, 76, 128))
		draw_line(Vector2(-12, -52), Vector2(12, -52), UiStyle.GOLD, 4.0, true)
		draw_circle(Vector2(0, 50), 4.0, UiStyle.GOLD, true, -1.0, true)


func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = Control.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	var shade := ColorRect.new()
	shade.color = Color("#0d1116")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	var phone_center := CenterContainer.new()
	phone_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(phone_center)
	var phone := PhoneIcon.new()
	phone.custom_minimum_size = Vector2(210, 210)
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone_center.add_child(phone)
	var title := UiStyle.label("ИГРАЕМ ГОРИЗОНТАЛЬНО", 40, UiStyle.TEXT, 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := UiStyle.label("Держи телефон горизонтально для удобного управления." if Platform.is_native_app else "Игра рассчитана на горизонтальный экран.", 24, UiStyle.TEXT_DIM, 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var turn := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	turn.tween_interval(0.25)
	turn.tween_property(phone, "angle", PI * 0.5, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	fade.tween_interval(SHOW_SECONDS)
	fade.tween_property(_cover, "modulate:a", 0.0, 0.25)
	fade.tween_callback(queue_free)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
