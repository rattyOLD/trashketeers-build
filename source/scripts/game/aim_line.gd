class_name AimLine
extends Node2D
## Тонкая прозрачная линия прицела: пока игрок держит стик стрельбы (или мышь), от ствола тянется
## пунктир туда, куда полетят пули. Не мешает обзору: светлая, гаснет к концу, у ближнего боя короче.

const LENGTH := 520.0
const MELEE_LENGTH := 150.0
const DASH := 22.0
const GAP := 14.0

var controller: WeaponController
var _alpha := 0.0
var _dir := Vector2.RIGHT


func _init() -> void:
	z_index = 5
	z_as_relative = false


func _process(delta: float) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var aiming := controller.manual_aim.length_squared() > 0.01 and not controller.auto_mode
	_alpha = move_toward(_alpha, 1.0 if aiming else 0.0, delta * (8.0 if aiming else 4.0))
	if aiming:
		_dir = controller.manual_aim.normalized()
	if _alpha > 0.0 or visible:
		queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01 or controller == null:
		return
	var melee := controller.weapon != null and controller.weapon.is_melee()
	var length := MELEE_LENGTH if melee else LENGTH
	var from := _dir * 34.0 + Vector2(0, -18)
	var t := 0.0
	while t < length:
		var a := from + _dir * t
		var b := from + _dir * minf(t + DASH, length)
		var fade := 1.0 - t / length
		draw_line(a, b, Color(1.0, 0.95, 0.85, 0.32 * fade * _alpha), 3.0, true)
		t += DASH + GAP
	# Точка в конце — куда примерно ляжет выстрел.
	draw_circle(from + _dir * length, 4.0, Color(1.0, 0.6, 0.4, 0.35 * _alpha))
