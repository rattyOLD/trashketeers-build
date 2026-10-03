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
		var r := 1.0 + 0.17 * sin(3.0 * a + p1) + 0.1 * sin(5.0 * a + p2) + 0.06 * sin(9.0 * a + p3)
		points.append(Vector2(cos(a), sin(a) * SQUASH) * r)
	_outlines[seed_value] = points
	return points


static func _scaled(points: PackedVector2Array, at: Vector2, radius: float, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = at + offset + points[i] * radius
	return result


## fade 0..1 — прозрачность лужи; foam — цвет пузырей и кромки (у пива белая пена).
static func puddle(canvas: CanvasItem, at: Vector2, radius: float, color: Color, seed_value: int, clock: float, fade: float = 1.0, foam: Color = Color(0, 0, 0, 0)) -> void:
	var outline_key := seed_value % 24
	var shape := outline(outline_key)
	var rim_color := color.darkened(0.55)
	var batch := _batch
	batch.polygon_cached(outline_key, shape, radius * 1.07, at, Color(rim_color, 0.6 * fade))
	batch.polygon_cached(outline_key, shape, radius, at, Color(color, 0.82 * fade))
	batch.polygon_cached(outline_key, shape, radius * 0.68, at + Vector2(-radius * 0.08, -radius * 0.05), Color(color.lightened(0.28), 0.55 * fade))
	batch.polygon_cached(outline_key, shape, radius * 0.3, at + Vector2(-radius * 0.18, -radius * 0.1), Color(color.lightened(0.55), 0.4 * fade))
	var edge := _scaled(shape, at, radius)
	edge.append(edge[0])
	batch.polyline(edge, Color(foam if foam.a > 0.0 else color.lightened(0.45), 0.8 * fade), 3.0, true)
	batch.arc(at + Vector2(-radius * 0.28, -radius * 0.2), radius * 0.5, PI * 1.05, PI * 1.55, 10, Color(1, 1, 1, 0.42 * fade), 3.0, true)
	var ripple := fmod(clock * 0.45 + float(seed_value % 7) * 0.13, 1.0)
	batch.arc(at, radius * (0.2 + 0.7 * ripple), 0.0, TAU, 24, Color(1, 1, 1, 0.22 * (1.0 - ripple) * fade), 2.0, true)
	var bubble_color := foam if foam.a > 0.0 else color.lightened(0.6)
	for b in BUBBLES:
		var cycle := clock * 0.75 + b * 0.37 + float(seed_value % 5) * 0.21
		var phase := fmod(cycle, 1.0)
		var index := floori(cycle) * 7 + b * 13 + seed_value
		var angle := float(index % 17) * 0.37 + b
		var spot := at + Vector2(cos(angle), sin(angle) * SQUASH) * radius * (0.12 + 0.55 * fmod(float(index % 11) * 0.09, 1.0))
		if phase < 0.8:
			var size := 2.0 + radius * 0.09 * (phase / 0.8)
			batch.circle(spot, size, Color(bubble_color, 0.4 * fade))
			batch.arc(spot, size, 0.0, TAU, 10, Color(1, 1, 1, 0.55 * fade), 1.5, true)
			batch.circle(spot + Vector2(-size * 0.3, -size * 0.3), size * 0.25, Color(1, 1, 1, 0.8 * fade))
		else:
			var pop := (phase - 0.8) / 0.2
			batch.arc(spot, radius * 0.11 * (1.0 + pop), 0.0, TAU, 12, Color(1, 1, 1, 0.5 * (1.0 - pop) * fade), 2.0, true)
	batch.flush(canvas)
