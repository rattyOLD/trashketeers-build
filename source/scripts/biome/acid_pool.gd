class_name AcidPool
extends Area2D
## Лужа кислоты из лопнувшего токсичного мешка (паспорт биома, §2): Area2D на слое декалей,
## плавно сжимается и исчезает за LIFETIME секунд. Пока жива — жжёт всех, кто в ней стоит
## (Енота и крыс: крыс можно заманивать в кислоту). Один экземпляр на мешок, переиспользуется.

const LIFETIME := 5.0
const RADIUS := 64.0
const TICK := 0.5
const DAMAGE := 5.0
const SLOW := 0.4
const TOXIC := Color("#39ff14")

var _time_left := 0.0
var _life := LIFETIME
var _size := 1.0
var _tick_left := 0.0
var _collision: CollisionShape2D
var _bubbles: Array[Vector3] = []
var _light_id := -1


func _init() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	visible = false
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	_collision.disabled = true
	add_child(_collision)
	for i in 7:
		_bubbles.append(Vector3(randf_range(-40, 40), randf_range(-18, 18), randf() * TAU))
	set_process(false)


func activate(at: Vector2, size: float = 1.0, life: float = LIFETIME) -> void:
	global_position = at
	_size = size
	_life = life
	_time_left = life
	_tick_left = TICK
	scale = Vector2.ONE * size
	visible = true
	EnvLights.remove(_light_id)
	_light_id = EnvLights.add(at, TOXIC, RADIUS * 2.2 * size, 0.45, self)
	collision_mask = PhysicsLayers.PLAYER | PhysicsLayers.ENEMY
	set_deferred("monitoring", true)
	_collision.set_deferred("disabled", false)
	set_process(true)


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		visible = false
		EnvLights.remove(_light_id)
		_light_id = -1
		collision_mask = 0
		set_deferred("monitoring", false)
		_collision.set_deferred("disabled", true)
		set_process(false)
		return
	scale = Vector2.ONE * _size * lerpf(0.15, 1.0, minf(_time_left / _life * 2.0, 1.0))
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK
		for body in get_overlapping_bodies():
			if body is Enemy and (body as Enemy).data != null:
				(body as Enemy).add_slow(SLOW, TICK * 2.0)
			if body.has_method("take_damage"):
				body.call("take_damage", DAMAGE, Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() * 0.001
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, RADIUS, Color(TOXIC, 0.3))
	draw_circle(Vector2(-10, 4), RADIUS * 0.75, Color(TOXIC, 0.35))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, Color(TOXIC, 0.75), 3.0, true)
	for b in _bubbles:
		var r := 3.0 + 2.5 * (0.5 + 0.5 * sin(t * 4.0 + b.z))
		draw_circle(Vector2(b.x, b.y * 1.8), r, Color(0.8, 1.0, 0.7, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
