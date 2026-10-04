class_name DashEffects
extends Node

const MAX_TARGETS := 8
const QUERY_LIMIT := 24
const HIT_RADIUS := Player.RADIUS + 8.0

var _player: Player
var _stats: RunStats
var _fx: FxManager
var _seen: Dictionary = {}
var _element_used := false
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
	_player.dash_started.connect(func() -> void:
		_seen.clear()
		_element_used = false)
	_player.dash_moved.connect(_on_moved)


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
