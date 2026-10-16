class_name ParkPaths
extends Node2D
## Парк поместья (выживание в Банке): круглая мраморная площадь в центре и плавные мощёные дорожки
## от неё к воротам, помосту босса и старту. Дорожки — Line2D с тайлом плитки и золотыми бордюрами,
## площадь — многоугольник с тем же тайлом. Чистая картинка: ходить можно везде.

const PATH_TEX := "res://assets/biome/bank_path.png"
const PLAZA_TEX := "res://assets/biome/bank_plaza.png"
## Каменный бордюр и мягкая тень по краю вместо яркой золотой обводки: дорожка лежит в газоне, а не нарисована поверх.
const CURB := Color("#a89272")
const CURB_SHADE := Color(0.08, 0.06, 0.03, 0.22)
const PATH_TINT := Color(0.9, 0.87, 0.82)

var paths: Array[PackedVector2Array] = []
var width := 150.0
## Индексы дорожек, которые упираются в забор: конец прямой, без скругления — дорожка не «пробивает» ограду.
var flat_ends: Array[int] = []


func build(center: Vector2, plaza_radius: float) -> void:
	var path_tex := load(PATH_TEX) as Texture2D
	for i in paths.size():
		var line := paths[i]
		var flat := flat_ends.has(i)
		_line(line, width + 34.0, null, Color(CURB_SHADE, CURB_SHADE.a * 0.5), flat)
		_line(line, width + 20.0, null, CURB_SHADE, flat)
		_line(line, width + 8.0, null, CURB, flat)
		_line(line, width, path_tex, PATH_TINT, flat)
	if plaza_radius <= 0.0:
		return
	# Площадь поверх дорожек: дорожки «вливаются» в неё.
	var ring := PackedVector2Array()
	for i in 48:
		ring.append(center + Vector2.from_angle(TAU * i / 48.0) * Vector2(plaza_radius, plaza_radius * 0.78))
	_polygon(ring, null, CURB_SHADE, 1.08)
	_polygon(ring, null, CURB, 1.03)
	_polygon(ring, load(PLAZA_TEX) as Texture2D, PATH_TINT, 1.0)


## Свалка: протоптанная тропа — мягкая тёмная полоса без бордюров (две ширины — размытый край).
func build_trail(color: Color) -> void:
	for line in paths:
		_line(line, width * 1.25, null, Color(color, color.a * 0.5))
		_line(line, width, null, color)


## Плавная дорожка из a в b: кривая Безье с боковым изгибом bend (px).
static func curve(a: Vector2, b: Vector2, bend: float) -> PackedVector2Array:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * bend
	var out := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		out.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return out


## Расстояние от точки до ближайшей дорожки.
func distance_to(p: Vector2) -> float:
	var best := INF
	for line in paths:
		for k in range(1, line.size()):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k])))
	return best


func _line(points: PackedVector2Array, w: float, texture: Texture2D, color: Color, flat_end: bool = false) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = w
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_NONE if flat_end else Line2D.LINE_CAP_ROUND
	if texture != null:
		line.texture = texture
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	add_child(line)


func _polygon(points: PackedVector2Array, texture: Texture2D, color: Color, scale_k: float) -> void:
	var c := Vector2.ZERO
	for p in points:
		c += p
	c /= points.size()
	var poly := Polygon2D.new()
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(c + (p - c) * scale_k)
	poly.polygon = scaled
	poly.color = color
	if texture != null:
		poly.texture = texture
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.uv = scaled
	poly.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	add_child(poly)
