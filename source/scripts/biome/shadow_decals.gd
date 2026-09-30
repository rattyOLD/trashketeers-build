class_name ShadowDecals
extends Node2D
## Мягкие тени неподвижных объектов (заборы, машины, контейнеры, кучи мусора) на слое декалей:
## свет падает сверху-слева, поэтому тень смещена вправо-вниз на долю «высоты» объекта.
## Размытие — несколько вложенных полупрозрачных фигур. Статично: рисуется один раз, узел на
## сектор карты — чтобы экранная отбраковка отсекала невидимые секторы целиком.

const LAYERS := 4
const ALPHA := 0.075
const COLOR := Color(0.02, 0.0, 0.05)

var _rects: Array[Rect2] = []
var _heights := PackedFloat32Array()
var _circles := PackedVector3Array()


func add_rect(rect: Rect2, height: float) -> void:
	_rects.append(rect)
	_heights.append(height)
	queue_redraw()


func add_circle(center: Vector2, radius: float, height: float) -> void:
	_circles.append(Vector3(center.x + height * 0.22, center.y + height * 0.14, radius))
	queue_redraw()


func _draw() -> void:
	for i in _rects.size():
		var r := _rects[i]
		var h := _heights[i]
		var shifted := Rect2(r.position + Vector2(h * 0.22, h * 0.12), r.size + Vector2(h * 0.08, h * 0.2))
		for k in LAYERS:
			draw_rect(shifted.grow(2.0 + k * 5.0), Color(COLOR, ALPHA))
	for c in _circles:
		for k in LAYERS:
			draw_set_transform(Vector2(c.x, c.y), 0.0, Vector2(1.0, 0.62))
			draw_circle(Vector2.ZERO, c.z + 2.0 + k * 5.0, Color(COLOR, ALPHA))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
