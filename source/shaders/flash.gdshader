shader_type canvas_item;

// Вспышка при попадании: смешивает цвет с flash_color, сохраняя альфу.
// Работает и для спрайтов, и для процедурной отрисовки (_draw): там TEXTURE — белый пиксель.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(base.rgb, flash_color.rgb, flash_amount), base.a);
}
