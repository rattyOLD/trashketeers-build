shader_type canvas_item;
// Врагам — читаемый силуэт на тёмном асфальте: цветной ободок снаружи спрайта.
// Квад спрайта раздувается на outline_px во vertex(), иначе ободок обрезался бы краем текстуры.
// Один материал на тип врага (батчинг сохраняется), а индивидуальные данные особи
// приходят через self_modulate спрайта: r — сдвиг оттенка «волос» (насыщенные красные
// пиксели, ирокез/бандана), g — белая вспышка попадания, a — прозрачность.

uniform vec4 outline_color : source_color = vec4(1.0, 0.9, 0.8, 0.85);
uniform vec4 tint : source_color = vec4(1.0);
uniform float outline_px = 6.0;

varying vec4 v_data;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	v_data = COLOR;
	vec2 dir = UV * 2.0 - 1.0;
	VERTEX += dir * outline_px;
	UV += dir * outline_px * TEXTURE_PIXEL_SIZE;
}

// 1 внутри текстуры, 0 снаружи: сэмплы за краем раздутого квада не должны давать ободок.
float inside(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

void fragment() {
	vec4 base = vec4(0.0);
	if (UV.x >= 0.0 && UV.y >= 0.0 && UV.x <= 1.0 && UV.y <= 1.0) {
		base = texture(TEXTURE, UV);
	}
	vec3 rgb = base.rgb;
	if (v_data.r > 0.004) {
		vec3 hsv = rgb2hsv(rgb);
		float reddish = step(0.45, hsv.y) * step(0.25, hsv.z) * max(step(hsv.x, 0.05), step(0.93, hsv.x));
		if (reddish > 0.5) {
			hsv.x = fract(hsv.x + v_data.r);
			rgb = hsv2rgb(hsv);
		}
	}
	rgb *= tint.rgb;
	rgb = mix(rgb, vec3(1.0), clamp(v_data.g, 0.0, 1.0) * 0.85);

	vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
	vec2 dg = px * 0.7071;
	float ring = texture(TEXTURE, UV + vec2(px.x, 0.0)).a * inside(UV + vec2(px.x, 0.0));
	ring = max(ring, texture(TEXTURE, UV - vec2(px.x, 0.0)).a * inside(UV - vec2(px.x, 0.0)));
	ring = max(ring, texture(TEXTURE, UV + vec2(0.0, px.y)).a * inside(UV + vec2(0.0, px.y)));
	ring = max(ring, texture(TEXTURE, UV - vec2(0.0, px.y)).a * inside(UV - vec2(0.0, px.y)));
	ring = max(ring, texture(TEXTURE, UV + dg).a * inside(UV + dg));
	ring = max(ring, texture(TEXTURE, UV - dg).a * inside(UV - dg));
	ring = max(ring, texture(TEXTURE, UV + vec2(dg.x, -dg.y)).a * inside(UV + vec2(dg.x, -dg.y)));
	ring = max(ring, texture(TEXTURE, UV + vec2(-dg.x, dg.y)).a * inside(UV + vec2(-dg.x, dg.y)));
	float rim = clamp(ring, 0.0, 1.0) * outline_color.a;

	vec3 final_rgb = mix(outline_color.rgb, rgb, base.a);
	float final_a = base.a + rim * (1.0 - base.a);
	COLOR = vec4(final_rgb, final_a * v_data.a);
}
