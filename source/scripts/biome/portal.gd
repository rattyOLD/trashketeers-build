class_name Portal
extends Area2D
## Портал в следующую главу: появляется на помосте после победы над боссом. Раскрывается,
## крутит неоновый вихрь, втягивает искры; когда Енот входит в кольцо — сигнал entered.
## Он единственный на арене должен «звать» игрока, поэтому яркий и пульсирует.

signal entered

const RADIUS := 70.0
const OPEN_TIME := 0.9
const SPARKS := 26

var color := Color("#b84dff")
var accent := Color("#00f5ff")
var _time := 0.0
var _open := 0.0
var _armed := false
var _sparks: Array[Vector3] = []
var _light: PointLight2D
var _light_id := -1


func _init() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitoring = false
	var shape := CircleShape2D.new()
	shape.radius = RADIUS * 0.7
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -RADIUS * 0.5)
	add_child(collision)
	for i in SPARKS:
		_sparks.append(Vector3(randf() * TAU, randf_range(0.6, 1.6), randf()))
	body_entered.connect(_on_body_entered)


func open(at: Vector2, main_color: Color, second_color: Color) -> void:
	global_position = at
	color = main_color
	accent = second_color
	_open = 0.0
	_armed = false
	visible = true
	if _light == null:
		_light = PointLight2D.new()
		_light.texture = NeonSign.get_light_texture()
		_light.texture_scale = 5.0
		_light.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
		add_child(_light)
	_light.color = color
	_light.energy = 0.0
	EnvLights.remove(_light_id)
	_light_id = EnvLights.add(at, color, 320.0, 0.8, _light)
	set_process(true)


func close() -> void:
	visible = false
	_armed = false
	set_deferred("monitoring", false)
	EnvLights.remove(_light_id)
	_light_id = -1
	set_process(false)


func _exit_tree() -> void:
	EnvLights.remove(_light_id)
	_light_id = -1


func _process(delta: float) -> void:
	_time += delta
	_open = minf(_open + delta / OPEN_TIME, 1.0)
	if _light != null:
		_light.energy = 1.4 * _open * (0.85 + 0.15 * sin(_time * 5.0))
	if _open >= 1.0 and not _armed:
		_armed = true
		set_deferred("monitoring", true)
	for i in _sparks.size():
		var s := _sparks[i]
		s.z -= delta * 0.55
		if s.z <= 0.0:
			s = Vector3(randf() * TAU, randf_range(0.6, 1.6), 1.0)
		_sparks[i] = s
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _armed and body is Player:
		_armed = false
		entered.emit()


func _draw() -> void:
	var e := _ease(_open)
	var center := Vector2(0, -RADIUS * 0.55)
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, RADIUS * 1.25 * e, Color(color, 0.22))
	draw_arc(Vector2.ZERO, RADIUS * 1.1 * e, 0.0, TAU, 48, Color(accent, 0.6), 5.0, true)
	draw_set_transform(center, 0.0, Vector2(0.78, 1.0) * e)
	for k in 6:
		var t := float(k) / 6.0
		var r := RADIUS * (1.0 - t * 0.8)
		var a0 := _time * (2.0 + t * 3.0) + t * 2.0
		draw_arc(Vector2.ZERO, r, a0, a0 + PI * 1.3, 32, Color(color.lerp(accent, t), 0.35 + 0.5 * t), 7.0 - t * 4.0, true)
	draw_circle(Vector2.ZERO, RADIUS * 0.34, Color(1, 1, 1, 0.55 + 0.25 * sin(_time * 6.0)))
	draw_circle(Vector2.ZERO, RADIUS * 0.22, Color(accent.lightened(0.5), 0.9))
	for s in _sparks:
		var dist := RADIUS * 1.4 * s.z * s.y
		var p := Vector2.from_angle(s.x + _time * 1.5) * dist
		draw_circle(p, 3.0 + 2.0 * (1.0 - s.z), Color(accent, 0.8 * (1.0 - s.z * 0.5)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0) + sin(t * PI) * 0.12
