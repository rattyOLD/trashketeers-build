shader_type canvas_item;
// Постобработка мира (под HUD и погодой): мягкий «фильмовый» тон, контраст и насыщенность,
// сплит-тонирование (тени — в фиолет, света — в тёплый неон), короткая хроматическая
// аберрация по краям экрана, которая вспыхивает при получении урона (aberration → 1).
// HD-2D (как Octopath / Live A Live): верх и низ кадра мягко размыты («миниатюра»), яркие места
// светятся, дальний (верхний) край тонет в дымке. Размытие и свечение берутся из mip-уровней
// копии экрана — без дополнительных проходов.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D screen_mip : hint_screen_texture, filter_linear_mipmap;
uniform float contrast = 1.04;
uniform float saturation = 0.98;
uniform vec3 shadow_tint = vec3(0.10, 0.02, 0.16);
uniform vec3 highlight_tint = vec3(0.06, 0.03, -0.02);
uniform float aberration = 0.0;
uniform float base_aberration = 0.0;
// Резкая полоса вокруг героя (доля высоты экрана от центра) и размытие краёв в пикселях 720p.
uniform float focus_y = 0.5;
uniform float focus_half = 0.25;
uniform float focus_ramp = 0.22;
uniform float tilt_blur = 0.0;
// Свечение: всё ярче порога расплывается мягким ореолом.
uniform float glow_strength = 0.0;
uniform float glow_threshold = 0.62;
// Дымка сверху кадра (дальний план).
uniform vec4 haze_color : source_color = vec4(0.8, 0.85, 1.0, 0.0);
uniform float haze_reach = 0.42;

vec3 blurred(vec2 uv, float px, vec2 pixel) {
	float lod = log2(max(px, 1.0));
	vec2 step_uv = pixel * px * 0.5;
	// Четыре выборки со сдвигом сглаживают квадратные ступени mip-уровня. SCREEN_PIXEL_SIZE
	// передаётся аргументом: встроенные переменные доступны только внутри fragment().
	return (textureLod(screen_mip, uv + vec2(step_uv.x, step_uv.y), lod).rgb
		+ textureLod(screen_mip, uv + vec2(-step_uv.x, step_uv.y), lod).rgb
		+ textureLod(screen_mip, uv + vec2(step_uv.x, -step_uv.y), lod).rgb
		+ textureLod(screen_mip, uv + vec2(-step_uv.x, -step_uv.y), lod).rgb) * 0.25;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - 0.5;
	float edge = dot(from_center, from_center);
	// Смещение ограничено пикселями, а не долей экрана: прежние 0.012 давали
	// десятки пикселей цветового расслоения при непрерывном уроне в поздних волнах.
	vec2 shift = from_center * SCREEN_PIXEL_SIZE * clamp(base_aberration + aberration, 0.0, 1.0) * 2.0 * (0.4 + edge * 4.0);
	vec3 col;
	col.r = texture(screen_texture, uv + shift).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - shift).b;
	float res_scale = 1.0 / (SCREEN_PIXEL_SIZE.y * 720.0);
	float away = smoothstep(focus_half, focus_half + focus_ramp, abs(uv.y - focus_y));
	if (tilt_blur > 0.0 && away > 0.001) {
		col = mix(col, blurred(uv, tilt_blur * res_scale * away, SCREEN_PIXEL_SIZE), away);
	}
	if (glow_strength > 0.0) {
		vec3 wide = blurred(uv, 10.0 * res_scale, SCREEN_PIXEL_SIZE) * 0.6 + blurred(uv, 22.0 * res_scale, SCREEN_PIXEL_SIZE) * 0.4;
		// Порог по яркости, а не по каналам: светлая дорожка днём не выгорает в белое,
		// а неон и огонь светятся своим цветом.
		float bright = dot(wide, vec3(0.299, 0.587, 0.114));
		col += wide * smoothstep(glow_threshold, 1.0, bright) * glow_strength;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	float lum = clamp(luma, 0.0, 1.0);
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.45, lum)) * 0.6;
	col += highlight_tint * smoothstep(0.55, 1.0, lum);
	col = mix(col, haze_color.rgb, haze_color.a * (1.0 - smoothstep(0.0, haze_reach, uv.y)));
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
