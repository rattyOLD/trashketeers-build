class_name PolyBatch
extends RefCounted
## Заливки из _draw одним вызовом отрисовки. Рендерер Compatibility рисует каждый draw_circle /
## draw_colored_polygon / draw_polyline / draw_arc отдельным draw call (полигоны не батчатся),
## а WebGL на телефоне платит за каждый вызов. Здесь те же фигуры собираются в один массив
## треугольников с той же геометрией, что строит движок (renderer_canvas_cull.cpp 4.4: круг —
## 64 сегмента, полилиния — лента с бисектрисами и перьями сглаживания), и уходят в
## canvas_item_add_triangle_array. Порядок треугольников = порядок вызовов, поэтому наложение
## полупрозрачных фигур не меняется.
## Пока батч не сброшен (flush), между фигурами нельзя рисовать другое (текстуры, текст) —
## перед ними flush. Трансформ задаётся set_transform батча, а у самого CanvasItem на момент
## flush должен стоять единичный.

const CIRCLE_SEGMENTS := 64
const FEATHER := 1.25

static var _unit_circle := PackedVector2Array()
static var _shapes := {}
static var _f32_cell := PackedFloat32Array([0.0])

var points := PackedVector2Array()
var colors := PackedColorArray()
var xform := Transform2D.IDENTITY
var _fill := PackedColorArray()
var _strip := PackedVector2Array()
var _strip_colors := PackedColorArray()


## Как CanvasItem.draw_set_transform: поворот, затем масштаб по осям экрана (scale_basis).
func set_transform(position: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	var t := Transform2D(rotation, position)
	t.x = Vector2(t.x.x * scale.x, t.x.y * scale.y)
	t.y = Vector2(t.y.x * scale.x, t.y.y * scale.y)
	xform = t


func reset_transform() -> void:
	xform = Transform2D.IDENTITY


func is_empty() -> bool:
	return points.is_empty()


func flush(canvas: CanvasItem) -> void:
	if not points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), PackedInt32Array(), points, colors)
	points.clear()
	colors.clear()


## draw_circle(pos, radius, color) без сглаживания.
func circle(pos: Vector2, radius: float, color: Color) -> void:
	if _unit_circle.is_empty():
		_build_unit_circle()
	_append(xform * Transform2D(Vector2(radius, 0.0), Vector2(0.0, radius), pos) * _unit_circle, color)


## draw_colored_polygon(polygon, color).
func polygon(polygon_points: PackedVector2Array, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon_points)
	if indices.is_empty():
		return
	var placed := xform * polygon_points
	var start := points.size()
	points.resize(start + indices.size())
	for i in indices.size():
		points[start + i] = placed[indices[i]]
	_append_color(color, indices.size())


## Тот же контур в другом масштабе и месте: триангуляция строится один раз на key.
## Заливка простого многоугольника не зависит от выбора триангуляции — пиксели те же.
func polygon_cached(key: Variant, shape: PackedVector2Array, scale: float, offset: Vector2, color: Color) -> void:
	var tris: PackedVector2Array = _shapes.get(key, PackedVector2Array())
	if tris.is_empty():
		var indices := Geometry2D.triangulate_polygon(shape)
		if indices.is_empty():
			return
		tris.resize(indices.size())
		for i in indices.size():
			tris[i] = shape[indices[i]]
		_shapes[key] = tris
	_append(xform * Transform2D(Vector2(scale, 0.0), Vector2(0.0, scale), offset) * tris, color)


## draw_rect(rect, color) с заливкой, без сглаживания.
func rect(area: Rect2, color: Color) -> void:
	var r := area.abs()
	var p := r.position
	var e := r.end
	var quad := PackedVector2Array([p, Vector2(e.x, p.y), e, p, e, Vector2(p.x, e.y)])
	_append(xform * quad, color)


## draw_line(from, to, color, width, antialiased) при width >= 0: квад из двух треугольников,
## со сглаживанием — ещё четыре пера по краям (как canvas_item_add_line).
func line(from: Vector2, to: Vector2, color: Color, width: float, antialiased: bool = false) -> void:
	var diff := from - to
	var dir := diff.orthogonal().normalized()
	var t := dir * width * 0.5
	var bl := from + t
	var br := from - t
	var er := to - t
	var el := to + t
	_append(xform * PackedVector2Array([bl, br, er, bl, er, el]), color)
	if not antialiased:
		return
	var border_size := FEATHER * (width if width < 1.0 else 1.0)
	var border := dir * border_size
	var border2 := diff.normalized() * border_size
	_feather(bl, bl + border, el + border, el, color)
	_feather(br, br - border, er - border, er, color)
	_feather(bl, bl + border2, br + border2, br, color)
	_feather(el, el - border2, er - border2, er, color)
	_feather(bl, bl + border2, bl + border + border2, bl + border, color, true)
	_feather(br, br + border2, br - border + border2, br - border, color, true)
	_feather(el, el - border2, el + border - border2, el + border, color, true)
	_feather(er, er - border2, er - border - border2, er - border, color, true)


## Перо сглаживания: квад p0..p3, цвет на p0 и p3 (у углового пера — только на p0), остальное прозрачно.
func _feather(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Color, corner: bool = false) -> void:
	var clear := Color(color, 0.0)
	var start := points.size()
	points.append_array(xform * PackedVector2Array([p0, p1, p2, p0, p2, p3]))
	colors.resize(start + 6)
	colors[start] = color
	colors[start + 1] = clear
	colors[start + 2] = clear
	colors[start + 3] = color
	colors[start + 4] = clear
	colors[start + 5] = clear if corner else color


## draw_arc — точки дуги как в CanvasItem::draw_arc, в float32 движка: от этого зависит, замкнёт ли
## polyline полный круг (у больших радиусов последняя точка не совпадает с первой — шов с перьями).
func arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, color: Color, width: float, antialiased: bool = false) -> void:
	var arc_points := PackedVector2Array()
	arc_points.resize(point_count)
	var start := _f32(start_angle)
	var tau := _f32(TAU)
	var delta_angle := clampf(_f32(_f32(end_angle) - start), -tau, tau)
	var denominator := _f32(point_count - 1.0)
	for i in point_count:
		var theta := _f32(_f32(_f32(i / denominator) * delta_angle) + start)
		arc_points[i] = center + Vector2(cos(theta), sin(theta)) * radius
	polyline(arc_points, color, width, antialiased)


## draw_polyline(points, color, width, antialiased) при width >= 0.
func polyline(line_points: PackedVector2Array, color: Color, width: float, antialiased: bool = false) -> void:
	var count := line_points.size()
	if count < 2:
		return
	var loop := line_points[0].is_equal_approx(line_points[count - 1])
	var first_dir := Vector2.ZERO
	for i in range(1, count):
		first_dir = (line_points[i] - line_points[i - 1]).normalized()
		if not first_dir.is_zero_approx():
			break
	var last_dir := Vector2.ZERO
	for i in range(count - 1, 0, -1):
		last_dir = (line_points[i] - line_points[i - 1]).normalized()
		if not last_dir.is_zero_approx():
			break
	var clear := Color(color, 0.0)
	var pair_count := count * 2
	var extra := 4 if antialiased and not loop else 0
	var middle := PackedVector2Array()
	middle.resize(pair_count + extra)
	var middle_colors := PackedColorArray()
	middle_colors.resize(pair_count + extra)
	middle_colors.fill(color)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var side_colors := PackedColorArray()
	var border_size := FEATHER * (width if width < 1.0 else 1.0)
	if antialiased:
		var side_count := pair_count + (0 if loop else 5)
		left.resize(side_count)
		right.resize(side_count)
		side_colors.resize(side_count)
	var prev_dir := Vector2.ZERO
	for i in count:
		var is_first := i == 0
		var is_last := i == count - 1
		var dir := _segment_dir(line_points, i, prev_dir)
		if is_first and loop:
			prev_dir = last_dir
		elif is_last and loop:
			prev_dir = first_dir
		var base_offset: Vector2
		if is_first and not loop:
			base_offset = first_dir.orthogonal()
		elif is_last and not loop:
			base_offset = last_dir.orthogonal()
		else:
			base_offset = _edge_offset(dir, prev_dir)
		var edge := base_offset * (width * 0.5)
		var pos := line_points[i]
		if not antialiased:
			middle[i * 2] = pos + edge
			middle[i * 2 + 1] = pos - edge
			prev_dir = dir
			continue
		var border := base_offset * border_size
		var j := i * 2 + (0 if loop else 2)
		middle[j] = pos + edge
		middle[j + 1] = pos - edge
		left[j] = pos + edge
		left[j + 1] = pos + edge + border
		right[j] = pos - edge
		right[j + 1] = pos - edge - border
		side_colors[j] = color
		side_colors[j + 1] = clear
		if is_first and not loop:
			var begin := -dir * border_size
			middle[0] = pos + edge + begin
			middle[1] = pos - edge + begin
			middle_colors[0] = clear
			middle_colors[1] = clear
			left[0] = pos + edge + begin
			left[1] = pos + edge + begin + border
			right[0] = pos - edge + begin
			right[1] = pos - edge + begin - border
			side_colors[0] = clear
			side_colors[1] = clear
		if is_last and not loop:
			var end := prev_dir * border_size
			var e := pair_count + 2
			middle[e] = pos + edge + end
			middle[e + 1] = pos - edge + end
			middle_colors[e] = clear
			middle_colors[e + 1] = clear
			left[e] = pos + edge
			left[e + 1] = pos + edge + end + border
			left[e + 2] = pos + edge + end
			right[e] = pos - edge
			right[e + 1] = pos - edge + end - border
			right[e + 2] = pos - edge + end
			side_colors[e] = color
			side_colors[e + 1] = clear
			side_colors[e + 2] = clear
		prev_dir = dir
	_append_strip(middle, middle_colors)
	if antialiased:
		_append_strip(left, side_colors)
		_append_strip(right, side_colors)


static func _segment_dir(line_points: PackedVector2Array, index: int, prev_dir: Vector2) -> Vector2:
	if index == line_points.size() - 1:
		return prev_dir
	var dir := (line_points[index + 1] - line_points[index]).normalized()
	return prev_dir if dir.is_zero_approx() else dir


static func _edge_offset(dir: Vector2, prev_dir: Vector2) -> Vector2:
	var length := 1.0
	var bisector := (prev_dir * dir.length() - dir * prev_dir.length()).normalized()
	var angle := atan2(bisector.cross(prev_dir), bisector.dot(prev_dir))
	var sin_angle := sin(angle)
	if not is_zero_approx(sin_angle) and not dir.is_equal_approx(prev_dir):
		length = clampf(1.0 / sin_angle, -3.0, 3.0)
	else:
		bisector = dir.orthogonal()
	if bisector.is_zero_approx():
		bisector = dir.orthogonal()
	return bisector * length


## Лента треугольников (strip) → список: треугольник k = вершины k, k+1, k+2.
func _append_strip(strip: PackedVector2Array, strip_colors: PackedColorArray) -> void:
	var tri_count := strip.size() - 2
	if tri_count <= 0:
		return
	var placed := xform * strip
	var start := points.size()
	points.resize(start + tri_count * 3)
	colors.resize(start + tri_count * 3)
	for k in tri_count:
		var o := start + k * 3
		points[o] = placed[k]
		points[o + 1] = placed[k + 1]
		points[o + 2] = placed[k + 2]
		colors[o] = strip_colors[k]
		colors[o + 1] = strip_colors[k + 1]
		colors[o + 2] = strip_colors[k + 2]


func _append(placed: PackedVector2Array, color: Color) -> void:
	points.append_array(placed)
	_append_color(color, placed.size())


func _append_color(color: Color, count: int) -> void:
	if _fill.size() != count:
		_fill.resize(count)
	_fill.fill(color)
	colors.append_array(_fill)


## Как canvas_item_add_circle: веер (центр, i, i + 1), углы i·TAU/64 в float32.
static func _build_unit_circle() -> void:
	var step := _f32(_f32(TAU) / CIRCLE_SEGMENTS)
	var rim := PackedVector2Array()
	rim.resize(CIRCLE_SEGMENTS + 1)
	for i in CIRCLE_SEGMENTS + 1:
		var angle := _f32(i * step)
		rim[i] = Vector2(cos(angle), sin(angle))
	_unit_circle.resize(CIRCLE_SEGMENTS * 3)
	for i in CIRCLE_SEGMENTS:
		_unit_circle[i * 3] = Vector2.ZERO
		_unit_circle[i * 3 + 1] = rim[i]
		_unit_circle[i * 3 + 2] = rim[i + 1]


## Округление до float32 (real_t движка): скаляры GDScript — double.
static func _f32(value: float) -> float:
	_f32_cell[0] = value
	return _f32_cell[0]
