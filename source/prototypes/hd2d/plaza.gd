extends Node3D
## Прототип HD-2D (бриф v36): площадь Банка в 3D — земля, терраса со ступенями, фонтан, дома;
## персонажи и предметы — пиксельные спрайты, стоящие вертикально; наклонная перспективная камера,
## закатное солнце с тенями, фонари с настоящим светом, дымка, свечение и размытие краёв кадра.
## Временный арт: текущие спрайты и плитки Банка. Игру не затрагивает, запускается отдельной сценой.
## Масштаб брифа: 32 px арта = 1 м; временный арт масштабируется по нужной высоте в метрах.

## Материалы Астры (бриф v36): плитка на 2×2 м (64 или 96 px — размер берётся из файла), по три
## совместимых по краям варианта.
const MATERIALS := "res://prototypes/hd2d/materials/"
const MATERIAL_M := 2.0
## Варианты раскладываются мозаикой 3×3 (6×6 м на повтор), чтобы плитка не читалась сеткой.
const MOSAIC := [[0, 1, 2], [2, 0, 1], [1, 2, 0]]
const NORMAL_STRENGTH := 0.65
## Пиксель жёсткий, как в HD-2D: спрайты без mip-уровней, земля — анизотропно (без каши вдали).
## Модульные предметы Астры (v36, 48 px/м): фонарь на тумбе и кадка; опоры и крепление — из manifest.
const PROPS := "res://prototypes/hd2d/props/"
const BANK_DIR := "res://prototypes/hd2d/buildings/"
const BANK_MODEL := BANK_DIR + "bank_hall.glb"
const BANK_FRONT := 5.75
const BANK_GLOW := Color(1.0, 0.53, 0.16)
const BANK_GLOW_ENERGY := 0.55
## Плита террасы на крыше банка — высота над опорой модели (8.22 м + цоколь 0.6 м).
const BANK_ROOF := 8.82
## Плотность пикселя и крепление фонаря берутся из manifest сдачи (48 или 96 px/м).
const PROP_PX_PER_M := 48.0
const LANTERN_MOUNT := 1.2708333
const LANTERN_GLOW := Color("#ffc574")
const LANTERN_GLOW_ENERGY := 0.45
const PLAZA := Vector2(34.0, 26.0)
const TERRACE_Z := -6.0
const TERRACE_H := 1.2
const STEPS := 4
const CAMERA_PITCH := -32.0
const CAMERA_FOV := 30.0
const CAMERA_DISTANCE := 28.0
const HERO_SPEED := 4.2
const MOB_SPEED := 2.2
const MOB_COUNT := 12
const FIRE_GAP := 0.16
const BULLET_SPEED := 16.0
const SPRITE_TILT := -12.0
const RACCOON_CELL := Vector2i(300, 200)
const RICO96 := "res://prototypes/hd2d/chars/raccoon_idle"
const RICO96_ANCHOR := Vector2(128, 224)
const RICO96_DENSITY := 96.0
const PIG_GUARD96 := "res://prototypes/hd2d/chars/pig_guard_idle.png"
const PIG_GUARD96_ANCHOR := Vector2(128, 224)

var _camera: Camera3D
var _post: ShaderMaterial
var _hero: Node3D
## Новый Рико Астры (96 px/м, нормали): плоскость с материалом вместо старого спрайта.
var _hero_body: MeshInstance3D
var _hero_sprite: Sprite3D
var _hero_frames: Array[Texture2D] = []
var _hero_time := 0.0
var _hero_dir := Vector2.RIGHT
var _mobs: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _fire_wait := 0.0
var _time := 0.0
var _sniper_frames: Array[Rect2] = []
var _sniper_feet: Array[Vector2] = []
var _sniper_run: Array = []
var _rng := RandomNumberGenerator.new()
var _prop_density := PROP_PX_PER_M
var _lantern_mount := LANTERN_MOUNT
## Опоры предметов из всех manifest сдачи: "папка/файл" → anchor_px.
var _anchors := {}


func _ready() -> void:
	_rng.seed = 35
	_read_prop_manifest()
	_build_environment()
	_build_ground()
	_build_terrace()
	_build_buildings()
	_build_fountain()
	_build_props()
	_build_hero()
	_build_mobs()
	_build_camera()
	_build_post()


# --- Свет и атмосфера -----------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#e9c79a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6f7bb0")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("#f2cf9c")
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.18
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	# Закатное солнце спереди слева (со стороны камеры): лица освещены, тени уходят назад вправо.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffcb8a")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.9
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
	add_child(sun)


# --- Земля, терраса, дома -------------------------------------------------------------------------

func _mosaic(material: String, suffix: String) -> Texture2D:
	var variants: Array[Image] = []
	for i in 3:
		var path := "%s%s_%02d%s.png" % [MATERIALS, material, i + 1, suffix]
		if not ResourceLoader.exists(path):
			return null
		var image := (load(path) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		variants.append(image)
	var side := variants[0].get_width()
	var mosaic := Image.create(side * 3, side * 3, true, Image.FORMAT_RGBA8)
	for y in 3:
		for x in 3:
			mosaic.blit_rect(variants[MOSAIC[y][x]], Rect2i(0, 0, side, side), Vector2i(x, y) * side)
	mosaic.generate_mipmaps()
	return ImageTexture.create_from_image(mosaic)


func _material(name: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _mosaic(name, "")
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / (MATERIAL_M * 3.0)
	material.roughness = 0.9
	var normal := _mosaic(name, "_n")
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = NORMAL_STRENGTH
	return material


func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node


func _build_ground() -> void:
	var lawn := _material("lawn")
	var cobble := _material("cobble_gold")
	var worn := _material("cobble_worn")
	var pink := _material("rose_path")
	_box(Vector3(PLAZA.x + 40.0, 0.2, PLAZA.y + 40.0), Vector3(0, -0.1, 0), lawn)
	_box(Vector3(PLAZA.x - 6.0, 0.02, PLAZA.y - 12.0), Vector3(0, 0.01, 3.0), cobble)
	# Розовые дорожки крестом через площадь.
	_box(Vector3(3.0, 0.03, PLAZA.y - 12.0), Vector3(-1.5, 0.015, 3.0), pink)
	_box(Vector3(PLAZA.x - 6.0, 0.03, 2.4), Vector3(0, 0.015, 6.0), pink)
	# Вытертая брусчатка там, где ходят чаще всего: у ступеней и вокруг фонтана.
	_box(Vector3(8.0, 0.025, 3.0), Vector3(0, 0.0125, TERRACE_Z + 3.6), worn)
	_box(Vector3(8.5, 0.025, 7.5), Vector3(6.0, 0.0125, 2.0), worn)
	# Клумбы по краям площади появятся с клумбой Астры (бортик и цветы); голая земля смотрелась заглушкой.


func _build_terrace() -> void:
	var marble := _material("marble")
	var stone := _material("stone_wall")
	var riser := _material("step_riser")
	var depth := 13.0
	_box(Vector3(PLAZA.x, TERRACE_H, depth), Vector3(0, TERRACE_H * 0.5, TERRACE_Z - depth * 0.5), marble)
	# Подпорная стена — отдельная коробка с камнем спереди, ступени по центру.
	_box(Vector3(PLAZA.x, TERRACE_H, 0.3), Vector3(0, TERRACE_H * 0.5, TERRACE_Z + 0.15), stone)
	for i in STEPS:
		var h := TERRACE_H * float(STEPS - i) / float(STEPS)
		var z := TERRACE_Z + 0.3 + 0.45 * i + 0.225
		_box(Vector3(6.0, h, 0.45), Vector3(0, h * 0.5, z), marble)
		# Передняя грань ступени — своя текстура (тонкая плита перед коробкой).
		_box(Vector3(6.0, TERRACE_H / float(STEPS), 0.02), Vector3(0, h - TERRACE_H / float(STEPS) * 0.5, z + 0.235), riser)


func _build_buildings() -> void:
	var wall := _material("plaster")
	var roof := _material("roof_red")
	var back := TERRACE_Z - 10.0
	# Лавки по бокам — пока коробки со старыми спрайтами; их 3D-версии Астра делает после банка.
	for at: Vector3 in [Vector3(-13.0, 0, back + 0.5), Vector3(13.0, 0, back + 0.5)]:
		var size := Vector3(8, 6, 6)
		_box(size, at + Vector3(0, TERRACE_H + size.y * 0.5, 0), wall)
		_box(Vector3(size.x + 0.6, 0.6, size.z + 0.6), at + Vector3(0, TERRACE_H + size.y + 0.3, 0), roof)
	_sprite("res://assets/district/bank/pigs_villa.png", Vector3(-13.0, TERRACE_H, back + 3.6), 6.5)
	_sprite("res://assets/district/bank/pigs_boutique.png", Vector3(13.0, TERRACE_H, back + 3.6), 5.5)
	_build_bank()


## Банк Астры в 3D (v37/v38): .glb с пиксельными текстурами 96 px/м. Ступени входа выходят
## к балюстраде террасы; вечером стекло окон и настенных фонарей светится по маскам.
func _build_bank() -> void:
	if not ResourceLoader.exists(BANK_MODEL):
		return
	var bank := (load(BANK_MODEL) as PackedScene).instantiate() as Node3D
	# Передний край ступеней модели — z = +5.75 от опоры; ставим его в 0.8 м от балюстрады.
	bank.position = Vector3(0, TERRACE_H, TERRACE_Z - 0.8 - BANK_FRONT)
	add_child(bank)
	for node in bank.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var glow := ""
		if "Window_Glass" in str(mesh.name):
			glow = "bank_glass_glow.png"
		elif "Lantern_Glass" in str(mesh.name):
			glow = "bank_trim_glow.png"
		if glow.is_empty():
			continue
		var material := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.emission_enabled = true
		material.emission = BANK_GLOW
		material.emission_texture = load(BANK_DIR + glow)
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = BANK_GLOW_ENERGY
		mesh.material_override = material
	_furnish_bank_roof(bank.position)
	# Настенные фонари по сторонам двери дают настоящий тёплый свет на фасад.
	for x: float in [-1.8, 1.8]:
		var light := OmniLight3D.new()
		light.light_color = Color("#ffb45e")
		light.light_energy = 1.2
		light.omni_range = 5.0
		light.position = bank.position + Vector3(x, 3.4, 4.4)
		add_child(light)


## Терраса на крыше обжита: кадки по углам и столики кафе под зонтами у выхода на крышу.
## Координаты — в плане модели (x вправо, y от фасада вглубь, как в Blender).
func _furnish_bank_roof(origin: Vector3) -> void:
	var at := func(x: float, y: float) -> Vector3: return origin + Vector3(x, BANK_ROOF, -y)
	# Выход на крышу стоит в западном углу; кафе и кадки — на открытой части террасы.
	for xy: Vector2 in [Vector2(-1.6, 2.8), Vector2(6.7, 3.1)]:
		_item("bank_flower_planter", at.call(xy.x, xy.y))
	for xy: Vector2 in [Vector2(1.6, -1.0), Vector2(5.0, -1.0)]:
		var spot: Vector3 = at.call(xy.x, xy.y)
		_item("cafe96/bank_cafe_table", spot)
		_item("cafe96/bank_cafe_chair_left", spot + Vector3(-0.85, 0, 0.05))
		_item("cafe96/bank_cafe_chair_right", spot + Vector3(0.85, 0, 0.05))
		_item("cafe96/bank_umbrella_standalone", spot + Vector3(0.9, 0, -0.6))


func _build_fountain() -> void:
	var at := Vector3(6.0, 0, 2.0)
	var marble := _material("marble")
	for ring: Array in [[3.0, 0.6], [1.5, 1.1]]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = ring[0]
		mesh.bottom_radius = ring[0]
		mesh.height = ring[1]
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = marble
		node.position = at + Vector3(0, ring[1] * 0.5, 0)
		add_child(node)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.35, 0.75, 0.95, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.emission_enabled = true
	water.emission = Color(0.2, 0.55, 0.8)
	water.emission_energy_multiplier = 0.4
	water.metallic_specular = 1.0
	water.roughness = 0.05
	var pool := CylinderMesh.new()
	pool.top_radius = 2.75
	pool.bottom_radius = 2.75
	pool.height = 0.05
	var surface := MeshInstance3D.new()
	surface.mesh = pool
	surface.material_override = water
	surface.position = at + Vector3(0, 0.62, 0)
	add_child(surface)
	_sprite("res://assets/props/ch2/pig_statue.png", at + Vector3(0, 1.1, 0.0), 2.2)


func _build_props() -> void:
	# Фонари с настоящим тёплым светом.
	for x: float in [-9.0, 9.0, -15.0, 15.0]:
		_lamp(Vector3(x, 0, TERRACE_Z + 2.0))
	for x: float in [-5.0, 5.0]:
		_lamp(Vector3(x, TERRACE_H, TERRACE_Z - 1.5))
	# Балюстрада по краю террасы: секции по 2 м, три варианта сколов вперемешку; проход у ступеней.
	var sections := ["street96/bank_balustrade", "street96/bank_balustrade_02", "street96/bank_balustrade_03"]
	var k := 0
	for x in range(-16, 17, 2):
		if absf(x) > 3.0:
			_item(sections[(k * 7 + 3) % 3], Vector3(x, TERRACE_H, TERRACE_Z - 0.2))
			k += 1
	for at: Vector3 in [Vector3(-14.0, 0, 9.0), Vector3(-11.5, 0, TERRACE_Z + 2.0), Vector3(11.5, 0, TERRACE_Z + 2.0)]:
		_item("bank_flower_planter", at)
	# Уличное кафе: зонт на своей подставке рядом со столиком, стулья по бокам.
	for at: Vector3 in [Vector3(-11.5, 0, 1.5), Vector3(12.5, 0, 8.0)]:
		_item("cafe96/bank_cafe_table", at)
		_item("cafe96/bank_cafe_chair_left", at + Vector3(-0.85, 0, 0.05))
		_item("cafe96/bank_cafe_chair_right", at + Vector3(0.85, 0, 0.05))
		_item("cafe96/bank_umbrella_standalone", at + Vector3(0.9, 0, -0.6))
	# Передний план: ограда и фонари у самой камеры — их размоет край кадра.
	for x in range(-18, 19, 3):
		_sprite("res://assets/props/ch2/railing.png", Vector3(x, 0, PLAZA.y * 0.5 + 1.0), 1.6)
	_sprite("res://assets/props/ch2/lamp_banner.png", Vector3(-6.0, 0, PLAZA.y * 0.5 + 2.5), 4.2)
	_sprite("res://assets/props/ch2/lamp_banner.png", Vector3(10.0, 0, PLAZA.y * 0.5 + 2.0), 4.2)


func _read_prop_manifest() -> void:
	for folder: String in ["", "cafe96/", "street96/"]:
		var sub: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPS + folder + "manifest.json")) if FileAccess.file_exists(PROPS + folder + "manifest.json") else null
		if sub is Dictionary:
			for file: Dictionary in sub.get("files", []):
				if file.has("anchor_px"):
					_anchors[folder + str(file["file"]).get_basename()] = Vector2(file["anchor_px"][0], file["anchor_px"][1])
	var path := PROPS + "manifest.json"
	if not FileAccess.file_exists(path):
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary:
		return
	_prop_density = float(manifest.get("pixels_per_metre", PROP_PX_PER_M))
	for part: Dictionary in manifest.get("assembly", {}).get("parts", []):
		if str(part.get("file", "")).begins_with("bank_lantern"):
			_lantern_mount = float(part.get("position_m", [0, LANTERN_MOUNT, 0])[1])


func _anchor(name: String, fallback: Vector2) -> Vector2:
	return _anchors.get(name, fallback)


## Предмет Астры по имени из manifest (опора — оттуда же).
func _item(name: String, at: Vector3) -> Node3D:
	return _prop(name, _anchor(name, Vector2(0, 0)), at)


func _lamp(at: Vector3) -> void:
	var pivot := _prop("bank_pedestal", _anchor("bank_pedestal", Vector2(48, 71)), at)
	# Фонарь крепится к тумбе в той же наклонённой плоскости спрайта, чуть ближе к камере.
	var lantern := _prop("bank_lantern", _anchor("bank_lantern", Vector2(36, 103)), Vector3.ZERO, pivot)
	lantern.position = Vector3(0, _lantern_mount, 0.005)
	lantern.rotation = Vector3.ZERO
	var light := OmniLight3D.new()
	light.light_color = Color("#ffb45e")
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = at + Vector3(0, _lantern_mount + 1.0, 0.3)
	add_child(light)


## Предмет Астры как плоскость с настоящим материалом: альфа-срез, карта нормалей камня и
## свечение стекла по маске (умножением — светится только стекло, а не железо корпуса).
func _prop(name: String, anchor: Vector2, at: Vector3, parent: Node3D = self) -> Node3D:
	var albedo := load(PROPS + name + ".png") as Texture2D
	var size := albedo.get_size()
	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.85
	if ResourceLoader.exists(PROPS + name + "_n.png"):
		material.normal_enabled = true
		material.normal_texture = load(PROPS + name + "_n.png")
		material.normal_scale = 0.45
	if ResourceLoader.exists(PROPS + name + "_glow.png"):
		material.emission_enabled = true
		material.emission = LANTERN_GLOW
		material.emission_texture = load(PROPS + name + "_glow.png")
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = LANTERN_GLOW_ENERGY
	var quad := QuadMesh.new()
	quad.size = size / _prop_density
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Опора (низ-центр по manifest) приходится на точку pivot.
	mesh.position = Vector3(size.x * 0.5 - anchor.x, size.y * 0.5 - (size.y - anchor.y), 0) / _prop_density
	var pivot := Node3D.new()
	pivot.position = at
	pivot.rotation_degrees.x = SPRITE_TILT
	parent.add_child(pivot)
	pivot.add_child(mesh)
	return pivot


## Вертикальный спрайт с низом в точке at, высотой height метров; слегка наклонён к камере.
func _sprite(path: String, at: Vector3, height: float) -> Sprite3D:
	var texture := load(path) as Texture2D
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = height / float(texture.get_height())
	sprite.centered = true
	sprite.offset = Vector2(0, texture.get_height() * 0.5)
	_style(sprite)
	sprite.position = at
	add_child(sprite)
	return sprite


func _style(sprite: Sprite3D) -> void:
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sprite.rotation_degrees.x = SPRITE_TILT


# --- Герой и мобы ---------------------------------------------------------------------------------

func _build_hero() -> void:
	if ResourceLoader.exists(RICO96 + ".png"):
		_hero = Node3D.new()
		_hero.position = Vector3(-3, 0, 4)
		add_child(_hero)
		var albedo := load(RICO96 + ".png") as Texture2D
		var size := albedo.get_size()
		var material := StandardMaterial3D.new()
		material.albedo_texture = albedo
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.8
		material.normal_enabled = true
		material.normal_texture = load(RICO96 + "_n.png")
		material.normal_scale = 0.25
		var quad := QuadMesh.new()
		quad.size = size / RICO96_DENSITY
		_hero_body = MeshInstance3D.new()
		_hero_body.mesh = quad
		_hero_body.material_override = material
		_hero_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_hero_body.position = Vector3(size.x * 0.5 - RICO96_ANCHOR.x, size.y * 0.5 - (size.y - RICO96_ANCHOR.y), 0) / RICO96_DENSITY
		var tilt := Node3D.new()
		tilt.rotation_degrees.x = SPRITE_TILT
		_hero.add_child(tilt)
		tilt.add_child(_hero_body)
		return
	var sheet := (load("res://assets/heroes/tactical/raccoon_run.png") as Texture2D).get_image()
	if sheet.is_compressed():
		sheet.decompress()
	for i in 8:
		_hero_frames.append(ImageTexture.create_from_image(sheet.get_region(Rect2i((i % 4) * RACCOON_CELL.x, (i / 4) * RACCOON_CELL.y, RACCOON_CELL.x, RACCOON_CELL.y))))
	_hero_sprite = Sprite3D.new()
	_hero_sprite.texture = _hero_frames[0]
	# Рост Енота в кадре ~165 px из 200; временный арт тоньше свиней, поэтому 1.9 м.
	_hero_sprite.pixel_size = 1.9 / 165.0
	_hero_sprite.offset = Vector2(0, RACCOON_CELL.y * 0.5 - 10.0)
	_style(_hero_sprite)
	_hero_sprite.position = Vector3(-3, 0, 4)
	add_child(_hero_sprite)
	_hero = _hero_sprite


func _build_mobs() -> void:
	var sheets: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/frames.json")) as Dictionary)["sheets"]
	var sniper: Dictionary = sheets["pig_sniper"]
	for f: Array in sniper["frames"]:
		_sniper_frames.append(Rect2(f[0], f[1], f[2], f[3]))
		_sniper_feet.append(Vector2(f[4], f[5]))
	_sniper_run = sniper["clips"]["run"]["frames"]
	for i in MOB_COUNT:
		_spawn_mob(i)


func _spawn_mob(i: int) -> void:
	# Пока из новых свиней есть только щитовик Астры (96 px/м) — толпа из них; старые — запасной вариант.
	var kinds := ["pig_guard96"] if ResourceLoader.exists(PIG_GUARD96) else ["pig_default", "pig_heavy", "pig_royal", "pig_angry", "pig_sniper"]
	var kind: String = kinds[i % kinds.size()]
	var sprite := Sprite3D.new()
	var height := 1.9 if kind != "pig_heavy" else 2.2
	if kind == "pig_guard96":
		sprite.texture = load(PIG_GUARD96)
		sprite.pixel_size = 1.0 / RICO96_DENSITY
		sprite.offset = Vector2(0, PIG_GUARD96_ANCHOR.y - sprite.texture.get_height() * 0.5)
	elif kind == "pig_sniper":
		sprite.texture = load("res://assets/enemies/pig_sniper.png")
		sprite.region_enabled = true
		sprite.pixel_size = 1.9 / 96.0
	else:
		var texture := load("res://assets/enemies/%s.png" % kind) as Texture2D
		sprite.texture = texture
		sprite.pixel_size = height / float(texture.get_height())
		sprite.offset = Vector2(0, texture.get_height() * 0.5)
	_style(sprite)
	var side := _rng.randf() * TAU
	sprite.position = _hero.position + Vector3(cos(side), 0, sin(side)) * _rng.randf_range(9.0, 13.0)
	sprite.position.z = clampf(sprite.position.z, TERRACE_Z + 2.5, PLAZA.y * 0.5 - 1.0)
	add_child(sprite)
	var mob := {"node": sprite, "kind": kind, "hp": 3, "flash": 0.0, "phase": _rng.randf() * 10.0}
	if i < _mobs.size():
		_mobs[i] = mob
	else:
		_mobs.append(mob)


func _process(delta: float) -> void:
	_time += delta
	_move_hero(delta)
	_move_mobs(delta)
	_fire(delta)
	_move_bullets(delta)
	_follow_camera(delta)


func _move_hero(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input == Vector2.ZERO:
		# Без ввода герой обходит площадь восьмёркой — для видео и скриншотов.
		input = Vector2(cos(_time * 0.45), sin(_time * 0.9) * 0.8)
	var step := input.normalized() * HERO_SPEED * delta
	var target := _hero.position + Vector3(step.x, 0, step.y)
	target.x = clampf(target.x, -PLAZA.x * 0.5 + 2.0, PLAZA.x * 0.5 - 2.0)
	target.z = clampf(target.z, TERRACE_Z + 1.2, PLAZA.y * 0.5 - 1.5)
	if Vector2(target.x - 6.0, target.z - 2.0).length() < 3.3:
		target = _hero.position
	_hero.position = target
	if absf(input.x) > 0.1:
		_hero_dir = Vector2(signf(input.x), 0)
	_hero_time += delta
	if _hero_sprite != null:
		_hero_sprite.flip_h = _hero_dir.x < 0
		_hero_sprite.texture = _hero_frames[int(_hero_time * 12.0) % _hero_frames.size()]
	else:
		# Один кадр idle: шаг передаётся лёгким подпрыгиванием, пока Астра рисует бег. Разворот —
		# через UV: отражённая плоскость повернулась бы к свету обратной стороной и стала чёрной.
		var material := _hero_body.material_override as StandardMaterial3D
		var left := _hero_dir.x < 0
		material.uv1_scale = Vector3(-1.0 if left else 1.0, 1.0, 1.0)
		material.uv1_offset = Vector3(1.0 if left else 0.0, 0.0, 0.0)
		_hero_body.get_parent().position.y = absf(sin(_hero_time * 9.0)) * 0.05


func _move_mobs(delta: float) -> void:
	for i in _mobs.size():
		var mob: Dictionary = _mobs[i]
		var node: Sprite3D = mob["node"]
		var to_hero := _hero.position - node.position
		to_hero.y = 0
		var push := Vector3.ZERO
		for other: Dictionary in _mobs:
			if other == mob:
				continue
			var gap: Vector3 = node.position - (other["node"] as Sprite3D).position
			gap.y = 0
			if gap.length() < 1.6 and gap.length() > 0.01:
				push += gap.normalized() * (1.6 - gap.length()) * 3.0
		var walk := to_hero.normalized() * MOB_SPEED if to_hero.length() > 3.2 else Vector3.ZERO
		node.position += (walk + push) * delta
		node.position.z = clampf(node.position.z, TERRACE_Z + 1.0, PLAZA.y * 0.5 - 1.0)
		node.flip_h = to_hero.x < 0
		mob["flash"] = maxf(float(mob["flash"]) - delta, 0.0)
		node.modulate = Color(1.0, 0.55, 0.5) if float(mob["flash"]) > 0.0 else Color.WHITE
		if mob["kind"] == "pig_sniper":
			var frame: int = _sniper_run[int((_time + float(mob["phase"])) * 10.0) % _sniper_run.size()]
			node.region_rect = _sniper_frames[frame]
			var rect := _sniper_frames[frame]
			node.offset = Vector2(rect.size.x * 0.5 - _sniper_feet[frame].x, _sniper_feet[frame].y - rect.size.y * 0.5)
		else:
			# Временный арт без кадров шага: покачивание при ходьбе.
			node.rotation_degrees.z = sin((_time + float(mob["phase"])) * 9.0) * 4.0


func _fire(delta: float) -> void:
	_fire_wait -= delta
	if _fire_wait > 0.0 or _mobs.is_empty():
		return
	var best: Dictionary = {}
	var best_d := 14.0
	for mob: Dictionary in _mobs:
		var d := (mob["node"] as Sprite3D).position.distance_to(_hero.position)
		if d < best_d:
			best_d = d
			best = mob
	if best.is_empty():
		return
	_fire_wait = FIRE_GAP
	var from := _hero.position + Vector3(0, 1.0, 0)
	var to := (best["node"] as Sprite3D).position + Vector3(0, 1.0, 0)
	_hero_dir = Vector2(signf(to.x - from.x), 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.85, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.7, 0.3)
	glow.emission_energy_multiplier = 4.0
	var bullet := MeshInstance3D.new()
	bullet.mesh = mesh
	bullet.material_override = glow
	bullet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bullet.position = from
	add_child(bullet)
	_bullets.append({"node": bullet, "velocity": (to - from).normalized() * BULLET_SPEED, "life": 1.2})


func _move_bullets(delta: float) -> void:
	for i in range(_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = _bullets[i]
		var node: MeshInstance3D = bullet["node"]
		node.position += bullet["velocity"] * delta
		bullet["life"] = float(bullet["life"]) - delta
		var hit := false
		for j in _mobs.size():
			var mob: Dictionary = _mobs[j]
			var body: Vector3 = (mob["node"] as Sprite3D).position + Vector3(0, 1.0, 0)
			if body.distance_to(node.position) < 0.7:
				hit = true
				mob["flash"] = 0.1
				mob["hp"] = int(mob["hp"]) - 1
				if int(mob["hp"]) <= 0:
					(mob["node"] as Sprite3D).queue_free()
					_spawn_mob(j)
				break
		if hit or float(bullet["life"]) <= 0.0:
			node.queue_free()
			_bullets.remove_at(i)


# --- Камера и пост-обработка ----------------------------------------------------------------------

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.rotation_degrees = Vector3(CAMERA_PITCH, 0, 0)
	_camera.far = 200.0
	add_child(_camera)
	_camera.make_current()
	_follow_camera(1.0)


func _follow_camera(delta: float) -> void:
	var back := Vector3(0, sin(deg_to_rad(-CAMERA_PITCH)), cos(deg_to_rad(-CAMERA_PITCH))) * CAMERA_DISTANCE
	var target := _hero.position + Vector3(0, 0.8, -3.0) + back
	_camera.position = _camera.position.lerp(target, 1.0 - exp(-delta * 4.0))
	# Резкая полоса держится на герое: размыты только дальний и ближний планы.
	if _post != null:
		var at := _camera.unproject_position(_hero.position + Vector3(0, 0.9, 0))
		_post.set_shader_parameter(&"focus_y", clampf(at.y / get_viewport().get_visible_rect().size.y, 0.3, 0.75))


## Та же цветокоррекция, что в 2D-бою: размытие верха и низа (в наклонной камере это глубина
## резкости), свечение ярких мест и дымка сверху.
func _build_post() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/color_grade.gdshader")
	material.set_shader_parameter(&"tilt_blur", 2.0)
	material.set_shader_parameter(&"focus_half", 0.4)
	material.set_shader_parameter(&"focus_ramp", 0.12)
	material.set_shader_parameter(&"glow_strength", 0.12)
	material.set_shader_parameter(&"glow_threshold", 0.9)
	material.set_shader_parameter(&"haze_color", Color(1.0, 0.86, 0.62, 0.0))
	material.set_shader_parameter(&"shadow_tint", Vector3(0.08, 0.02, 0.14))
	material.set_shader_parameter(&"highlight_tint", Vector3(0.06, 0.03, -0.03))
	rect.material = material
	_post = material
	layer.add_child(rect)
