class_name HeroSkills
extends Node
## Активный навык героя (кнопка рывка; у героев с навыком она вызывает навык, а не рывок). У Бродяги навыка нет.
## Урон идёт через BulletPool.explode: он бьёт и обычных врагов, и Хладгора (когда тот на земле),
## поэтому навыки работают в любом режиме. Статусы (заморозка, яд, поджог) — только по Enemy.

signal used(skill_id: String)

const ENEMY_QUERY_LIMIT := 64

var skill: Dictionary = {}
var _player: Player
var _fx: FxManager
var _stats: RunStats
var _shake: Callable
var _left := 0.0
var _query: PhysicsShapeQueryParameters2D
var _hero := ""


func setup(hero_id: String, player: Player, fx: FxManager, stats: RunStats, shake: Callable) -> void:
	_hero = hero_id
	_player = player
	_fx = fx
	_stats = stats
	_shake = shake
	skill = CharacterDB.get_character(hero_id).get("skill", {})
	_left = 3.0 if not skill.is_empty() else 0.0


func has_skill() -> bool:
	return not skill.is_empty()


func title() -> String:
	return str(skill.get("title", ""))


func fraction() -> float:
	if skill.is_empty():
		return 0.0
	return clampf(_left / _cooldown(), 0.0, 1.0)


func _cooldown() -> float:
	return float(skill["cooldown"]) * _player.dash_cooldown_mult


func _physics_process(delta: float) -> void:
	if _left > 0.0 and not get_tree().paused:
		_left = maxf(_left - delta, 0.0)


func try_use() -> bool:
	if skill.is_empty() or _left > 0.0 or _player == null or _player.is_dead or _player.is_stunned():
		return false
	_left = _cooldown()
	match str(skill["id"]):
		"fire_ring":
			_fire_ring()
		"ice_dome":
			_ice_dome()
		"assassin_hour":
			_assassin_hour()
		"rail_dash":
			_rail_dash()
		"toxic_flask":
			_toxic_flask()
		"drone_strike":
			_drone_strike()
	if _shake.is_valid():
		_shake.call(0.35)
	SoundManager.play(&"shield_up")
	used.emit(str(skill["id"]))
	return true


func _power() -> float:
	return 1.0 + _stats.get_stat(&"damage_mult")


func _enemies_in(center: Vector2, radius: float) -> Array[Enemy]:
	if _query == null:
		_query = PhysicsShapeQueryParameters2D.new()
		_query.shape = CircleShape2D.new()
		_query.collision_mask = PhysicsLayers.ENEMY
		_query.collide_with_areas = false
	(_query.shape as CircleShape2D).radius = radius
	_query.transform = Transform2D(0.0, center)
	var found: Array[Enemy] = []
	for hit in _player.get_world_2d().direct_space_state.intersect_shape(_query, ENEMY_QUERY_LIMIT):
		var enemy := hit["collider"] as Enemy
		if enemy != null and enemy.is_alive():
			found.append(enemy)
	return found


## Направление рывка-навыка: куда игрок ведёт джойстик; без него — ручной прицел или взгляд, автоприцел не перехватывает управление.
func _steer_dir() -> Vector2:
	if _player.move_input.length() > 0.2:
		return _player.move_input.normalized()
	var wc := _player.weapon_controller
	if wc.manual_aim != Vector2.ZERO:
		return wc.manual_aim
	return wc.aim_direction.normalized() if wc.aim_direction.length() > 0.1 else Vector2.RIGHT


func _aim() -> Vector2:
	var dir := _player.weapon_controller.aim_direction
	if _player.weapon_controller.has_target and dir.length() > 0.1:
		return dir.normalized()
	if _player.move_input.length() > 0.2:
		return _player.move_input.normalized()
	return dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT


func _later(delay: float, action: Callable) -> void:
	get_tree().create_timer(delay, false).timeout.connect(action)


func _fire_ring() -> void:
	var at := _player.global_position
	var color := Color("#ff8a2a")
	for k in 3:
		_later(0.09 * k, func() -> void:
			if is_instance_valid(_player):
				_fx.ring(at, color.lerp(Color("#ffe27a"), 0.3 * k), 260.0 + 60.0 * k))
	_fx.burst(at, Color("#ffb347"), 38, 460.0, 5.0)
	BulletPool.explode(at, 300.0, 70.0 * _power(), Bullet.Team.PLAYER, color, 1.6, &"fire")
	for enemy in _enemies_in(at, 320.0):
		enemy.add_bleed(16.0 * _power(), 4.0, true)
	_player.grant_invuln(0.25)


func _ice_dome() -> void:
	var zone := SkillZone.new()
	zone.setup(_player, 380.0, 4.0, Color("#8fdcff"), 0.25, true)
	zone.tick.connect(func(enemy: Enemy) -> void:
		enemy.add_slow(0.65, 2.0))
	_player.get_parent().add_child(zone)
	_fx.ring(_player.global_position, Color("#e8fbff"), 380.0)
	_fx.burst(_player.global_position, Color("#bff0ff"), 30, 360.0, 4.0)
	for enemy in _enemies_in(_player.global_position, 380.0):
		enemy.add_stagger(999.0, true)
		enemy.add_slow(0.6, 3.5)
	_player.grant_invuln(1.6)


func _assassin_hour() -> void:
	_stats.add_flat(&"crit_chance_add", 1.0)
	_stats.add_flat(&"damage_mult", 0.25)
	_player.apply_run_stats(_stats)
	_player.grant_invuln(0.5)
	_fx.ring(_player.global_position, Color("#b46bff"), 190.0)
	_fx.burst(_player.global_position, Color("#7a3bd1"), 26, 320.0, 4.0)
	_fx.popup(_player.global_position + Vector2(0, -90), "ЧАС УБИЙЦЫ", Color("#d9a8ff"), 28.0)
	_later(4.0, func() -> void:
		if not is_instance_valid(_player):
			return
		_stats.add_flat(&"crit_chance_add", -1.0)
		_stats.add_flat(&"damage_mult", -0.25)
		_player.apply_run_stats(_stats))


func _rail_dash() -> void:
	var dir := _steer_dir()
	var start := _player.global_position
	var color := Color("#5cf3ff")
	_player.grant_invuln(1.0)
	_player.lunge(dir, 560.0)
	for step in range(1, 8):
		var at := start + dir * (70.0 * step)
		_later(0.03 * step, func() -> void:
			BulletPool.explode(at, 95.0, 95.0 * _power(), Bullet.Team.PLAYER, color, 0.8, &"shock")
			_fx.burst(at, color, 6, 240.0, 3.5))
	_fx.ring(start, color, 120.0)


func _toxic_flask() -> void:
	var from := _player.global_position
	var near := _enemies_in(from, 700.0)
	var target := from + _aim() * 280.0
	var best := INF
	for enemy in near:
		var d := from.distance_squared_to(enemy.global_position)
		if d < best:
			best = d
			target = enemy.global_position
	var zone := SkillZone.new()
	zone.setup(_player, 210.0, 6.0, Color("#7dff5c"), 0.4, false)
	zone.global_position = target
	zone.tick.connect(func(enemy: Enemy) -> void:
		enemy.add_poison(14.0 * _power(), 3.0, 5)
		enemy.add_slow(0.35, 0.7))
	_player.get_parent().add_child(zone)
	zone.global_position = target
	_fx.ring(target, Color("#7dff5c"), 210.0)
	_fx.burst(target, Color("#9dff7a"), 26, 300.0, 4.5)


func _drone_strike() -> void:
	var dir := _aim()
	var start := _player.global_position
	var warn := Color("#ff4d6d")
	for i in 8:
		var at := start + dir * (120.0 + 105.0 * i)
		_fx.ring(at, warn, 70.0)
		_later(0.7 + 0.11 * i, func() -> void:
			BulletPool.explode(at, 125.0, 115.0 * _power(), Bullet.Team.PLAYER, Color("#ffb347"), 1.5)
			_fx.burst(at, Color("#ffb347"), 12, 340.0, 4.5)
			if _shake.is_valid():
				_shake.call(0.12))
	_fx.popup(start + Vector2(0, -90), "НАЛЁТ!", Color("#ffb0a0"), 28.0)


## Зона на земле: рисуется полупрозрачным кругом и раз в interval вызывает tick для каждого врага внутри.
class SkillZone:
	extends Node2D
	signal tick(enemy: Enemy)

	var radius := 200.0
	var life := 4.0
	var color := Color.WHITE
	var interval := 0.3
	var follow: Node2D
	var _time := 0.0
	var _next := 0.0
	var _query: PhysicsShapeQueryParameters2D

	func setup(owner_node: Node2D, r: float, duration: float, tint: Color, tick_interval: float, follow_owner: bool) -> void:
		radius = r
		life = duration
		color = tint
		interval = tick_interval
		global_position = owner_node.global_position
		z_index = -8
		if follow_owner:
			follow = owner_node

	func _physics_process(delta: float) -> void:
		_time += delta
		if follow != null and is_instance_valid(follow):
			global_position = follow.global_position
		if _time >= life:
			queue_free()
			return
		_next -= delta
		if _next <= 0.0:
			_next = interval
			_apply()
		queue_redraw()

	func _apply() -> void:
		if _query == null:
			_query = PhysicsShapeQueryParameters2D.new()
			_query.shape = CircleShape2D.new()
			_query.collision_mask = PhysicsLayers.ENEMY
			_query.collide_with_areas = false
		(_query.shape as CircleShape2D).radius = radius
		_query.transform = Transform2D(0.0, global_position)
		for hit in get_world_2d().direct_space_state.intersect_shape(_query, 64):
			var enemy := hit["collider"] as Enemy
			if enemy != null and enemy.is_alive():
				tick.emit(enemy)

	func _draw() -> void:
		var fade := clampf(minf(_time / 0.25, (life - _time) / 0.6), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		draw_circle(Vector2.ZERO, radius, Color(color, (0.12 + 0.05 * pulse) * fade))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(color, (0.55 + 0.2 * pulse) * fade), 4.0, true)
		for k in 6:
			var a := _time * 0.6 + k * TAU / 6.0
			draw_circle(Vector2.from_angle(a) * radius * (0.35 + 0.4 * fmod(_time * 0.3 + k * 0.17, 1.0)), 5.0, Color(color, 0.5 * fade))
