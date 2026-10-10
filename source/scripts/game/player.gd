class_name Player
extends CharacterBody2D
## Енот. Проходит сквозь врагов (иначе толпа запирает его на телефоне),
## упирается только в стены и препятствия. Контактный урон считают сами враги.
## Постоянная прокачка (Сила / Выносливость / Броня) приходит из SaveService при старте боя.

signal health_changed(hp: float, max_hp: float)
signal damaged(amount: float)
signal dash_started
signal dash_moved(from: Vector2, to: Vector2)
## Рывок закончился (точка остановки): молот бьёт по площади здесь.
signal dash_ended(at: Vector2)

## Кто нанёс последний урон Еноту: уходит в отчёт о забеге.
static var last_source: StringName = &"?"
signal died
signal fell_into_void

const RADIUS := 20.0
const BASE_SPEED := 240.0
const BASE_MAX_HP := 100.0
const BASE_MAGNET := 110.0
const INVULN_TIME := 0.7
const KNOCKBACK_DECAY := 5.0
const FALL_TIME := 0.9
const STEP_INTERVAL := 0.3
const SHIELD_RECHARGE := 12.0
const SHIELD_COLOR := Color(0.3, 0.9, 1.0)
const MAX_RESIST := 0.6
const MAX_SPEED_BONUS := 1.8
const DASH_DURATION := 0.22
const DASH_SPEED := 780.0
const DASH_COOLDOWN := 5.0
const DASH_MIN_COOLDOWN := 3.5

var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP
var move_speed := BASE_SPEED
var magnet_radius := BASE_MAGNET
var move_input := Vector2.ZERO
var is_dead := false
var is_falling := false
## Доля поглощаемого урона (перк «Броня»), 0..0.6.
var armor := 0.0
var last_damage_taken := 0.0
## Бонус к максимуму HP из постоянной прокачки («Выносливость»).
var bonus_max_hp := 0.0
## Множитель перезарядки навыка от героя (CharacterDB, stats.dash).
var skill_cooldown_mult := 1.0
var fx: FxManager
## Внешняя тяга (магнитные мины) — выставляется каждый кадр, сама не затухает.
var external_pull := Vector2.ZERO
## Моргенштерн: натяжение цепи тянет героя к шару (FlailRig.pull).
var flail_pull := Vector2.ZERO
## Замедление от мин (1 — нет).
var move_slow := 1.0
## Вброд по протоке/каналу (AcidRiver): замедление, отдельно от ловушек, которые пишут move_slow.
var terrain_slow := 1.0
## Поверхность под ногами (LevelSpawner.surface_at) — для звука шагов; пусто — «камень».
var surface_query: Callable

var visual: RaccoonVisual
var weapon_controller: WeaponController

var _invuln := 0.0
var _knockback := Vector2.ZERO
var _step_timer := 0.0
var _speed_buff := 0.0
## «Кураж» ближнего боя: временная прибавка скорости за убийства (BattleBase ведёт стаки).
var rush_buff := 0.0
var _snare := 0.0
var _stun := 0.0
var shield := 0
var vest := 0
var shield_max := 0
var _shield_timer := 0.0
var _resist := 0.0
var dash_remaining := 0.0
var dash_cooldown := DASH_COOLDOWN
var _dash_left := 0.0
var _dash_direction := Vector2.RIGHT
var _dash_distance_mult := 1.0
var _last_move_direction := Vector2.RIGHT


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
	# Линию прицела рисует AimLine (от дула, по направлению пуль); у визуала своя не нужна — было две разных.
	visual.show_aim_line = false
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
	var aim_line := AimLine.new()
	aim_line.controller = weapon_controller
	add_child(aim_line)
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
	dash_cooldown = maxf(DASH_MIN_COOLDOWN, DASH_COOLDOWN - clampf(stats.get_stat(&"dodge_cooldown"), 0.0, 1.5)) * Ascension.dash_mult()
	_dash_distance_mult = 1.0 + clampf(stats.get_stat(&"dodge_distance"), 0.0, 0.2)
	var new_max := BASE_MAX_HP + bonus_max_hp + stats.get_stat(&"max_hp_add")
	if new_max > max_hp:
		hp += new_max - max_hp
	max_hp = new_max
	hp = minf(hp, max_hp)
	move_speed = BASE_SPEED * (1.0 + minf(stats.get_stat(&"move_speed_mult"), MAX_SPEED_BONUS))
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


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_snare = maxf(_snare - delta, 0.0)
	_stun = maxf(_stun - delta, 0.0)
	dash_remaining = maxf(dash_remaining - delta, 0.0)
	if move_input.length_squared() > 0.04:
		_last_move_direction = move_input.normalized()
	var speed := move_speed * (1.0 + _speed_buff + rush_buff) * move_slow * terrain_slow * (0.15 if _snare > 0.0 else 1.0)
	velocity = (Vector2.ZERO if _stun > 0.0 else move_input.limit_length(1.0) * speed) + _knockback + external_pull + flail_pull
	var dashing := _dash_left > 0.0 and _stun <= 0.0
	if dashing:
		velocity = _dash_direction * DASH_SPEED * _dash_distance_mult * minf(_dash_left / maxf(delta, 0.001), 1.0)
	_dash_left = maxf(_dash_left - delta, 0.0)
	_knockback = _knockback.lerp(Vector2.ZERO, clampf(KNOCKBACK_DECAY * delta, 0.0, 1.0))
	var before := global_position
	move_and_slide()
	if dashing:
		dash_moved.emit(before, global_position)
		if _dash_left <= 0.0:
			dash_ended.emit(global_position)
	_invuln = maxf(_invuln - delta, 0.0)
	_tick_steps(delta)
	_tick_shield(delta)
	var aim := weapon_controller.aim_direction if weapon_controller.has_target else velocity
	visual.aiming = weapon_controller.has_target
	var melee_weapon := weapon_controller.weapon != null and weapon_controller.weapon.is_melee()
	visual.melee_active = melee_weapon
	if melee_weapon:
		visual.melee_offset = weapon_controller.melee.offset
		visual.melee_scale = weapon_controller.melee.size_scale
	var steps := visual.footsteps
	visual.update_motion(velocity, aim, delta)
	if visual.footsteps != steps:
		if fx != null:
			fx.dust(global_position + Vector2(-8.0 * signf(velocity.x), 6.0), 1, 6.0)
		SoundManager.play_step(surface_query.call(global_position) if surface_query.is_valid() else &"stone")
	visual.set_env_light(EnvLights.sample(global_position), delta)
	visual.modulate.a = 0.55 if _invuln > 0.0 and int(_invuln * 20.0) % 2 == 0 else 1.0


func try_dash() -> bool:
	if not is_inside_tree() or get_tree().paused or is_dead or is_falling or is_stunned() or dash_remaining > 0.0 or _dash_left > 0.0:
		return false
	_dash_direction = move_input.normalized() if move_input.length_squared() > 0.04 else _last_move_direction
	_dash_left = DASH_DURATION
	dash_remaining = dash_cooldown
	_knockback = Vector2.ZERO
	# Рывок — честное окно неуязвимости на всю длину рывка: удары боссов можно «пройти насквозь».
	grant_invuln(DASH_DURATION + 0.08)
	dash_started.emit()
	if fx != null:
		fx.ring(global_position, Color("#64d8f5"), 36.0)
	SoundManager.play(&"step", -4.0, false)
	return true


func is_dashing() -> bool:
	return _dash_left > 0.0


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


func _draw() -> void:
	if is_dead:
		return
	# Тонкий неподвижный ободок отделяет героя от пола, без дополнительного света.
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 24, Color("#161410"), 5.0, true)
	draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 24, Color(1.0, 0.78, 0.34, 0.6), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if shield > 0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		for i in shield:
			var radius := 34.0 + 5.0 * i
			draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.9))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(SHIELD_COLOR, 0.35 + 0.3 * pulse), 4.0, true)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(1, 1, 1, 0.5 * pulse), 1.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tick_steps(delta: float) -> void:
	if velocity.length_squared() < 3600.0:
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
	if is_dead or _invuln > 0.0 or amount <= 0.0 or Tester.flag("god"):
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
	if vest > 0:
		vest -= 1
		_invuln = 0.8
		SoundManager.play(&"shield_up", -4.0, false)
		if fx != null:
			fx.ring(global_position, Color("#ffb347"), 70.0)
			fx.burst(global_position + Vector2(0, -8), Color("#ffb347"), 14, 260.0, 3.5)
		return
	var hp_before := hp
	hp = maxf(hp - amount * (1.0 - armor) * (1.0 - _resist), 0.0)
	last_damage_taken = hp_before - hp
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


## Захват магнитной миной: почти стоп на time секунд.
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
	if not is_dead:
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
	visual.revive()
	health_changed.emit(hp, max_hp)


func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(hp + amount * Ascension.heal_mult(), max_hp)
	health_changed.emit(hp, max_hp)


func _on_weapon_changed(weapon: WeaponData) -> void:
	visual.weapon_color = weapon.effect_color
	visual.weapon_icon = weapon.icon


func _on_melee_swing(weapon: WeaponData, _origin: Vector2, direction: Vector2, _combo: int, heavy: bool, _side: float) -> void:
	visual.kick(direction, (0.5 + 0.18 * weapon.weight) * (1.6 if heavy else 1.0))


## Звуковой акцент «кончается магазин / перегрев»: [каждый N-й выстрел, звук, питч, громкость dB, тяжёлая отдача].
const SHOT_ACCENTS := {
	&"shot_pistol": [7, &"ui_click", 0.55, -3.0, false],
	&"shot_sniper": [7, &"ui_click", 0.5, -2.0, true],
	&"shot_double": [7, &"ui_click", 0.6, -3.0, true],
	&"shot_shotgun": [7, &"ui_click", 0.5, -3.0, true],
	&"shot_launcher": [7, &"ui_click", 0.45, -2.0, true],
	&"shot_smg": [30, &"ui_click", 0.7, -4.0, false],
	&"shot_rifle": [30, &"ui_click", 0.65, -4.0, false],
	&"shot_lmg": [70, &"ui_click", 0.5, -3.0, false],
	&"shot_laser": [24, &"beam_charge", 1.5, -16.0, false],
	&"shot_rail": [10, &"beam_charge", 1.2, -14.0, false],
	&"shot_railgun": [5, &"beam_charge", 1.0, -10.0, true],
	&"flame": [60, &"beam_charge", 0.8, -16.0, false],
}

const PAID_WEAPONS: Array[StringName] = [&"railgun_v1", &"coil_v1", &"sniper_v1", &"casino_v1"]
const PAID_ACCENT := [6, &"star_dust", 1.5, -6.0, true]

var _shot_count := 0
var _accent_weapon: StringName = &""


func _on_fired(weapon: WeaponData, _origin: Vector2, direction: Vector2) -> void:
	visual.kick(direction, weapon.recoil)
	var accent: Array = PAID_ACCENT if PAID_WEAPONS.has(weapon.id) else SHOT_ACCENTS.get(weapon.fire_sound, [])
	if accent.is_empty():
		return
	if weapon.id != _accent_weapon:
		_accent_weapon = weapon.id
		_shot_count = 0
	_shot_count += 1
	if bool(accent[4]):
		Platform.haptic("light")
	if _shot_count % int(accent[0]) == 0:
		SoundManager.play_pitched(accent[1], accent[2], accent[3])
