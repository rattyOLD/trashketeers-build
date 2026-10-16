class_name GroundPools
extends Node2D
## Тёплые пятна света на полу у огня, фонарей и неона: на тёмной Свалке без них свет есть только
## на персонажах, а земля ровная. Одно сложение (ADD) одним узлом под персонажами, без PointLight2D —
## работает и на качестве «Эконом». Пятно приплюснуто по вертикали, как свет на земле в перспективе.

const GAIN := 0.85
const SQUASH := 0.62
const FLICKER := 0.06

var _buffer := EnvLights.LightBuffer.new()
var _clock := 0.0


func _init() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	EnvLights.collect(view, _buffer)
	var tex := LightMap.light_texture()
	var limit := mini(_buffer.positions.size(), BattleQuality.light_limit)
	for i in limit:
		var at := _buffer.positions[i]
		var r := _buffer.radii[i] * 1.05
		var c := _buffer.colors[i]
		var wobble := 1.0 + FLICKER * sin(_clock * 7.0 + at.x * 0.013)
		draw_texture_rect(tex, Rect2(at - Vector2(r, r * SQUASH), Vector2(r * 2.0, r * 2.0 * SQUASH)), false, Color(c.r, c.g, c.b, 1.0) * (GAIN * wobble * c.a))
