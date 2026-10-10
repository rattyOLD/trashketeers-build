class_name AttackTelegraph
extends RefCounted
## Координаты и радиус совпадают с кругом проверки урона, без перспективного сжатия.

static func circle(canvas: Node2D, center: Vector2, radius: float, progress: float, tint: Color) -> void:
	var t := clampf(progress, 0.0, 1.0)
	var points := 32 if SaveService.is_fx_lite() else 48
	canvas.draw_circle(center, radius, Color(tint, (0.09 + 0.12 * t) * tint.a))
	canvas.draw_arc(center, radius, 0.0, TAU, points, Color(0.08, 0.03, 0.02, 0.9 * tint.a), 7.0, true)
	canvas.draw_arc(center, radius, 0.0, TAU, points, Color(tint, 0.9 * tint.a), 3.0, true)
	if t > 0.0:
		canvas.draw_arc(center, radius * 0.88, -PI / 2.0, -PI / 2.0 + TAU * t, points, Color(1.0, 0.88, 0.54, tint.a), 3.0, true)
