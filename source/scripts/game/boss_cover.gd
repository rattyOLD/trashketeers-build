class_name BossCover
extends Node2D
## Reuse map cover: preserve it to block shots, or destroy it near the boss
## to open an attack window. No extra collisions or navigation changes.
const LIMIT := 3
const MARK_RANGE := 700.0
const BLAST_RANGE := 185.0
var _boss: WeakRef
var _barrels: Array[WeakRef] = []
var interruptions := 0
var _draw_left := 0.0

func attach(boss: Enemy, objects: Array[DestructibleObject]) -> int:
	clear()
	if boss.data.boss_pattern != "baron":
		return 0
	_boss = weakref(boss)
	var candidates: Array[DestructibleObject] = []
	for object in objects:
		if is_instance_valid(object) and object.is_intact() and object.is_fuel_container() and object.global_position.distance_to(boss.global_position) <= MARK_RANGE:
			candidates.append(object)
	candidates.sort_custom(func(a: DestructibleObject, b: DestructibleObject) -> bool: return a.global_position.distance_squared_to(boss.global_position) < b.global_position.distance_squared_to(boss.global_position))
	for object in candidates.slice(0, LIMIT):
		_barrels.append(weakref(object))
		object.destroyed.connect(_broken)
	queue_redraw()
	return _barrels.size()

func _broken(object: DestructibleObject) -> void:
	if _boss == null:
		return
	var boss := _boss.get_ref() as Enemy
	if boss == null or not boss.is_alive() or boss.data.boss_pattern != "baron" or boss.global_position.distance_to(object.global_position) > BLAST_RANGE + boss.data.radius:
		return
	# A short opening rather than a percentage-HP explosion that scales into a one-shot.
	boss.posture_stun = maxf(boss.posture_stun, 0.9)
	boss._status_key = -1
	interruptions += 1
	queue_redraw()

func _process(delta: float) -> void:
	if _boss == null:
		return
	var boss := _boss.get_ref() as Enemy
	if boss == null or not boss.is_alive() or boss.data.boss_pattern != "baron":
		clear()
		return
	_draw_left -= delta
	if _draw_left <= 0.0:
		_draw_left = 0.15
		queue_redraw()

func _draw() -> void:
	for ref in _barrels:
		var object := ref.get_ref() as DestructibleObject
		if object == null or not object.is_intact():
			continue
		var at := to_local(object.global_position)
		draw_arc(at, 32.0, 0.0, TAU, 24, Color("#f5cd79"), 2.0, true)
		var boss := _boss.get_ref() as Enemy if _boss != null else null
		if boss != null and boss.global_position.distance_to(object.global_position) <= BLAST_RANGE + boss.data.radius:
			draw_arc(at, BLAST_RANGE, 0.0, TAU, 40, Color(1.0, 0.74, 0.3, 0.25), 1.5, true)

func clear() -> void:
	for ref in _barrels:
		var object := ref.get_ref() as DestructibleObject
		if object != null and object.destroyed.is_connected(_broken):
			object.destroyed.disconnect(_broken)
	_barrels.clear()
	_boss = null
	queue_redraw()

func _exit_tree() -> void:
	clear()
