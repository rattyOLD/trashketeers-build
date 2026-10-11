shader_type canvas_item;
#include "res://shaders/paint_palette.gdshaderinc"
varying vec4 item_color;
void vertex() { item_color = COLOR; }
// Thin cool contour and a directional light edge preserve the painted anatomy.
uniform float rim_strength = 0.14;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
float inside(vec2 uv) {
	vec2 end = frame_rect.xy + frame_rect.zw;
	return step(frame_rect.x, uv.x) * step(frame_rect.y, uv.y) * step(uv.x, end.x) * step(uv.y, end.y);
}
vec2 sprite_uv(vec2 uv, vec2 texel) {
	return clamp(uv, frame_rect.xy + texel * 0.5, frame_rect.xy + frame_rect.zw - texel * 0.5);
}
void fragment() {
	vec4 base = (texture(TEXTURE, sprite_uv(UV, TEXTURE_PIXEL_SIZE)) * inside(UV));
	vec2 px = TEXTURE_PIXEL_SIZE * 3.0;
	float edge = max((texture(TEXTURE, sprite_uv(UV + vec2(px.x, 0.0), TEXTURE_PIXEL_SIZE)) * inside(UV + vec2(px.x, 0.0))).a, (texture(TEXTURE, sprite_uv(UV - vec2(px.x, 0.0), TEXTURE_PIXEL_SIZE)) * inside(UV - vec2(px.x, 0.0))).a);
	edge = max(edge, max((texture(TEXTURE, sprite_uv(UV + vec2(0.0, px.y), TEXTURE_PIXEL_SIZE)) * inside(UV + vec2(0.0, px.y))).a, (texture(TEXTURE, sprite_uv(UV - vec2(0.0, px.y), TEXTURE_PIXEL_SIZE)) * inside(UV - vec2(0.0, px.y))).a));
	float lit_edge = (1.0 - (texture(TEXTURE, sprite_uv(UV - px * 1.3, TEXTURE_PIXEL_SIZE)) * inside(UV - px * 1.3)).a) * base.a;
	vec3 rgb = painted_color(base.rgb) + vec3(0.66, 0.78, 0.8) * lit_edge * rim_strength;
	rgb = mix(vec3(0.42, 0.53, 0.55), rgb, base.a);
	COLOR = item_color * vec4(rgb, base.a + edge * 0.45 * (1.0 - base.a));
}
