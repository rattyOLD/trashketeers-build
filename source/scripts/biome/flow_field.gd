class_name FlowField
extends RefCounted
## Поле направлений для крыс в лабиринте: BFS от клетки Енота по проходимым клеткам сетки
## (8 соседей, без срезания углов у стен). Считается только в окне radius вокруг Енота
## и не чаще, чем раз в REBUILD_INTERVAL: вне окна крысы бегут напрямую.
## direction_at() — шаг к соседу с меньшей дистанцией, то есть в обход стен.

const NEIGHBORS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const NEIGHBOR_X := [1, -1, 0, 0, 1, 1, -1, -1]
const NEIGHBOR_Y := [0, 0, 1, -1, 1, -1, 1, -1]

var size := Vector2i.ZERO

var _blocked := PackedByteArray()
var _dist := PackedInt32Array()
var _queue := PackedInt32Array()
var _directions := PackedVector2Array()
var _direction_valid := PackedByteArray()


func setup(grid_size: Vector2i, blocked: PackedByteArray) -> void:
	size = grid_size
	_blocked = blocked
	_dist.resize(size.x * size.y)
	_dist.fill(-1)
	_queue.resize(size.x * size.y)
	_directions.resize(size.x * size.y)
	_direction_valid.resize(size.x * size.y)
	_direction_valid.fill(0)


func set_blocked(cell: Vector2i, is_blocked: bool) -> void:
	if _inside(cell):
		var index := _index(cell)
		var value := 1 if is_blocked else 0
		if _blocked[index] != value:
			_blocked[index] = value
			_direction_valid.fill(0)


## Горячий цикл (до ~2800 ячеек × 8 соседей раз в 0.3 с в WebAssembly): индексы считаются
## вручную, без вызовов _inside/_index и без Vector2i-аллокаций на соседа.
func rebuild(target: Vector2i, radius: int) -> void:
	_direction_valid.fill(0)
	_dist.fill(-1)
	if not _inside(target) or _blocked[_index(target)] == 1:
		return
	var w := size.x
	var min_x := maxi(target.x - radius, 0)
	var max_x := mini(target.x + radius, size.x - 1)
	var min_y := maxi(target.y - radius, 0)
	var max_y := mini(target.y + radius, size.y - 1)
	var head := 0
	var tail := 1
	var start := target.y * w + target.x
	_dist[start] = 0
	_queue[0] = start
	while head < tail:
		var current := _queue[head]
		head += 1
		var cx := current % w
		var cy := current / w
		var nd := _dist[current] + 1
		for k in 8:
			var ox: int = NEIGHBOR_X[k]
			var oy: int = NEIGHBOR_Y[k]
			var nx := cx + ox
			var ny := cy + oy
			if nx < min_x or nx > max_x or ny < min_y or ny > max_y:
				continue
			var ni := ny * w + nx
			if _dist[ni] != -1 or _blocked[ni] == 1:
				continue
			if ox != 0 and oy != 0 and (_blocked[cy * w + nx] == 1 or _blocked[ny * w + cx] == 1):
				continue
			_dist[ni] = nd
			_queue[tail] = ni
			tail += 1


## Единичный вектор к соседней клетке ближе к Еноту; ZERO — поле здесь не посчитано.
func direction_at(cell: Vector2i) -> Vector2:
	if not _inside(cell):
		return Vector2.ZERO
	var index := _index(cell)
	if _direction_valid[index] == 0:
		_directions[index] = _direction_uncached(cell)
		_direction_valid[index] = 1
	return _directions[index]


## Между перестроениями поля ответ одинаков для всех врагов в этой клетке.
func _direction_uncached(cell: Vector2i) -> Vector2:
	var here := _dist[_index(cell)]
	if here == -1 and _blocked[_index(cell)] == 1:
		return _escape_direction(cell)
	if here <= 0:
		return Vector2.ZERO
	var best := here
	var best_offset := Vector2i.ZERO
	for offset in NEIGHBORS:
		var next: Vector2i = cell + offset
		if not _inside(next):
			continue
		if offset.x != 0 and offset.y != 0:
			if _blocked[_index(Vector2i(next.x, cell.y))] == 1 or _blocked[_index(Vector2i(cell.x, next.y))] == 1:
				continue
		var d := _dist[_index(next)]
		if d != -1 and d < best:
			best = d
			best_offset = offset
	return Vector2(best_offset).normalized()


## Враг, чей центр заехал в клетку укрытия, выходит к ближайшей посчитанной клетке
## (иначе он бежит напрямую, упирается в проп и застревает).
func _escape_direction(cell: Vector2i) -> Vector2:
	for r in [1, 2]:
		var best := 1 << 30
		var best_offset := Vector2i.ZERO
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				var next := cell + Vector2i(ox, oy)
				if not _inside(next):
					continue
				var d := _dist[_index(next)]
				if d >= 0 and d < best:
					best = d
					best_offset = Vector2i(ox, oy)
		if best_offset != Vector2i.ZERO:
			return Vector2(best_offset).normalized()
	return Vector2.ZERO


func distance_at(cell: Vector2i) -> int:
	return _dist[_index(cell)] if _inside(cell) else -1


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x
