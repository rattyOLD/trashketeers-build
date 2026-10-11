class_name ChainHazards
extends Node2D
## Разлив → предупреждение → огонь/разряд. Фиксированный бюджет, общий рисунок,
## физические часы и отложенная передача соседям вместо рекурсивных взрывов.

const CAPACITY := 16
const WARNING := 1.25
const TICK := 0.5
const FIRE_RADIUS := 76.0
const SHOCK_RADIUS := 96.0
var player: Player
var enemies: EnemyManager
var fx: FxManager
var _zones: Array[Dictionary] = []
var _objects: Array[WeakRef] = []
var _clock := 0.0
var _draw_cd := 0.0
var _warning: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_warning = Node2D.new()
	_warning.z_as_relative = false
	_warning.z_index = 24
	_warning.draw.connect(_draw_warnings)
	add_child(_warning)
	BulletPool.exploded.connect(_on_explosion)
	BulletPool.bullet_hit.connect(_on_bullet_hit)


func attach(objects: Array[DestructibleObject]) -> void:
	clear()
	for object in objects:
		_objects.append(weakref(object))
		if not object.leaked.is_connected(_on_leaked):
			object.leaked.connect(_on_leaked)
		if not object.destroyed.is_connected(_on_destroyed):
			object.destroyed.connect(_on_destroyed)


func clear() -> void:
	for ref in _objects:
		var object := ref.get_ref() as DestructibleObject
		if object == null:
			continue
		if object.leaked.is_connected(_on_leaked):
			object.leaked.disconnect(_on_leaked)
		if object.destroyed.is_connected(_on_destroyed):
			object.destroyed.disconnect(_on_destroyed)
	_objects.clear()
	_zones.clear()
	_clock = 0.0
	queue_redraw()
	if _warning != null:
		_warning.queue_redraw()


func _exit_tree() -> void:
	clear()
	if BulletPool.exploded.is_connected(_on_explosion):
		BulletPool.exploded.disconnect(_on_explosion)
	if BulletPool.bullet_hit.is_connected(_on_bullet_hit):
		BulletPool.bullet_hit.disconnect(_on_bullet_hit)


func spill(at: Vector2, electrical: bool = false) -> void:
	if get_tree().paused:
		return
	for zone in _zones:
		if bool(zone["electric"]) == electrical and (zone["at"] as Vector2).distance_squared_to(at) < 36.0 * 36.0:
			return
	# Активную опасность никогда не переставляем в другое место при переполнении.
	if _zones.size() >= CAPACITY:
		return
	_zones.append({"at": at, "electric": electrical, "armed": electrical, "age": 0.0, "tick": 0.0,
		"left": WARNING + 3.0 if electrical else 20.0, "radius": SHOCK_RADIUS if electrical else FIRE_RADIUS, "spread": false})
	queue_redraw()


func ignite(at: Vector2, radius: float) -> void:
	if get_tree().paused:
		return
	for zone in _zones:
		if zone["armed"] or (zone["at"] as Vector2).distance_to(at) > radius + float(zone["radius"]):
			continue
		zone["armed"] = true
		zone["age"] = 0.0
		zone["left"] = WARNING + 6.0
		zone["tick"] = 0.0
	queue_redraw()


func _on_leaked(object: DestructibleObject) -> void:
	spill(object.global_position + Vector2(0, -6))


func _on_destroyed(object: DestructibleObject) -> void:
	var effect := str(object._destruct.get("effect", ""))
	if object.is_fuel_container():
		_on_leaked(object)
		ignite(object.global_position, 25.0)
	elif effect == "sparks":
		spill(object.global_position, true)


func _on_explosion(at: Vector2, radius: float, _color: Color, _team: Bullet.Team) -> void:
	ignite(at, radius)


func on_fired(weapon: WeaponData, origin: Vector2, direction: Vector2) -> void:
	if weapon.icon != &"flamer":
		return
	for zone in _zones:
		var offset: Vector2 = zone["at"] - origin
		if offset.length() < minf(weapon.max_distance, 300.0) and offset.normalized().dot(direction) > 0.8:
			ignite(zone["at"], 0.0)


func _on_bullet_hit(bullet: Bullet, target: Node2D) -> void:
	if bullet.weapon == null:
		return
	if bullet.weapon.icon == &"flamer" or bullet.weapon.burn > 0.0:
		ignite(target.global_position, 24.0)


func _physics_process(delta: float) -> void:
	if get_tree().paused or player == null or player.is_dead or _zones.is_empty():
		return
	_clock += delta
	var propagation: Array[Dictionary] = []
	# Урон может породить новый разлив: этот разлив начнёт тикать на следующем шаге.
	for zone in _zones.duplicate():
		zone["left"] -= delta
		zone["age"] += delta
		if not zone["armed"] or float(zone["age"]) < WARNING:
			continue
		if not zone["spread"]:
			zone["spread"] = true
			propagation.append(zone)
			SoundManager.play_warning(&"beam_charge", -12.0)
		zone["tick"] -= delta
		if zone["tick"] <= 0.0:
			zone["tick"] += TICK
			_damage(zone)
	for zone in propagation:
		ignite(zone["at"], float(zone["radius"]) * 0.65)
	for i in range(_zones.size() - 1, -1, -1):
		if _zones[i]["left"] <= 0:
			_zones.remove_at(i)
	_draw_cd -= delta
	if _draw_cd <= 0.0:
		_draw_cd = 0.1
		queue_redraw()
		_warning.queue_redraw()


func _damage(zone: Dictionary) -> void:
	var at: Vector2 = zone["at"]
	var radius: float = zone["radius"]
	var electric: bool = zone["electric"]
	var kind: StringName = &"shock" if electric else &"fire"
	if player.global_position.distance_to(at) < radius:
		Player.last_source = &"shock" if electric else &"fire"
		player.take_damage(5.0 if electric else 4.0)
	if enemies != null:
		for e: Enemy in enemies.get_active().duplicate():
			if e.is_alive() and e.global_position.distance_to(at) < radius + e.get_radius() * 0.3:
				Enemy.next_kind = kind
				e.take_damage(16.0 if electric else 12.0)
				if e.is_alive():
					e.add_slow(0.15, 0.6)
	for ref in _objects:
		var object := ref.get_ref() as DestructibleObject
		if object != null and object.is_intact() and object.global_position.distance_to(at) < radius:
			object.take_damage(10.0)
	if fx != null:
		fx.burst(at, Color("#76c9dc") if electric else Color("#df8d42"), 2, 34.0, 3.0)


func _draw() -> void:
	for zone in _zones:
		var at: Vector2 = zone["at"]
		var radius: float = zone["radius"]
		var active: bool = zone["armed"] and float(zone["age"]) >= WARNING
		draw_set_transform(at, 0, Vector2(1, 0.62))
		draw_circle(Vector2.ZERO, radius, Color("#233138") if zone["electric"] else Color("#25221b"))
		draw_arc(Vector2.ZERO, radius * 0.8, 0.3, 4.9, 28, Color("#536760"), 2, true)
		if active:
			var color := Color("#66b8d1") if zone["electric"] else Color("#db8440")
			draw_circle(Vector2.ZERO, radius * 0.9, Color(color, 0.28))
			for i in 7:
				var p := Vector2.from_angle(i * 2.4) * radius * (0.25 + 0.08 * i)
				var height := 8.0 + 4.0 * sin(_clock * 5 + i)
				draw_line(p, p + Vector2(3, -height), color, 3, true)
		draw_set_transform(Vector2.ZERO)


func _draw_warnings() -> void:
	for zone in _zones:
		if not zone["armed"]:
			continue
		var at: Vector2 = zone["at"]
		var radius: float = zone["radius"]
		var color := Color("#81d4ed") if zone["electric"] else Color("#f0bb67")
		_warning.draw_arc(at, radius, 0, TAU, 48, Color("#17212a"), 5, true)
		_warning.draw_arc(at, radius, 0, TAU, 48, color, 2, true)
		if float(zone["age"]) < WARNING:
			var progress := clampf(float(zone["age"]) / WARNING, 0, 1)
			_warning.draw_arc(at, radius + 5, -PI / 2, -PI / 2 + TAU * progress, 48, color, 3, true)
			_warning.draw_line(at + Vector2(0, -15), at + Vector2(0, -4), color, 3, true)
			_warning.draw_circle(at + Vector2(0, 3), 2, color)
