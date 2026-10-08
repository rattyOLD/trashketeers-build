class_name AimReticle
extends Node2D
## Прицел на линии огня (как в шутерах): четыре штриха, которые раскрываются от каждого выстрела и сводятся
## обратно; красный, когда пуля летит точно во врага. В центре вспыхивает хитмаркер «X»: белый — попадание,
## красный и крупный — убийство. Живёт на своём CanvasLayer поверх мира, чтобы цветокоррекция его не глушила.

const IDLE_DISTANCE := 230.0
const BLOOM_PER_SHOT := 0.28
const BLOOM_DECAY := 3.2
const HIT_LIFE := 0.12
const KILL_LIFE := 0.26
const WHITE := Color(1.0, 0.97, 0.9)
const RED := Color("#ff3b30")

var controller: WeaponController
var origin: Node2D

var _bloom := 0.0
var _hit := 0.0
var _hit_crit := false
var _kill := 0.0
var _shown := 0.0


func _ready() -> void:
	z_index = 10


func kick() -> void:
	_bloom = minf(_bloom + BLOOM_PER_SHOT, 1.0)


func hit(crit: bool) -> void:
	_hit = HIT_LIFE
	_hit_crit = crit


func kill() -> void:
	_kill = KILL_LIFE


func _process(delta: float) -> void:
	if controller == null or origin == null or not is_instance_valid(origin):
		return
	var firing := controller.trigger and not controller.auto_mode
	_shown = move_toward(_shown, 1.0 if firing else 0.0, delta * (10.0 if firing else 4.0))
	_bloom = maxf(_bloom - delta * BLOOM_DECAY * (0.4 + 0.6 * (1.0 - _bloom)), 0.0)
	_hit = maxf(_hit - delta, 0.0)
	_kill = maxf(_kill - delta, 0.0)
	if _shown <= 0.0 and _hit <= 0.0 and _kill <= 0.0:
		visible = false
		return
	visible = true
	var target := controller.aim_target
	var distance := IDLE_DISTANCE
	if target != null and is_instance_valid(target):
		distance = origin.global_position.distance_to(target.global_position)
	global_position = origin.global_position + controller.aim_direction.normalized() * clampf(distance, 90.0, 420.0)
	queue_redraw()


func _draw() -> void:
	# Размер на экране не зависит от отдаления камеры: делим на её масштаб.
	var zoom := get_viewport().get_canvas_transform().get_scale().x if get_viewport() != null else 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / maxf(zoom, 0.1))
	var locked := controller != null and controller.aim_target != null and is_instance_valid(controller.aim_target)
	var color := Color(RED if locked else WHITE, 0.9 * _shown)
	var gap := 11.0 + 22.0 * _bloom
	var length := 15.0
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a := dir * gap
		var b := dir * (gap + length)
		draw_line(a, b, Color(0, 0, 0, 0.55 * _shown), 7.0, true)
		draw_line(a, b, color, 3.5, true)
	draw_circle(Vector2.ZERO, 3.0, color)
	if _kill > 0.0:
		_draw_x(_kill / KILL_LIFE, RED, 20.0, 5.0)
	elif _hit > 0.0:
		_draw_x(_hit / HIT_LIFE, Color("#ffb347") if _hit_crit else WHITE, 14.0, 3.5)


## Хитмаркер: четыре диагональных штриха вокруг центра, на появлении чуть шире.
func _draw_x(life: float, tint: Color, size: float, width: float) -> void:
	var spread := 6.0 + 5.0 * (1.0 - life)
	var alpha := clampf(life * 1.6, 0.0, 1.0)
	for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n := dir.normalized()
		draw_line(n * spread, n * (spread + size), Color(0, 0, 0, 0.6 * alpha), width + 2.5, true)
		draw_line(n * spread, n * (spread + size), Color(tint, alpha), width, true)
