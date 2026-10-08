class_name LiquidDraw
extends RefCounted
## Общая отрисовка луж (кислота, пиво, масло, кровь): неровная кромка, слои глубины, блик,
## пузыри, которые растут и лопаются, и расходящаяся рябь. Контур кэшируется по зерну, поэтому
## лужа не выделяет память каждый кадр.

const POINTS := 36
const BUBBLES := 6
const SQUASH := 0.62

static var _outlines := {}
static var _batch := PolyBatch.new()


static func outline(seed_value: int) -> PackedVector2Array:
	if _outlines.has(seed_value):
		return _outlines[seed_value]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	var points := PackedVector2Array()
	for i in POINTS:
		var a := TAU * float(i) / POINTS
		var r := 1.0 + 0.12 * sin(2.0 * a + p1) + 0.08 * sin(3.0 * a + p2) + 0.035 * sin(7.0 * a + p3)
		points.append(Vector2(cos(a), sin(a) * SQUASH) * r)
	_outlines[seed_value] = points
	return points


static func _scaled(points: PackedVector2Array, at: Vector2, radius: float, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = at + offset + points[i] * radius
	return result


## Лужа как жидкость, а не пластилин: тёмный мокрый ореол вокруг, полупрозрачная гладь, глубже к центру,
## отражение неба сверху, светлая кромка только снизу, яркие переливающиеся блики и рябь от капель.
## fade 0..1 — прозрачность лужи; foam — цвет пузырей (у пива белая пена); bubbly — кипит ли (кислота, пиво).
static func puddle(canvas: CanvasItem, at: Vector2, radius: float, color: Color, seed_value: int, clock: float, fade: float = 1.0, foam: Color = Color(0, 0, 0, 0), bubbly: bool = true) -> void:
	var outline_key := seed_value % 24
	var shape := outline(outline_key)
	var batch := _batch
	# Лужа плоская: никакой тени под ней. Мокрый пол вокруг чуть темнее, край мягкий (гладь набирается слоями).
	batch.polygon_cached(outline_key, shape, radius * 1.1, at, Color(0.0, 0.0, 0.02, 0.16 * fade))
	batch.polygon_cached(outline_key, shape, radius, at, Color(color, 0.3 * fade))
	batch.polygon_cached(outline_key, shape, radius * 0.88, at, Color(color, 0.22 * fade))
	# Глубина к центру.
	batch.polygon_cached(outline_key, shape, radius * 0.62, at + Vector2(radius * 0.04, radius * 0.04), Color(color.darkened(0.35), 0.26 * fade))
	# Отражение неба/неона — светлое пятно у дальнего (верхнего) края.
	batch.polygon_cached(outline_key, shape, radius * 0.5, at + Vector2(-radius * 0.18, -radius * 0.16), Color(color.lightened(0.55), 0.16 * fade))
	batch.polygon_cached(outline_key, shape, radius * 0.3, at + Vector2(-radius * 0.24, -radius * 0.2), Color(color.lightened(0.7), 0.14 * fade))
	# Тонкая светлая кромка только у ближнего края — свет на краю воды.
	var edge := _scaled(shape, at, radius * 0.97)
	var lower := PackedVector2Array()
	for i in range(int(POINTS * 0.08), int(POINTS * 0.42)):
		lower.append(edge[i])
	batch.polyline(lower, Color(foam if foam.a > 0.0 else color.lightened(0.6), 0.3 * fade), 1.5, true)
	# Блики: вытянутые, переливаются.
	var shimmer := 0.5 + 0.5 * sin(clock * 1.6 + float(seed_value % 9))
	var glint := at + Vector2(-radius * 0.3, -radius * 0.2)
	batch.line(glint, glint + Vector2(radius * 0.34, -radius * 0.04), Color(1, 1, 1, (0.22 + 0.28 * shimmer) * fade), maxf(radius * 0.045, 2.0))
	batch.line(glint + Vector2(radius * 0.42, -radius * 0.05), glint + Vector2(radius * 0.52, -radius * 0.065), Color(1, 1, 1, (0.15 + 0.25 * shimmer) * fade), maxf(radius * 0.035, 1.5))
	batch.circle(at + Vector2(radius * 0.32, radius * 0.12), maxf(radius * 0.035, 1.5), Color(1, 1, 1, (0.25 + 0.4 * (1.0 - shimmer)) * fade))
	# Рябь от капель: эллипсы расходятся и гаснут.
	batch.set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SQUASH))
	for k in 2:
		var ripple := fmod(clock * 0.5 + float(seed_value % 7) * 0.13 + k * 0.5, 1.0)
		var drop := int(clock * 0.5 + float(seed_value % 7) * 0.13 + k * 0.5) * 5 + k * 11 + seed_value
		var spot := Vector2(cos(float(drop % 13)), sin(float(drop % 13))) * radius * 0.35
		var c := (at + spot) / Vector2(1.0, SQUASH)
		batch.arc(c, radius * (0.08 + 0.32 * ripple), 0.0, TAU, 20, Color(1, 1, 1, 0.32 * (1.0 - ripple) * fade), 1.6, true)
	batch.reset_transform()
	if bubbly:
		var bubble_color := foam if foam.a > 0.0 else color.lightened(0.6)
		for b in BUBBLES:
			var cycle := clock * 0.75 + b * 0.37 + float(seed_value % 5) * 0.21
			var phase := fmod(cycle, 1.0)
			var index := floori(cycle) * 7 + b * 13 + seed_value
			var angle := float(index % 17) * 0.37 + b
			var spot := at + Vector2(cos(angle), sin(angle) * SQUASH) * radius * (0.12 + 0.55 * fmod(float(index % 11) * 0.09, 1.0))
			if phase < 0.8:
				var size := 2.0 + radius * 0.07 * (phase / 0.8)
				batch.circle(spot, size, Color(bubble_color, 0.35 * fade))
				batch.circle(spot + Vector2(-size * 0.3, -size * 0.3), size * 0.3, Color(1, 1, 1, 0.75 * fade))
			else:
				var pop := (phase - 0.8) / 0.2
				batch.arc(spot, radius * 0.1 * (1.0 + pop), 0.0, TAU, 12, Color(1, 1, 1, 0.45 * (1.0 - pop) * fade), 1.6, true)
	batch.flush(canvas)


## Только блеск жидкости поверх готовой текстуры лужи: блики и рябь (лужи босса-пивовара — картинки Астры).
static func sheen(canvas: CanvasItem, at: Vector2, radius: float, seed_value: int, clock: float, fade: float) -> void:
	var batch := _batch
	var shimmer := 0.5 + 0.5 * sin(clock * 1.8 + float(seed_value % 9))
	var glint := at + Vector2(-radius * 0.32, -radius * 0.18 * SQUASH)
	batch.line(glint, glint + Vector2(radius * 0.36, -radius * 0.03), Color(1, 1, 1, (0.4 + 0.35 * shimmer) * fade), maxf(radius * 0.06, 2.5))
	batch.line(glint + Vector2(radius * 0.44, -radius * 0.04), glint + Vector2(radius * 0.55, -radius * 0.05), Color(1, 1, 1, (0.25 + 0.3 * shimmer) * fade), maxf(radius * 0.045, 2.0))
	batch.set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SQUASH))
	for k in 2:
		var ripple := fmod(clock * 0.6 + float(seed_value % 7) * 0.17 + k * 0.5, 1.0)
		var drop := int(clock * 0.6 + float(seed_value % 7) * 0.17 + k * 0.5) * 5 + k * 11 + seed_value
		var spot := Vector2(cos(float(drop % 13)), sin(float(drop % 13))) * radius * 0.3
		batch.arc((at + spot) / Vector2(1.0, SQUASH), radius * (0.08 + 0.3 * ripple), 0.0, TAU, 18, Color(1, 1, 1, 0.3 * (1.0 - ripple) * fade), 1.6, true)
	batch.reset_transform()
	batch.flush(canvas)
