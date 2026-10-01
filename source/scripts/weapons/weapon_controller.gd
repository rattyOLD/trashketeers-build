class_name WeaponController
extends Node2D
## Автоприцел и стрельба игрока. Цель выдаёт target_finder режима (бой / Налёт):
## Callable(from: Vector2, max_distance: float) -> Node2D. Это O(n) по distance_squared
## раз в RETARGET_INTERVAL, а не Area2D-детектор: пулированные враги включаются deferred,
## и Area2D выдавала бы устаревшие цели. Цель обязана иметь метод is_targetable().

signal fired(weapon: WeaponData, origin: Vector2, direction: Vector2)
signal weapon_changed(weapon: WeaponData)
signal slots_changed
signal overdrive_changed(active: bool)
signal overdrive_fired

const MAX_SLOTS := 3
const EQUIP_DELAY := 0.22
const OVERDRIVE_TIME := 4.0
const OVERDRIVE_BASE := 2.5
const OVERDRIVE_STEP := 0.75

const RETARGET_INTERVAL := 0.1
## Стреляем только по тем, кто на экране: за кадром враги не «видны» игроку.
const AUTO_SCREEN_RANGE := 600.0
const MUZZLE_DISTANCE := 44.0
## Ближе этого запаса за дулом цель считается «в упор»: пуля стартует от корпуса,
## иначе она родилась бы уже за спиной крысы и прошла мимо.
const POINT_BLANK_MARGIN := 14.0
const POINT_BLANK_SPAWN := 10.0

var base_weapon: WeaponData
var slots: Array[WeaponData] = [null, null, null]
var active_slot := 0
var slot_count := 2
var weapon: WeaponData
var aim_direction := Vector2.RIGHT
## Ручной прицел: направление от пальца/мыши, пока он зажат; ZERO — работает автоприцел.
var has_target := false
## Callable(direction: Vector2) -> Vector2: глобальная точка дула нарисованного ствола.
var muzzle_provider: Callable

var _target_finder: Callable
var _stats: RunStats
var _cooldown := 0.0
var _overdrive_left := 0.0
var _retarget_timer := 0.0
var _target: Node2D
var _ray: PhysicsRayQueryParameters2D
var _last_pos := Vector2.ZERO
var _still_time := 0.0
var _spin_up := 0.0
## Ближний бой: цикл удара, комбо и оглушение ведёт MeleeFighter.
var melee: MeleeFighter


func _init() -> void:
	melee = MeleeFighter.new()
	add_child(melee)


func setup(target_finder: Callable, start_weapon: WeaponData, stats: RunStats) -> void:
	_target_finder = target_finder
	_stats = stats
	slot_count = Controls.weapon_slot_count()
	slots = [start_weapon, null, null]
	active_slot = 0
	set_base_weapon(start_weapon)
	slots_changed.emit()


func first_empty_slot() -> int:
	for i in slot_count:
		if slots[i] == null:
			return i
	return -1


func set_slot(index: int, new_weapon: WeaponData) -> void:
	slots[index] = new_weapon
	if index == active_slot:
		set_base_weapon(new_weapon)
	slots_changed.emit()


func switch_slot(index: int) -> bool:
	if index < 0 or index >= slot_count or slots[index] == null or index == active_slot:
		return false
	active_slot = index
	set_base_weapon(slots[index])
	_cooldown = maxf(_cooldown, EQUIP_DELAY)
	slots_changed.emit()
	return true


func cycle_slot() -> bool:
	for step in range(1, slot_count):
		var index := (active_slot + step) % slot_count
		if slots[index] != null:
			return switch_slot(index)
	return false


## Рывок заряжает следующий выстрел рельсотрона: он бьёт в разы сильнее и вылетает без ожидания.
func charge_overdrive() -> void:
	if weapon == null or not weapon.dash_charge:
		return
	_overdrive_left = OVERDRIVE_TIME
	_cooldown = 0.0
	overdrive_changed.emit(true)


func set_base_weapon(new_weapon: WeaponData) -> void:
	if new_weapon == null:
		return
	base_weapon = new_weapon
	melee.reset()
	_rebuild()


func apply_run_stats(stats: RunStats) -> void:
	_stats = stats
	_rebuild()


func _rebuild() -> void:
	weapon = base_weapon.with_run_stats(_stats) if _stats != null else base_weapon
	_cooldown = minf(_cooldown, weapon.fire_interval)
	weapon_changed.emit(weapon)


func _physics_process(delta: float) -> void:
	if weapon == null or not _target_finder.is_valid():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	_still_time = _still_time + delta if moved < 30.0 * delta else 0.0
	if _overdrive_left > 0.0:
		_overdrive_left -= delta
		if _overdrive_left <= 0.0:
			overdrive_changed.emit(false)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _is_target_valid():
		_retarget_timer = RETARGET_INTERVAL
		_target = _target_finder.call(global_position, weapon.max_distance)

	if weapon.is_melee():
		_melee_step(delta)
		return

	var auto := _target != null and _is_target_valid() and global_position.distance_squared_to(_target.global_position) <= AUTO_SCREEN_RANGE * AUTO_SCREEN_RANGE
	has_target = auto
	if not auto:
		_spin_up = maxf(_spin_up - delta * 0.8, 0.0)
		return

	var aim_point := _target.global_position
	aim_direction = global_position.direction_to(aim_point)
	if _cooldown > 0.0:
		return
	_cooldown = weapon.fire_interval
	if weapon.trait_id == &"spin":
		_cooldown *= lerpf(1.7, 0.6, _spin_up)
		_spin_up = minf(_spin_up + weapon.fire_interval / 1.8, 1.0)
	var muzzle := global_position + aim_direction * MUZZLE_DISTANCE
	if muzzle_provider.is_valid():
		muzzle = muzzle_provider.call(aim_direction)
	var spawn := muzzle
	var direction := aim_direction
	var target_distance := global_position.distance_to(aim_point)
	if target_distance > global_position.distance_to(muzzle) + POINT_BLANK_MARGIN and not _is_blocked(muzzle):
		direction = muzzle.direction_to(aim_point)
	else:
		spawn = global_position + aim_direction * POINT_BLANK_SPAWN
	var scale := 1.0
	if _overdrive_left > 0.0 and weapon.dash_charge:
		scale = OVERDRIVE_BASE + OVERDRIVE_STEP * (_stats.get_stat(&"rail_overdrive") if _stats != null else 0.0)
		_overdrive_left = 0.0
		overdrive_changed.emit(false)
		overdrive_fired.emit()
	scale *= _trait_scale(target_distance)
	BulletPool.fire(weapon, spawn, direction, Bullet.Team.PLAYER, scale)
	fired.emit(weapon, muzzle, direction)


func _melee_step(delta: float) -> void:
	has_target = _target != null or melee.busy
	melee.tick(delta, weapon, _target, global_position)
	if melee.busy or _target != null:
		aim_direction = melee.direction


func _trait_scale(target_distance: float) -> float:
	match weapon.trait_id:
		&"close":
			return lerpf(1.9, 0.55, clampf(target_distance / weapon.max_distance, 0.0, 1.0))
		&"focus":
			return 0.75 + 1.25 * clampf(_still_time, 0.0, 1.0)
	return 1.0


## Дуло нарисованного ствола может торчать за стену, у которой стоит Енот: тогда пуля
## стартует от корпуса, иначе она родилась бы по ту сторону стены.
func _is_blocked(muzzle: Vector2) -> bool:
	if _ray == null:
		_ray = PhysicsRayQueryParameters2D.new()
		_ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.OBSTACLE
		_ray.collide_with_areas = false
	_ray.from = global_position
	_ray.to = muzzle
	return not get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


func _is_target_valid() -> bool:
	if not is_instance_valid(_target) or not _target.call("is_targetable"):
		return false
	var reach := weapon.max_distance
	return global_position.distance_squared_to(_target.global_position) <= reach * reach
