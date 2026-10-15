class_name AttackTelegraph
extends RefCounted
## Координаты и радиус совпадают с кругом проверки урона, без перспективного сжатия.

## Недавние круги и вспышки в мировых координатах: по ним герой понимает, что его закрыло, и включает контур.
const COVER_LIMIT := 32
static var _cover: Array[Vector4] = []


## Отметить область, закрывающую персонажей (x, y, радиус, до какого времени в мс).
static func mark_cover(at: Vector2, radius: float, seconds: float) -> void:
	var until := float(Time.get_ticks_msec()) + seconds * 1000.0
	if _cover.size() >= COVER_LIMIT:
		_cover.pop_front()
	_cover.append(Vector4(at.x, at.y, radius, until))


## Тело босса: одна запись на кадр, не вытесняет круги атак.
static var _boss_cover := Vector4.ZERO


static func mark_boss_cover(at: Vector2, radius: float) -> void:
	_boss_cover = Vector4(at.x, at.y, radius, float(Time.get_ticks_msec()) + 150.0)


static func covers(point: Vector2, margin: float) -> bool:
	var now := float(Time.get_ticks_msec())
	if _boss_cover.w >= now and point.distance_squared_to(Vector2(_boss_cover.x, _boss_cover.y)) < _boss_cover.z * _boss_cover.z:
		return true
	var i := _cover.size() - 1
	while i >= 0:
		var c := _cover[i]
		if c.w < now:
			_cover.remove_at(i)
		elif point.distance_squared_to(Vector2(c.x, c.y)) < (c.z + margin) * (c.z + margin):
			return true
		i -= 1
	return false


static func circle(canvas: Node2D, center: Vector2, radius: float, progress: float, tint: Color) -> void:
	var t := clampf(progress, 0.0, 1.0)
	var contrast := bool(SaveService.data.get("contrast_warnings", false))
	if contrast:
		tint = Color(Color("#fff0b8"), tint.a)
	var points := 32 if SaveService.is_fx_lite() else 48
	mark_cover(canvas.get_global_transform() * center, radius, 0.15)
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
