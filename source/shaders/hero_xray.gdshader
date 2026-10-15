shader_type canvas_item;
// Контур героя поверх меток и взрывов: светлая обводка и лёгкая заливка силуэта, без самого рисунка.
// Чтение TEXTURE только внутри fragment(): рендер Compatibility не принимает его аргументом функции.
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 0.95, 0.78, 1.0);
uniform float strength = 0.0;
float inside(vec2 uv) {
	vec2 end = frame_rect.xy + frame_rect.zw;
	return step(frame_rect.x, uv.x) * step(frame_rect.y, uv.y) * step(uv.x, end.x) * step(uv.y, end.y);
}
vec2 clamp_uv(vec2 uv) {
	return clamp(uv, frame_rect.xy, frame_rect.xy + frame_rect.zw);
}
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * 4.0;
	float base = texture(TEXTURE, clamp_uv(UV)).a * inside(UV);
	vec2 o1 = UV + vec2(px.x, 0.0);
	vec2 o2 = UV - vec2(px.x, 0.0);
	vec2 o3 = UV + vec2(0.0, px.y);
	vec2 o4 = UV - vec2(0.0, px.y);
	vec2 o5 = UV + px * 0.7;
	vec2 o6 = UV - px * 0.7;
	float near = texture(TEXTURE, clamp_uv(o1)).a * inside(o1);
	near = max(near, texture(TEXTURE, clamp_uv(o2)).a * inside(o2));
	near = max(near, texture(TEXTURE, clamp_uv(o3)).a * inside(o3));
	near = max(near, texture(TEXTURE, clamp_uv(o4)).a * inside(o4));
	near = max(near, texture(TEXTURE, clamp_uv(o5)).a * inside(o5));
	near = max(near, texture(TEXTURE, clamp_uv(o6)).a * inside(o6));
	float ring = clamp(near - base, 0.0, 1.0);
	float fill = step(0.5, base) * 0.07;
	COLOR = vec4(line_color.rgb, (ring * 0.95 + fill) * strength * line_color.a);
}
