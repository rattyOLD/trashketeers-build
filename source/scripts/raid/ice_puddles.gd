class_name IcePuddles
extends Node2D
## Ледяные лужи от осколков: пока лужа жива, Енот в ней мёрзнет и замедляется.
## Фиксированный пул: старейшая лужа перезаписывается, узлы не создаются на лету.

const ART := "res://assets/raid/ice_puddle.png"
const CAPACITY := 10
const LIFETIME := 9.0
const RADIUS := 104.0
const SQUASH := 0.66
const FADE_IN := 0.25
const FADE_OUT := 1.6

var _at: Array[Vector2] = []
var _age: Array[float] = []
var _next := 0


func _init() -> void:
	z_index = -7
	for i in CAPACITY:
		_at.append(Vector2.ZERO)
		_age.append(INF)


func spawn(at: Vector2) -> void:
	_at[_next] = at
	_age[_next] = 0.0
	_next = (_next + 1) % CAPACITY


func contains(point: Vector2) -> bool:
	for i in CAPACITY:
		if _age[i] >= LIFETIME:
			continue
		var d := point - _at[i]
		if d.x * d.x / (RADIUS * RADIUS) + d.y * d.y / (RADIUS * RADIUS * SQUASH * SQUASH) < 0.8:
			return true
	return false


func _process(delta: float) -> void:
	for i in CAPACITY:
		if _age[i] < LIFETIME:
			_age[i] += delta
	queue_redraw()


func _draw() -> void:
	var art := ArenaProp.texture_of(ART)
	if art == null:
		return
	for i in CAPACITY:
		var age := _age[i]
		if age >= LIFETIME:
			continue
		var alpha := minf(age / FADE_IN, 1.0) * minf((LIFETIME - age) / FADE_OUT, 1.0)
		var grow := 0.75 + 0.25 * minf(age / FADE_IN, 1.0)
		var size := Vector2(RADIUS * 2.0, RADIUS * 2.0 * SQUASH) * 1.12 * grow
		draw_texture_rect(art, Rect2(_at[i] - size * 0.5, size), false, Color(1, 1, 1, alpha * 0.95))
