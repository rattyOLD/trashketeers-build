class_name StoryGate
extends Node2D
## Ворота-шторка в стене комнаты: заперты, пока засада не зачищена; физическая коллизия + рольставни.

signal opened

const LIFT_TIME := 1.1
const COLOR_PLATE := Color("#2c2f44")
const COLOR_RIB := Color("#1a1c2b")
const COLOR_LAMP_LOCKED := Color("#ff3b5c")
const COLOR_LAMP_OPEN := Color("#7cff6b")

static var _frames: Array[Texture2D] = []
static var _sign: Texture2D
var rect := Rect2()
var is_open := false

var _body: StaticBody2D
var _shape: CollisionShape2D
var _lift := 0.0
var _target := 0.0
var _time := 0.0


func setup(gate_rect: Rect2) -> void:
	rect = gate_rect
	_body = StaticBody2D.new()
	_body.collision_layer = PhysicsLayers.WORLD
	_shape = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	_shape.shape = box
	_shape.position = rect.get_center()
	_body.add_child(_shape)
	add_child(_body)
	y_sort_enabled = false


func open() -> void:
	if is_open:
		return
	is_open = true
	_target = 1.0
	_shape.set_deferred("disabled", true)
	SoundManager.play(&"shield_up", -2.0, false)


func close() -> void:
	is_open = false
	_target = 0.0
	_shape.set_deferred("disabled", false)
	SoundManager.play(&"shield_up", -2.0, false)


func _process(delta: float) -> void:
	_time += delta
	_lift = move_toward(_lift, _target, delta / LIFT_TIME)
	queue_redraw()


static func _load_frames() -> void:
	if not _frames.is_empty():
		return
	for name in ["closed", "raise_1", "raise_2", "raise_3", "raise_4", "open"]:
		var tex := load("res://assets/story/gates/%s.png" % name) as Texture2D
		if tex == null:
			_frames.clear()
			return
		_frames.append(tex)


func _draw() -> void:
	_load_frames()
	if _sign == null:
		_sign = load("res://assets/story/gates/aquilon_sign.png") as Texture2D
	if not _frames.is_empty():
		var index := clampi(roundi(_lift * float(_frames.size() - 1)), 0, _frames.size() - 1)
		var pad := Vector2(24.0, 18.0)
		draw_texture_rect(_frames[index], Rect2(rect.position - pad, rect.size + pad * 2.0), false)
		var glow := COLOR_LAMP_OPEN if is_open else Color(COLOR_LAMP_LOCKED, 0.6 + 0.4 * sin(_time * 6.0))
		draw_circle(rect.position + Vector2(-6.0, -4.0), 7.0, Color(glow, 0.55))
		_draw_sign()
		return
	var r := rect
	var plate_h := r.size.y * (1.0 - _lift)
	var pillar := Color("#3a3d56")
	draw_rect(Rect2(r.position + Vector2(-18, -26), Vector2(18, r.size.y + 40)), pillar)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y - 26), Vector2(18, r.size.y + 40)), pillar)
	draw_rect(Rect2(r.position + Vector2(-18, -26), Vector2(r.size.x + 36, 18)), Color("#4a4e68"))
	if plate_h > 2.0:
		var plate := Rect2(r.position, Vector2(r.size.x, plate_h))
		draw_rect(plate, COLOR_PLATE)
		var y := plate.position.y + 10.0
		while y < plate.end.y:
			draw_line(Vector2(plate.position.x, y), Vector2(plate.end.x, y), COLOR_RIB, 3.0)
			y += 14.0
		var x := plate.position.x
		while x < plate.end.x:
			draw_line(Vector2(x, plate.end.y - 10.0), Vector2(x + 12.0, plate.end.y), Color("#ffb020"), 5.0)
			draw_line(Vector2(x + 12.0, plate.end.y - 10.0), Vector2(x + 24.0, plate.end.y), COLOR_RIB, 5.0)
			x += 24.0
		draw_rect(plate, Color("#0c0d16"), false, 4.0)
	var pulse := 0.6 + 0.4 * sin(_time * 6.0)
	var lamp := COLOR_LAMP_OPEN if is_open else Color(COLOR_LAMP_LOCKED, pulse)
	for side in [-1.0, 1.0]:
		var lx: float = r.get_center().x + side * (r.size.x * 0.5 + 9.0)
		draw_circle(Vector2(lx, r.position.y - 14.0), 9.0, lamp)
		draw_circle(Vector2(lx, r.position.y - 14.0), 16.0, Color(lamp, 0.25))
	_draw_sign()


func _draw_sign() -> void:
	if _sign == null:
		return
	var width := minf(rect.size.x * 0.7, 116.0)
	var height := width * float(_sign.get_height()) / float(_sign.get_width())
	draw_texture_rect(_sign, Rect2(Vector2(rect.get_center().x - width * 0.5, rect.position.y - height - 8.0), Vector2(width, height)), false)
