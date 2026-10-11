// Повреждения остаются на корпусе; альфа и силуэт исходной картинки сохраняются.
uniform float boss_damage : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wear_rect = vec4(0.0, 0.0, 1.0, 1.0);

vec3 worn_boss(vec3 rgb, vec2 uv) {
	if (boss_damage <= 0.0) { return rgb; }
	vec2 p = (uv - wear_rect.xy) / max(wear_rect.zw, vec2(0.0001));
	float torso = smoothstep(0.28, 0.37, p.y) * (1.0 - smoothstep(0.73, 0.85, p.y));
	float panels = smoothstep(0.13, 0.25, p.x) * (1.0 - smoothstep(0.78, 0.90, p.x));
	vec2 grid = p * vec2(9.0, 11.0);
	float seed = fract(sin(dot(floor(grid), vec2(127.1, 311.7))) * 43758.5453);
	vec2 local = fract(grid) - vec2(0.25 + seed * 0.5, 0.5);
	float active = step(seed, boss_damage * 0.63) * torso * panels;
	float scar = abs(local.y + local.x * (seed - 0.5));
	float cut = (1.0 - smoothstep(0.014, 0.043, scar)) * (1.0 - smoothstep(0.16, 0.32, abs(local.x)));
	float dent = 1.0 - smoothstep(0.055, 0.17, length(local * vec2(1.0, 1.4)));
	float glint = (1.0 - smoothstep(0.015, 0.040, abs(local.y - 0.07))) * (1.0 - smoothstep(0.10, 0.22, abs(local.x)));
	rgb = mix(rgb, rgb * 0.43, dent * active * 0.7);
	rgb = mix(rgb, vec3(0.22, 0.19, 0.15), cut * active * 0.78);
	return rgb + glint * active * 0.06;
}
