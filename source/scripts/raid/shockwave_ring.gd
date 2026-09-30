class_name ShockwaveRing
extends Line2D
## Плоская ударная волна приземления (паспорт Алтаря, §2): кольцо Line2D, которое
## расширяется, истончается и «дрожит» — точки окружности смещаются шумом по радиусу.
## Создаётся заранее и переиспользуется через play().

const POINTS := 48
const DURATION := 0.55

var _time := -1.0
var _max_radius := 200.0
var _phase := 0.0


func _init() -> void:
	closed = true
	width = 10.0
	default_color = Color.WHITE
	joint_mode = Line2D.LINE_JOINT_ROUND
	visible = false
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	for i in POINTS:
		add_point(Vector2.ZERO)
	set_process(false)


func play(center: Vector2, max_radius: float, color: Color, delay: float = 0.0) -> void:
	global_position = center
	_max_radius = max_radius
	default_color = color
	_phase = randf() * TAU
	_time = -delay
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _time < 0.0:
		return
	var t := _time / DURATION
	if t >= 1.0:
		visible = false
		set_process(false)
		return
	visible = true
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var radius := _max_radius * eased
	for i in POINTS:
		var a := TAU * i / POINTS
		var wobble := sin(a * 5.0 + _phase + t * 12.0) * 6.0 * (1.0 - t)
		set_point_position(i, Vector2.from_angle(a) * (radius + wobble) * Vector2(1.0, 0.6))
	width = lerpf(14.0, 2.0, t)
	modulate.a = 1.0 - t
