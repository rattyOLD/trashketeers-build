class_name MeleeFighter
extends Node
## Ближний бой Енота (дочерний узел WeaponController). Цикл удара: замах → взмах → восстановление.
## Урон наносится один раз в момент HIT_MOMENT взмаха: сектор перед Енотом, круг радиусом reach.
## Попадание проходит через BulletPool.bullet_hit с «пулей-заместителем», поэтому цифры урона, вампиризм,
## яд/огонь/кровь и прочие перки забега работают для клинков так же, как для стволов. Отдельных нод
## на удар нет: заместитель один на всё оружие, эффекты берёт на себя пул FxManager.

signal swing_started(weapon: WeaponData, origin: Vector2, direction: Vector2, combo: int, heavy: bool, side: float)
signal hit_resolved(weapon: WeaponData, at: Vector2, count: int, finisher: bool, heavy: bool)

enum Phase { IDLE, WINDUP, SWING, RECOVERY }

const COMBO_WINDOW := 0.6
const HEAVY_CHARGE_TIME := 0.9
const HIT_MOMENT := 0.3
const QUERY_LIMIT := 40
const ECHO_DELAY := 0.09
const ECHO_SCALE := 0.6
const ICE_WAVE_EVERY := 3
const GRAVITY_WINDOW := 2.5
const ENEMY_BODY := 22.0
const FINISHER_MULT := 1.6
const COMBO_STEP := 0.12
const KILLS_PER_GROWTH := 10
const MAX_GROWTH := 1.0
const PULL_FORCE := 620.0
const CLASS_STAGGER := {"dagger": 0.6, "sword": 1.0, "katana": 0.8, "axe": 1.2, "spear": 1.0, "hammer": 1.8, "shield": 1.3}
const PIERCING_CLASSES := ["axe", "hammer"]

## Смещение угла клинка относительно прицела (рад): его рисует RaccoonVisual.
var offset := 0.0
var direction := Vector2.RIGHT
var busy := false
var size_scale := 1.0

var _weapon: WeaponData
var _phase := Phase.IDLE
var _phase_time := 0.0
var _phase_len := 0.0
var _combo := 0
var _combo_left := 0.0
var _side := 1.0
var _heavy := false
var _finisher := false
var _idle_time := 0.0
var _hit_done := false
var _echo_left := -1.0
var _speed := 1.0
var _kills := 0
var _swings := 0
var _gravity_center := Vector2.ZERO
var _gravity_left := 0.0
var _query: PhysicsShapeQueryParameters2D
var _proxy: Bullet
var _wave_weapon: WeaponData
var _wave_source: WeaponData
var _lunge_distance := 0.0


func reset() -> void:
	_phase = Phase.IDLE
	_phase_time = 0.0
	_combo = 0
	_combo_left = 0.0
	_idle_time = 0.0
	_echo_left = -1.0
	offset = 0.0
	busy = false


func growth() -> float:
	return minf(float(_kills / KILLS_PER_GROWTH) * 0.1, MAX_GROWTH)


func effective_reach(weapon: WeaponData) -> float:
	var grow := growth() if weapon.trait_id == &"junk_grow" else 0.0
	return weapon.melee_reach * (1.0 + grow)


## Вызывается контроллером каждый физический кадр, пока в руках клинок. target — ближайшая цель или null.
func tick(delta: float, weapon: WeaponData, target: Node2D, origin: Vector2) -> void:
	_weapon = weapon
	size_scale = 1.0 + (growth() if weapon.trait_id == &"junk_grow" else 0.0)
	_speed = maxf((weapon.windup + weapon.swing + weapon.recovery) / maxf(weapon.fire_interval, 0.02), 0.2)
	_combo_left = maxf(_combo_left - delta, 0.0)
	_gravity_left = maxf(_gravity_left - delta, 0.0)
	if _echo_left >= 0.0:
		_echo_left -= delta
		if _echo_left < 0.0:
			_resolve_hit(origin, ECHO_SCALE, true)
	match _phase:
		Phase.IDLE:
			offset = lerpf(offset, 0.0, clampf(delta * 14.0, 0.0, 1.0))
			_idle_time += delta
			busy = false
			if target != null:
				var aim: Vector2 = target.call("get_aim_point") if target.has_method("get_aim_point") else target.global_position
				var to_target := aim - origin
				direction = to_target.normalized() if to_target.length_squared() > 1.0 else direction
				if to_target.length() <= weapon.max_distance:
					_begin_swing(origin, to_target.length())
		_:
			busy = true
			_advance(delta, origin)


func _begin_swing(origin: Vector2, distance: float) -> void:
	_combo = _combo + 1 if _combo_left > 0.0 else 0
	if _combo >= _weapon.combo_hits:
		_combo = 0
	_heavy = _idle_time >= HEAVY_CHARGE_TIME and _combo == 0
	_finisher = _weapon.combo_hits > 1 and _combo == _weapon.combo_hits - 1
	_side = -_side
	_idle_time = 0.0
	_hit_done = false
	_swings += 1
	_phase = Phase.WINDUP
	_phase_time = 0.0
	var chain := 0.7 if _combo > 0 else 1.0
	_phase_len = _weapon.windup * chain * (1.6 if _heavy else 1.0) / _speed
	_lunge_distance = clampf(distance - effective_reach(_weapon) * 0.7, 0.0, _weapon.lunge * (1.35 if _finisher or _heavy else 1.0))


func _advance(delta: float, origin: Vector2) -> void:
	_phase_time += delta
	var t := clampf(_phase_time / maxf(_phase_len, 0.001), 0.0, 1.0)
	var arc := _weapon.arc_rad
	match _phase:
		Phase.WINDUP:
			offset = -_side * arc * 0.55 * (1.0 - pow(1.0 - t, 2.0))
			if t >= 1.0:
				_phase = Phase.SWING
				_phase_time = 0.0
				_phase_len = _weapon.swing * (1.25 if _finisher else 1.0) / _speed
				var player := get_parent().get_parent() as Player
				if player != null and _lunge_distance > 1.0:
					player.lunge(direction, _lunge_distance)
				SoundManager.play_pitched(&"dash", clampf(1.7 - 0.18 * _weapon.weight, 0.7, 1.6), -9.0)
				swing_started.emit(_weapon, origin, direction, _combo, _heavy, _side)
		Phase.SWING:
			var eased := t * t * (3.0 - 2.0 * t)
			offset = _side * arc * lerpf(-0.5, 0.5, eased)
			if not _hit_done and t >= HIT_MOMENT:
				_hit_done = true
				_resolve_hit(origin, 1.0, false)
			if t >= 1.0:
				_phase = Phase.RECOVERY
				_phase_time = 0.0
				_phase_len = _weapon.recovery * (1.2 if _finisher or _heavy else 1.0) / _speed
		Phase.RECOVERY:
			offset = _side * arc * 0.5 * (1.0 - t)
			if t >= 1.0:
				_phase = Phase.IDLE
				_combo_left = COMBO_WINDOW
				offset = 0.0


func _combo_scale() -> float:
	var scale := 1.0 + COMBO_STEP * _combo
	if _finisher:
		scale = FINISHER_MULT
	if _heavy:
		scale *= _weapon.heavy_mult
	return scale


func _get_query() -> PhysicsShapeQueryParameters2D:
	if _query == null:
		_query = PhysicsShapeQueryParameters2D.new()
		_query.shape = CircleShape2D.new()
		_query.collide_with_bodies = true
		_query.collide_with_areas = false
		_query.collision_mask = PhysicsLayers.ENEMY | PhysicsLayers.OBSTACLE
	return _query


func _get_proxy() -> Bullet:
	if _proxy == null:
		_proxy = Bullet.new()
		_proxy.team = Bullet.Team.PLAYER
		add_child(_proxy)
	return _proxy


func _resolve_hit(origin: Vector2, echo_scale: float, echo: bool) -> void:
	var weapon := _weapon
	var reach := effective_reach(weapon)
	var query := _get_query()
	(query.shape as CircleShape2D).radius = reach + ENEMY_BODY
	query.transform = Transform2D(0.0, origin)
	var hits := get_viewport().get_world_2d().direct_space_state.intersect_shape(query, QUERY_LIMIT)
	var arc := weapon.arc_rad * (1.25 if _finisher else 1.0)
	if weapon.melee_class == "axe" and _finisher:
		arc = TAU
	var scale := _combo_scale() * echo_scale
	var strong := _finisher or _heavy
	var proxy := _get_proxy()
	proxy.weapon = weapon
	proxy.damage_scale = scale
	proxy.pierced = 0
	var landed := 0
	var center := Vector2.ZERO
	var victims: Array[Node2D] = []
	for hit in hits:
		var target := hit["collider"] as Node2D
		if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
			continue
		var to_target := target.global_position - origin
		var distance := to_target.length()
		if distance > reach + ENEMY_BODY:
			continue
		var spread := arc * 0.5 + atan2(ENEMY_BODY, maxf(distance, 1.0))
		if arc < TAU and absf(angle_difference(to_target.angle(), direction.angle())) > spread:
			continue
		var crit := randf() < weapon.crit_chance
		var amount := weapon.damage * scale * (weapon.crit_mult if crit else 1.0)
		var push := to_target.normalized() if distance > 1.0 else direction
		proxy.position = target.global_position
		proxy.velocity = push * 100.0
		proxy.last_hit_crit = crit
		var knock := weapon.knockback * (2.2 if strong else 1.0)
		if target is Enemy:
			var enemy := target as Enemy
			if enemy.is_alive():
				Enemy.next_kind = &"melee"
			enemy.take_bullet(amount, push, knock, crit, PIERCING_CLASSES.has(weapon.melee_class) or strong)
			if enemy.is_alive():
				enemy.add_stagger(weapon.stagger * CLASS_STAGGER.get(weapon.melee_class, 1.0) * (1.6 if _heavy else 1.0) * echo_scale, strong)
			elif weapon.trait_id == &"junk_grow":
				_kills += 1
			if weapon.trait_id == &"ice_wave" and enemy.is_alive():
				enemy.add_slow(0.55, 2.5)
		else:
			target.call("take_damage", amount, push * knock, crit)
		BulletPool.bullet_hit.emit(proxy, target)
		landed += 1
		center += target.global_position
		victims.append(target)
	if landed > 0 and not echo:
		center /= float(landed)
		hit_resolved.emit(weapon, center, landed, _finisher, _heavy)
	if echo:
		return
	_apply_trait(weapon, origin, victims, scale, reach)
	if weapon.trait_id == &"echo":
		_echo_left = ECHO_DELAY


func _apply_trait(weapon: WeaponData, origin: Vector2, victims: Array[Node2D], scale: float, reach: float) -> void:
	match weapon.trait_id:
		&"quake":
			if _finisher or _heavy:
				BulletPool.explode(origin + direction * reach * 0.8, 130.0, weapon.damage * 0.6 * scale, Bullet.Team.PLAYER, weapon.effect_color, 1.6)
		&"ice_wave":
			if _swings % ICE_WAVE_EVERY == 0:
				BulletPool.fire(_get_wave_weapon(weapon), origin + direction * 34.0, direction, Bullet.Team.PLAYER, 1.0)
		&"gravity":
			if _gravity_left > 0.0:
				BulletPool.explode(_gravity_center, 150.0, weapon.damage * 0.9, Bullet.Team.PLAYER, weapon.effect_color, 1.4)
				_gravity_left = 0.0
			elif not victims.is_empty():
				_gravity_center = origin + direction * reach * 0.75
				_gravity_left = GRAVITY_WINDOW
				for victim in victims:
					if victim is Enemy:
						(victim as Enemy).pull_toward(_gravity_center, PULL_FORCE)


func _get_wave_weapon(weapon: WeaponData) -> WeaponData:
	if _wave_weapon == null or _wave_source != weapon:
		_wave_source = weapon
		var base := WeaponDB.get_weapon(&"frost_shard_v1")
		_wave_weapon = base.duplicate_data() if base != null else weapon.duplicate_data()
		_wave_weapon.kind = "gun"
		_wave_weapon.damage = weapon.damage * 0.55
		_wave_weapon.piercing = true
		_wave_weapon.bullet_speed = 760.0
		_wave_weapon.max_distance = 620.0
		_wave_weapon.bullet_lifetime = 1.0
		_wave_weapon.projectiles_per_shot = 1
		_wave_weapon.spread_rad = 0.0
		_wave_weapon.explosion_radius = 0.0
		_wave_weapon.explosion_damage = 0.0
		_wave_weapon.ricochet_count = 0
		_wave_weapon.bullet_radius = 26.0
		_wave_weapon.sprite_scale *= 1.8
		_wave_weapon.crit_chance = weapon.crit_chance
		_wave_weapon.effect_color = weapon.effect_color
		_wave_weapon.fire_sound = &""
	return _wave_weapon
