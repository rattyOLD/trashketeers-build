class_name WarmCircles
extends Node2D
## Тёплые круги ульты «Абсолютный Ноль»: только внутри них метель не морозит Енота.

const RADIUS := 150.0
const FADE_IN := 0.5

var _points: Array[Vector2] = []
var _age := 0.0
var _fade_out := -1.0


func _init() -> void:
	z_index = -6
	z_as_relative = false
	visible = false
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func show_at(points: Array[Vector2]) -> void:
	_points = points
	_age = 0.0
	_fade_out = -1.0
	modulate.a = 1.0
	visible = true
	set_process(true)
	queue_redraw()


func hide_circles() -> void:
	if not visible:
		return
	_fade_out = 0.4


func contains(point: Vector2) -> bool:
	if not visible or _fade_out >= 0.0:
		return false
	for p in _points:
		if p.distance_to(point) <= RADIUS:
			return true
	return false


func nearest_to(point: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for p in _points:
		var d := p.distance_to(point)
		if d < best_d:
			best_d = d
			best = p
	return best


func _process(delta: float) -> void:
	_age += delta
	if _fade_out >= 0.0:
		_fade_out -= delta
		modulate.a = clampf(_fade_out / 0.4, 0.0, 1.0)
		if _fade_out <= 0.0:
			visible = false
			_fade_out = -1.0
			set_process(false)
			return
	queue_redraw()


func _draw() -> void:
	var grow := clampf(_age / FADE_IN, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_age * 5.0)
	for p in _points:
		var r := RADIUS * grow
		for layer in 6:
			draw_circle(p, r * (1.0 - layer * 0.14), Color(1.0, 0.55, 0.15, 0.05 + 0.02 * layer))
		draw_arc(p, r, 0.0, TAU, 72, Color(1.0, 0.78, 0.35, 0.65 + 0.3 * pulse), 5.0, true)
		draw_arc(p, r * 0.72, _age * 0.9, _age * 0.9 + TAU * 0.7, 48, Color(1.0, 0.9, 0.6, 0.45), 3.0, true)
		for i in 8:
			var a := _age * 1.3 + TAU * i / 8.0
			var flame := p + Vector2.from_angle(a) * r * 0.5
			draw_circle(flame - Vector2(0, 8.0 * pulse), 9.0 + 4.0 * pulse, Color(1.0, 0.7, 0.2, 0.5))
