class_name Player
extends CharacterBody2D
## Енот. Проходит сквозь врагов (иначе толпа запирает его на телефоне),
## упирается только в стены и препятствия. Контактный урон считают сами враги.
## Рывок (dash): короткий бросок с неуязвимостью — ответ на телеграфы крыс.
## Постоянная прокачка (Сила / Выносливость / Броня) приходит из SaveService при старте боя.

signal health_changed(hp: float, max_hp: float)
signal damaged(amount: float)
signal died
signal fell_into_void
signal dashed
signal dash_moved(from: Vector2, to: Vector2)
signal dash_ended(at: Vector2)

const RADIUS := 20.0
const BASE_SPEED := 240.0
const BASE_MAX_HP := 100.0
const BASE_MAGNET := 110.0
const INVULN_TIME := 0.7
const KNOCKBACK_DECAY := 5.0
const FALL_TIME := 0.9
const DASH_SPEED := 980.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 1.4
const DASH_IFRAMES := 0.3
const GHOST_INTERVAL := 0.03
const STEP_INTERVAL := 0.3
const DASH_GHOST_COLOR := Color(0.45, 0.95, 1.0)
const SHIELD_RECHARGE := 12.0
const SHIELD_COLOR := Color(0.3, 0.9, 1.0)
const MAX_RESIST := 0.6
const MAX_SPEED_BONUS := 1.8
const MAX_DASH_HASTE := 3.0
const DASH_BOOST_TIME := 2.0

var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP
var move_speed := BASE_SPEED
var magnet_radius := BASE_MAGNET
var move_input := Vector2.ZERO
var is_dead := false
var is_falling := false
## Доля поглощаемого урона (перк «Броня»), 0..0.6.
var armor := 0.0
## Бонус к максимуму HP из постоянной прокачки («Выносливость»).
var bonus_max_hp := 0.0
## Время до следующего заряда рывка (0, когда все заряды полны).
var dash_cooldown_left := 0.0
var dash_charges := 1
var dash_max_charges := 1
## Множитель перезарядки рывка от героя (CharacterDB, stats.dash).
var dash_cooldown_mult := 1.0
var fx: FxManager
## Внешняя тяга (магнитные мины) — выставляется каждый кадр, сама не затухает.
var external_pull := Vector2.ZERO
## Замедление от мин (1 — нет).
var move_slow := 1.0

var visual: RaccoonVisual
var weapon_controller: WeaponController

var _invuln := 0.0
var _dash_iframes := 0.0
var _knockback := Vector2.ZERO
var _dash_time := 0.0
var _dash_haste := 0.0
var _dash_range := 0.0
var _dash_boost := 0.0
var _boost_left := 0.0
var _dash_dir := Vector2.RIGHT
var _ghost_timer := 0.0
var _step_timer := 0.0
var _speed_buff := 0.0
var _snare := 0.0
var _stun := 0.0
var shield := 0
var shield_max := 0
var _shield_timer := 0.0
var _resist := 0.0
var _dash_cooling := false
var _ready_flash := 0.0


func _init() -> void:
	collision_layer = PhysicsLayers.PLAYER
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.OBSTACLE | PhysicsLayers.PROP
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	visual = RaccoonVisual.new()
	add_child(visual)
	# Своё мягкое пятно света на полу: енот читается даже в тёмных углах карты.
	var glow := PointLight2D.new()
	glow.texture = NeonSign.get_light_texture()
	glow.texture_scale = 3.4
	glow.color = Color("#ffe6c4")
	glow.energy = 0.42
	glow.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
	glow.position = Vector2(0, 10)
	add_child(glow)

	weapon_controller = WeaponController.new()
	weapon_controller.position = Vector2(0, 4)
	weapon_controller.muzzle_provider = visual.get_muzzle_global
	add_child(weapon_controller)
	weapon_controller.weapon_changed.connect(_on_weapon_changed)
	weapon_controller.fired.connect(_on_fired)
	weapon_controller.melee.swing_started.connect(_on_melee_swing)


func setup(target_finder: Callable, start_weapon: WeaponData, stats: RunStats) -> void:
	weapon_controller.setup(target_finder, start_weapon, stats)
	apply_run_stats(stats)
	hp = max_hp
	health_changed.emit(hp, max_hp)


func apply_run_stats(stats: RunStats) -> void:
	var new_max := BASE_MAX_HP + bonus_max_hp + stats.get_stat(&"max_hp_add")
	if new_max > max_hp:
		hp += new_max - max_hp
	max_hp = new_max
	hp = minf(hp, max_hp)
	move_speed = BASE_SPEED * (1.0 + minf(stats.get_stat(&"move_speed_mult"), MAX_SPEED_BONUS))
	_dash_haste = minf(stats.get_stat(&"dash_haste"), MAX_DASH_HASTE)
	_dash_range = minf(stats.get_stat(&"dash_range"), 2.5)
	_dash_boost = stats.get_stat(&"dash_boost")
	var charges := 1 + int(stats.get_stat(&"dash_charges"))
	if charges > dash_max_charges:
		dash_charges += charges - dash_max_charges
	dash_max_charges = charges
	dash_charges = mini(dash_charges, dash_max_charges)
	magnet_radius = BASE_MAGNET * (1.0 + stats.get_stat(&"magnet_mult"))
	weapon_controller.apply_run_stats(stats)
	_resist = clampf(stats.get_stat(&"damage_resist"), 0.0, MAX_RESIST)
	var new_shield := int(stats.get_stat(&"shield_max"))
	if new_shield > shield_max:
		shield += new_shield - shield_max
	shield_max = new_shield
	shield = mini(shield, shield_max)
	queue_redraw()
	health_changed.emit(hp, max_hp)


## Временный бонус скорости (стартовый «Адреналин»): доля от базовой скорости.
func set_speed_buff(amount: float) -> void:
	_speed_buff = amount


func is_dashing() -> bool:
	return _dash_time > 0.0


func dash_cooldown_total() -> float:
	return DASH_COOLDOWN * dash_cooldown_mult / (1.0 + _dash_haste)


## 0 — рывок готов, 1 — только что потрачен последний заряд.
func dash_fraction() -> float:
	if dash_charges > 0:
		return 0.0
	return clampf(dash_cooldown_left / maxf(dash_cooldown_total(), 0.01), 0.0, 1.0)


func refund_dash(seconds: float) -> void:
	if dash_charges < dash_max_charges:
		dash_cooldown_left -= seconds


func request_dash() -> bool:
	if is_dead or _stun > 0.0 or dash_charges <= 0 or _dash_time > 0.0:
		return false
	var dir := move_input
	if dir.length_squared() < 0.01:
		if weapon_controller.has_target:
			dir = weapon_controller.aim_direction
		else:
			dir = Vector2(1.0 if visual.aim_direction.x >= 0.0 else -1.0, 0.0)
	_dash_dir = dir.normalized()
	_dash_time = DASH_TIME * (1.0 + _dash_range)
	_dash_iframes = maxf(DASH_IFRAMES, _dash_time + 0.1)
	_snare = 0.0
	_stun = 0.0
	dash_charges -= 1
	if dash_cooldown_left <= 0.0:
		dash_cooldown_left = dash_cooldown_total()
	_ghost_timer = 0.0
	visual.dashing = true
	SoundManager.play(&"dash")
	if fx != null:
		fx.dust(global_position + Vector2(0, 18), 6, 40.0)
	dashed.emit()
	return true


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if dash_charges < dash_max_charges:
		dash_cooldown_left -= delta
		if dash_cooldown_left <= 0.0:
			dash_charges += 1
			dash_cooldown_left = dash_cooldown_total() if dash_charges < dash_max_charges else 0.0
	_boost_left = maxf(_boost_left - delta, 0.0)
	var start_position := global_position
	var was_dashing := _dash_time > 0.0
	_dash_iframes = maxf(_dash_iframes - delta, 0.0)
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * DASH_SPEED
		_ghost_timer -= delta
		if _ghost_timer <= 0.0 and fx != null:
			_ghost_timer = GHOST_INTERVAL
			fx.ghost(visual.get_ghost_texture(), global_position + visual.get_ghost_offset(), visual.get_ghost_scale(), DASH_GHOST_COLOR)
		if _dash_time <= 0.0:
			visual.dashing = false
	else:
		_snare = maxf(_snare - delta, 0.0)
		_stun = maxf(_stun - delta, 0.0)
		var speed := move_speed * (1.0 + _speed_buff + (_dash_boost if _boost_left > 0.0 else 0.0)) * move_slow * (0.15 if _snare > 0.0 else 1.0)
		velocity = (Vector2.ZERO if _stun > 0.0 else move_input.limit_length(1.0) * speed) + _knockback + external_pull
	_knockback = _knockback.lerp(Vector2.ZERO, clampf(KNOCKBACK_DECAY * delta, 0.0, 1.0))
	move_and_slide()
	if was_dashing:
		dash_moved.emit(start_position, global_position)
		if _dash_time <= 0.0:
			_boost_left = DASH_BOOST_TIME if _dash_boost > 0.0 else 0.0
			dash_ended.emit(global_position)
	_invuln = maxf(_invuln - delta, 0.0)
	_tick_steps(delta)
	_tick_shield(delta)
	_tick_dash_feedback(delta)
	var aim := weapon_controller.aim_direction if weapon_controller.has_target else velocity
	visual.aiming = weapon_controller.has_target
	var melee_weapon := weapon_controller.weapon != null and weapon_controller.weapon.is_melee()
	visual.melee_active = melee_weapon
	if melee_weapon:
		visual.melee_offset = weapon_controller.melee.offset
		visual.melee_scale = weapon_controller.melee.size_scale
	visual.update_motion(velocity, aim, delta)
	visual.set_env_light(EnvLights.sample(global_position), delta)
	visual.modulate.a = 0.55 if _invuln > 0.0 and int(_invuln * 20.0) % 2 == 0 else 1.0


func _tick_shield(delta: float) -> void:
	if shield_max <= 0:
		return
	if shield < shield_max:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			shield += 1
			_shield_timer = SHIELD_RECHARGE
			if fx != null:
				fx.ring(global_position, SHIELD_COLOR, 46.0)
	queue_redraw()


func _tick_dash_feedback(delta: float) -> void:
	var cooling := dash_charges <= 0
	if _dash_cooling and not cooling:
		_ready_flash = 1.0
		SoundManager.play(&"dash_ready", -6.0, false)
		if fx != null:
			fx.ring(global_position + Vector2(0, 16), Color(0.45, 0.95, 1.0), 44.0)
			fx.burst(global_position + Vector2(0, 16), Color(0.6, 1.0, 1.0), 8, 180.0, 2.8)
	_dash_cooling = cooling
	if _ready_flash > 0.0:
		_ready_flash = maxf(_ready_flash - delta * 2.5, 0.0)
	if cooling or _ready_flash > 0.0 or dash_charges < dash_max_charges:
		queue_redraw()


func _draw() -> void:
	if is_dead:
		return
	if _dash_cooling:
		var progress := 1.0 - dash_fraction()
		SoftGlow.pool(self, Vector2(0, 20), 34.0, 0.42, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2(0, 20), 0.0, Vector2(1.0, 0.42))
		draw_arc(Vector2.ZERO, 30.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, Color(0.35, 0.9, 1.0, 0.25 + 0.3 * progress), 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif _ready_flash > 0.0:
		var r := 30.0 + 26.0 * (1.0 - _ready_flash)
		SoftGlow.rim(self, Vector2(0, 20), r * 1.15, 0.42, Color(0.7, 1.0, 1.0, _ready_flash * 0.7))
	if dash_max_charges > 1:
		var recharge := 1.0 - clampf(dash_cooldown_left / maxf(dash_cooldown_total(), 0.01), 0.0, 1.0)
		for i in dash_max_charges:
			var at := Vector2((i - (dash_max_charges - 1) * 0.5) * 16.0, 36.0)
			if i < dash_charges:
				draw_circle(at, 5.0, Color(0.5, 1.0, 1.0, 0.95))
			else:
				draw_circle(at, 5.0, Color(0.1, 0.2, 0.3, 0.6))
				if i == dash_charges:
					draw_arc(at, 5.0, -PI * 0.5, -PI * 0.5 + TAU * recharge, 12, Color(0.5, 1.0, 1.0, 0.9), 2.5, true)
	if shield > 0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		for i in shield:
			var radius := 34.0 + 5.0 * i
			draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.9))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(SHIELD_COLOR, 0.35 + 0.3 * pulse), 4.0, true)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(1, 1, 1, 0.5 * pulse), 1.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tick_steps(delta: float) -> void:
	if velocity.length_squared() < 3600.0 or _dash_time > 0.0:
		_step_timer = minf(_step_timer, 0.08)
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = STEP_INTERVAL * BASE_SPEED / maxf(velocity.length(), 1.0)
	SoundManager.play(&"step", -9.0)
	if fx != null:
		fx.dust(global_position + Vector2(randf_range(-8, 8), 20), 1, 14.0)


func take_damage(amount: float, _direction: Vector2 = Vector2.ZERO, _is_crit: bool = false) -> void:
	if is_dead or _invuln > 0.0 or _dash_iframes > 0.0 or amount <= 0.0 or Tester.flag("god"):
		return
	if shield > 0:
		shield -= 1
		_shield_timer = SHIELD_RECHARGE
		_invuln = 0.6
		queue_redraw()
		SoundManager.play(&"shield_up", -4.0, false)
		if fx != null:
			fx.ring(global_position, SHIELD_COLOR, 70.0)
			fx.burst(global_position + Vector2(0, -8), SHIELD_COLOR, 12, 260.0, 3.5)
		return
	hp = maxf(hp - amount * (1.0 - armor) * (1.0 - _resist), 0.0)
	_invuln = INVULN_TIME
	visual.flash()
	damaged.emit(amount)
	health_changed.emit(hp, max_hp)
	Platform.haptic("light")
	if hp <= 0.0:
		is_dead = true
		visual.modulate.a = 1.0
		visual.play_death()
		died.emit()


## Захват магнитной миной: почти стоп на time секунд (рывок снимает).
func stun(time: float) -> void:
	_stun = maxf(_stun, time)


func grant_invuln(time: float) -> void:
	_invuln = maxf(_invuln, time)


func is_stunned() -> bool:
	return _stun > 0.0


func snare(time: float) -> void:
	_snare = maxf(_snare, time)
	if fx != null:
		fx.ring(global_position, Color("#35e6ff"), 50.0)


## Радиальный толчок (например, удар приземления дракона): затухает сам.
## Шаг к цели при ударе ближнего боя: дистанция в пикселях (затухание отброса ≈ 5/с).
func lunge(direction: Vector2, distance: float) -> void:
	if not is_dead and _dash_time <= 0.0:
		_knockback += direction.normalized() * distance * (KNOCKBACK_DECAY + 0.2)


func apply_knockback(impulse: Vector2) -> void:
	if not is_dead:
		_knockback += impulse


## Край платформы Алтаря: скорость 0, Енот уменьшается до нуля и исчезает в космосе.
func fall_into_void() -> void:
	if is_dead:
		return
	is_dead = true
	is_falling = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	SoundManager.play(&"comet_fall", 0.0, false)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ZERO, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation", TAU, FALL_TIME)
	tween.chain().tween_callback(func() -> void: fell_into_void.emit())


## Второй шанс: Енот встаёт с долей HP и короткой неуязвимостью.
func revive(hp_fraction: float, invulnerability: float) -> void:
	if not is_dead or is_falling:
		return
	is_dead = false
	hp = max_hp * clampf(hp_fraction, 0.05, 1.0)
	_invuln = invulnerability
	_knockback = Vector2.ZERO
	_dash_time = 0.0
	visual.dashing = false
	visual.revive()
	health_changed.emit(hp, max_hp)


func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)


func _on_weapon_changed(weapon: WeaponData) -> void:
	visual.weapon_color = weapon.effect_color
	visual.weapon_icon = weapon.icon


func _on_melee_swing(weapon: WeaponData, _origin: Vector2, direction: Vector2, _combo: int, heavy: bool, _side: float) -> void:
	visual.kick(direction, (0.5 + 0.18 * weapon.weight) * (1.6 if heavy else 1.0))


func _on_fired(weapon: WeaponData, _origin: Vector2, direction: Vector2) -> void:
	visual.kick(direction, weapon.recoil)
