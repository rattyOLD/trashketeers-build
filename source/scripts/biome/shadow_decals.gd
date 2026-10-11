class_name ShadowDecals
extends Node2D
## Контактная и падающая тень неподвижных объектов. Одна статичная сетка на сектор.
const COLOR := Color(0.015, 0.02, 0.025)
var _rects: Array[Rect2] = []
var _heights := PackedFloat32Array()
var _circles := PackedVector3Array()
var _rect_active := PackedByteArray()
var _circle_active := PackedByteArray()
var _mesh: ArrayMesh
var _dirty := true
var _layers := 4


func _ready() -> void:
	_layers = 2 if SaveService.get_quality() == 0 else 4


func add_rect(rect: Rect2, height: float, owner: Node2D = null) -> void:
	var index := _rects.size()
	_rects.append(rect)
	_heights.append(height)
	_rect_active.append(1)
	if owner != null:
		owner.tree_exiting.connect(_remove_rect.bind(index), CONNECT_ONE_SHOT)
	_dirty = true
	queue_redraw()


func add_circle(center: Vector2, radius: float, height: float, owner: Node2D = null) -> void:
	var index := _circles.size()
	_circles.append(Vector3(center.x + height * 0.22, center.y + height * 0.14, radius))
	_circle_active.append(1)
	if owner != null:
		owner.tree_exiting.connect(_remove_circle.bind(index), CONNECT_ONE_SHOT)
	_dirty = true
	queue_redraw()


func _remove_rect(index: int) -> void:
	_rect_active[index] = 0
	_dirty = true
	queue_redraw()


func _remove_circle(index: int) -> void:
	_circle_active[index] = 0
	_dirty = true
	queue_redraw()


func _bake() -> void:
	var mesh := FlatMesh.new()
	for i in _rects.size():
		if _rect_active[i] == 0:
			continue
		var r := _rects[i]
		var h := _heights[i]
		var shift := Vector2(h * 0.24, h * 0.18)
		for k in _layers:
			mesh.rect(Rect2(r.position + shift, r.size + Vector2(h * 0.08, h * 0.16)).grow(3 + k * 5), Color(COLOR, 0.21 / _layers))
		mesh.set_transform(r.get_center(), 0, Vector2(1, 0.5))
		mesh.circle(Vector2.ZERO, maxf(r.size.x * 0.54, 8), Color(COLOR, 0.20), 16)
		mesh.reset_transform()
	for i in _circles.size():
		if _circle_active[i] == 0:
			continue
		var c := _circles[i]
		mesh.set_transform(Vector2(c.x, c.y), 0, Vector2(1, 0.62))
		for k in _layers:
			mesh.circle(Vector2.ZERO, c.z + 3 + k * 5, Color(COLOR, 0.25 / _layers), 16)
		mesh.circle(Vector2.ZERO, c.z * 0.86, Color(COLOR, 0.16), 16)
		mesh.reset_transform()
	_mesh = mesh.commit()
	_dirty = false


func _draw() -> void:
	if _dirty:
		_bake()
	if _mesh != null:
		draw_mesh(_mesh, null)
