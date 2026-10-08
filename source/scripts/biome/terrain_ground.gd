class_name TerrainGround
extends Node2D
## Подложка местности выживания: поверх плит пола — «грязные» пятна земли района (асфальт в трещинах,
## лужи, мусор) по маске шума с мягким краем и тёмной каймой. Та же маска решает, где стоит хлам
## (LevelSpawner._density), поэтому замусоренная земля и укрытия совпадают, а чистые плиты — поле боя.
## Один прямоугольник с шейдером на всю площадку: один вызов отрисовки, маска — маленькая текстура.

const MASK_STEP := 24.0
const SHADER := """
shader_type canvas_item;
uniform sampler2D overlay : repeat_enable, filter_linear;
uniform sampler2D mask : filter_linear;
uniform vec2 origin;
uniform vec2 size;
uniform float tile = 256.0;
uniform float threshold = 0.5;
uniform float soft = 0.07;
uniform vec4 tint : source_color = vec4(1.0);
varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	float n = texture(mask, (world - origin) / size).r;
	float a = smoothstep(threshold - soft, threshold + soft, n);
	vec4 c = texture(overlay, world / tile);
	// Кайма: на границе пятна земля темнее — грязь стекает на плиты.
	float rim = 1.0 - 0.35 * (1.0 - abs(a * 2.0 - 1.0));
	float edge = smoothstep(threshold - soft * 2.5, threshold - soft, n) * (1.0 - a);
	COLOR = vec4(mix(vec3(0.0), c.rgb * tint.rgb * rim, a), max(c.a * a, edge * 0.35) * tint.a);
}
"""


## rect — площадка; density(p) -> float в -1..1 (тот же шум, что у расстановки).
func build(rect: Rect2, overlay_path: String, density: Callable, threshold: float, tint: Color) -> void:
	var overlay := load(overlay_path) as Texture2D
	if overlay == null:
		return
	var w := maxi(int(rect.size.x / MASK_STEP), 2)
	var h := maxi(int(rect.size.y / MASK_STEP), 2)
	var image := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			var p := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * MASK_STEP
			image.set_pixel(x, y, Color.from_hsv(0.0, 0.0, clampf(float(density.call(p)) * 1.4 + 0.5, 0.0, 1.0)))
	var material_shader := Shader.new()
	material_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = material_shader
	mat.set_shader_parameter("overlay", overlay)
	mat.set_shader_parameter("mask", ImageTexture.create_from_image(image))
	mat.set_shader_parameter("origin", rect.position)
	mat.set_shader_parameter("size", Vector2(w, h) * MASK_STEP)
	mat.set_shader_parameter("threshold", clampf(threshold * 1.4 + 0.5, 0.0, 1.0))
	mat.set_shader_parameter("tint", tint)
	material = mat
	light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	_rect = rect
	queue_redraw()


var _rect := Rect2()


func _draw() -> void:
	if _rect.size != Vector2.ZERO:
		draw_rect(_rect, Color.WHITE)
