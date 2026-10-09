class_name DashEffects
extends Node

const MAX_TARGETS := 8
const QUERY_LIMIT := 24
const HIT_RADIUS := Player.RADIUS + 8.0
## Катана «Срез»: рывок режет всех на пути уроном катаны; раненых (< LOW_HP) — всегда критом;
## CUT_STREAK убийств одним рывком — «раж» (скорость ударов на время, см. Game._on_katana_rage).
const LOW_HP := 0.35
const CUT_STREAK := 3
const CUT_RADIUS := Player.RADIUS + 26.0

## Сколько врагов срезано насмерть этим рывком (катана).
signal katana_rage(kills: int)
## Удар молота в конце рывка (Game трясёт камеру).
signal hammer_slammed(at: Vector2)

var _player: Player
var _stats: RunStats
var _fx: FxManager
var _seen: Dictionary = {}
var _element_used := false
var _cut_seen: Dictionary = {}
var _cut_kills := 0
var _cut_query := PhysicsShapeQueryParameters2D.new()
var _cut_shape := CapsuleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()
var _shape := CapsuleShape2D.new()


func setup(player: Player, stats: RunStats, fx: FxManager) -> void:
	_player = player
	_stats = stats
	_fx = fx
	_shape.radius = HIT_RADIUS
	_query.shape = _shape
	_query.collision_mask = PhysicsLayers.ENEMY
	_query.collide_with_areas = false
	_cut_shape.radius = CUT_RADIUS
	_cut_query.shape = _cut_shape
	_cut_query.collision_mask = PhysicsLayers.ENEMY
	_cut_query.collide_with_areas = false
	_player.dash_moved.connect(_katana_cut)
	_player.dash_ended.connect(_hammer_slam)
	_player.dash_started.connect(func() -> void:
		_cut_seen.clear()
		_cut_kills = 0
		_seen.clear()
		_element_used = false
		_ghost_step = 0
		_skin = Cosmetics.dash_colors()
		if _fx != null and _skin[1].a > 0.0:
			_fx.burst(_player.global_position + Vector2(0, -20), _skin[0], 10, 200.0, 3.6)
		if _fx != null:
			_fx.dust(_player.global_position + Vector2(0, 8), 5, 40.0))
	_player.dash_moved.connect(_on_moved)
	_player.dash_moved.connect(_leave_ghost)


## Послеобразы рывка: голубые полупрозрачные копии героя по пути (каждый второй кадр — шлейф без каши).
var _ghost_step := 0
## Скин рывка (Cosmetics): [цвет послеобраза, цвет искр — прозрачный у стандартного].
var _skin: Array[Color] = [Color(0.45, 0.85, 1.0), Color(0, 0, 0, 0)]


func _leave_ghost(from: Vector2, _to: Vector2) -> void:
	_ghost_step += 1
	if _ghost_step % 2 == 0 or _fx == null or _player.visual == null:
		return
	var visual := _player.visual
	_fx.ghost(visual.get_ghost_texture(), from + visual.get_ghost_offset(), visual.get_ghost_scale(), _skin[0])
	if _skin[1].a > 0.0 and _ghost_step % 4 == 1:
		_fx.burst(from + Vector2(0, -20), _skin[1], 3, 90.0, 3.0)


func _on_moved(from: Vector2, to: Vector2) -> void:
	var rank := mini(int(_stats.get_stat(&"dodge_damage")), 3)
	if rank <= 0 or _seen.size() >= MAX_TARGETS:
		return
	var travel := to - from
	_shape.height = HIT_RADIUS * 2.0 + travel.length()
	_query.transform = Transform2D(travel.angle() - PI * 0.5, (from + to) * 0.5)
	var hits := _player.get_world_2d().direct_space_state.intersect_shape(_query, QUERY_LIMIT)
	for hit in hits:
		var target := hit["collider"] as Node2D
		if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
			continue
		var id := target.get_instance_id()
		if _seen.has(id) or _seen.size() >= MAX_TARGETS:
			continue
		_seen[id] = true
		var at := target.global_position
		var enemy := target as Enemy
		if enemy != null and not enemy.is_alive():
			continue
		Enemy.next_kind = &"dash"
		target.call("take_damage", 12.0 + rank * 6.0, Vector2.ZERO, false)
		Enemy.next_kind = &""
		if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
			var poison := mini(int(_stats.get_stat(&"dodge_poison")), 2)
			if poison > 0:
				enemy.add_dash_poison(1.0 + poison * 3.0)
		if _element_used:
			continue
		_element_used = true
		var blast := mini(int(_stats.get_stat(&"dodge_blast")), 2)
		if blast > 0:
			BulletPool.explode(at, 72.0, 8.0 + blast * 6.0, Bullet.Team.PLAYER, Color("#ff9b32"), 0.3)
		var shock := mini(int(_stats.get_stat(&"dodge_shock")), 2)
		if shock > 0:
			_shock(at, id, 12.0 + shock * 6.0)


## Рывок с оружием ближнего боя режет по-своему (тестеры): топор/меч — один сильный разрез по всем на пути,
## катана/кинжал — серия мелких разрезов, молот/щит — удар по площади в конце рывка. Катана «Срез» вдобавок
## всегда критует по раненым и даёт «раж» за три убийства одним рывком.
const AXE_CUT := 1.2
const KATANA_CUTS := 3
const KATANA_CUT := 0.45
const HAMMER_SLAM := 1.3
const HAMMER_RADIUS := 150.0


func _melee_style(weapon: WeaponData) -> String:
	if weapon == null or not weapon.is_melee():
		return ""
	match weapon.melee_class:
		"axe", "sword":
			return "axe"
		"katana", "dagger":
			return "katana"
		"hammer", "shield":
			return "hammer"
	return "axe"


func _katana_cut(from: Vector2, to: Vector2) -> void:
	var weapon := _player.weapon_controller.weapon
	var style := _melee_style(weapon)
	if style == "" or style == "hammer" or _cut_seen.size() >= MAX_TARGETS:
		return
	var travel := to - from
	_cut_shape.height = CUT_RADIUS * 2.0 + travel.length()
	_cut_query.transform = Transform2D(travel.angle() - PI * 0.5, (from + to) * 0.5)
	for hit in _player.get_world_2d().direct_space_state.intersect_shape(_cut_query, QUERY_LIMIT):
		var enemy := hit["collider"] as Enemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var id := enemy.get_instance_id()
		if _cut_seen.has(id) or _cut_seen.size() >= MAX_TARGETS:
			continue
		_cut_seen[id] = true
		var at := enemy.global_position
		var dir := travel.normalized()
		if style == "axe":
			# Один тяжёлый разрез: крупная вспышка поперёк пути.
			_cut(enemy, weapon, weapon.damage * AXE_CUT, randf() < weapon.crit_chance, dir)
			if _fx != null:
				_fx.burst_dir(at, dir, weapon.effect_color, 10, 0.35, 380.0, 4.0)
				_fx.ring(at, weapon.effect_color, 46.0)
		else:
			# Серия мелких разрезов с небольшим разбросом во времени.
			var low := weapon.trait_id == &"dash_cut" and enemy.hp / maxf(enemy.max_hp, 1.0) < LOW_HP
			for k in KATANA_CUTS:
				if not is_instance_valid(enemy) or not enemy.is_alive():
					break
				var crit := low or randf() < weapon.crit_chance
				_cut(enemy, weapon, weapon.damage * KATANA_CUT, crit, dir.rotated(randf_range(-0.6, 0.6)))
				if _fx != null:
					_fx.burst_dir(at + Vector2(randf_range(-14, 14), randf_range(-14, 6)), dir.rotated(randf_range(-1.0, 1.0)), weapon.effect_color, 3, 0.4, 260.0, 2.4)
		if not enemy.is_alive():
			_cut_kills += 1
			if weapon.trait_id == &"dash_cut" and _cut_kills == CUT_STREAK:
				katana_rage.emit(_cut_kills)


func _cut(enemy: Enemy, weapon: WeaponData, amount: float, crit: bool, dir: Vector2) -> void:
	Enemy.next_kind = &"dash"
	enemy.take_damage(amount * (weapon.crit_mult if crit else 1.0), dir, crit)
	Enemy.next_kind = &""


## Молот/щит: в конце рывка — удар по площади с оглушением.
func _hammer_slam(at: Vector2) -> void:
	var weapon := _player.weapon_controller.weapon
	if _melee_style(weapon) != "hammer":
		return
	var circle := CircleShape2D.new()
	circle.radius = HAMMER_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = PhysicsLayers.ENEMY
	query.collide_with_areas = false
	for hit in _player.get_world_2d().direct_space_state.intersect_shape(query, QUERY_LIMIT):
		var enemy := hit["collider"] as Enemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		_cut(enemy, weapon, weapon.damage * HAMMER_SLAM, randf() < weapon.crit_chance, (enemy.global_position - at).normalized())
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.add_stagger(2.0)
	if _fx != null:
		_fx.ring(at, weapon.effect_color, HAMMER_RADIUS)
		_fx.dust(at + Vector2(0, 8), 10, 90.0)
		_fx.burst(at, weapon.effect_color, 16, 300.0, 4.0)
	hammer_slammed.emit(at)


func _shock(at: Vector2, source_id: int, damage: float) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 130.0
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = PhysicsLayers.ENEMY
	query.collide_with_areas = false
	var jumps := 0
	for hit in _player.get_world_2d().direct_space_state.intersect_shape(query, QUERY_LIMIT):
		var target := hit["collider"] as Node2D
		if not is_instance_valid(target) or target.get_instance_id() == source_id or not target.has_method("take_damage"):
			continue
		if target is Enemy and not (target as Enemy).is_alive():
			continue
		var position := target.global_position
		Enemy.next_kind = &"shock"
		target.call("take_damage", damage, Vector2.ZERO, false)
		Enemy.next_kind = &""
		if _fx != null:
			_fx.ring(position, Color("#6adcff"), 32.0)
		jumps += 1
		if jumps >= 2:
			break
