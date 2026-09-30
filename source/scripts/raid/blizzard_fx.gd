class_name BlizzardFx
extends CanvasLayer
## Экранная метель ульты: белёсая дымка и косые полосы снега поверх боя, но под интерфейсом.

const STREAKS := 70

var _veil: Control
var _target := 0.0
var _level := 0.0
var _time := 0.0
var _streaks: Array = []


func _init() -> void:
	layer = 5
	for i in STREAKS:
		_streaks.append([randf(), randf(), randf_range(0.6, 1.6), randf_range(40.0, 120.0)])
	_veil = Control.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.draw.connect(_draw_veil)
	add_child(_veil)
	visible = false


func set_active(active: bool) -> void:
	_target = 1.0 if active else 0.0
	if active:
		visible = true


func _process(delta: float) -> void:
	_time += delta
	_level = move_toward(_level, _target, delta * 1.6)
	if _level <= 0.0 and _target <= 0.0:
		visible = false
		return
	_veil.queue_redraw()


func _draw_veil() -> void:
	var size := _veil.size
	_veil.draw_rect(Rect2(Vector2.ZERO, size), Color(0.78, 0.92, 1.0, 0.22 * _level))
	for s in _streaks:
		var x := posmod(s[0] * size.x - _time * s[3] * 4.0, size.x)
		var y := posmod(s[1] * size.y + _time * s[3] * 2.2, size.y)
		var length: float = 60.0 * s[2]
		_veil.draw_line(Vector2(x, y), Vector2(x - length, y + length * 0.4), Color(1, 1, 1, 0.5 * _level), 2.0 * s[2], true)
