class_name EnemyManager
extends Node
## Пул врагов на бой. Все экземпляры создаются в setup() до начала геймплея.
## Устройство как у BulletPool: стек свободных + плотный массив активных со swap-remove.
## В отличие от пуль, живого врага при нехватке НЕ переиспользуем:
## внезапно исчезнувший враг — это баг для игрока, поэтому спавн просто пропускается.

signal enemy_died(enemy: Enemy)
signal enemy_damaged(enemy: Enemy, amount: float, is_crit: bool, kind: StringName)
signal enemy_exploded(enemy: Enemy, at: Vector2, radius: float, damage: float)
signal enemy_blocked(enemy: Enemy, at: Vector2)
signal enemy_blinked(enemy: Enemy, from: Vector2, to: Vector2)
signal enemy_fx(enemy: Enemy, kind: String, at: Vector2, radius: float)
signal boss_phase(enemy: Enemy, phase: int)

var _free: Array[Enemy] = []
var _active: Array[Enemy] = []
var _player: Player
## Навигация по полю путей уровня (LevelSpawner.nav_direction); пустой Callable — бег напрямую.
var _nav: Callable


func setup(player: Player, container: Node2D, capacity: int, nav: Callable = Callable()) -> void:
	_player = player
	_nav = nav
	for i in capacity:
		var enemy := Enemy.new()
		enemy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		enemy.died.connect(_on_enemy_died)
		enemy.damaged.connect(_on_enemy_damaged)
		enemy.exploded.connect(_on_enemy_exploded)
		enemy.blocked.connect(func(e: Enemy, at: Vector2) -> void: enemy_blocked.emit(e, at))
		enemy.blinked.connect(func(e: Enemy, a: Vector2, b: Vector2) -> void: enemy_blinked.emit(e, a, b))
		enemy.fx_requested.connect(func(e: Enemy, k: String, at: Vector2, r: float) -> void: enemy_fx.emit(e, k, at, r))
		enemy.boss_phase.connect(func(e: Enemy, ph: int) -> void: boss_phase.emit(e, ph))
		container.add_child(enemy)
		_free.append(enemy)


func spawn(data: EnemyData, at: Vector2, hp_mult: float = 1.0, dmg_mult: float = 1.0) -> Enemy:
	if data == null or _free.is_empty():
		return null
	var enemy: Enemy = _free.pop_back()
	enemy.pool_index = _active.size()
	_active.append(enemy)
	enemy.activate(data, at, hp_mult, dmg_mult)
	var seen_key := "seen_" + String(data.id)
	if SaveService.get_stat(seen_key) == 0:
		SaveService.add_stat(seen_key, 1, false)
	return enemy


func release(enemy: Enemy) -> void:
	if enemy == null or enemy.pool_index < 0:
		return
	var index := enemy.pool_index
	var last: Enemy = _active.pop_back()
	if last != enemy:
		_active[index] = last
		last.pool_index = index
	enemy.pool_index = -1
	enemy.deactivate()
	_free.append(enemy)


func release_all() -> void:
	while not _active.is_empty():
		release(_active.back())


func drop_pooled_visuals() -> void:
	for enemy in _free:
		enemy.drop_visual()


func get_active_count() -> int:
	return _active.size()


func find_nearest(from: Vector2, max_distance: float) -> Enemy:
	var best: Enemy = null
	var best_dist_sq := max_distance * max_distance
	for enemy in _active:
		if not enemy.is_alive():
			continue
		var dist_sq := from.distance_squared_to(enemy.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = enemy
	return best


## Автоприцел с приоритетом угрозы: боссы и дальнобойные/взрывные «кажутся» ближе.
func find_priority(from: Vector2, max_distance: float) -> Enemy:
	var best: Enemy = null
	var best_score := max_distance * max_distance
	for enemy in _active:
		if not enemy.is_alive():
			continue
		var dist_sq := from.distance_squared_to(enemy.global_position)
		if dist_sq > max_distance * max_distance:
			continue
		var weight := 1.0
		match enemy.data.behavior:
			EnemyData.Behavior.BOSS:
				weight = 0.3
			EnemyData.Behavior.RANGED, EnemyData.Behavior.EXPLODER, EnemyData.Behavior.BOMBER, EnemyData.Behavior.TRAPPER:
				weight = 0.55
			EnemyData.Behavior.ASSASSIN:
				weight = 0.7
		var score := dist_sq * weight
		if score < best_score:
			best_score = score
			best = enemy
	return best


const SEPARATION_SPEED := 140.0
const PLAYER_PUSH := 190.0
const FAR_DISTANCE_SQ := 1100.0 * 1100.0
var _frame := 0


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_frame += 1
	var player_pos := _player.global_position
	_compute_separation()
	# Обход с конца по той же причине, что и в BulletPool: смерть врага внутри тика
	# (контакт, отражённый урон) делает swap-remove, и проход вперёд пропустил бы элемент.
	var i := _active.size() - 1
	while i >= 0:
		if i < _active.size():
			var enemy := _active[i]
			if enemy.is_alive():
				if enemy.global_position.distance_squared_to(player_pos) > FAR_DISTANCE_SQ and not enemy.data.is_boss():
					# Далёкие враги думают через кадр с удвоенным шагом: их не видно, а нагрузка падает.
					if (_frame + i) & 1 == 0:
						enemy.tick(delta * 2.0, _player, _nav)
				else:
					enemy.tick(delta, _player, _nav)
		i -= 1


## Расталкивание через сетку ячеек: пара проверяется, только если враги в соседних клетках (раньше —
## все пары, O(n²): при 30+ врагах это заметная доля кадра на слабом телефоне). Крупные враги (боссы,
## танки) с радиусом больше клетки проверяются со всеми, как раньше. Итог тот же, что у полного перебора.
const SEP_CELL := 110.0
var _sep_grid := {}


func _compute_separation() -> void:
	var count := _active.size()
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	positions.resize(count)
	radii.resize(count)
	_sep_grid.clear()
	var big := PackedInt32Array()
	for i in count:
		var e := _active[i]
		e.separation = Vector2.ZERO
		positions[i] = e.global_position
		radii[i] = e.get_radius()
		if radii[i] * 2.3 > SEP_CELL:
			big.append(i)
		var key := Vector2i(floori(positions[i].x / SEP_CELL), floori(positions[i].y / SEP_CELL))
		if _sep_grid.has(key):
			(_sep_grid[key] as PackedInt32Array).append(i)
		else:
			_sep_grid[key] = PackedInt32Array([i])
	var player_pos := _player.global_position
	for i in count:
		var push := Vector2.ZERO
		var pi := positions[i]
		var ri := radii[i]
		var is_big := ri * 2.3 > SEP_CELL
		var cell := Vector2i(floori(pi.x / SEP_CELL), floori(pi.y / SEP_CELL))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var bucket: Variant = _sep_grid.get(cell + Vector2i(dx, dy))
				if bucket == null:
					continue
				for j: int in bucket:
					# Пару считает младший индекс; пары с крупным врагом — отдельным проходом ниже.
					if j <= i or (radii[j] * 2.3 > SEP_CELL) or is_big:
						continue
					push += _sep_pair(i, j, positions, radii)
		if is_big:
			for j in count:
				if j != i and (j > i or radii[j] * 2.3 <= SEP_CELL):
					push += _sep_pair(i, j, positions, radii)
		var to_player := pi - player_pos
		var near := ri + Player.RADIUS
		var pd := to_player.length()
		if pd < near and pd > 0.01 and not _active[i].data.is_boss():
			push += to_player / pd * (1.0 - pd / near) * PLAYER_PUSH
		_active[i].separation += push


## Толчок пары: возвращает силу на i, на j добавляет противоположную.
func _sep_pair(i: int, j: int, positions: PackedVector2Array, radii: PackedFloat32Array) -> Vector2:
	var d := positions[j] - positions[i]
	var reach := (radii[i] + radii[j]) * 1.15
	var dist_sq := d.length_squared()
	if dist_sq >= reach * reach or dist_sq < 0.01:
		return Vector2.ZERO
	var dist := sqrt(dist_sq)
	var force := d / dist * (1.0 - dist / reach) * SEPARATION_SPEED
	_active[j].separation += force
	return -force


func get_active() -> Array[Enemy]:
	return _active


func _on_enemy_damaged(enemy: Enemy, amount: float, is_crit: bool, kind: StringName) -> void:
	enemy_damaged.emit(enemy, amount, is_crit, kind)


## Взрыв обрабатывается отложенно: он наносит урон соседям, а мы можем быть внутри
## take_damage другой крысы (цепная реакция) — так глубина стека не растёт.
func _on_enemy_exploded(enemy: Enemy, at: Vector2, radius: float, damage: float) -> void:
	enemy_exploded.emit.call_deferred(enemy, at, radius, damage)


func _on_enemy_died(enemy: Enemy) -> void:
	enemy_died.emit(enemy)
	release(enemy)
