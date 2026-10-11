shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool metal = true;
varying vec4 item_color;

void vertex() { item_color = COLOR; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec4 base = texture(TEXTURE, UV) * item_color;
	vec2 grid = UV * vec2(11.0, 13.0);
	vec2 cell = floor(grid);
	float seed = hash(cell);
	vec2 p = fract(grid) - vec2(0.25 + seed * 0.5, 0.5);
	float active = step(seed, damage_amount * 0.58) * step(0.0, damage_amount - 0.001);
	float scratch = (1.0 - smoothstep(0.018, 0.052, abs(p.y + p.x * (seed - 0.5)))) * (1.0 - smoothstep(0.13, 0.28, abs(p.x)));
	float dent = (1.0 - smoothstep(0.065, 0.16, length(p * vec2(1.0, 1.45)))) * (metal ? 1.0 : 0.45);
	float rim = (1.0 - smoothstep(0.018, 0.045, abs(p.y - 0.085))) * (1.0 - smoothstep(0.07, 0.14, abs(p.x)));
	base.rgb = mix(base.rgb, base.rgb * 0.35, dent * active * 0.8);
	base.rgb = mix(base.rgb, metal ? vec3(0.53, 0.49, 0.40) : vec3(0.38, 0.24, 0.13), scratch * active * 0.65);
	base.rgb += rim * active * (metal ? 0.065 : 0.02);
	COLOR = vec4(mix(base.rgb, flash_color.rgb, flash_amount), base.a);
}
