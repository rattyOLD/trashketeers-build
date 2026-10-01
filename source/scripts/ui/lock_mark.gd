class_name LockMark
extends Control
## Маленький замочек и перечёркивающая линия поверх закрытой кнопки режима.


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := Vector2(size.x - 16.0, 22.0)
	draw_arc(c + Vector2(0, -8), 6.0, PI, TAU, 14, Color("#1a0033"), 7.0, true)
	draw_arc(c + Vector2(0, -8), 6.0, PI, TAU, 14, Color("#d8d0ff"), 3.5, true)
	var body := Rect2(c + Vector2(-9, -8), Vector2(18, 15))
	draw_rect(body.grow(2.5), Color("#1a0033"))
	draw_rect(body, Color("#ffd257"))
	draw_circle(c + Vector2(0, 1), 3.0, Color("#1a0033"))
	draw_line(c + Vector2(0, 1), c + Vector2(0, 5), Color("#1a0033"), 3.0)
	draw_line(Vector2(14.0, size.y - 14.0), Vector2(size.x - 14.0, 14.0), Color(1, 0.35, 0.45, 0.8), 3.0, true)
