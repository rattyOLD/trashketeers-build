class_name FlatMesh
extends RefCounted
## Статичный рисунок из простых фигур одной сеткой: вместо десятков draw_circle/draw_line (каждый — свой
## вызов отрисовки в Compatibility) копим треугольники с цветом вершин и рисуем одним draw_mesh.
## API повторяет CanvasItem.draw_*: так старый код рисования переносится почти без правок.

var _verts := PackedVector2Array()
var _colors := PackedColorArray()
var _xf := Transform2D.IDENTITY
var _mesh: ArrayMesh


func set_transform(pos: Vector2, rot: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_xf = Transform2D(rot, scale, 0.0, pos)


func reset_transform() -> void:
	_xf = Transform2D.IDENTITY


func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_verts.append(_xf * a)
	_verts.append(_xf * b)
	_verts.append(_xf * c)
	_colors.append(color)
	_colors.append(color)
	_colors.append(color)


func circle(center: Vector2, radius: float, color: Color, segments: int = 16) -> void:
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, segments + 1):
		var p := center + Vector2.from_angle(TAU * i / segments) * radius
		_tri(center, prev, p, color)
		prev = p


func line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	var n := (b - a).orthogonal().normalized() * width * 0.5
	if n == Vector2.ZERO:
		return
	_tri(a - n, a + n, b + n, color)
	_tri(a - n, b + n, b - n, color)


func rect(r: Rect2, color: Color) -> void:
	_tri(r.position, Vector2(r.end.x, r.position.y), r.end, color)
	_tri(r.position, r.end, Vector2(r.position.x, r.end.y), color)


func arc(center: Vector2, radius: float, from: float, to: float, segments: int, color: Color, width: float = 1.0) -> void:
	var prev := center + Vector2.from_angle(from) * radius
	for i in range(1, segments + 1):
		var p := center + Vector2.from_angle(lerpf(from, to, float(i) / segments)) * radius
		line(prev, p, color, width)
		prev = p


## Выпуклый или звёздный относительно первой точки многоугольник (веером).
func polygon(points: PackedVector2Array, color: Color) -> void:
	for i in range(1, points.size() - 1):
		_tri(points[0], points[i], points[i + 1], color)


func is_empty() -> bool:
	return _verts.is_empty()


func commit() -> ArrayMesh:
	if _verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_verts = PackedVector2Array()
	_colors = PackedColorArray()
	return _mesh
