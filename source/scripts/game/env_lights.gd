class_name EnvLights
extends RefCounted
## Реестр источников света мира (бочки с огнём, фонари, терминалы, неон, кислота, вспышки).
## Пол освещают дешёвые аддитивные «пятна» (GroundGlow) и PointLight2D только на слой пола,
## а персонажей — этот реестр: sample(pos) складывает цвет ближайших источников с затуханием,
## и шейдер рига умножает на него цвет енота/крысы. У костра енот тёплый, у неоновой вывески —
## розовый, в темноте — тусклый. Пространственный хэш по клеткам CELL: выборка — 3×3 клетки.

const CELL := 320.0
const MAX_RADIUS := 320.0
const FLASH_CAPACITY := 12
## id = индекс + поколение × ID_STRIDE: пятна прошлой сцены (меню), уходящие из дерева после
## clear(), не должны снять чужой источник с тем же индексом.
const ID_STRIDE := 1 << 20

static var _pos := PackedVector2Array()
static var _color := PackedColorArray()
static var _radius := PackedFloat32Array()
static var _nodes: Array = []
static var _grid: Dictionary = {}
static var _free: Array[int] = []
static var _flash_pos := PackedVector2Array()
static var _flash_color := PackedColorArray()
static var _flash_radius := PackedFloat32Array()
static var _flash_life := PackedFloat32Array()
static var _flash_total := PackedFloat32Array()
static var _flash_next := 0
static var _generation := 1


static func clear() -> void:
	_generation += 1
	_pos.clear()
	_color.clear()
	_radius.clear()
	_nodes.clear()
	_grid.clear()
	_free.clear()
	_flash_pos.resize(FLASH_CAPACITY)
	_flash_color.resize(FLASH_CAPACITY)
	_flash_radius.resize(FLASH_CAPACITY)
	_flash_life.resize(FLASH_CAPACITY)
	_flash_total.resize(FLASH_CAPACITY)
	_flash_life.fill(0.0)


## Постоянный источник. node (необязательно) — чей modulate.a задаёт мерцание.
static func add(at: Vector2, color: Color, radius: float, strength: float, node: CanvasItem = null) -> int:
	var id: int
	var c := Color(color.r * strength, color.g * strength, color.b * strength, 1.0)
	if _free.is_empty():
		id = _pos.size()
		_pos.append(at)
		_color.append(c)
		_radius.append(minf(radius, MAX_RADIUS))
		_nodes.append(node)
	else:
		id = _free.pop_back()
		_pos[id] = at
		_color[id] = c
		_radius[id] = minf(radius, MAX_RADIUS)
		_nodes[id] = node
	var key := _key(at)
	if not _grid.has(key):
		_grid[key] = PackedInt32Array()
	var bucket: PackedInt32Array = _grid[key]
	bucket.append(id)
	_grid[key] = bucket
	return id + _generation * ID_STRIDE


static func remove(handle: int) -> void:
	if handle < 0 or handle / ID_STRIDE != _generation:
		return
	var id := handle % ID_STRIDE
	if id >= _pos.size() or _radius[id] <= 0.0:
		return
	var key := _key(_pos[id])
	if _grid.has(key):
		var list: PackedInt32Array = _grid[key]
		var index := list.find(id)
		if index >= 0:
			list.remove_at(index)
			_grid[key] = list
	_radius[id] = 0.0
	_nodes[id] = null
	_free.append(id)


## Кратковременная вспышка (выстрел, взрыв): гаснет за life секунд.
static func flash(at: Vector2, color: Color, radius: float, strength: float, life: float) -> void:
	if _flash_life.size() < FLASH_CAPACITY:
		clear()
	var k := _flash_next
	_flash_next = (_flash_next + 1) % FLASH_CAPACITY
	_flash_pos[k] = at
	_flash_color[k] = Color(color.r * strength, color.g * strength, color.b * strength, 1.0)
	_flash_radius[k] = radius
	_flash_life[k] = life
	_flash_total[k] = life


static func tick(delta: float) -> void:
	for k in _flash_life.size():
		if _flash_life[k] > 0.0:
			_flash_life[k] = maxf(_flash_life[k] - delta, 0.0)


## Суммарный свет в точке (RGB, 0 — темно). Мягкий квадратичный спад к краю радиуса.
static func sample(at: Vector2) -> Color:
	var sum := Color(0, 0, 0, 1)
	var center := _key(at)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := center + Vector2i(dx, dy)
			if not _grid.has(key):
				continue
			for id in (_grid[key] as PackedInt32Array):
				var r := _radius[id]
				var d := at.distance_to(_pos[id])
				if d >= r:
					continue
				var f := 1.0 - d / r
				f *= f
				var node: CanvasItem = _nodes[id]
				if node != null and is_instance_valid(node):
					f *= (node as Light2D).energy if node is Light2D else node.modulate.a
					if not node.is_visible_in_tree():
						f = 0.0
				sum += _color[id] * f
	for k in _flash_life.size():
		if _flash_life[k] <= 0.0:
			continue
		var d := at.distance_to(_flash_pos[k])
		if d >= _flash_radius[k]:
			continue
		var f := (1.0 - d / _flash_radius[k]) * (_flash_life[k] / _flash_total[k])
		sum += _flash_color[k] * f
	return Color(minf(sum.r, 1.2), minf(sum.g, 1.2), minf(sum.b, 1.2), 1.0)


## Источники в прямоугольнике view (с мерцанием и вспышками) — для карты освещения (LightMap).
static func collect(view: Rect2, out_pos: PackedVector2Array, out_color: PackedColorArray, out_radius: PackedFloat32Array) -> void:
	out_pos.clear()
	out_color.clear()
	out_radius.clear()
	for id in _pos.size():
		var r := _radius[id]
		if r <= 0.0 or not view.grow(r).has_point(_pos[id]):
			continue
		var f := 1.0
		var node: CanvasItem = _nodes[id]
		if node != null and is_instance_valid(node):
			if not node.is_visible_in_tree():
				continue
			f = (node as Light2D).energy if node is Light2D else node.modulate.a
		out_pos.append(_pos[id])
		out_color.append(_color[id] * f)
		out_radius.append(r)
	for k in _flash_life.size():
		if _flash_life[k] <= 0.0 or not view.grow(_flash_radius[k]).has_point(_flash_pos[k]):
			continue
		out_pos.append(_flash_pos[k])
		out_color.append(_flash_color[k] * (_flash_life[k] / _flash_total[k]))
		out_radius.append(_flash_radius[k])


static func _key(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))
