class_name GroundDetail
extends Node2D
## Мелочь на земле, чтобы пол не читался одной плиткой (как в Hades и Brawl Stars): трещины, масляные пятна,
## лужи с неоновым отблеском, люки, следы краски (Свалка); опавшие лепестки, камешки, тень от клумб (Банк).
## Рисуется один раз (без _process); узел — на четверть карты, чтобы экранная отбраковка отсекала невидимое.

var bank := false
var _items: Array = []
var _rng := RandomNumberGenerator.new()


## spots — точки, где можно рисовать (свободная земля); seed — повторяемость раскладки.
func build(spots: Array[Vector2], seed_value: int, is_bank: bool) -> void:
	bank = is_bank
	_rng.seed = seed_value
	for p in spots:
		# Свалка: только тихие детали (трещина, масляное пятно, редкий люк) — без пёстрых болтов и краски,
		# чтобы пол не рябил под врагами и пулями.
		var kind: int = _rng.randi() % 4 if is_bank else int([0, 0, 1, 1, 3][_rng.randi() % 5])
		_items.append([p, kind, _rng.randf() * TAU, _rng.randf_range(0.7, 1.3)])
	queue_redraw()


func _draw() -> void:
	for item: Array in _items:
		var p: Vector2 = item[0]
		var kind: int = item[1]
		var rot: float = item[2]
		var k: float = item[3]
		if bank:
			_draw_bank(p, kind, rot, k)
		else:
			_draw_junk(p, kind, rot, k)
	draw_set_transform(Vector2.ZERO)


func _draw_junk(p: Vector2, kind: int, rot: float, k: float) -> void:
	match kind:
		0:
			# Трещина: ломаная с ответвлением.
			var dir := Vector2.from_angle(rot)
			var a := p
			for i in 5:
				var b := a + dir.rotated(_rng.randf_range(-0.6, 0.6)) * 22.0 * k
				draw_line(a, b, Color(0.02, 0.0, 0.05, 0.55), 2.2)
				if i == 2:
					draw_line(b, b + dir.rotated(1.2) * 18.0 * k, Color(0.02, 0.0, 0.05, 0.45), 1.6)
				a = b
		1:
			# Масляное пятно с радужной кромкой.
			draw_set_transform(p, rot, Vector2(1.0, 0.55) * k)
			draw_circle(Vector2.ZERO, 34.0, Color(0.02, 0.0, 0.06, 0.45))
			draw_arc(Vector2.ZERO, 30.0, 0.3, 2.4, 16, Color(0.6, 0.3, 1.0, 0.18), 3.0)
			draw_arc(Vector2.ZERO, 26.0, 3.0, 4.6, 16, Color(0.2, 0.9, 0.8, 0.14), 3.0)
			draw_set_transform(Vector2.ZERO)
		2:
			# Лужа с отблеском неона.
			draw_set_transform(p, 0.0, Vector2(1.0, 0.45) * k)
			draw_circle(Vector2.ZERO, 46.0, Color(0.06, 0.04, 0.14, 0.55))
			draw_circle(Vector2(-10, -6), 30.0, Color(0.95, 0.3, 0.75, 0.10))
			draw_line(Vector2(-22, -10), Vector2(16, -14), Color(0.6, 0.95, 1.0, 0.35), 2.0)
			draw_set_transform(Vector2.ZERO)
		3:
			# Люк.
			draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 24.0, Color(0.04, 0.03, 0.06, 0.85))
			draw_circle(Vector2.ZERO, 20.0, Color(0.22, 0.2, 0.26, 0.9))
			draw_set_transform(Vector2.ZERO)
			for i in 3:
				draw_line(p + Vector2(-13, -4 + i * 4), p + Vector2(13, -4 + i * 4), Color(0.05, 0.04, 0.08, 0.8), 1.6)
		4:
			# След краски из баллончика.
			var c := [Color(1.0, 0.3, 0.7, 0.32), Color(0.3, 1.0, 0.9, 0.3), Color(1.0, 0.8, 0.2, 0.3)][int(k * 10.0) % 3] as Color
			var dir := Vector2.from_angle(rot)
			draw_line(p - dir * 30.0 * k, p + dir * 30.0 * k, c, 7.0)
			draw_circle(p + dir * 30.0 * k, 5.0, c)
		_:
			# Россыпь болтов и стекла.
			for i in 6:
				var q := p + Vector2(_rng.randf_range(-22, 22), _rng.randf_range(-12, 12))
				draw_circle(q, 2.0, Color(0.7, 0.75, 0.85, 0.45) if i % 2 == 0 else Color(0.3, 0.9, 0.6, 0.4))


func _draw_bank(p: Vector2, kind: int, rot: float, k: float) -> void:
	match kind:
		0:
			# Лепестки.
			for i in 7:
				var q := p + Vector2.from_angle(rot + i) * _rng.randf_range(4.0, 26.0) * k
				draw_circle(q, 3.0, Color(1.0, 0.65, 0.8, 0.75) if i % 2 == 0 else Color(1.0, 0.95, 0.85, 0.7))
		1:
			# Камешки.
			for i in 4:
				var q := p + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-8, 8))
				draw_circle(q + Vector2(0, 2), 4.0, Color(0, 0, 0, 0.2))
				draw_circle(q, 4.0, Color(0.85, 0.82, 0.76, 0.9))
		2:
			# Пятно сочной травы (тёмнее и светлее газона).
			draw_set_transform(p, rot, Vector2(1.0, 0.6) * k)
			draw_circle(Vector2.ZERO, 40.0, Color(0.1, 0.35, 0.1, 0.16))
			draw_circle(Vector2(10, -4), 22.0, Color(0.6, 0.9, 0.4, 0.12))
			draw_set_transform(Vector2.ZERO)
		_:
			# Монетка в траве — у свиней деньги валяются.
			draw_circle(p + Vector2(0, 1), 5.0, Color(0, 0, 0, 0.25))
			draw_circle(p, 5.0, Color(1.0, 0.82, 0.3, 0.9))
			draw_circle(p + Vector2(-1.5, -1.5), 1.6, Color(1, 1, 1, 0.8))
