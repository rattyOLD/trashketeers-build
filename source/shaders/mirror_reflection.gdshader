shader_type canvas_item;
render_mode blend_add;

// Отражение актёра на зеркальном обсидиане: спрайт уже перевёрнут узлом (flip_v),
// шейдер размывает его по вертикали (5 выборок) и гасит до strength — по паспорту 0.15.
uniform float strength : hint_range(0.0, 1.0) = 0.15;
uniform float blur_px = 3.0;
uniform vec4 tint : source_color = vec4(0.75, 0.95, 1.0, 1.0);

void fragment() {
	vec2 step_uv = vec2(0.0, TEXTURE_PIXEL_SIZE.y * blur_px);
	vec4 c = texture(TEXTURE, UV) * 0.36;
	c += texture(TEXTURE, UV + step_uv) * 0.22;
	c += texture(TEXTURE, UV - step_uv) * 0.22;
	c += texture(TEXTURE, UV + step_uv * 2.0) * 0.1;
	c += texture(TEXTURE, UV - step_uv * 2.0) * 0.1;
	float fade = 1.0 - UV.y * 0.6;
	COLOR = vec4(c.rgb * tint.rgb, c.a * strength * fade);
}
