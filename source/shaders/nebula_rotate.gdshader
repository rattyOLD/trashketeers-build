shader_type canvas_item;

// Туманность космоса: текстура медленно вращается вокруг центра через поворот UV.
uniform float speed = 0.01;
uniform vec4 crimson : source_color = vec4(0.0);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float a = TIME * speed;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	vec2 uv = rot * centered + vec2(0.5);
	vec4 c = texture(TEXTURE, fract(uv));
	float edge = smoothstep(0.5, 0.35, length(centered));
	COLOR = vec4(mix(c.rgb, crimson.rgb, crimson.a), c.a * edge) * COLOR;
}
