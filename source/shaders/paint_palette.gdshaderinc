// Общая светотень рисунка. Не меняет UV, альфу и геометрию персонажа.
uniform float paint_strength = 0.18;
uniform vec3 paint_shadow = vec3(0.82, 0.93, 1.04);
uniform vec3 paint_light = vec3(1.05, 1.01, 0.91);
uniform float paint_saturation = 0.86;

vec3 painted_color(vec3 rgb) {
	float l = dot(rgb, vec3(0.299, 0.587, 0.114));
	vec3 toned = mix(vec3(l), rgb, paint_saturation);
	toned *= mix(paint_shadow, paint_light, smoothstep(0.12, 0.78, l));
	return mix(rgb, toned, paint_strength);
}
