class_name SectorPatch
extends Node2D
## Покрытие сектора выживания (мини-парк — трава, кафе — плитка, стоянка — асфальт): мягкий
## «пятнистый» многоугольник с тайлом, тёмной каймой и бордюром — квартал читается как отдельное место.

const POINTS := 28


func build(center: Vector2, radius: float, texture: Texture2D, tint: Color, curb: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var ring := PackedVector2Array()
	for i in POINTS:
		var a := TAU * i / POINTS
		var r := radius * (1.0 + 0.12 * sin(3.0 * a + p1) + 0.07 * sin(5.0 * a + p2))
		ring.append(center + Vector2(cos(a), sin(a) * 0.78) * r)
	var shade := Polygon2D.new()
	shade.polygon = _scaled(ring, center, 1.06)
	shade.color = Color(0, 0, 0, 0.28)
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
	var edge := Line2D.new()
	var closed := ring.duplicate()
	closed.append(ring[0])
	edge.points = closed
	edge.width = 7.0
	edge.default_color = curb
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	edge.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	add_child(edge)


static func _scaled(ring: PackedVector2Array, center: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		out.append(center + (p - center) * k)
	return out
