class_name EnemyAccessories
extends Node2D
## Аксессуары особи поверх спрайта крысы: узел — ребёнок Sprite2D, поэтому рисует в пикселях
## текстуры и повторяет все трансформации спрайта (покачивание, приседание, разворот по X).
## anchor — точка головы из enemies.json; смещения ниже подобраны под листы rat_punk / cyber_rat.

const LINE := Color("#140a1e")
const METAL := Color("#c9ced9")
const GOLD := Color("#ffc93c")
const CLOTH_COLORS: Array[Color] = [Color("#ff2e63"), Color("#2ec4ff"), Color("#ffe14d"), Color("#7cff6b"), Color("#b84dff")]

var anchor := Vector2.ZERO
var items: PackedStringArray = PackedStringArray()
var cloth := Color("#ff2e63")
var fuse_lit := false
var _time := 0.0

static var _batch := PolyBatch.new()


func setup(anchor_point: Vector2, pool: PackedStringArray, forced: bool) -> void:
	anchor = anchor_point
	items = PackedStringArray()
	cloth = CLOTH_COLORS.pick_random()
	if forced:
		items = pool.duplicate()
	elif not pool.is_empty():
		var shuffled := Array(pool)
		shuffled.shuffle()
		for i in randi_range(1, mini(2, shuffled.size())):
			items.append(shuffled[i])
	fuse_lit = false
	visible = not items.is_empty()
	set_process(items.has("bomb") or items.has("booster"))
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for item in items:
		match item:
			"bandana":
				_draw_bandana(anchor + Vector2(-14, 52))
			"spikes":
				_draw_spikes(anchor + Vector2(-20, 58))
			"earring":
				_draw_earring(anchor + Vector2(-40, 26))
			"shades":
				_draw_shades(anchor + Vector2(12, 24))
			"chain":
				_draw_chain(anchor + Vector2(-30, 86))
			"goggles":
				_draw_goggles(anchor + Vector2(-4, -6))
			"antenna":
				_draw_antenna(anchor + Vector2(-16, -26))
			"stripe":
				_draw_stripe(anchor + Vector2(52, 40))
			"bomb":
				_draw_bomb(anchor + Vector2(-58, 72))
			"booster":
				_draw_booster(anchor + Vector2(-112, 66))
	_batch.flush(self)


func _draw_bandana(p: Vector2) -> void:
	var poly := PackedVector2Array([p + Vector2(-26, -6), p + Vector2(26, -10), p + Vector2(4, 30)])
	_batch.polygon(_grow(poly, 4.0), LINE)
	_batch.polygon(poly, cloth)
	_batch.circle(p + Vector2(0, 6), 3.0, Color(1, 1, 1, 0.8))
	_batch.circle(p + Vector2(-8, -2), 2.4, Color(1, 1, 1, 0.8))


func _draw_spikes(p: Vector2) -> void:
	_batch.rect(Rect2(p + Vector2(-30, -6), Vector2(60, 13)).grow(3.0), LINE)
	_batch.rect(Rect2(p + Vector2(-30, -6), Vector2(60, 13)), Color("#2b2233"))
	for i in 5:
		var base := p + Vector2(-24 + i * 12, -6)
		var spike := PackedVector2Array([base + Vector2(-5, 0), base + Vector2(5, 0), base + Vector2(0, -15)])
		_batch.polygon(_grow(spike, 2.5), LINE)
		_batch.polygon(spike, METAL)


func _draw_earring(p: Vector2) -> void:
	_batch.arc(p, 9.0, 0.0, TAU, 16, LINE, 7.0, true)
	_batch.arc(p, 9.0, 0.0, TAU, 16, GOLD, 3.5, true)


func _draw_shades(p: Vector2) -> void:
	var lens := Rect2(p + Vector2(-8, -9), Vector2(34, 16))
	_batch.rect(lens.grow(3.0), LINE)
	_batch.rect(lens, Color("#1d1a2b"))
	_batch.line(lens.position + Vector2(4, 4), lens.position + Vector2(14, 4), cloth, 3.0)
	_batch.line(p + Vector2(-8, -3), p + Vector2(-30, -8), LINE, 5.0)


func _draw_chain(p: Vector2) -> void:
	var points := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		points.append(p + Vector2(lerpf(-34, 34, t), sin(t * PI) * 22.0))
	_batch.polyline(points, LINE, 9.0, true)
	_batch.polyline(points, GOLD, 4.5, true)
	_batch.circle(points[4] + Vector2(0, 8), 7.0, LINE)
	_batch.circle(points[4] + Vector2(0, 8), 4.5, GOLD)


func _draw_goggles(p: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var c: Vector2 = p + Vector2(side * 14.0, 0)
		_batch.circle(c, 12.0, LINE)
		_batch.circle(c, 8.5, Color(cloth, 0.9))
		_batch.circle(c + Vector2(-3, -3), 3.0, Color(1, 1, 1, 0.8))


func _draw_antenna(p: Vector2) -> void:
	_batch.line(p, p + Vector2(-8, -44), LINE, 7.0)
	_batch.line(p, p + Vector2(-8, -44), METAL, 3.0)
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	_batch.circle(p + Vector2(-8, -48), 8.0, LINE)
	_batch.circle(p + Vector2(-8, -48), 5.5, Color(cloth, 0.6 + 0.4 * blink))


func _draw_stripe(p: Vector2) -> void:
	var poly := PackedVector2Array([p + Vector2(-8, -60), p + Vector2(8, -60), p + Vector2(18, 60), p + Vector2(2, 60)])
	_batch.polygon(poly, Color(cloth, 0.85))


func _draw_bomb(p: Vector2) -> void:
	_batch.circle(p, 30.0, LINE)
	_batch.circle(p, 26.0, Color("#26222f"))
	_batch.circle(p + Vector2(-9, -9), 8.0, Color(1, 1, 1, 0.25))
	_batch.rect(Rect2(p + Vector2(-8, -34), Vector2(16, 10)).grow(3.0), LINE)
	_batch.rect(Rect2(p + Vector2(-8, -34), Vector2(16, 10)), METAL)
	var fuse := PackedVector2Array([p + Vector2(0, -34), p + Vector2(6, -46), p + Vector2(18, -52)])
	_batch.polyline(fuse, LINE, 6.0, true)
	_batch.polyline(fuse, Color("#d9b27a"), 3.0, true)
	var spark := p + Vector2(18, -52)
	var rate := 0.05 if fuse_lit else 0.012
	var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * rate)
	var size := (13.0 if fuse_lit else 8.0) * (0.7 + 0.3 * flicker)
	_batch.circle(spark, size * 1.6, Color(1.0, 0.6, 0.1, 0.35))
	_batch.circle(spark, size, Color(1.0, 0.85, 0.3))
	_batch.circle(spark, size * 0.45, Color.WHITE)


func _draw_booster(p: Vector2) -> void:
	var flicker := 0.75 + 0.25 * sin(_time * 40.0)
	var tail := 46.0 * flicker
	var flame := PackedVector2Array([p + Vector2(0, -14), p + Vector2(0, 14), p + Vector2(-tail, 0)])
	_batch.polygon(flame, Color(1.0, 0.45, 0.15, 0.85))
	var core := PackedVector2Array([p + Vector2(0, -7), p + Vector2(0, 7), p + Vector2(-tail * 0.55, 0)])
	_batch.polygon(core, Color(1.0, 0.95, 0.6))


static func _grow(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(poly, amount, Geometry2D.JOIN_ROUND)
	return grown[0] if not grown.is_empty() else poly
