shader_type canvas_item;
varying vec4 item_color;
void vertex() { item_color = COLOR; }
// Thin cool contour and a directional light edge preserve the painted anatomy.
uniform float rim_strength = 0.14;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * 3.0;
	float edge = max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	edge = max(edge, max(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	float lit_edge = (1.0 - texture(TEXTURE, UV - px * 1.3).a) * base.a;
	vec3 rgb = base.rgb + vec3(0.66, 0.78, 0.8) * lit_edge * rim_strength;
	rgb = mix(vec3(0.42, 0.53, 0.55), rgb, base.a);
	COLOR = item_color * vec4(rgb, base.a + edge * 0.45 * (1.0 - base.a));
}
