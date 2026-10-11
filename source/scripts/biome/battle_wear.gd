class_name BattleWear
extends Node2D
## Следы остаются до перехода главы. Один атлас и одна сетка, без покадрового обновления.
const CAPACITY := 128
const ATLAS := preload("res://assets/world/battle_wear.png")
var marks: Array[Dictionary] = []
var _next := 0
var _pending := false
var _mesh: ArrayMesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)


func stamp(at: Vector2, kind: int, width: float) -> void:
	if not is_inside_tree() or get_tree().paused:
		return
	# Повторные взрывы в одной точке не забивают весь буфер и не затемняют пол слоями.
	for mark in marks:
		if int(mark["kind"]) == kind and (mark["at"] as Vector2).distance_squared_to(at) < 28.0 * 28.0:
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3(at.x, at.y, _next + marks.size()))
	var entry := {"at": at, "kind": clampi(kind, 0, 3), "width": clampf(width, 36, 180), "angle": rng.randf_range(-0.35, 0.35)}
	if marks.size() < CAPACITY:
		marks.append(entry)
	else:
		marks[_next] = entry
		_next = (_next + 1) % CAPACITY
	if not _pending:
		_pending = true
		_rebuild.call_deferred()


func clear() -> void:
	marks.clear()
	_next = 0
	_mesh = null
	queue_redraw()


func _rebuild() -> void:
	_pending = false
	if marks.is_empty():
		return
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	for mark in marks:
		var half := Vector2(float(mark["width"]) * 0.5, float(mark["width"]) * 0.32)
		var corners := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
		var origin := Vector2(int(mark["kind"]) % 2, int(mark["kind"]) / 2) * 0.5
		var tex_coords := PackedVector2Array([origin, origin + Vector2(0.5, 0), origin + Vector2(0.5, 0.5), origin + Vector2(0, 0.5)])
		for i in [0, 1, 2, 0, 2, 3]:
			vertices.append((mark["at"] as Vector2) + corners[i].rotated(float(mark["angle"])))
			uv.append(tex_coords[i])
			colors.append(Color(0.78, 0.78, 0.78, 0.7 if int(mark["kind"]) == 0 else 0.85))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	queue_redraw()


func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, ATLAS)
