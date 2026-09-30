class_name WhiteDragonLaser
extends Node2D
## Призматический лазер: трассировка и визуал. Куда смотреть и кого жечь, решает WhiteDragon.
## cast() — один intersect_ray по слою SHIELD (купола кристаллов, collide_with_areas):
## точка попадания фиксируется на границе купола, иначе луч уходит на всю длину.
## Визуал: Line2D-оболочка (неоново-голубая, аддитив) + Line2D-ядро (ослепительно-белое,
## текстура-градиент поперёк луча), в точке контакта с полом — GPUParticles2D: неоново-розовые
## искры (#FF00FF) и пиксельный дым; обсидиан под концом луча выжигается (ScorchLayer).

enum Mode { OFF, TELEGRAPH, FIRE }

const LENGTH := 1700.0
const REACH := 660.0
const HALF_ANGLE := 0.27
const SCORCH_INTERVAL := 0.05
const SHELL_COLOR := Color("#7fdcff")
const CORE_COLOR := Color("#ffffff")
const SPARK_COLOR := Color("#e8fbff")
const SMOKE_COLOR := Color("#cfeeff")

var mode: Mode = Mode.OFF
var origin := Vector2.ZERO
var end_point := Vector2.ZERO
var aim := 0.0
var tint := SHELL_COLOR

var _scorch: ScorchLayer
var _ray := PhysicsRayQueryParameters2D.new()
var _sparks: GPUParticles2D
var _smoke: GPUParticles2D
var _scorch_timer := 0.0
var _time := 0.0


func setup(exclude: Array[RID], scorch: ScorchLayer) -> void:
	_scorch = null
	_ray.collision_mask = PhysicsLayers.SHIELD
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = false
	_ray.exclude = exclude

	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive

	_sparks = ParticleFactory.stream(ParticleFactory.tex_spark(), 48, 0.45, ParticleFactory.material({
		"direction": Vector2.UP, "spread": 180.0, "velocity": Vector2(160, 420), "damping": Vector2(200, 320),
		"gravity": Vector2(0, 260), "align": true, "scale": Vector2(0.8, 1.5), "color": SPARK_COLOR, "fade_from": 0.4,
	}))
	_sparks.material = additive
	_smoke = ParticleFactory.stream(ParticleFactory.tex_pixel(), 30, 1.1, ParticleFactory.material({
		"direction": Vector2.UP, "spread": 40.0, "velocity": Vector2(30, 80), "damping": Vector2(10, 30),
		"scale": Vector2(2.0, 4.0), "scale_curve_end": 0.3, "color": Color(SMOKE_COLOR, 0.7), "fade_from": 0.2,
	}))
	add_child(_smoke)
	add_child(_sparks)
	_set_mode(Mode.OFF)


func show_telegraph(color: Color) -> void:
	tint = color
	_set_mode(Mode.TELEGRAPH)


func show_fire() -> void:
	_scorch_timer = 0.0
	_set_mode(Mode.FIRE)


func hide_beam() -> void:
	_set_mode(Mode.OFF)


## Трассирует луч из from под углом angle и обновляет визуал.
## Возвращает {"end": Vector2, "collider": Object или null}.
func cast(from: Vector2, angle: float, delta: float) -> Dictionary:
	origin = from
	aim = angle
	var dir := Vector2.from_angle(angle)
	_ray.from = from
	_ray.to = from + dir * LENGTH
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	end_point = hit["position"] if not hit.is_empty() else _ray.to
	_update_visuals(delta)
	return {"end": end_point, "collider": hit.get("collider")}


func _update_visuals(delta: float) -> void:
	_time += delta
	if mode == Mode.FIRE:
		_sparks.global_position = end_point
		_smoke.global_position = end_point
	queue_redraw()


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_sparks.emitting = mode == Mode.FIRE
	_smoke.emitting = mode == Mode.FIRE
	queue_redraw()


func _fan(length: float, half: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array([origin])
	for i in steps + 1:
		pts.append(origin + Vector2.from_angle(aim + lerpf(-half, half, float(i) / steps)) * length)
	return pts


## Морозное дыхание - конус: яркое ядро у пасти, к краю тает; упирается в купол щита.
func _draw() -> void:
	if mode == Mode.OFF:
		return
	var length := minf(REACH, origin.distance_to(end_point))
	if mode == Mode.TELEGRAPH:
		var blink := 0.35 + 0.65 * absf(sin(_time * 22.0))
		var edge := Color(tint, 0.9 * blink)
		draw_line(origin, origin + Vector2.from_angle(aim - HALF_ANGLE) * REACH, edge, 4.0, true)
		draw_line(origin, origin + Vector2.from_angle(aim + HALF_ANGLE) * REACH, edge, 4.0, true)
		draw_arc(origin, REACH, aim - HALF_ANGLE, aim + HALF_ANGLE, 32, Color(tint, 0.5 * blink), 3.0, true)
		draw_colored_polygon(_fan(REACH, HALF_ANGLE, 16), Color(tint, 0.05 + 0.05 * blink))
		return
	var wobble := 1.0 + sin(_time * 34.0) * 0.06
	var outer := _fan(length, HALF_ANGLE * wobble, 18)
	var colors := PackedColorArray([Color(tint, 0.85)])
	for i in outer.size() - 1:
		colors.append(Color(tint, 0.12))
	draw_polygon(outer, colors)
	var inner := _fan(length * 0.82, HALF_ANGLE * 0.45 * wobble, 12)
	var inner_colors := PackedColorArray([Color(CORE_COLOR, 0.95)])
	for i in inner.size() - 1:
		inner_colors.append(Color(SHELL_COLOR, 0.0))
	draw_polygon(inner, inner_colors)
	for i in 7:
		var lane := fmod(_time * 1.3 + i * 0.37, 1.0)
		var a := aim + sin(i * 2.3 + _time * 3.0) * HALF_ANGLE * 0.8
		var at := origin + Vector2.from_angle(a) * length * lane
		draw_circle(at, 5.0 * (1.0 - lane) + 1.5, Color(1, 1, 1, 0.9 * (1.0 - lane)))
