class_name GroundPools
extends Node2D
## Тёплые пятна света на полу у огня, фонарей и неона: на тёмной Свалке без них свет есть только
## на персонажах, а земля ровная. Одно сложение (ADD) одним узлом под персонажами, без PointLight2D —
## работает и на качестве «Эконом». Маски Астры (assets/world/lights, бриф v33): огонь, фонарь, неон
## и отражения неона в мокром асфальте; источник выбирает маску по своему цвету.

const GAIN := 0.85
const FLICKER := 0.06
const LIGHTS := "res://assets/world/lights/"
## Отражение неона ложится чуть ниже источника и слабее самого пятна.
const REFLECT_GAIN := 0.55

var _buffer := EnvLights.LightBuffer.new()
var _clock := 0.0
var _fire: Texture2D
var _lamp: Texture2D
var _neon: Texture2D
var _reflect_pink: Texture2D
var _reflect_cyan: Texture2D


func _init() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	var fallback := LightMap.light_texture()
	_fire = _load("pool_fire.png", fallback)
	_lamp = _load("pool_lamp.png", fallback)
	_neon = _load("pool_neon.png", fallback)
	_reflect_pink = _load("reflect_neon_pink.png", null)
	_reflect_cyan = _load("reflect_neon_cyan.png", null)


func _load(file: String, fallback: Texture2D) -> Texture2D:
	var path := LIGHTS + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else fallback


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	EnvLights.collect(view, _buffer)
	var limit := mini(_buffer.positions.size(), BattleQuality.light_limit)
	for i in limit:
		var at := _buffer.positions[i]
		var r := _buffer.radii[i] * 1.05
		var c := _buffer.colors[i]
		var wobble := 1.0 + FLICKER * sin(_clock * 7.0 + at.x * 0.013)
		var tint := Color(c.r, c.g, c.b, 1.0) * (GAIN * wobble * c.a)
		var top := maxf(c.r, maxf(c.g, c.b))
		var saturation := (top - minf(c.r, minf(c.g, c.b))) / maxf(top, 0.001)
		var hue := c.h
		if saturation < 0.35:
			draw_texture_rect(_lamp, Rect2(at - Vector2(r, r * 0.8), Vector2(r * 2.0, r * 1.6)), false, tint)
		elif hue < 0.13 or hue > 0.97:
			draw_texture_rect(_fire, Rect2(at - Vector2(r, r * 0.8), Vector2(r * 2.0, r * 1.6)), false, tint)
		else:
			draw_texture_rect(_neon, Rect2(at - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), false, tint)
			var reflect: Texture2D = _reflect_pink if hue > 0.75 else (_reflect_cyan if hue > 0.42 and hue < 0.7 else null)
			if reflect != null:
				var glow := Color(1, 1, 1, 1) * (REFLECT_GAIN * wobble * c.a)
				draw_texture_rect(reflect, Rect2(at + Vector2(-r * 0.6, r * 0.15), Vector2(r * 1.2, r * 0.6)), false, glow)
