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


const SEPARATION_SPEED := 140.0
const PLAYER_PUSH := 190.0


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_compute_separation()
	# Обход с конца по той же причине, что и в BulletPool: смерть врага внутри тика
	# (контакт, отражённый урон) делает swap-remove, и проход вперёд пропустил бы элемент.
	var i := _active.size() - 1
	while i >= 0:
		if i < _active.size():
			var enemy := _active[i]
			if enemy.is_alive():
				enemy.tick(delta, _player, _nav)
		i -= 1


## O(n²) по живым врагам (их одновременно ≤ ~60): отталкивание пропорционально перекрытию.
func _compute_separation() -> void:
	var count := _active.size()
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	positions.resize(count)
	radii.resize(count)
	for i in count:
		var e := _active[i]
		e.separation = Vector2.ZERO
		positions[i] = e.global_position
		radii[i] = e.get_radius()
	var player_pos := _player.global_position
	for i in count:
		var push := Vector2.ZERO
		for j in range(i + 1, count):
			var d := positions[j] - positions[i]
			var reach := (radii[i] + radii[j]) * 1.15
			var dist_sq := d.length_squared()
			if dist_sq >= reach * reach or dist_sq < 0.01:
				continue
			var dist := sqrt(dist_sq)
			var force := d / dist * (1.0 - dist / reach) * SEPARATION_SPEED
			push -= force
			_active[j].separation += force
		var to_player := positions[i] - player_pos
		var near := radii[i] + Player.RADIUS
		var pd := to_player.length()
		if pd < near and pd > 0.01 and not _active[i].data.is_boss():
			push += to_player / pd * (1.0 - pd / near) * PLAYER_PUSH
		_active[i].separation += push


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
