class_name SceneryAmbience
extends Node2D
## Локальные детали зданий. Пауза останавливает весь ход анимации, включая перерисовку.
var kind := "garage"
var phase := 0.0
var clock := 0.0
static var _steam: GradientTexture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"scenery_ambience")
	if _steam == null:
		_steam = GradientTexture2D.new()
		_steam.width = 64
		_steam.height = 64
		_steam.fill = GradientTexture2D.FILL_RADIAL
		_steam.fill_from = Vector2(0.5, 0.5)
		_steam.fill_to = Vector2(1, 0.5)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.72, 0.8, 0.82, 0.22), Color(0.72, 0.8, 0.82, 0)])
		_steam.gradient = g


func _process(delta: float) -> void:
	clock += delta
	if get_viewport_rect().grow(280).has_point(get_global_transform_with_canvas().origin):
		queue_redraw()


func _draw() -> void:
	var t := clock + phase
	if kind in ["garage", "bar", "apartments"]:
		var vent: Vector2 = {"bar": Vector2(6, -357), "garage": Vector2(-54, -432), "apartments": Vector2(-66, -416)}[kind]
		for i in 5:
			var age := fposmod(t * 0.22 + i * 0.2, 1.0)
			var center := vent + Vector2(age * 42 + sin(t * 0.6 + i) * 7, -age * 86)
			var size := Vector2(24, 18) + Vector2(56, 44) * age
			draw_texture_rect(_steam, Rect2(center - size * 0.5, size), false, Color(1, 1, 1, sin(age * PI) * 0.72))
	if kind in ["garage", "workshop"]:
		var cable := PackedVector2Array()
		for i in 13:
			var k := i / 12.0
			var from := Vector2(-158, -268) if kind == "workshop" else Vector2(-152, -346)
			var to := Vector2(148, -295) if kind == "workshop" else Vector2(138, -333)
			cable.append(from.lerp(to, k) + Vector2(0, sin(k * PI) * (20 + sin(t * 0.9) * 2)))
		draw_polyline(cable, Color("#171f23"), 4, true)
		draw_polyline(cable, Color(0.31, 0.39, 0.39, 0.7), 1, true)
		var cycle := fposmod(t, 7.3)
		if cycle < 0.22:
			var at := cable[9]
			for i in 4:
				var direction := Vector2.from_angle(-2.4 + i * 0.68)
				var start := at + direction * cycle * 56
				draw_line(start, start + direction * 7, Color(1, 0.78, 0.35, 1 - cycle / 0.22), 1.8, true)
	if kind == "workshop":
		var strength := 0.6 + 0.4 * sin(t * 1.6)
		draw_circle(Vector2(92, -364), 5, Color(1, 0.69, 0.21, strength), false, 1.4, true)
