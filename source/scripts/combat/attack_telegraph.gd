class_name AttackTelegraph
extends RefCounted
## Координаты и радиус совпадают с кругом проверки урона, без перспективного сжатия.

static func circle(canvas: Node2D, center: Vector2, radius: float, progress: float, tint: Color) -> void:
	var t := clampf(progress, 0.0, 1.0)
	var contrast := bool(SaveService.data.get("contrast_warnings", false))
	if contrast:
		tint = Color(Color("#fff0b8"), tint.a)
	var points := 32 if SaveService.is_fx_lite() else 48
	canvas.draw_circle(center, radius, Color(tint, (0.09 + 0.12 * t) * tint.a))
	canvas.draw_arc(center, radius, 0.0, TAU, points, Color(0.08, 0.03, 0.02, 0.9 * tint.a), 7.0, true)
	canvas.draw_arc(center, radius, 0.0, TAU, points, Color(tint, 0.9 * tint.a), 3.0, true)
	if contrast:
		# Метки формы читаются без различения красного и зелёного, радиус не меняется.
		for i in 8:
			var dir := Vector2.from_angle(TAU * i / 8.0)
			canvas.draw_line(center + dir * radius * 0.78, center + dir * radius * 0.93, Color("#17100b"), 6.0)
			canvas.draw_line(center + dir * radius * 0.78, center + dir * radius * 0.93, tint, 2.5)
	if t > 0.0:
		canvas.draw_arc(center, radius * 0.88, -PI / 2.0, -PI / 2.0 + TAU * t, points, Color(1.0, 0.88, 0.54, tint.a), 3.0, true)


static func ink(tint: Color) -> Color:
	return Color(Color("#fff0b8"), tint.a) if bool(SaveService.data.get("contrast_warnings", false)) else tint
