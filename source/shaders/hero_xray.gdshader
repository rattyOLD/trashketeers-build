shader_type canvas_item;
// Контур героя поверх меток и взрывов: светлая обводка и лёгкая заливка силуэта, без самого рисунка.
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 0.95, 0.78, 1.0);
uniform float strength = 0.0;
float inside(vec2 uv) {
	vec2 end = frame_rect.xy + frame_rect.zw;
	return step(frame_rect.x, uv.x) * step(frame_rect.y, uv.y) * step(uv.x, end.x) * step(uv.y, end.y);
}
float alpha_at(sampler2D tex, vec2 uv) {
	return texture(tex, clamp(uv, frame_rect.xy, frame_rect.xy + frame_rect.zw)).a * inside(uv);
}
void fragment() {
	float base = alpha_at(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * 4.0;
	float near = max(max(alpha_at(TEXTURE, UV + vec2(px.x, 0.0)), alpha_at(TEXTURE, UV - vec2(px.x, 0.0))), max(alpha_at(TEXTURE, UV + vec2(0.0, px.y)), alpha_at(TEXTURE, UV - vec2(0.0, px.y))));
	near = max(near, max(alpha_at(TEXTURE, UV + px * 0.7), alpha_at(TEXTURE, UV - px * 0.7)));
	float ring = clamp(near - base, 0.0, 1.0);
	float fill = step(0.5, base) * 0.07;
	COLOR = vec4(line_color.rgb, (ring * 0.95 + fill) * strength * line_color.a);
}
