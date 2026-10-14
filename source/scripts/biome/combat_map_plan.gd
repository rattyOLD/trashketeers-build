class_name CombatMapPlan
extends RefCounted
## Свободные боевые маршруты планируются до расстановки объектов, без изменения русла и стен.

const ROUTE_RADIUS := 80.0
const CELL_PAD := 46.0
const STYLES: Array[StringName] = [&"wide_loop", &"crossroads", &"flank"]
var style: StringName
var routes: Array[PackedVector2Array] = []
var clearings := PackedVector3Array()


func build(start: Vector2, boss_area: Rect2, inner: Rect2, river_points: PackedVector2Array, plan_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = plan_seed
	style = STYLES[rng.randi_range(0, STYLES.size() - 1)]
	routes.clear()
	clearings.clear()
	var top := Vector2(boss_area.get_center().x, boss_area.end.y + 160.0)
	var half := minf(inner.size.x * 0.27, 760.0)
	for p in river_points:
		half = minf(half, absf(p.x - top.x) - 400.0)
	half = maxf(half, 180.0)
	var left := half * rng.randf_range(0.8, 1.0)
	var right := half * rng.randf_range(0.8, 1.0)
	var radius := 240.0
	if style == &"crossroads":
		left *= 0.65
		right *= 0.65
		radius = 310.0
	elif style == &"flank":
		if rng.randf() < 0.5:
			left *= 0.42
		else:
			right *= 0.42
		radius = 190.0
	var low_y := lerpf(start.y, top.y, rng.randf_range(0.23, 0.3))
	var high_y := lerpf(start.y, top.y, rng.randf_range(0.68, 0.75))
	var low_left := Vector2(top.x - left, low_y)
	var high_left := Vector2(top.x - left, high_y)
	var low_right := Vector2(top.x + right, low_y)
	var high_right := Vector2(top.x + right, high_y)
	routes.append(PackedVector2Array([start, low_left, high_left, top]))
	routes.append(PackedVector2Array([start, low_right, high_right, top]))
	if style == &"crossroads":
		routes.append(PackedVector2Array([low_left, high_right]))
		routes.append(PackedVector2Array([low_right, high_left]))
	else:
		routes.append(PackedVector2Array([low_left.lerp(high_left, 0.5), low_right.lerp(high_right, 0.5)]))
	clearings.append(Vector3(start.x, start.y, 160.0))
	clearings.append(Vector3(top.x, top.y, 190.0))
	var center := Vector2(top.x, (low_y + high_y) * 0.5)
	clearings.append(Vector3(center.x, center.y, radius))
	var side := low_left if style == &"flank" and left > right else high_right
	clearings.append(Vector3(side.x, side.y, minf(radius, 220.0)))


func reserves(point: Vector2, padding: float = 0.0) -> bool:
	for clearing in clearings:
		if point.distance_squared_to(Vector2(clearing.x, clearing.y)) < pow(clearing.z + padding, 2):
			return true
	for line in routes:
		for i in range(1, line.size()):
			var nearest := Geometry2D.get_closest_point_to_segment(point, line[i - 1], line[i])
			if point.distance_squared_to(nearest) < pow(ROUTE_RADIUS + padding, 2):
				return true
	return false
