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
## Декорации трона босса на слое мира (сортировка по Y): трон из хлама, колонки, прожекторы и свет.
class BossSet:
	extends Node2D
	var _lights: PackedInt32Array = PackedInt32Array()

	func _init() -> void:
		y_sort_enabled = true

	## region пустой — вся картинка; width — ширина в мире; foot — точка касания пола.
	func piece(path: String, region: Rect2, foot: Vector2, width: float, flip: bool = false) -> Sprite2D:
		var tex := load(path) as Texture2D
		if tex == null:
			return null
		var sprite := Sprite2D.new()
		if region.size != Vector2.ZERO:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = region
			tex = atlas
		sprite.texture = tex
		sprite.scale = Vector2.ONE * width / tex.get_width()
		sprite.offset = Vector2(0, -tex.get_height() * 0.5 + 6.0)
		sprite.position = foot
		sprite.flip_h = flip
		add_child(sprite)
		return sprite

	func light(at: Vector2, color: Color, radius: float, strength: float) -> void:
		_lights.append(EnvLights.add(at, color, radius, strength))

	func _exit_tree() -> void:
		for id in _lights:
			EnvLights.remove(id)
		_lights.clear()


class BossStage:
	extends Node2D
	var rect := Rect2()
	var style := "junkyard"
	var _time := 0.0
	var _tiles: Array[Texture2D] = []

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_time += delta
		var rate := 20.0 if SaveService.get_quality() > 0 else 8.0
		if int(_time * rate) == int((_time - delta) * rate):
			return
		# Анимация помоста (ринг, огни, лучи) — только пока он в кадре.
		var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
		if view.intersects(rect.grow(300.0)):
			queue_redraw()

	func _draw() -> void:
		if style == "bank":
			_draw_bank()
		else:
			_draw_junkyard()

	## Помост Короля Свалки: клёпаные плиты Астры с сигнальной окантовкой, передний борт с тенью,
	## неоновое кольцо-ринг в центре с бегущими огнями и метки углов; два луча прожекторов скрещиваются
	## на центре и медленно ходят. Трон, колонки и прожекторы — BossSet на слое мира.
	func _draw_junkyard() -> void:
		var b := ArenaDecor._batch
		var r := rect
		# Передний борт помоста — помост приподнят.
		b.rect(Rect2(r.position + Vector2(-10, r.size.y - 4), Vector2(r.size.x + 20, 34)), Color("#0c0d14"))
		b.rect(Rect2(r.position + Vector2(-10, r.size.y - 4), Vector2(r.size.x + 20, 6)), Color("#4b4f6b"))
		b.rect(r.grow(10), Color("#14151f"))
		b.flush(self)
		if _tiles.is_empty():
			for i in 3:
				var tex := load("res://assets/story/boss/floor_%d.png" % (i + 1)) as Texture2D
				if tex != null:
					_tiles.append(tex)
		var cell := 192.0
		if not _tiles.is_empty():
			var y := r.position.y
			var row := 0
			while y < r.end.y - 1.0:
				var x := r.position.x
				var col := 0
				while x < r.end.x - 1.0:
					var size := Vector2(minf(cell, r.end.x - x), minf(cell, r.end.y - y))
					var tex: Texture2D = _tiles[(col * 7 + row * 13) % _tiles.size()]
					draw_texture_rect_region(tex, Rect2(Vector2(x, y), size), Rect2(Vector2.ZERO, size * 256.0 / cell), Color(0.82, 0.8, 0.9))
					x += cell
					col += 1
				y += cell
				row += 1
		var c := r.get_center() + Vector2(0, 10)
		var rad := minf(r.size.x * 0.34, r.size.y * 0.62)
		var squash := Vector2(1.0, 0.62)
		var pulse := 0.6 + 0.3 * sin(_time * 3.0)
		b.set_transform(Vector2.ZERO, 0.0, squash)
		var cs := c / squash
		# Ринг: тёмная чаша, двойное неоновое кольцо, бегущие огни.
		b.circle(cs, rad * 1.04, Color(0.02, 0.0, 0.04, 0.45))
		b.arc(cs, rad * 1.02, 0.0, TAU, 64, Color(1.0, 0.16, 0.36, 0.25 * pulse), 22.0)
		b.arc(cs, rad, 0.0, TAU, 64, Color(1.0, 0.3, 0.5, pulse), 9.0)
		b.arc(cs, rad * 0.92, 0.0, TAU, 64, Color(1.0, 0.6, 0.25, 0.6 * pulse), 4.0)
		b.arc(cs, rad * 0.38, 0.0, TAU, 40, Color(1.0, 0.16, 0.36, 0.35 * pulse), 4.0)
		for k in 16:
			var ang := TAU * k / 16.0 + _time * 0.6
			var lit := 0.35 + 0.65 * maxf(0.0, sin(_time * 4.0 - k * 0.8))
			b.circle(cs + Vector2.from_angle(ang) * rad * 1.08, 6.0, Color(1.0, 0.82, 0.35, lit))
		b.reset_transform()
		# Перекрестие в центре — «здесь дерётся босс».
		for side in [-1.0, 1.0]:
			b.line(c + Vector2(side * rad * 0.22, 0), c + Vector2(side * rad * 0.5, 0), Color(1.0, 0.16, 0.36, 0.5 * pulse), 4.0)
		_hazard(b, Rect2(Vector2(r.position.x, r.end.y - 14), Vector2(r.size.x, 14)))
		b.flush(self)
		_beams(c, rad, Color(1.0, 0.92, 0.6))
		var cx := r.get_center().x
		for k in 3:
			var sw := 260.0 - k * 40.0
			var sy := r.end.y + 30.0 + k * 9.0
			b.rect(Rect2(cx - sw * 0.5, sy, sw, 9), Color("#3a3f58").darkened(k * 0.18))
			b.rect(Rect2(cx - sw * 0.5, sy, sw, 2), Color("#6b7090").darkened(k * 0.18))
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

	## Лучи прожекторов из передних углов помоста на центр, медленно ходят.
	func _beams(c: Vector2, rad: float, tint: Color) -> void:
		var r := rect
		var squash := Vector2(1.0, 0.62)
		for side in [-1.0, 1.0]:
			var from := Vector2(c.x + side * (r.size.x * 0.5 + 40.0), r.end.y + 30.0)
			var aim := c + Vector2(sin(_time * 0.7 + side) * rad * 0.35, cos(_time * 0.5) * rad * 0.12)
			var dir := (aim - from).normalized()
			var n := dir.orthogonal()
			var far := aim + dir * rad * 0.35
			var w := rad * 0.34
			draw_polygon(PackedVector2Array([from - n * 10.0, from + n * 10.0, far + n * w, far - n * w]),
				PackedColorArray([Color(tint, 0.34), Color(tint, 0.34), Color(tint, 0.0), Color(tint, 0.0)]))
			draw_set_transform(Vector2.ZERO, 0.0, squash)
			draw_circle(aim / squash, w * 0.85, Color(tint, 0.16))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## Помост Магната: мраморный подиум с золотой окантовкой и шахматной инкрустацией, золотой
	## медальон-ринг в центре, красная дорожка через ступени, лучи прожекторов.
	func _draw_bank() -> void:
		var b := ArenaDecor._batch
		var r := rect
		var cx := r.get_center().x
		b.rect(Rect2(r.position + Vector2(-12, r.size.y - 4), Vector2(r.size.x + 24, 34)), Color("#9c8a84"))
		b.rect(Rect2(r.position + Vector2(-12, r.size.y - 4), Vector2(r.size.x + 24, 5)), Color("#f6eee8"))
		b.rect(r.grow(12), Color("#c9962e"))
		b.rect(r.grow(5), Color("#7a5418"))
		b.rect(r, Color("#efe3dc"))
		var cell := 96.0
		var y := r.position.y
		var row := 0
		while y < r.end.y - 1.0:
			var x := r.position.x
			var col := 0
			while x < r.end.x - 1.0:
				if (row + col) % 2 == 0:
					b.rect(Rect2(x, y, minf(cell, r.end.x - x), minf(cell, r.end.y - y)), Color("#e2d0c8"))
				x += cell
				col += 1
			y += cell
			row += 1
		var inner := r.grow(-22)
		for e in [[inner.position, Vector2(inner.end.x, inner.position.y)], [Vector2(inner.position.x, inner.end.y), inner.end],
				[inner.position, Vector2(inner.position.x, inner.end.y)], [Vector2(inner.end.x, inner.position.y), inner.end]]:
			b.line(e[0], e[1], Color("#d4a33c"), 4.0)
		var c := r.get_center() + Vector2(0, 10)
		var rad := minf(r.size.x * 0.34, r.size.y * 0.62)
		var squash := Vector2(1.0, 0.62)
		var pulse := 0.65 + 0.25 * sin(_time * 2.4)
		b.set_transform(Vector2.ZERO, 0.0, squash)
		var cs := c / squash
		b.circle(cs, rad * 1.02, Color(1.0, 0.85, 0.4, 0.18 * pulse))
		b.arc(cs, rad, 0.0, TAU, 64, Color("#c9962e"), 12.0)
		b.arc(cs, rad, 0.0, TAU, 64, Color(1.0, 0.9, 0.5, pulse), 4.0)
		b.arc(cs, rad * 0.8, 0.0, TAU, 56, Color("#d4a33c"), 4.0)
		for k in 12:
			var ang := TAU * k / 12.0 + _time * 0.3
			b.circle(cs + Vector2.from_angle(ang) * rad * 0.9, 7.0, Color(1.0, 0.92, 0.6, 0.5 + 0.5 * maxf(0.0, sin(_time * 3.0 - k))))
		b.reset_transform()
		b.flush(self)
		var carpet := Rect2(cx - 90, r.position.y + 30, 180, r.size.y + 150)
		draw_rect(carpet.grow(8), Color("#b8862e"))
		draw_rect(carpet, Color("#b3122e"))
		draw_rect(Rect2(carpet.position.x + 12, carpet.position.y, 6, carpet.size.y), Color("#e8b84a"))
		draw_rect(Rect2(carpet.end.x - 18, carpet.position.y, 6, carpet.size.y), Color("#e8b84a"))
		for k in 3:
			var sy := r.end.y + 30.0 + k * 16.0
			draw_rect(Rect2(r.position.x + 40 + k * 20, sy, r.size.x - 80 - k * 40, 14), Color("#f4efe6").darkened(0.06 * k))
			draw_rect(Rect2(r.position.x + 40 + k * 20, sy + 12, r.size.x - 80 - k * 40, 3), Color("#c9a86a"))
		_beams(c, rad, Color(1.0, 0.95, 0.8))


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

	## Дождевые лужи: тёмная вода с отражением неонового неба, бликами и рябью (общая отрисовка луж).
	func _draw() -> void:
		for p in puddles:
			var r: Vector2 = p[1]
			LiquidDraw.puddle(self, p[0], r.x, Color(0.13, 0.12, 0.3), int(float(p[3]) * 1000.0) + 7, _time, 1.0, Color(0, 0, 0, 0), false)


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
