class_name ChargeTower
extends Node2D
## Вышка-ретранслятор (Выживание 2.0): стой в круге — вышка заряжается; вышел — заряд медленно тает.
## Полный заряд → Game предлагает выбор 1 из 3 «прошивок» (статы с редкостью, редкость тянет Удача).
## Рисунок временный (код): мачта с тарелкой и мигающим огнём; арт Астры — assets/world/charge_tower.png.

signal charged(tower: ChargeTower)

const RADIUS := 130.0
const CHARGE_TIME := 5.0
const DECAY := 0.25
const ART := "res://assets/world/charge_tower.png"

var player: Node2D
var used := false
var _charge := 0.0
var _time := randf() * 10.0
var _art: Texture2D


func _ready() -> void:
	if ResourceLoader.exists(ART):
		_art = load(ART) as Texture2D


func _process(delta: float) -> void:
	_time += delta
	if used or player == null or not is_instance_valid(player):
		if used:
			set_process(false)
			queue_redraw()
		return
	var inside := player.global_position.distance_squared_to(global_position) < RADIUS * RADIUS
	var before := _charge
	_charge = clampf(_charge + (delta / CHARGE_TIME if inside else -delta * DECAY / CHARGE_TIME), 0.0, 1.0)
	if _charge >= 1.0:
		used = true
		charged.emit(self)
	if inside or before != _charge or int(_time * 4.0) != int((_time - delta) * 4.0):
		queue_redraw()


func _draw() -> void:
	var tint := Color("#6adcff") if not used else Color(0.5, 0.5, 0.6)
	# Круг зоны: пунктир по краю, заливка растёт с зарядом.
	if not used:
		# Столб света над вышкой — виден издалека, зовёт к себе.
		var pulse := 0.5 + 0.5 * sin(_time * 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-26, -150), Vector2(26, -150), Vector2(10, -420), Vector2(-10, -420)]),
			Color(tint, 0.10 + 0.06 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, RADIUS, Color(tint, 0.12 if not used else 0.03))
	if not used:
		draw_circle(Vector2.ZERO, RADIUS * _charge, Color(tint, 0.16))
		var dashes := 24
		for i in dashes:
			var a := TAU * float(i) / dashes + _time * 0.4
			draw_arc(Vector2.ZERO, RADIUS, a, a + TAU / dashes * 0.55, 4, Color(tint, 0.95), 6.0)
		if _charge > 0.0:
			draw_arc(Vector2.ZERO, RADIUS + 10.0, -PI * 0.5, -PI * 0.5 + TAU * _charge, 48, Color("#ffd23f"), 7.0)
	draw_set_transform(Vector2.ZERO)
	if _art != null:
		draw_texture(_art, Vector2(-_art.get_width() * 0.5, -_art.get_height() + 6.0), Color.WHITE if not used else Color(0.6, 0.6, 0.65))
		return
	# Мачта: тень, ферма, тарелка, огонь.
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	var steel := Color("#3a3550") if not used else Color("#2c2a33")
	draw_colored_polygon(PackedVector2Array([Vector2(-22, 0), Vector2(22, 0), Vector2(6, -150), Vector2(-6, -150)]), Color("#120d1c"))
	draw_colored_polygon(PackedVector2Array([Vector2(-18, -2), Vector2(18, -2), Vector2(4, -146), Vector2(-4, -146)]), steel)
	for i in 5:
		var y := -10.0 - i * 28.0
		var w := 18.0 - i * 2.8
		draw_line(Vector2(-w, y), Vector2(w, y - 22.0), Color("#120d1c"), 3.0)
		draw_line(Vector2(w, y), Vector2(-w, y - 22.0), Color("#120d1c"), 3.0)
	draw_arc(Vector2(10, -132), 22.0, PI * 0.6, PI * 1.6, 12, Color("#120d1c"), 9.0)
	draw_arc(Vector2(10, -132), 22.0, PI * 0.6, PI * 1.6, 12, Color("#c9c3d9") if not used else Color("#6b6878"), 5.0)
	var blink := 0.5 + 0.5 * sin(_time * (6.0 if _charge > 0.0 else 2.5))
	var light := Color("#ff4d4d") if not used else Color("#444")
	if _charge > 0.0 and not used:
		light = Color("#ffd23f")
	draw_circle(Vector2(0, -156), 7.0, Color("#120d1c"))
	draw_circle(Vector2(0, -156), 5.0, light)
	if not used:
		draw_circle(Vector2(0, -156), 12.0 + 6.0 * blink, Color(light, 0.25 * blink))
