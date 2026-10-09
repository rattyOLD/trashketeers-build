class_name WeaponController
extends Node2D
## Стрельба игрока. Стреляет, пока зажат палец на правом стике (или левая кнопка мыши): trigger + manual_aim.
## Подсказка прицела: враг в узком конусе вокруг направления пальца ловится точно. Автострельба (auto_mode)
## осталась только для ботов и тестов. Цель выдаёт target_finder режима (бой / Налёт):
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
var has_target := false
## Зажат ли «курок» и куда целятся (нормаль; ZERO — в последнем направлении).
var trigger := false
var manual_aim := Vector2.ZERO
## Старое автонаведение: только боты и тесты (force_auto включают тестовые сцены).
static var force_auto := false
var auto_mode := false
## Конус подсказки прицела: огнестрел — узкий, ближний бой — шире.
const ASSIST_COS_GUN := 0.97
const ASSIST_COS_MELEE := 0.8
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
	auto_mode = force_auto
	melee = MeleeFighter.new()
	melee.swing_started.connect(_on_swing_for_wave)
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


## Навык героя заряжает следующий выстрел рельсотрона: он бьёт в разы сильнее и вылетает без ожидания.
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

	if weapon.melee_class == "flail":
		_flail_step(delta)
		return
	_hide_flail()
	if weapon.is_melee():
		_melee_step(delta)
		return

	var aim_point := Vector2.ZERO
	if auto_mode:
		var auto := _target != null and _is_target_valid() and global_position.distance_squared_to(_target.global_position) <= AUTO_SCREEN_RANGE * AUTO_SCREEN_RANGE
		has_target = auto
		if not auto:
			_spin_up = maxf(_spin_up - delta * 0.8, 0.0)
			return
		aim_point = _target.global_position
	else:
		has_target = trigger
		if not trigger:
			_spin_up = maxf(_spin_up - delta * 0.8, 0.0)
			return
		var dir := manual_aim if manual_aim.length_squared() > 0.01 else aim_direction
		var helped := _assist_target(dir, ASSIST_COS_GUN, minf(weapon.max_distance, AUTO_SCREEN_RANGE))
		aim_point = helped.global_position if helped != null else global_position + dir * weapon.max_distance
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


## Фаза 2, «Летящий слайс»: каждый 3-й взмах выпускает серп (рисунок дуги оружия) — 60% урона за ранг,
## пробивает толпу, летит на ~3 дальности удара.
var _wave_count := 0
var _wave_weapon: WeaponData
var _wave_source: WeaponData


func _on_swing_for_wave(w: WeaponData, origin: Vector2, direction: Vector2, _combo: int, _heavy: bool, _side: float) -> void:
	var rank := _stats.get_stat(&"melee_wave") if _stats != null else 0.0
	if rank <= 0.0:
		return
	_wave_count += 1
	if _wave_count % 3 != 0:
		return
	if _wave_source != w or _wave_weapon == null:
		_wave_source = w
		_wave_weapon = w.duplicate_data()
		_wave_weapon.bullet_texture = WeaponVfx.slash_for(w)
		_wave_weapon.bullet_speed = 640.0
		_wave_weapon.bullet_radius = 30.0
		_wave_weapon.bullet_lifetime = 1.2
		_wave_weapon.piercing = true
		_wave_weapon.ricochet_count = 0
		_wave_weapon.projectiles_per_shot = 1
		_wave_weapon.explosion_radius = 0.0
		_wave_weapon.trail_points = 0
		_wave_weapon.bullet_modulate = Color.WHITE
		_wave_weapon.fire_sound = &""
		var tex_w := float(_wave_weapon.bullet_texture.get_width()) if _wave_weapon.bullet_texture != null else 160.0
		# Рисунок дуги смотрит «назад» (-x): отражаем, чтобы серп летел выпуклостью вперёд.
		_wave_weapon.sprite_scale = Vector2(-1.0, 1.0) * (90.0 / maxf(tex_w, 1.0))
	_wave_weapon.damage = w.damage * 0.6 * rank
	_wave_weapon.max_distance = w.melee_reach * 3.0
	var bullet := BulletPool.spawn(_wave_weapon, origin + direction * 30.0, direction, Bullet.Team.PLAYER)
	if bullet != null:
		bullet.damage_scale = 1.0


## Моргенштерн: шар на цепи (FlailRig). Стик прицела раскручивает шар, в авторежиме он крутится сам;
## попадания идут через melee.hit_resolved — работают хитстоп, тряска и «Кровопийца».
var flail: FlailRig


func _flail_step(delta: float) -> void:
	if flail == null:
		flail = FlailRig.new()
		add_child(flail)
		flail.ball_hit.connect(func(at: Vector2, count: int, strong: bool) -> void:
			melee.hit_resolved.emit(weapon, at, count, false, strong))
	flail.visible = true
	var player := get_parent() as Player
	var at := global_position
	if player != null and player.visual != null:
		at = player.visual.get_muzzle_global(aim_direction)
	var control := manual_aim if not auto_mode and trigger else Vector2.ZERO
	flail.tick(delta, at, control, auto_mode, weapon)
	has_target = true
	var to_ball := flail.ball - global_position
	if to_ball.length_squared() > 1.0:
		aim_direction = to_ball.normalized()
	if player != null:
		player.flail_pull = flail.pull


func _hide_flail() -> void:
	if flail == null or not flail.visible:
		return
	flail.visible = false
	flail._ready_ball = false
	var player := get_parent() as Player
	if player != null:
		player.flail_pull = Vector2.ZERO


func _melee_step(delta: float) -> void:
	if auto_mode:
		has_target = _target != null or melee.busy
		melee.tick(delta, weapon, _target, global_position)
		if melee.busy or _target != null:
			aim_direction = melee.direction
		return
	has_target = trigger or melee.busy
	var dir := manual_aim if manual_aim.length_squared() > 0.01 else aim_direction
	var target: Node2D = _assist_target(dir, ASSIST_COS_MELEE, weapon.max_distance) if trigger else null
	melee.tick(delta, weapon, target, global_position, dir if trigger else Vector2.ZERO)
	if melee.busy or trigger:
		aim_direction = melee.direction if melee.busy else dir


## Ближайшая к прицелу цель в конусе: ловит врага, если палец смотрит почти на него.
func _assist_target(dir: Vector2, min_cos: float, max_distance: float) -> Node2D:
	if _target == null or not _is_target_valid():
		return null
	var to := _target.global_position - global_position
	if to.length_squared() > max_distance * max_distance or to.length_squared() < 1.0:
		return null
	return _target if to.normalized().dot(dir) >= min_cos else null


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
