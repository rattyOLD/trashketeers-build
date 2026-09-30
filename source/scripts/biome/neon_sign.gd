class_name NeonSign
extends Node2D
## Мерцающая неоновая вывеска на заборе (паспорт биома, §3): полусломанный неон.
## Большую часть времени горит ровно, затем с задержкой уходит в серию быстрых
## выключений или в тусклый режим. PointLight2D мягко подсвечивает асфальт вокруг.
## Свет задевает только пол (range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR):
## в Compatibility каждый Light2D перерисовывает освещённые узлы, и так дешевле всего.

enum Icon { CHEESE, ARROW, RACCOON, NO_RAT }
enum Mode { STABLE, GLITCH, DIM }

const PLATE := Color("#141026")
const TUBE_OFF := Color("#3a2f4d")
const LIGHT_ENERGY := 1.1
const LIGHT_SCALE := 2.4

static var _light_texture: GradientTexture2D

var icon: Icon = Icon.CHEESE
var color := Color("#ff2ea6")

var _light: PointLight2D
var _mode: Mode = Mode.STABLE
var _mode_left := 0.0
var _toggles_left := 0
var _lit := true
var _level := 1.0
var _light_id := -1


func setup(sign_icon: Icon, sign_color: Color) -> void:
	icon = sign_icon
	color = sign_color
	_light = PointLight2D.new()
	_light.texture = get_light_texture()
	_light.texture_scale = LIGHT_SCALE
	_light.color = color
	_light.energy = LIGHT_ENERGY
	_light.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
	_light.position = Vector2(0, 90)
	add_child(_light)
	_enter(Mode.STABLE, randf_range(0.3, 3.0))


func _ready() -> void:
	_register.call_deferred()


func _register() -> void:
	if _light != null and is_inside_tree():
		_light_id = EnvLights.add(_light.global_position, color, 280.0, 0.5 / LIGHT_ENERGY, _light)


func _exit_tree() -> void:
	EnvLights.remove(_light_id)
	_light_id = -1


func _process(delta: float) -> void:
	_mode_left -= delta
	if _mode_left > 0.0:
		return
	match _mode:
		Mode.STABLE:
			if randf() < 0.7:
				_toggles_left = randi_range(3, 9)
				_enter(Mode.GLITCH, 0.0)
			else:
				_enter(Mode.DIM, randf_range(0.3, 1.1))
		Mode.GLITCH:
			_lit = not _lit
			_level = 1.0 if _lit else 0.0
			_toggles_left -= 1
			if _toggles_left <= 0:
				_enter(Mode.STABLE, randf_range(1.5, 5.0))
			else:
				_mode_left = randf_range(0.03, 0.14)
		Mode.DIM:
			_enter(Mode.STABLE, randf_range(1.5, 5.0))
	_apply_level()


func _enter(mode: Mode, duration: float) -> void:
	_mode = mode
	_mode_left = duration
	match mode:
		Mode.STABLE:
			_lit = true
			_level = 1.0
		Mode.DIM:
			_lit = true
			_level = 0.3
	_apply_level()


func _apply_level() -> void:
	_light.energy = LIGHT_ENERGY * _level
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-30, -30, 60, 60).grow(3.0), Color("#0a0714"))
	draw_rect(Rect2(-30, -30, 60, 60), PLATE)
	var tube := TUBE_OFF.lerp(color, _level)
	if _level > 0.05:
		_draw_icon(Color(color, 0.25 * _level), 9.0)
	_draw_icon(tube, 3.5)
	if _level > 0.5:
		_draw_icon(Color(1, 1, 1, 0.55 * _level), 1.2)


func _draw_icon(c: Color, width: float) -> void:
	match icon:
		Icon.CHEESE:
			_poly([Vector2(-20, 12), Vector2(20, 12), Vector2(20, -6), Vector2(-20, 4), Vector2(-20, 12)], c, width)
			_poly([Vector2(-20, 4), Vector2(8, -14), Vector2(20, -6)], c, width)
			draw_arc(Vector2(-4, 5), 3.5, 0.0, TAU, 12, c, width * 0.6, true)
			draw_arc(Vector2(9, 1), 2.5, 0.0, TAU, 12, c, width * 0.6, true)
		Icon.ARROW:
			_poly([Vector2(-20, 0), Vector2(14, 0)], c, width)
			_poly([Vector2(4, -12), Vector2(18, 0), Vector2(4, 12)], c, width)
		Icon.RACCOON:
			draw_arc(Vector2(0, 2), 16.0, 0.0, TAU, 28, c, width, true)
			_poly([Vector2(-14, -6), Vector2(-16, -20), Vector2(-6, -13)], c, width)
			_poly([Vector2(14, -6), Vector2(16, -20), Vector2(6, -13)], c, width)
			_poly([Vector2(-11, 0), Vector2(11, 0)], c, width * 1.4)
		Icon.NO_RAT:
			draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, c, width, true)
			_poly([Vector2(-14, -14), Vector2(14, 14)], c, width)
			_poly([Vector2(-10, 6), Vector2(-2, -2), Vector2(8, -2), Vector2(12, 4)], c, width * 0.8)


func _poly(points: Array, c: Color, width: float) -> void:
	draw_polyline(PackedVector2Array(points), c, width, true)


static func get_light_texture() -> GradientTexture2D:
	if _light_texture != null:
		return _light_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	_light_texture = GradientTexture2D.new()
	_light_texture.gradient = gradient
	_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_texture.fill_from = Vector2(0.5, 0.5)
	_light_texture.fill_to = Vector2(1.0, 0.5)
	_light_texture.width = 128
	_light_texture.height = 128
	return _light_texture
