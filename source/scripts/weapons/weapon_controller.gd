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
signal slot_switched(previous: int, current: int)
signal melee_contact(enemy: Enemy, damage: float)
signal slots_changed
signal overdrive_changed(active: bool)
signal overdrive_fired

const MAX_SLOTS := 3
const EQUIP_DELAY := 0.22
const OVERDRIVE_TIME := 4.0
const OVERDRIVE_BASE := 2.5
const OVERDRIVE_STEP := 0.75
const SPIN_UP_SECONDS := 2.0
const SPIN_DOWN_PER_SECOND := 0.8

const RETARGET_INTERVAL := 0.1
const ASSIST_REACQUIRE_COS := 0.995
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
## Shared with AimLine: the actual projectile origin/direction, including muzzle parallax.
var shot_origin := Vector2.INF
var shot_direction := Vector2.RIGHT
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
## Optional manual finder(from, range, direction, cosine, clear_path).
var aim_target_finder: Callable

var _target_finder: Callable
var _stats: RunStats
var _cooldown := 0.0
## Каждый слот восстанавливается отдельно, в том числе пока оружие убрано.
var _slot_cooldowns := PackedFloat32Array([0.0, 0.0, 0.0])
var _equip_left := 0.0
var _overdrive_left := 0.0
var _retarget_timer := 0.0
var _target: Node2D
var _ray: PhysicsRayQueryParameters2D
var _aim_ray: PhysicsRayQueryParameters2D
var _using_manual_finder := false
var _last_manual_dir := Vector2.ZERO
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
	_cooldown = 0.0
	_slot_cooldowns.fill(0.0)
	_equip_left = 0.0
	set_base_weapon(start_weapon)
	slots_changed.emit()


func first_empty_slot() -> int:
	for i in slot_count:
		if slots[i] == null:
			return i
	return -1


func set_slot(index: int, new_weapon: WeaponData) -> void:
	if index < 0 or index >= slot_count or new_weapon == null:
		return
	if slots[index] != new_weapon:
		_slot_cooldowns[index] = 0.0
		if index == active_slot:
			_cooldown = 0.0
			_equip_left = EQUIP_DELAY
	slots[index] = new_weapon
	if index == active_slot:
		set_base_weapon(new_weapon)
	slots_changed.emit()


func switch_slot(index: int) -> bool:
	if index < 0 or index >= slot_count or slots[index] == null or index == active_slot:
		return false
	var previous := active_slot
	_slot_cooldowns[previous] = _cooldown
	active_slot = index
	set_base_weapon(slots[index])
	_cooldown = _slot_cooldowns[index]
	_equip_left = EQUIP_DELAY
	slots_changed.emit()
	slot_switched.emit(previous, index)
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
	_spin_up = 0.0
	_still_time = 0.0
	_last_pos = global_position
	_target = null
	_retarget_timer = 0.0
	_using_manual_finder = false
	_last_manual_dir = Vector2.ZERO
	shot_origin = Vector2.INF
	melee.reset()
	_rebuild()


func apply_run_stats(stats: RunStats) -> void:
	_stats = stats
	_rebuild()


func _rebuild() -> void:
	weapon = base_weapon.with_run_stats(_stats) if _stats != null else base_weapon
	if _stats != null and _stats.switch_boost_left > 0.0:
		weapon.damage *= CombatTactics.swap_damage_multiplier(CombatTactics.rank(_stats, "switcher"))
	weapon_changed.emit(weapon)


func _physics_process(delta: float) -> void:
	if weapon == null or not _target_finder.is_valid():
		return
	# Сохраняем остаток шага только для продолжающейся стрельбы, без долга за простой.
	var overdue := minf(maxf(delta - _cooldown, 0.0), delta) if _cooldown > 0.0 else 0.0
	_cooldown = maxf(_cooldown - delta, 0.0)
	_equip_left = maxf(_equip_left - delta, 0.0)
	for index in slot_count:
		if index != active_slot:
			_slot_cooldowns[index] = maxf(_slot_cooldowns[index] - delta, 0.0)
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	_still_time = _still_time + delta if moved < 30.0 * delta else 0.0
	if _overdrive_left > 0.0:
		_overdrive_left -= delta
		if _overdrive_left <= 0.0:
			overdrive_changed.emit(false)
	_retarget_timer -= delta
	var manual_dir := (manual_aim if manual_aim.length_squared() > 0.01 else aim_direction).normalized()
	var directed := not auto_mode and trigger and weapon.melee_class != "flail" and aim_target_finder.is_valid()
	var turned := directed and manual_dir.dot(_last_manual_dir) < ASSIST_REACQUIRE_COS
	if _retarget_timer <= 0.0 or (_target != null and not _is_target_valid()) or directed != _using_manual_finder or turned:
		_retarget_timer = RETARGET_INTERVAL
		_using_manual_finder = directed
		_last_manual_dir = manual_dir
		if directed:
			var cone := ASSIST_COS_MELEE if weapon.is_melee() else ASSIST_COS_GUN
			_target = aim_target_finder.call(global_position, minf(weapon.max_distance, AUTO_SCREEN_RANGE), manual_dir, cone, _can_aim_at)
		else:
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
		var auto := _target != null and _is_target_valid() and global_position.distance_squared_to(AimAssist.point(_target)) <= AUTO_SCREEN_RANGE * AUTO_SCREEN_RANGE
		has_target = auto
		if not auto:
			_tick_spin(delta, false)
			return
		aim_point = AimAssist.point(_target)
	else:
		has_target = trigger
		if not trigger:
			_tick_spin(delta, false)
			return
		var dir := manual_dir
		var helped := _assist_target(dir, ASSIST_COS_GUN, minf(weapon.max_distance, AUTO_SCREEN_RANGE))
		aim_point = AimAssist.point(helped) if helped != null else global_position + dir * weapon.max_distance
	aim_direction = global_position.direction_to(aim_point)
	_tick_spin(delta, has_target)
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
	shot_origin = spawn
	shot_direction = direction
	if _cooldown > 0.0 or _equip_left > 0.0:
		return
	_cooldown = weapon.fire_interval
	if weapon.trait_id == &"spin":
		_cooldown *= lerpf(1.7, 0.6, _spin_up)
	# Раскрутка не должна обходить бюджет, уже учтённый в with_run_stats.
	var requested_interval := _cooldown
	_cooldown = maxf(_cooldown, maxf(float(weapon.projectiles_per_shot) / WeaponData.BULLET_BUDGET_PER_SEC, delta))
	var rate_scale := _cooldown / requested_interval
	_cooldown = maxf(_cooldown - overdue, 0.0)
	var scale := rate_scale
	if _overdrive_left > 0.0 and weapon.dash_charge:
		scale *= OVERDRIVE_BASE + OVERDRIVE_STEP * (_stats.get_stat(&"rail_overdrive") if _stats != null else 0.0)
		_overdrive_left = 0.0
		overdrive_changed.emit(false)
		overdrive_fired.emit()
	scale *= _trait_scale(target_distance)
	BulletPool.fire(weapon, spawn, direction, Bullet.Team.PLAYER, scale, global_position)
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
		# Арт Астры (фаза 2): летящий серп — кадр из листа flying_slash (6×192×96, вправо).
		var serp := PhaseFx.frame("flying_slash", 3, Vector2(192, 96))
		_wave_weapon.bullet_texture = serp if serp != null else WeaponVfx.slash_for(w)
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
		_wave_weapon.sprite_scale = (Vector2(1.0, 1.0) * (120.0 / maxf(tex_w, 1.0))) if serp != null else Vector2(-1.0, 1.0) * (90.0 / maxf(tex_w, 1.0))
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
		flail.enemy_hit.connect(func(enemy: Enemy, damage: float) -> void: melee_contact.emit(enemy, damage))
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
	var to := AimAssist.point(_target) - global_position
	if to.length_squared() > max_distance * max_distance or to.length_squared() < 1.0:
		return null
	if to.normalized().dot(dir.normalized()) < min_cos:
		return null
	return _target if _using_manual_finder or _can_aim_at(_target) else null


func _tick_spin(delta: float, firing: bool) -> void:
	if weapon.trait_id != &"spin":
		_spin_up = 0.0
	elif firing:
		_spin_up = minf(_spin_up + delta / SPIN_UP_SECONDS, 1.0)
	else:
		_spin_up = maxf(_spin_up - delta * SPIN_DOWN_PER_SECOND, 0.0)


func _trait_scale(_target_distance: float) -> float:
	match weapon.trait_id:
		&"focus":
			return 0.75 + 1.25 * clampf(_still_time, 0.0, 1.0)
	return 1.0


## Дуло может пройти сквозь стену или близкого врага. Пуля должна родиться перед ними.
func _is_blocked(muzzle: Vector2) -> bool:
	if _ray == null:
		_ray = PhysicsRayQueryParameters2D.new()
		_ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.OBSTACLE | PhysicsLayers.ENEMY
		_ray.collide_with_areas = true
		_ray.hit_from_inside = true
	_ray.from = global_position
	_ray.to = muzzle
	return not get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


func _can_aim_at(target: Node2D) -> bool:
	if _aim_ray == null:
		_aim_ray = PhysicsRayQueryParameters2D.new()
		# SHIELD защищает героя от врагов, но пропускает его собственные пули.
		_aim_ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.OBSTACLE
		_aim_ray.collide_with_areas = true
		_aim_ray.hit_from_inside = true
	_aim_ray.from = global_position
	_aim_ray.to = AimAssist.point(target)
	var hit := get_world_2d().direct_space_state.intersect_ray(_aim_ray)
	return hit.is_empty() or hit["collider"] == target


func _is_target_valid() -> bool:
	if not is_instance_valid(_target) or not _target.call("is_targetable"):
		return false
	var reach := weapon.max_distance
	return global_position.distance_squared_to(AimAssist.point(_target)) <= reach * reach
