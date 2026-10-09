shader_type canvas_item;

// Матовое тёмное стекло всплывающих окон: 9-точечное размытие экрана под панелью,
// тонировка и скруглённые углы (SDF). Mip-размытие экрана в Compatibility недоступно,
// поэтому выборки делаются вручную — 9 чтений на пиксель, только на площади окна.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blur_radius = 4.0;
uniform vec4 tint : source_color = vec4(0.133, 0.114, 0.098, 0.82);
uniform vec2 rect_size = vec2(600.0, 800.0);
uniform float corner_radius = 28.0;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_radius;
	vec3 sum = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			sum += texture(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * px).rgb;
		}
	}
	vec3 glass = mix(sum / 9.0, tint.rgb, tint.a);
	float d = rounded_box(UV * rect_size - rect_size * 0.5, rect_size * 0.5, corner_radius);
	float mask = 1.0 - smoothstep(-1.0, 1.0, d);
	COLOR = vec4(glass, mask * COLOR.a);
}
