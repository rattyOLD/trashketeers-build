shader_type canvas_item;
#include "res://shaders/paint_palette.gdshaderinc"
varying vec4 item_color;
void vertex() { item_color = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(painted_color(c.rgb), c.a) * item_color;
}
