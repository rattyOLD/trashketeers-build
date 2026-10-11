shader_type canvas_item;
#include "res://shaders/paint_palette.gdshaderinc"
#include "res://shaders/boss_wear.gdshaderinc"
varying vec4 item_color;
void vertex() { item_color = COLOR; }
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(worn_boss(painted_color(tex.rgb), UV), tex.a) * item_color;
}
