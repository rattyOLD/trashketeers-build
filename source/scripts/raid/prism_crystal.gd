class_name PrismCrystal
extends StaticBody2D
## Призматический кристалл-укрытие Алтаря (документ геометрии рейда, §1–2).
##
## Поле — Area2D с кругом FIELD_RADIUS = 64 px на слое SHIELD. Луч дракона (intersect_ray с
## collide_with_areas) останавливается ровно на границе этого круга: laser_entry_point()
## считает ту же точку аналитически (пересечение луча и окружности), absorb_laser() снимает
## прочность damage * delta. При нуле — взрыв осколков GPUParticles2D, узел выключается и
## ждёт, пока DragonArena не переставит его в новое место (переиспользование вместо instantiate).
##
## Геометрическая тень: из точки-источника к кругу поля проводятся две касательные;
## всё, что дальше кристалла и внутри этого конуса, защищено. shields_point() учитывает
## радиус защищаемого тела: Енот в тени, только если в конус целиком помещается его круг.

signal destroyed(crystal: PrismCrystal)

const FIELD_RADIUS := 64.0
const BODY_RADIUS := 22.0
const MAX_DURABILITY := 100.0
const FIELD_OFFSET := Vector2(0, -18)
const HIT_FLASH_TIME := 0.12
const CRYSTAL := Color("#6fc7ff")
const CRYSTAL_LIGHT := Color("#e8fbff")
const CRYSTAL_DARK := Color("#2a6fa8")
const FIELD := Color("#9ff6ff")
const ART := "res://assets/raid/ice_shield.png"
const DAMAGE_RED := Color("#ff2244")
const LINE := Color("#071b25")
const SHADOW_DRAW_LENGTH := 900.0

var durability := MAX_DURABILITY
## Откуда сейчас светит луч: DragonArena обновляет, чтобы подсвечивать тень на полу.
var shadow_source := Vector2.INF

var _body_shape: CollisionShape2D
var _field: Area2D
var _field_shape: CollisionShape2D
var _shards: GPUParticles2D
var _sparkle: GPUParticles2D
var _hit_flash := 0.0
var _time := 0.0


func setup(fx_layer: Node2D) -> void:
	collision_layer = PhysicsLayers.PROP
	collision_mask = 0
	var body := CircleShape2D.new()
	body.radius = BODY_RADIUS
	_body_shape = CollisionShape2D.new()
	_body_shape.shape = body
	_body_shape.position = Vector2(0, -6)
	add_child(_body_shape)

	_field = Area2D.new()
	_field.collision_layer = PhysicsLayers.SHIELD
	_field.collision_mask = 0
	_field.monitoring = false
	var circle := CircleShape2D.new()
	circle.radius = FIELD_RADIUS
	_field_shape = CollisionShape2D.new()
	_field_shape.shape = circle
	_field_shape.position = FIELD_OFFSET
	_field.add_child(_field_shape)
	add_child(_field)

	_shards = ParticleFactory.burst(ParticleFactory.tex_crystal_shard(), 44, 0.9, ParticleFactory.material({
		"spread": 180.0, "velocity": Vector2(200, 480), "radial_accel": Vector2(160, 320),
		"damping": Vector2(60, 120), "spin": Vector2(-900, 900), "angle": Vector2(0, 360),
		"scale": Vector2(0.8, 1.8), "colors": [CRYSTAL, CRYSTAL_LIGHT, CRYSTAL_DARK], "fade_from": 0.55,
	}))
	_sparkle = ParticleFactory.burst(ParticleFactory.tex_pixel(), 24, 0.6, ParticleFactory.material({
		"spread": 180.0, "velocity": Vector2(80, 260), "damping": Vector2(80, 160),
		"scale": Vector2(1.0, 2.0), "colors": [Color.WHITE, FIELD], "fade_from": 0.3,
	}))
	fx_layer.add_child(_shards)
	fx_layer.add_child(_sparkle)
	_time = randf() * TAU


## Ставит кристалл на новое место и восстанавливает прочность (спавн из пула).
func place(at: Vector2) -> void:
	position = at
	durability = MAX_DURABILITY
	visible = true
	collision_layer = PhysicsLayers.PROP
	_field.collision_layer = PhysicsLayers.SHIELD
	_body_shape.set_deferred("disabled", false)
	_field_shape.set_deferred("disabled", false)
	_sparkle.global_position = global_position + FIELD_OFFSET
	_sparkle.restart()


## Тихо убирает кристалл в резерв пула (без осколков и звука).
func retire() -> void:
	durability = 0.0
	visible = false
	collision_layer = 0
	_field.collision_layer = 0
	_body_shape.set_deferred("disabled", true)
	_field_shape.set_deferred("disabled", true)


func is_intact() -> bool:
	return durability > 0.0


func get_field_center() -> Vector2:
	return global_position + FIELD_OFFSET


## Точка, где луч из from по направлению dir входит в круг поля; Vector2.INF — промах.
## Решение |from + dir*t - c|² = r²: t = b - sqrt(b² - (|from - c|² - r²)), где b = dir·(c - from).
func laser_entry_point(from: Vector2, dir: Vector2) -> Vector2:
	if not is_intact():
		return Vector2.INF
	var to_center := get_field_center() - from
	var b := dir.dot(to_center)
	var disc := b * b - (to_center.length_squared() - FIELD_RADIUS * FIELD_RADIUS)
	if disc < 0.0:
		return Vector2.INF
	var t := b - sqrt(disc)
	if t < 0.0:
		return Vector2.INF
	return from + dir * t


## Вызывается лучом каждый физический кадр, пока он упирается в поле.
func absorb_laser(damage_per_second: float, delta: float) -> void:
	if not is_intact():
		return
	durability -= damage_per_second * delta
	_hit_flash = HIT_FLASH_TIME
	if durability <= 0.0:
		_shatter()


## Геометрическая тень: защищена ли точка (с радиусом тела body_radius) от источника source.
func shields_point(point: Vector2, source: Vector2, body_radius: float = 0.0) -> bool:
	if not is_intact():
		return false
	var to_center := get_field_center() - source
	var center_dist := to_center.length()
	if center_dist <= FIELD_RADIUS:
		return false
	var to_point := point - source
	var point_dist := to_point.length()
	if point_dist <= center_dist:
		return false
	var half_cone := asin(FIELD_RADIUS / center_dist)
	var offset := absf(wrapf(to_point.angle() - to_center.angle(), -PI, PI))
	var body_cone := asin(clampf(body_radius / point_dist, 0.0, 1.0))
	return offset + body_cone <= half_cone


## Многоугольник тени на полу (для подсказки игроку, где укрыться от луча).
func shadow_polygon(source: Vector2, length: float = SHADOW_DRAW_LENGTH) -> PackedVector2Array:
	var center := get_field_center()
	var to_center := center - source
	var dist := to_center.length()
	if dist <= FIELD_RADIUS:
		return PackedVector2Array()
	var half_cone := asin(FIELD_RADIUS / dist)
	var tangent_len := sqrt(dist * dist - FIELD_RADIUS * FIELD_RADIUS)
	var base_angle := to_center.angle()
	var left := source + Vector2.from_angle(base_angle - half_cone) * tangent_len
	var right := source + Vector2.from_angle(base_angle + half_cone) * tangent_len
	var far := tangent_len + length
	return PackedVector2Array([
		left, source + Vector2.from_angle(base_angle - half_cone) * far,
		source + Vector2.from_angle(base_angle + half_cone) * far, right,
	])


func _shatter() -> void:
	durability = 0.0
	visible = false
	collision_layer = 0
	_field.collision_layer = 0
	_body_shape.set_deferred("disabled", true)
	_field_shape.set_deferred("disabled", true)
	_shards.global_position = get_field_center()
	_sparkle.global_position = get_field_center()
	_shards.restart()
	_sparkle.restart()
	SoundManager.play(&"crystal_break", 2.0, false)
	destroyed.emit(self)


func _process(delta: float) -> void:
	if not is_intact():
		return
	_time += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, 46.0, Color(0, 0.05, 0.15, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_field()
	var art := ArenaProp.texture_of(ART)
	if art == null:
		return
	var health := durability / MAX_DURABILITY
	var hit := _hit_flash > 0.0 and int(_time * 30.0) % 2 == 0
	var tint := Color(1.6, 0.6, 0.6) if hit else Color(1, 1, 1).lerp(Color(0.8, 0.9, 1.0), 1.0 - health)
	draw_texture_rect(art, Rect2(Vector2(-54, -128), Vector2(108, 134)), false, tint)


func _draw_field() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.2)
	var hit := _hit_flash > 0.0
	var tint := DAMAGE_RED if hit else FIELD
	draw_circle(FIELD_OFFSET, FIELD_RADIUS, Color(tint, 0.05 + (0.1 if hit else 0.02 * pulse)))
	draw_arc(FIELD_OFFSET, FIELD_RADIUS, 0.0, TAU, 56, Color(tint, 0.25 + 0.1 * pulse + (0.35 if hit else 0.0)), 2.5, true)
	var health := durability / MAX_DURABILITY
	draw_arc(FIELD_OFFSET, FIELD_RADIUS - 6.0, -PI * 0.5, -PI * 0.5 + TAU * health, 40, Color(tint, 0.4), 3.0, true)
