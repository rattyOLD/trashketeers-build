class_name RaidEnvironment
extends WorldEnvironment
## Неоновое свечение Алтаря Вечности (Glow через WorldEnvironment).
## Проверено в Godot 4.4 Web (Compatibility/WebGL2): 2D-glow работает при
## background_mode = BG_CANVAS. HDR для 2D в Compatibility нет — яркость пикселя не выше 1.0,
## поэтому порог свечения опущен до HDR_THRESHOLD: светятся белый дракон, бирюзовые руны,
## лазер и кристаллы, а почти чёрный обсидиан (#05050A) остаётся матовым.
## Glow — полноэкранный многопроходный блюр: на слабых телефонах выключается в Настройках.

const HDR_THRESHOLD := 0.58
const INTENSITY := 1.7
const STRENGTH := 1.2
const BLOOM := 0.06


func _init() -> void:
	environment = build_environment()


static func build_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = INTENSITY
	env.glow_strength = STRENGTH
	env.glow_bloom = BLOOM
	env.glow_hdr_threshold = HDR_THRESHOLD
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env
