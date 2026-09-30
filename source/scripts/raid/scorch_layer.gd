class_name ScorchLayer
extends Node2D
## Выжженные следы Призматического Луча на обсидиане. Пул данных фиксированного размера
## (кольцевой буфер): при переполнении новый след перезаписывает самый старый.

const CAPACITY := 160
const LIFE := 7.0

var _pos := PackedVector2Array()
var _life := PackedFloat32Array()
var _color := PackedColorArray()
var _next := 0
var _alive := 0


func _init() -> void:
	_pos.resize(CAPACITY)
	_life.resize(CAPACITY)
	_color.resize(CAPACITY)


func add(at: Vector2, glow: Color) -> void:
	if _life[_next] <= 0.0:
		_alive += 1
	_pos[_next] = at + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	_life[_next] = LIFE
	_color[_next] = glow
	_next = (_next + 1) % CAPACITY


func _process(delta: float) -> void:
	if _alive == 0:
		return
	for i in CAPACITY:
		if _life[i] > 0.0:
			_life[i] -= delta
			if _life[i] <= 0.0:
				_alive -= 1
	queue_redraw()


func _draw() -> void:
	for i in CAPACITY:
		var life := _life[i]
		if life <= 0.0:
			continue
		var t := life / LIFE
		draw_circle(_pos[i], 26.0, Color(0.02, 0.0, 0.05, 0.55 * t))
		draw_circle(_pos[i], 15.0, Color(_color[i], 0.22 * t * t))
