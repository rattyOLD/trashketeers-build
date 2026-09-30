shader_type canvas_item;
// GPU-риг для 2D-персонажей (енот, крысы). Спрайт натянут на сетку MeshInstance2D (RigSprite),
// каждая вершина деформируется до 12 костями. Веса костей лежат в трёх RGBA-картах в UV-пространстве
// спрайта; кости применяются строго по порядку индексов — дети раньше родителей (ухо → голова →
// корпус, кончик хвоста → середина → основание), поэтому получается честная иерархия FK:
// поворот ребёнка вокруг его точки в позе покоя, затем поворот родителя вокруг своей.
//
// Фрагмент: перекраска регионов «градиентной картой» по яркости (мех / одежда / шарф / кожа /
// металл / радужка) — светотень и штрихи рисунка сохраняются, меняется только палитра; слой
// нарисованных аксессуаров скина; веки (моргание, прищур, «довольные» глаза); вращение колеса
// (полярный поворот UV в кольце); сдвиг оттенка «волос» у крыс; обводка и вспышка попадания.

uniform bool rig_enabled = true;
uniform sampler2D weights0 : filter_linear, repeat_disable;
uniform sampler2D weights1 : filter_linear, repeat_disable;
uniform sampler2D weights2 : filter_linear, repeat_disable;
uniform vec2 bone_pivot[12];
uniform float bone_angle[12];
uniform vec2 bone_offset[12];
// Растяжение кости относительно покоя (0 — без изменений): пропорции персонажей и squash/stretch.
uniform vec2 bone_stretch[12];

uniform bool recolor_enabled = false;
uniform sampler2D regions0 : filter_linear, repeat_disable;
uniform sampler2D regions1 : filter_linear, repeat_disable;
// Регион i: цвета градиента тени/середины/света и сила перекраски (grad_light.a).
uniform vec4 grad_dark[6];
uniform vec4 grad_mid[6];
uniform vec4 grad_light[6];
// Диапазон яркости региона в исходном рисунке: x — самый тёмный, y — самый светлый.
uniform vec2 grad_range[6];

uniform bool overlay_enabled = false;
uniform sampler2D overlay : filter_linear, repeat_disable;

uniform vec4 eye0 = vec4(-1.0);
uniform vec4 eye1 = vec4(-1.0);
uniform float blink = 0.0;
uniform float squint = 0.0;
uniform float happy = 0.0;
uniform vec4 lash_color : source_color = vec4(0.09, 0.05, 0.08, 1.0);

// Колесо (кибер-крыса): xy — центр (UV), z — rx/ry эллипса в перспективе; радиусы шины в px.
// Протектор крутится только в секторе ±~100° от +x (слева колесо перекрыто выхлопом), к краям
// сектора угол плавно гаснет — без шва.
uniform vec4 wheel = vec4(-1.0);
uniform vec2 wheel_radii = vec2(0.0);
uniform float wheel_angle = 0.0;

uniform float hue_shift = 0.0;
uniform float flash = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float outline_px = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 0.9, 0.8, 0.85);
uniform float alpha = 1.0;
// Свет окружения (EnvLights.sample): огонь, неон, вспышки выстрелов подкрашивают персонажа.
uniform vec3 env_light = vec3(0.0);

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
	if (rig_enabled) {
		vec4 w0 = textureLod(weights0, UV, 0.0);
		vec4 w1 = textureLod(weights1, UV, 0.0);
		vec4 w2 = textureLod(weights2, UV, 0.0);
		vec2 p = VERTEX;
		for (int i = 0; i < 12; i++) {
			float wi = i < 4 ? w0[i] : (i < 8 ? w1[i - 4] : w2[i - 8]);
			if (wi < 0.002) {
				continue;
			}
			vec2 local = (p - bone_pivot[i]) * (vec2(1.0) + bone_stretch[i] * wi);
			float a = bone_angle[i] * wi;
			float c = cos(a);
			float s = sin(a);
			p = bone_pivot[i] + vec2(local.x * c - local.y * s, local.x * s + local.y * c) + bone_offset[i] * wi;
		}
		VERTEX = p;
	}
}

float inside(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

vec3 recolor(vec2 uv, vec3 col) {
	vec4 r0 = texture(regions0, uv);
	vec4 r1 = texture(regions1, uv);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	for (int i = 0; i < 6; i++) {
		float region = i < 4 ? r0[i] : r1[i - 4];
		float amount = region * grad_light[i].a;
		if (amount < 0.003) {
			continue;
		}
		float t = clamp((luma - grad_range[i].x) / max(grad_range[i].y - grad_range[i].x, 0.01), 0.0, 1.0);
		vec3 g = t < 0.5 ? mix(grad_dark[i].rgb, grad_mid[i].rgb, t * 2.0) : mix(grad_mid[i].rgb, grad_light[i].rgb, t * 2.0 - 1.0);
		col = mix(col, g, amount);
	}
	return col;
}

// Веко: в пространстве эллипса глаза d ∈ [-1, 1]; сверху опускается верхнее веко (моргание/прищур),
// снизу поднимается нижнее («довольные» глаза-дуги). lid — цвет меха прямо над глазом.
vec3 eyelid(vec4 eye, vec2 uv, vec3 col, vec3 lid) {
	if (eye.z <= 0.0) {
		return col;
	}
	vec2 d = (uv - eye.xy) / eye.zw;
	float r2 = dot(d, d);
	if (r2 > 1.15) {
		return col;
	}
	float close = clamp(max(blink, squint * 0.5), 0.0, 1.0);
	float upper = -1.1 + 2.25 * close + 0.25 * d.x * d.x * close;
	float lower = 1.1 - 1.3 * happy - 0.35 * squint + 0.35 * d.x * d.x * happy;
	float edge = 1.0 - smoothstep(0.95, 1.12, r2);
	float cover = max(step(d.y, upper), step(lower, d.y)) * edge;
	float lash = max(1.0 - smoothstep(0.0, 0.16, abs(d.y - upper)), 1.0 - smoothstep(0.0, 0.14, abs(d.y - lower)));
	lash *= edge * step(0.04, max(close, happy));
	col = mix(col, lid * (0.85 + 0.15 * (-d.y)), cover);
	return mix(col, lash_color.rgb, lash * 0.9);
}

vec3 lid_color(vec4 eye, vec3 sampled) {
	vec2 at = eye.xy - vec2(0.0, eye.w * 1.25);
	return recolor_enabled ? recolor(at, sampled) : sampled;
}

void fragment() {
	vec2 uv = UV;
	if (wheel.z > 0.0 && abs(wheel_angle) > 0.0001) {
		vec2 px = (uv - wheel.xy) / TEXTURE_PIXEL_SIZE;
		vec2 q = vec2(px.x / wheel.z, px.y);
		float r = length(q);
		float window = 1.0 - smoothstep(1.45, 1.9, abs(atan(q.y, q.x)));
		if (r > wheel_radii.x && r < wheel_radii.y && window > 0.0) {
			float a = wheel_angle * window;
			float c = cos(a);
			float s = sin(a);
			q = vec2(q.x * c - q.y * s, q.x * s + q.y * c);
			uv = wheel.xy + vec2(q.x * wheel.z, q.y) * TEXTURE_PIXEL_SIZE;
		}
	}
	vec4 base = texture(TEXTURE, uv) * inside(uv);
	vec3 rgb = base.rgb;
	if (recolor_enabled) {
		rgb = recolor(uv, rgb);
	}
	if (abs(hue_shift) > 0.004) {
		vec3 hsv = rgb2hsv(rgb);
		float reddish = step(0.45, hsv.y) * step(0.25, hsv.z) * max(step(hsv.x, 0.05), step(0.93, hsv.x));
		if (reddish > 0.5) {
			hsv.x = fract(hsv.x + hue_shift);
			rgb = hsv2rgb(hsv);
		}
	}
	float a = base.a;
	if (overlay_enabled) {
		// «over» без премультипликации: под прозрачной частью спрайта нет «цвета», поэтому
		// полупрозрачное стекло шлема не должно смешиваться с мусорным RGB под нулевой альфой.
		vec4 ov = texture(overlay, uv) * inside(uv);
		float out_a = ov.a + a * (1.0 - ov.a);
		rgb = out_a > 0.001 ? (ov.rgb * ov.a + rgb * a * (1.0 - ov.a)) / out_a : rgb;
		a = out_a;
	}
	if (eye0.z > 0.0 && max(max(blink, squint), happy) > 0.01) {
		rgb = eyelid(eye0, uv, rgb, lid_color(eye0, texture(TEXTURE, eye0.xy - vec2(0.0, eye0.w * 1.25)).rgb));
		rgb = eyelid(eye1, uv, rgb, lid_color(eye1, texture(TEXTURE, eye1.xy - vec2(0.0, eye1.w * 1.25)).rgb));
	}
	rgb *= tint.rgb;
	rgb = rgb * (vec3(1.0) + env_light * 0.85) + env_light * 0.04;
	rgb = mix(rgb, vec3(1.0), clamp(flash, 0.0, 1.0) * 0.85);

	if (outline_px > 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
		vec2 dg = px * 0.7071;
		float ring = texture(TEXTURE, uv + vec2(px.x, 0.0)).a * inside(uv + vec2(px.x, 0.0));
		ring = max(ring, texture(TEXTURE, uv - vec2(px.x, 0.0)).a * inside(uv - vec2(px.x, 0.0)));
		ring = max(ring, texture(TEXTURE, uv + vec2(0.0, px.y)).a * inside(uv + vec2(0.0, px.y)));
		ring = max(ring, texture(TEXTURE, uv - vec2(0.0, px.y)).a * inside(uv - vec2(0.0, px.y)));
		ring = max(ring, texture(TEXTURE, uv + dg).a * inside(uv + dg));
		ring = max(ring, texture(TEXTURE, uv - dg).a * inside(uv - dg));
		ring = max(ring, texture(TEXTURE, uv + vec2(dg.x, -dg.y)).a * inside(uv + vec2(dg.x, -dg.y)));
		ring = max(ring, texture(TEXTURE, uv + vec2(-dg.x, dg.y)).a * inside(uv + vec2(-dg.x, dg.y)));
		float rim = clamp(ring, 0.0, 1.0) * outline_color.a;
		rgb = mix(outline_color.rgb, rgb, a);
		a = a + rim * (1.0 - a);
	}
	COLOR = vec4(rgb, a * alpha * tint.a);
}
