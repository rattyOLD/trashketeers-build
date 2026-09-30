class_name Comet
extends Area2D
## Ледяная комета. Сама эта Area2D — предупреждающий маркер на земле: пока комета падает,
## маркер заполняется, в момент удара урон получают тела игрока внутри маркера.
## Живёт в CometPool: не удаляется, а выключается (deferred — удар может совпасть с физикой).

signal impacted(comet: Comet)

const IMPACT_RADIUS := 78.0
const FALL_HEIGHT := 560.0
const OUTLINE := Color("#1a0d33")
const WARNING := Color("#ff3355")

var pool_index := -1
var damage := 18.0
var tint := Color("#9fe8ff")

var _time := 0.0
var _fall_time := 1.2
var _collision: CollisionShape2D


func _init() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	visible = false
	var shape := CircleShape2D.new()
	shape.radius = IMPACT_RADIUS
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	_collision.disabled = true
	add_child(_collision)


func activate(at: Vector2, fall_time: float, impact_damage: float, color: Color) -> void:
	global_position = at
	_fall_time = maxf(fall_time, 0.2)
	_time = 0.0
	damage = impact_damage
	tint = color
	collision_mask = PhysicsLayers.PLAYER
	visible = true
	set_deferred("monitoring", true)
	_collision.set_deferred("disabled", false)


func deactivate() -> void:
	visible = false
	collision_mask = 0
	set_deferred("monitoring", false)
	_collision.set_deferred("disabled", true)


## Возвращает false, когда комета упала и её нужно вернуть в пул.
func tick(delta: float) -> bool:
	_time += delta
	queue_redraw()
	if _time < _fall_time:
		return true
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.call("take_damage", damage, global_position.direction_to(body.global_position))
	impacted.emit(self)
	return false


func _draw() -> void:
	var t := clampf(_time / _fall_time, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 18.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.82))
	draw_circle(Vector2.ZERO, IMPACT_RADIUS, Color(WARNING, 0.1 + 0.2 * t))
	draw_circle(Vector2.ZERO, IMPACT_RADIUS * t, Color(WARNING, 0.25))
	draw_arc(Vector2.ZERO, IMPACT_RADIUS, 0.0, TAU, 40, Color(WARNING, 0.6 + 0.4 * pulse), 4.0, true)
	draw_line(Vector2(-14, 0), Vector2(14, 0), Color(WARNING, 0.9), 3.0)
	draw_line(Vector2(0, -14), Vector2(0, 14), Color(WARNING, 0.9), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var fall_dir := Vector2(0.35, 1.0).normalized()
	var head := -fall_dir * FALL_HEIGHT * (1.0 - t * t)
	for i in 6:
		var k := float(i + 1)
		draw_circle(head - fall_dir * k * 16.0, 13.0 - k * 1.8, Color(tint, 0.5 - k * 0.07))
	var side := fall_dir.orthogonal()
	var shard := PackedVector2Array([head - fall_dir * 30.0, head + side * 13.0, head + fall_dir * 22.0, head - side * 13.0])
	draw_colored_polygon(shard, OUTLINE)
	var inner := PackedVector2Array([head - fall_dir * 24.0, head + side * 8.0, head + fall_dir * 16.0, head - side * 8.0])
	draw_colored_polygon(inner, tint)
	draw_colored_polygon(PackedVector2Array([head - fall_dir * 24.0, head + side * 3.0, head, head - side * 8.0]), Color(1, 1, 1, 0.85))
