class_name ArenaDecor
extends RefCounted
## Плоский декор арен (слой декалей, под персонажами): помост босса, ворота спавна, бордюры
## зон, пятна масла, лужи, парящие решётки. Всё рисуется один раз (или только на экране),
## без ярких точек и «светящихся кнопок» на полу — чтобы декор не выглядел интерактивным.
## Заливки идут через общий PolyBatch: один draw call на узел вместо вызова на каждую фигуру.

static var _batch := PolyBatch.new()


## Помост босса. junkyard — стальная сцена с жёлто-чёрной окантовкой, передней гранью-ступенью
## и красной неоновой полосой у задника; bank — красная ковровая дорожка с золотыми кантами
## и ступенями из белого мрамора (сами плиты — тайлы пола).
class BossStage:
	extends Node2D
	var rect := Rect2()
	var style := "junkyard"
	var _time := 0.0

	func _ready() -> void:
		set_process(style == "junkyard")

	func _process(delta: float) -> void:
		_time += delta
		if int(_time * 8.0) != int((_time - delta) * 8.0):
			queue_redraw()

	func _draw() -> void:
		if style == "bank":
			_draw_bank()
		else:
			_draw_junkyard()

	func _draw_junkyard() -> void:
		var b := ArenaDecor._batch
		var r := rect
		b.rect(Rect2(r.position + Vector2(0, r.size.y), Vector2(r.size.x, 26)), Color("#12131c"))
		b.rect(Rect2(r.position + Vector2(0, r.size.y), Vector2(r.size.x, 4)), Color("#3a3d56"))
		b.rect(r, Color("#262a3c"))
		var step := 64.0
		var x := r.position.x + step
		while x < r.end.x:
			b.line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("#1a1c2a"), 3.0)
			x += step
		var y := r.position.y + step
		while y < r.end.y:
			b.line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("#1a1c2a"), 3.0)
			y += step
		for py in range(int(r.position.y) + 12, int(r.end.y), 64):
			for px in range(int(r.position.x) + 12, int(r.end.x), 64):
				b.circle(Vector2(px, py), 2.5, Color("#4a4e68"))
		_hazard(b, Rect2(r.position, Vector2(r.size.x, 14)))
		_hazard(b, Rect2(Vector2(r.position.x, r.end.y - 14), Vector2(r.size.x, 14)))
		_hazard(b, Rect2(r.position, Vector2(14, r.size.y)))
		_hazard(b, Rect2(Vector2(r.end.x - 14, r.position.y), Vector2(14, r.size.y)))
		var pulse := 0.55 + 0.25 * sin(_time * 3.0)
		b.rect(Rect2(r.position + Vector2(40, 22), Vector2(r.size.x - 80, 6)), Color(1.0, 0.18, 0.3, pulse))
		var cx := r.get_center().x
		for k in 3:
			var w := 220.0 - k * 36.0
			var sy := r.end.y + 4.0 + k * 8.0
			b.rect(Rect2(cx - w * 0.5, sy, w, 8), Color("#2f3348").darkened(k * 0.15))
		b.flush(self)

	func _hazard(b: PolyBatch, r: Rect2) -> void:
		b.rect(r, Color("#1a1a1a"))
		var stripe := 22.0
		var horizontal := r.size.x >= r.size.y
		var length := r.size.x if horizontal else r.size.y
		var t := 0.0
		while t < length:
			var poly: PackedVector2Array
			if horizontal:
				var x0 := r.position.x + t
				poly = PackedVector2Array([Vector2(x0, r.end.y), Vector2(x0 + stripe * 0.5, r.position.y), Vector2(minf(x0 + stripe, r.end.x), r.position.y), Vector2(minf(x0 + stripe * 0.5, r.end.x), r.end.y)])
			else:
				var y0 := r.position.y + t
				poly = PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0 + stripe * 0.5), Vector2(r.end.x, minf(y0 + stripe, r.end.y)), Vector2(r.position.x, minf(y0 + stripe * 0.5, r.end.y))])
			b.polygon(poly, Color("#e8b41a"))
			t += stripe * 2.0

	func _draw_bank() -> void:
		var r := rect
		var cx := r.get_center().x
		var carpet := Rect2(cx - 90, r.position.y + 30, 180, r.size.y + 150)
		draw_rect(carpet.grow(8), Color("#b8862e"))
		draw_rect(carpet, Color("#b3122e"))
		draw_rect(Rect2(carpet.position.x + 12, carpet.position.y, 6, carpet.size.y), Color("#e8b84a"))
		draw_rect(Rect2(carpet.end.x - 18, carpet.position.y, 6, carpet.size.y), Color("#e8b84a"))
		for k in 3:
			var sy := r.end.y + k * 16.0
			draw_rect(Rect2(r.position.x + 40 + k * 20, sy, r.size.x - 80 - k * 40, 14), Color("#f4efe6").darkened(0.06 * k))
			draw_rect(Rect2(r.position.x + 40 + k * 20, sy + 12, r.size.x - 80 - k * 40, 3), Color("#c9a86a"))


## Ворота спавна по бокам арены: тёмная решётка с шевронами «внутрь» и полосой цвета главы.
class Gate:
	extends Node2D
	var rect := Rect2()
	var inward := 1.0
	var color := Color("#2e9bff")
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var b := ArenaDecor._batch
		b.rect(rect, Color(0.05, 0.05, 0.1, 0.55))
		var step := 16.0
		var y := rect.position.y
		while y < rect.end.y:
			b.line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0, 0, 0, 0.35), 2.0)
			y += step
		var edge_x := rect.end.x if inward > 0.0 else rect.position.x
		b.line(Vector2(edge_x, rect.position.y), Vector2(edge_x, rect.end.y), Color(color, 0.7), 4.0)
		var cy := rect.get_center().y
		for k in 3:
			var phase := fmod(_time * 0.8 + k / 3.0, 1.0)
			var x := lerpf(rect.position.x + 14.0, rect.end.x - 14.0, phase if inward > 0.0 else 1.0 - phase)
			var a := sin(phase * PI) * 0.55
			var tip := Vector2(x + 12.0 * inward, cy)
			b.polyline(PackedVector2Array([Vector2(x - 6.0 * inward, cy - 22), tip, Vector2(x - 6.0 * inward, cy + 22)]), Color(color, a), 5.0)
		b.flush(self)


## Золотые/каменные бордюры на границах зон пола (газон ↔ площадь ↔ дорожки).
class Curbs:
	extends Node2D
	var segments := PackedVector2Array()
	var color := Color("#c9a24a")
	var shade := Color("#7a5a2a")

	func _draw() -> void:
		for i in range(0, segments.size(), 2):
			var a := segments[i]
			var b := segments[i + 1]
			draw_line(a + Vector2(0, 3), b + Vector2(0, 3), Color(shade, 0.7), 7.0)
			draw_line(a, b, color, 6.0)


## Пятна масла и гари на полу: тёмные, матовые, без бликов.
class Stains:
	extends Node2D
	var spots: Array = []

	func _draw() -> void:
		var b := ArenaDecor._batch
		for s in spots:
			var at: Vector2 = s[0]
			var r: float = s[1]
			b.set_transform(at, s[2], Vector2(1.0, 0.55))
			b.circle(Vector2.ZERO, r, Color(0.02, 0.01, 0.04, 0.32))
			b.circle(Vector2(r * 0.2, -r * 0.1), r * 0.6, Color(0.02, 0.01, 0.04, 0.22))
		b.reset_transform()
		b.flush(self)


## Лужи: тёмная вода с приглушённым отражением неба, лёгкая рябь. Без аддитивного свечения.
class Puddles:
	extends Node2D
	var puddles: Array = []
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var b := ArenaDecor._batch
		for p in puddles:
			var r: Vector2 = p[1]
			b.set_transform(p[0], p[2], Vector2(1.0, r.y / r.x))
			b.circle(Vector2.ZERO, r.x, Color(0.06, 0.04, 0.14, 0.55))
			b.circle(Vector2(-r.x * 0.15, -r.x * 0.1), r.x * 0.72, Color(0.16, 0.1, 0.3, 0.35))
			var shimmer := 0.5 + 0.5 * sin(_time * 1.2 + p[3])
			b.arc(Vector2.ZERO, r.x * 0.8, -2.3, -1.0, 16, Color(0.7, 0.55, 0.95, 0.12 + 0.06 * shimmer), 4.0, true)
		b.reset_transform()
		b.flush(self)


## Решётка вентиляции с паром (декор главы 1): тёмный металл, пар поднимается и тает.
class SteamVent:
	extends Node2D
	const PUFFS := 7
	const LIFE := 2.6
	var _puffs: Array[Vector3] = []

	func _ready() -> void:
		for i in PUFFS:
			_puffs.append(Vector3(randf_range(-10, 10), 0, -float(i) / PUFFS * LIFE))
		var enabler := VisibleOnScreenEnabler2D.new()
		enabler.rect = Rect2(-80, -200, 160, 240)
		enabler.enable_node_path = NodePath("..")
		add_child(enabler)

	func _process(delta: float) -> void:
		for i in _puffs.size():
			var p := _puffs[i]
			p.z += delta
			if p.z > LIFE:
				p = Vector3(randf_range(-10, 10), 0, 0.0)
			_puffs[i] = p
		queue_redraw()

	func _draw() -> void:
		var b := ArenaDecor._batch
		b.set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		b.circle(Vector2.ZERO, 34.0, Color("#15161f"))
		b.arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, Color("#4a4e66"), 4.0, true)
		for k in 5:
			var x := -24.0 + k * 12.0
			b.line(Vector2(x, -28), Vector2(x, 28), Color("#2e3144"), 4.0)
		b.reset_transform()
		for p in _puffs:
			if p.z < 0.0:
				continue
			var t := p.z / LIFE
			b.circle(Vector2(p.x + sin(t * 4.0 + p.x) * 8.0, -t * 110.0 - 6.0), 10.0 + t * 26.0, Color(0.8, 0.8, 0.9, 0.22 * (1.0 - t)))
		b.flush(self)


## Декаль-картинка на полу (граффити, медальон).
static func floor_image(path: String, width: float, alpha: float = 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = ArenaProp.texture_of(path)
	if s.texture != null:
		s.scale = Vector2.ONE * width / s.texture.get_width()
	s.modulate.a = alpha
	return s
