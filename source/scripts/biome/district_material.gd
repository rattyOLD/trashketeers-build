class_name DistrictMaterial
extends RefCounted
## Общий ночной материал старых деталей: сохраняет металл и древесину, гасит кислотный неон.
static var _shader: Shader


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type canvas_item;
varying vec4 item_color;
void vertex() { item_color = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV) * item_color;
	float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	vec3 rgb = mix(vec3(l), c.rgb, 0.58);
	// Amber fixtures retain their warmth; cool accents become weathered teal.
	rgb *= vec3(0.92, 0.93, 0.96);
	COLOR = vec4(rgb, c.a);
}
"""
	return _shader
