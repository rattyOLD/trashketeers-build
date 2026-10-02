class_name ParticleFactory
extends RefCounted
## Сборка GPUParticles2D под WebGL/Compatibility (проверено в Godot 4.4 Web).
## Все эмиттеры создаются при постройке уровня, в геймплее только restart()/emitting.
## Текстуры частиц процедурные и кэшируются: ни одного PNG ради 12-пиксельных осколков.
## local_coords = false: выпущенные частицы остаются в мире, даже если эмиттер двигается.

const OUTLINE := Color("#0b1a26")

static var _textures: Dictionary = {}


## Одноразовый взрыв частиц. Запуск — restart().
static func burst(texture: Texture2D, amount: int, lifetime: float, material: ParticleProcessMaterial) -> GPUParticles2D:
	var p := _base(texture, amount, lifetime, material)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	return p


## Непрерывный поток частиц. Управление — emitting = true/false.
static func stream(texture: Texture2D, amount: int, lifetime: float, material: ParticleProcessMaterial) -> GPUParticles2D:
	var p := _base(texture, amount, lifetime, material)
	p.one_shot = false
	p.emitting = false
	return p


static func material(params: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	var direction: Vector2 = params.get("direction", Vector2.UP)
	m.direction = Vector3(direction.x, direction.y, 0.0)
	m.spread = params.get("spread", 180.0)
	m.initial_velocity_min = params.get("velocity", Vector2(100, 200)).x
	m.initial_velocity_max = params.get("velocity", Vector2(100, 200)).y
	var gravity: Vector2 = params.get("gravity", Vector2.ZERO)
	m.gravity = Vector3(gravity.x, gravity.y, 0.0)
	m.angular_velocity_min = params.get("spin", Vector2.ZERO).x
	m.angular_velocity_max = params.get("spin", Vector2.ZERO).y
	m.angle_min = params.get("angle", Vector2.ZERO).x
	m.angle_max = params.get("angle", Vector2.ZERO).y
	m.scale_min = params.get("scale", Vector2.ONE).x
	m.scale_max = params.get("scale", Vector2.ONE).y
	m.damping_min = params.get("damping", Vector2.ZERO).x
	m.damping_max = params.get("damping", Vector2.ZERO).y
	m.radial_accel_min = params.get("radial_accel", Vector2.ZERO).x
	m.radial_accel_max = params.get("radial_accel", Vector2.ZERO).y
	m.particle_flag_align_y = params.get("align", false)
	if params.has("emission_radius"):
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = params["emission_radius"]
	if params.has("emission_box"):
		var box: Vector2 = params["emission_box"]
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(box.x, box.y, 1.0)
	if params.has("colors"):
		m.color_initial_ramp = _pick_ramp(params["colors"])
	m.color = params.get("color", Color.WHITE)
	m.color_ramp = fade_ramp(params.get("fade_from", 0.6))
	if params.has("scale_curve_end"):
		m.scale_curve = _shrink_curve(params["scale_curve_end"])
	return m


## Альфа 1 до fade_from, затем плавно в 0 (fade-out в конце жизни).
static func fade_ramp(fade_from: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(clampf(fade_from, 0.01, 0.99), Color.WHITE)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Случайный цвет частицы строго из списка (без смешанных оттенков между ними).
static func _pick_ramp(colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	for i in colors.size():
		gradient.add_point(float(i) / colors.size(), colors[i])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _shrink_curve(end_scale: float) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, clampf(end_scale, 0.0, 1.0)))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _base(texture: Texture2D, amount: int, lifetime: float, process_material: ParticleProcessMaterial) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.texture = texture
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = process_material
	p.local_coords = false
	p.visibility_rect = Rect2(-600, -600, 1200, 1200)
	return p


# --- Процедурные текстуры частиц -------------------------------------------------------

static func tex_can() -> Texture2D:
	return _cached(&"can", func() -> Image:
		var img := _canvas(10, 14)
		_fill_rect(img, Rect2i(0, 0, 10, 14), OUTLINE)
		_fill_rect(img, Rect2i(1, 1, 8, 12), Color.WHITE)
		_fill_rect(img, Rect2i(1, 1, 8, 2), Color("#d8d8e8"))
		_fill_rect(img, Rect2i(1, 11, 8, 2), Color("#9aa0b8"))
		return img)


static func tex_spark() -> Texture2D:
	return _cached(&"spark", func() -> Image:
		var img := _canvas(6, 16)
		var zig := [Vector2i(3, 0), Vector2i(1, 4), Vector2i(4, 8), Vector2i(1, 12), Vector2i(3, 15)]
		for i in zig.size() - 1:
			_line(img, zig[i], zig[i + 1], Color.WHITE)
		return img)


static func tex_shard() -> Texture2D:
	return _cached(&"shard", func() -> Image:
		var img := _canvas(10, 10)
		for y in 10:
			for x in 10:
				if x + y <= 9 and x >= 1 and y >= 1:
					img.set_pixel(x, y, Color.WHITE if x + y <= 7 else OUTLINE)
		return img)


static func tex_crystal_shard() -> Texture2D:
	return _cached(&"crystal_shard", func() -> Image:
		var img := _canvas(8, 16)
		for y in 16:
			var half := int(round((1.0 - absf(y - 7.5) / 8.0) * 4.0))
			for x in range(4 - half, 4 + half):
				img.set_pixel(x, y, Color.WHITE if absi(x - 3) < half - 1 else Color(0.85, 0.85, 1.0))
		return img)


static func tex_drop() -> Texture2D:
	return _cached(&"drop", func() -> Image:
		var img := _canvas(10, 10)
		for y in 10:
			for x in 10:
				var d := Vector2(x - 4.5, y - 4.5).length()
				if d < 4.6:
					img.set_pixel(x, y, Color.WHITE if d < 3.4 else Color(1, 1, 1, 0.6))
		return img)


static func tex_pixel() -> Texture2D:
	return _cached(&"pixel", func() -> Image:
		var img := _canvas(4, 4)
		_fill_rect(img, Rect2i(0, 0, 4, 4), Color.WHITE)
		return img)


static func tex_rhombus() -> Texture2D:
	return _cached(&"rhombus", func() -> Image:
		var img := _canvas(12, 12)
		for y in 12:
			for x in 12:
				var d := absf(x - 5.5) + absf(y - 5.5)
				if d <= 5.5:
					img.set_pixel(x, y, Color(1, 1, 1, 0.9) if d <= 4.0 else Color(1, 1, 1, 0.4))
		return img)


static func tex_triangle() -> Texture2D:
	return _cached(&"triangle", func() -> Image:
		var img := _canvas(12, 12)
		for y in 12:
			var half := y * 0.5
			for x in 12:
				if absf(x - 5.5) <= half:
					img.set_pixel(x, y, Color(1, 1, 1, 0.9) if absf(x - 5.5) <= half - 1.2 else Color(1, 1, 1, 0.4))
		return img)


static func _cached(key: StringName, builder: Callable) -> Texture2D:
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(builder.call())
	return _textures[key]


static func _canvas(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	img.fill_rect(rect, color)


static func _line(img: Image, a: Vector2i, b: Vector2i, color: Color) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var t := float(i) / maxf(steps, 1)
		var p := Vector2(a).lerp(Vector2(b), t)
		img.set_pixel(int(round(p.x)), int(round(p.y)), color)
		img.set_pixel(clampi(int(round(p.x)) + 1, 0, img.get_width() - 1), int(round(p.y)), color)
