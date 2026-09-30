shader_type canvas_item;
// Постобработка мира (под HUD и погодой): мягкий «фильмовый» тон, контраст и насыщенность,
// сплит-тонирование (тени — в фиолет, света — в тёплый неон), лёгкое зерно и хроматическая
// аберрация по краям экрана, которая вспыхивает при получении урона (aberration → 1).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float contrast = 1.08;
uniform float saturation = 1.12;
uniform vec3 shadow_tint = vec3(0.10, 0.02, 0.16);
uniform vec3 highlight_tint = vec3(0.06, 0.03, -0.02);
uniform float grain = 0.035;
uniform float aberration = 0.0;
uniform float base_aberration = 0.0012;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - 0.5;
	float edge = dot(from_center, from_center);
	vec2 shift = from_center * (base_aberration + aberration * 0.012) * (0.4 + edge * 4.0);
	vec3 col;
	col.r = texture(screen_texture, uv + shift).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - shift).b;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	float lum = clamp(luma, 0.0, 1.0);
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.45, lum)) * 0.6;
	col += highlight_tint * smoothstep(0.55, 1.0, lum);
	col += (hash(uv * 800.0 + fract(TIME * 7.0) * 13.0) - 0.5) * grain;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
