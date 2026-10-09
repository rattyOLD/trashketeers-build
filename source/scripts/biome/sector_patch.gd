class_name SectorPatch
extends Node2D
## Покрытие сектора выживания. Природные места (парк, полянка) — мягкое «пятно» с размытым краем,
## рукотворные (кафе, стоянка, бассейн, энергобудка) — скруглённый прямоугольник с бордюром.
## Детали рисуются здесь же, одним узлом: цветы и кочки травы, полосы стриженого газона, разметка
## парковки, сигнальная кайма, вода бассейна (шейдер протоки), гирлянда лампочек над кафе.

const BLOB_POINTS := 32

var center := Vector2.ZERO
var half := Vector2.ZERO
var deco: Array = []
var _rng := RandomNumberGenerator.new()
var _lights: PackedInt32Array = PackedInt32Array()
var _dots: Array = []


## shape: "blob" | "rect"; deco — список деталей: flowers, tufts, stripes, bays, hazard, pool, garland.
func build(at: Vector2, radius: float, texture: Texture2D, tint: Color, curb: Color, seed_value: int, shape: String = "blob", details: Array = []) -> void:
	center = at
	deco = details
	_rng.seed = seed_value
	half = Vector2(radius, radius * 0.72)
	var ring := _blob(radius) if shape == "blob" else _rounded_rect(half, 46.0)
	# Мягкая тень-подложка: у природных — широкий размытый край, у рукотворных — узкая тень бордюра.
	var soft := shape == "blob"
	for k in (3 if soft else 1):
		var shade := Polygon2D.new()
		shade.polygon = _scaled(ring, 1.03 + 0.035 * k if soft else 1.025)
		shade.color = Color(0, 0, 0, 0.12 if soft else 0.3)
		shade.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
		add_child(shade)
	var body := Polygon2D.new()
	body.polygon = ring
	body.texture = texture
	body.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	body.uv = ring
	body.color = tint
	body.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	add_child(body)
	if soft:
		# Край травы не режется линией: внешний ободок той же травы полупрозрачный — переход мягкий.
		var fringe := Polygon2D.new()
		fringe.polygon = _scaled(ring, 1.045)
		fringe.texture = texture
		fringe.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		fringe.uv = fringe.polygon
		fringe.color = Color(tint, 0.45)
		fringe.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
		add_child(fringe)
		move_child(fringe, get_child_count() - 2)
	else:
		var edge := Line2D.new()
		var closed := ring.duplicate()
		closed.append(ring[0])
		edge.points = closed
		edge.width = 9.0
		edge.default_color = curb
		edge.joint_mode = Line2D.LINE_JOINT_ROUND
		edge.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
		add_child(edge)
	if deco.has("pool"):
		_add_pool()
	_scatter_dots()
	if deco.has("garland"):
		_add_garland_lights()
	# Детали — отдельным слоем поверх покрытия (собственный _draw узла оказался бы под дочерними полигонами).
	# Всё одной сеткой FlatMesh: один вызов отрисовки вместо десятков линий и кружков.
	var m := FlatMesh.new()
	_paint(m)
	var mesh := m.commit()
	if mesh != null:
		var layer := FxManager.DrawLayer.new()
		layer.painter = func(ci: CanvasItem) -> void: ci.draw_mesh(mesh, null)
		add_child(layer)
		layer.queue_redraw()


func _blob(radius: float) -> PackedVector2Array:
	var p1 := _rng.randf() * TAU
	var p2 := _rng.randf() * TAU
	var ring := PackedVector2Array()
	for i in BLOB_POINTS:
		var a := TAU * i / BLOB_POINTS
		var r := radius * (1.0 + 0.1 * sin(3.0 * a + p1) + 0.06 * sin(5.0 * a + p2))
		ring.append(center + Vector2(cos(a), sin(a) * 0.76) * r)
	return ring


func _rounded_rect(h: Vector2, corner: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	var c := minf(corner, minf(h.x, h.y) * 0.5)
	for q in 4:
		var sx := 1.0 if q == 0 or q == 3 else -1.0
		var sy := 1.0 if q < 2 else -1.0
		var corner_center := center + Vector2(sx * (h.x - c), sy * (h.y - c))
		var start: float = [0.0, PI * 0.5, PI, PI * 1.5][q]
		for i in 6:
			ring.append(corner_center + Vector2.from_angle(start + PI * 0.5 * i / 5.0) * c)
	return ring


func _scaled(ring: PackedVector2Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		out.append(center + (p - center) * k)
	return out


## Вода бассейна: та же текстура и шейдер, что у протоки (перекраска в бирюзу), плюс мраморный бортик.
func _add_pool() -> void:
	var h := half * Vector2(0.5, 0.42)
	var rim := Polygon2D.new()
	rim.polygon = _rounded_rect_at(h + Vector2(14, 14), 36.0)
	rim.color = Color("#f4efe6")
	add_child(rim)
	var water := Polygon2D.new()
	water.polygon = _rounded_rect_at(h, 30.0)
	water.texture = load(AcidRiver.ACID) as Texture2D
	water.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	water.uv = water.polygon
	var shader := Shader.new()
	shader.code = AcidRiver.SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("water", 1.0)
	mat.set_shader_parameter("flow", 0.012)
	water.material = mat
	add_child(water)
	_lights.append(EnvLights.add(center, Color("#6fd8ff"), 240.0, 0.3))


func _rounded_rect_at(h: Vector2, corner: float) -> PackedVector2Array:
	var keep := half
	half = h
	var ring := _rounded_rect(h, corner)
	half = keep
	return ring


## Мелкие детали поверх покрытия — заранее, чтобы _draw не крутил генератор.
func _scatter_dots() -> void:
	var count := 0
	if deco.has("flowers"):
		count = 46
	elif deco.has("tufts"):
		count = 30
	var colors := [Color("#ffe86b"), Color("#ff8fd0"), Color("#ffffff"), Color("#9fd8ff")]
	for i in count:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 0.88
		var p := center + Vector2(cos(a) * half.x, sin(a) * half.y) * d
		_dots.append([p, colors[_rng.randi() % colors.size()] if deco.has("flowers") else Color(0.25, 0.42, 0.22), _rng.randf_range(2.5, 4.5)])


func _add_garland_lights() -> void:
	var y := center.y - half.y * 0.55
	var x := center.x - half.x * 0.8
	while x <= center.x + half.x * 0.8:
		_lights.append(EnvLights.add(Vector2(x, y), Color("#ffd27a"), 150.0, 0.35))
		x += half.x * 0.4


func _paint(ci: FlatMesh) -> void:
	if deco.has("stripes"):
		# Стриженый газон: широкие полосы светлее/темнее, как на поле для гольфа.
		var band := 70.0
		var x := center.x - half.x
		var light := true
		while x < center.x + half.x:
			if light:
				var w := minf(band, center.x + half.x - x)
				var top := center.y - half.y * sqrt(maxf(0.0, 1.0 - pow((x + w * 0.5 - center.x) / half.x, 2.0))) * 0.9
				ci.rect(Rect2(x, top, w, (center.y - top) * 2.0), Color(1, 1, 1, 0.07))
			light = not light
			x += band
	if deco.has("bays"):
		# Разметка парковки: ряд мест вдоль задней стороны, буферная линия посередине.
		var bay := 120.0
		var x0 := center.x - half.x + 50.0
		while x0 < center.x + half.x - 40.0:
			ci.line(Vector2(x0, center.y - half.y + 26.0), Vector2(x0, center.y - 6.0), Color(1, 1, 1, 0.55), 4.0)
			x0 += bay
		ci.line(Vector2(center.x - half.x + 50.0, center.y - 6.0), Vector2(center.x + half.x - 50.0, center.y - 6.0), Color(1, 0.86, 0.3, 0.6), 4.0)
	if deco.has("hazard"):
		# Сигнальная жёлто-чёрная кайма по краю площадки энергобудки.
		var r := Rect2(center - half + Vector2(18, 18), half * 2.0 - Vector2(36, 36))
		var step := 28.0
		var t := 0.0
		while t < r.size.x:
			var c := Color("#e8b41a") if int(t / step) % 2 == 0 else Color(0.08, 0.08, 0.1)
			ci.line(Vector2(r.position.x + t, r.position.y), Vector2(minf(r.position.x + t + step, r.end.x), r.position.y), c, 8.0)
			ci.line(Vector2(r.position.x + t, r.end.y), Vector2(minf(r.position.x + t + step, r.end.x), r.end.y), c, 8.0)
			t += step
	for dot: Array in _dots:
		var p: Vector2 = dot[0]
		var c: Color = dot[1]
		var s: float = dot[2]
		if deco.has("flowers"):
			ci.circle(p + Vector2(0, 2), s, Color(0, 0, 0, 0.25))
			ci.circle(p, s, c)
			ci.circle(p, s * 0.4, Color("#ffd23f"))
		else:
			ci.line(p, p + Vector2(-3, -7), c, 2.0)
			ci.line(p, p + Vector2(0, -9), c, 2.0)
			ci.line(p, p + Vector2(3, -7), c, 2.0)
	if deco.has("garland"):
		# Гирлянда над столиками: провисающий провод между столбиками, лампочки светятся.
		var y := center.y - half.y * 0.55
		var x0 := center.x - half.x * 0.8
		var x1 := center.x + half.x * 0.8
		var prev := Vector2(x0, y)
		for i in range(1, 25):
			var t := float(i) / 24.0
			var p := Vector2(lerpf(x0, x1, t), y + sin(t * PI * 2.0) * 0.0 + 18.0 * sin(fmod(t * 2.0, 1.0) * PI))
			ci.line(prev, p, Color(0.1, 0.08, 0.06, 0.8), 2.0)
			if i % 2 == 0:
				ci.circle(p + Vector2(0, 5), 5.0, Color("#ffd27a"))
				ci.circle(p + Vector2(0, 5), 9.0, Color(1.0, 0.82, 0.45, 0.25))
			prev = p
		for px in [x0, x1]:
			ci.line(Vector2(px, y + 40.0), Vector2(px, y - 6.0), Color(0.15, 0.12, 0.1), 5.0)


func _exit_tree() -> void:
	for id in _lights:
		EnvLights.remove(id)
	_lights.clear()
