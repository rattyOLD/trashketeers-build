shader_type canvas_item;
// Виньетка: затемнение к краям экрана (радиальный спад), цвет tint — для «тревожных» волн.
uniform float strength = 0.45;
uniform vec4 tint : source_color = vec4(0.02, 0.0, 0.06, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= 0.8;
	float d = length(uv) * 1.55;
	float v = smoothstep(0.45, 1.05, d) * strength;
	COLOR = vec4(tint.rgb, v);
}
