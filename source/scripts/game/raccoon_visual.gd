class_name RaccoonVisual
extends Node2D
## Герой-налётчик на GPU-риге (RigSprite + shaders/rig2d.gdshader).
##
## Слои (дети по порядку отрисовки): корпус на риге → ствол → вытянутая рука (свой спрайт, вращается
## в плече к цели и держит ствол) → передние эффекты. Сам узел рисует тень и задние эффекты.
##
## Анимация — процедурная, но на костях: 12 костей (уши, голова, шарф, свободная лапа, корпус,
## три звена хвоста, две ноги). Бег — цикл шага с фазой, завязанной на скорость; idle — дыхание,
## покачивание хвоста, подёргивание ушей; переходы — плавное смешивание (_run, _dash_blend, ...);
## вторичная анимация — пружины (голова, уши, хвост, шарф) догоняют рывки и развороты.
## Лицо: моргание, прищур при попадании и прицеливании, «довольные» глаза при подборе и
## повышении уровня; голова чуть поворачивается к цели.
##
## Внешность = герой (CharacterDB: окрас меха и глаз, пропорции) + наряд (SaveService.SKINS:
## перекраска одежды/шарфа/ремней/металла + слой аксессуаров в развёртке спрайта).

const RIG_ID := "raccoon"
const OUTLINE := Color("#180e22")
const FLASH_TIME := 0.12
const HURT_TIME := 0.35
const PICKUP_TIME := 0.3
const CHEER_TIME := 0.9
const KICK_DECAY := 14.0
const AIM_SMOOTH := 20.0
const TEXTURE_PATH := "res://assets/player/raccoon.png"
const ARM_PATH := "res://assets/player/raccoon_arm.png"
const OVERLAY_DIR := "res://assets/skins/"
## Текстуры хранятся ~3x к миру для чёткости на экранах телефонов: в мире енот ~100 px в высоту.
const SPRITE_SCALE := 0.36
const ARM_REST := 0.055
const ARM_MIN := -1.05
const ARM_MAX := 1.2
## Угол руки без цели: ствол опущен вперёд-вниз.
const RELAXED_ANGLE := 0.55
const GUN_SCALE := 0.7
const SHADOW_OFFSET := Vector2(0, 18)
const SHADOW_RADIUS := 30.0
const REGIONS: Array[String] = ["fur", "clothes", "scarf", "leather", "metal", "iris"]
## Диапазоны яркости регионов в исходном рисунке (для градиентной карты).
const REGION_RANGES: Array[Vector2] = [Vector2(0.07, 0.9), Vector2(0.08, 0.41), Vector2(0.15, 0.49),
	Vector2(0.13, 0.43), Vector2(0.27, 0.72), Vector2(0.06, 0.83)]
## Пропорция героя → какие кости рига растягивает.
const PROPORTION_BONES := {"head": ["head"], "ears": ["ear_l", "ear_r"], "tail": ["tail_base"], "torso": ["torso"],
	"legs": ["leg_f", "leg_b"]}

static var _full_texture: Texture2D
static var _arm_texture: Texture2D
static var _hero_textures: Dictionary = {}

var aim_direction := Vector2.RIGHT
## false — цели нет: рука опущена, ствол смотрит вперёд-вниз.
var aiming := true
var weapon_color := Color("#00ffff")
var weapon_icon: StringName = &"pistol"
## Ближний бой: клинок поворачивается вокруг лапы на melee_offset (рад) и растёт с melee_scale.
var melee_active := false
var melee_offset := 0.0
var melee_scale := 1.0
var skin_effect := ""
var dashing := false
## 0..1 — положение бегущего блика по стволу (Idle-анимация меню).
var glint := 0.0

var body: RigSprite
var hero: Sprite2D
var _hero_mode := false
var _hero_cfg: Dictionary = {}
var _hero_frames: Array[AtlasTexture] = []
var _hero_shoulder := Vector2.ZERO
var arm: Sprite2D
var _arm_material: ShaderMaterial
var _gun_layer: Node2D
var _front_layer: Node2D
var _rig_ok := false
var _b: Dictionary = {}
var _shoulder := Vector2.ZERO
var _paw := Vector2.ZERO
var _arm_pivot := Vector2.ZERO
var _proportions: Dictionary = {}

var _time := 0.0
var _gait := 0.0
var _breath := 0.0
var _run := 0.0
var _dash_blend := 0.0
var _facing := 1.0
var _flash := 0.0
var _hurt := 0.0
var _pickup := 0.0
var _cheer := 0.0
var _kick := 0.0
var _climb := 0.0
var show_aim_line := false
var _flash_t := 0.0
var _body_kick := Vector2.ZERO
var _dead := false
var _death_t := 0.0
var _gun_angle := RELAXED_ANGLE
var _velocity := Vector2.ZERO
var _bob := 0.0
var _squash := 1.0
var _stretch := 1.0
var _sway := 0.0
var _hop := 0.0
var _aim_local := 0.0
var _env := Color(0, 0, 0)

var _head_spring := SpringValue.new(140.0, 11.0)
var _ear_spring := SpringValue.new(220.0, 9.0)
var _tail_spring := SpringValue.new(38.0, 4.5)
var _scarf_spring := SpringValue.new(55.0, 3.5)
var _blink_timer := 2.0
var _blink_t := -1.0
var _double_blink := false
var _twitch_timer := 3.0
var _twitch_l := SpringValue.new(260.0, 12.0)
var _twitch_r := SpringValue.new(260.0, 12.0)


func _init() -> void:
	body = RigSprite.new()
	add_child(body)
	hero = Sprite2D.new()
	hero.centered = false
	hero.visible = false
	add_child(hero)
	_rig_ok = body.setup(RIG_ID, 0.0, false)
	_gun_layer = Node2D.new()
	_gun_layer.draw.connect(_draw_gun_layer)
	add_child(_gun_layer)
	arm = Sprite2D.new()
	arm.centered = false
	_arm_material = ShaderMaterial.new()
	_arm_material.shader = load(RigSprite.SHADER_PATH)
	_arm_material.set_shader_parameter("rig_enabled", false)
	arm.material = _arm_material
	add_child(arm)
	_front_layer = Node2D.new()
	_front_layer.draw.connect(_draw_effect_front)
	add_child(_front_layer)
	if not _rig_ok:
		body.visible = false
		arm.visible = false
		return
	for bone_name in (body.rig["bone_index"] as Dictionary):
		_b[bone_name] = body.bone(bone_name)
	var extra: Dictionary = body.rig["extra"]
	_shoulder = _vec(extra.get("shoulder", [0, 0]))
	_paw = _vec(extra.get("paw", [60, 0]))
	_arm_pivot = _vec(extra.get("arm_tex_pivot", [0, 0]))
	arm.texture = _get_arm_texture()
	arm.offset = -_arm_pivot
	var arm_regions: Array = extra.get("arm_regions", [])
	if arm_regions.size() >= 2:
		_arm_material.set_shader_parameter("regions0", RigDB.data_texture(arm_regions[0]))
		_arm_material.set_shader_parameter("regions1", RigDB.data_texture(arm_regions[1]))
	_blink_timer = randf_range(1.0, 3.5)
	_twitch_timer = randf_range(2.0, 5.0)
	apply_look(SaveService.get_character(), SaveService.get_skin())


static func _vec(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) if value is Array and (value as Array).size() >= 2 else Vector2.ZERO


# --- Внешность -------------------------------------------------------------------------------------

func apply_skin(skin: Dictionary) -> void:
	apply_look(SaveService.get_character(), skin)


## Герой + наряд → параметры шейдера. Регионы наряда перекрывают регионы героя.
func apply_look(character: Dictionary, skin: Dictionary) -> void:
	skin_effect = str(skin.get("effect", ""))
	if not _rig_ok:
		return
	if character.has("sprite") and (not bool(character["sprite"].get("classic_only", false)) or (skin.get("look", {}) as Dictionary).is_empty()):
		_enter_hero(character["sprite"])
		return
	_leave_hero()
	var look: Dictionary = skin.get("look", {})
	var recolor: Dictionary = (character.get("recolor", {}) as Dictionary).duplicate()
	var skin_recolor: Dictionary = look.get("recolor", {})
	for region in skin_recolor:
		recolor[region] = skin_recolor[region]
	var params := build_recolor(recolor)
	for material: ShaderMaterial in [body.shader_material, _arm_material]:
		material.set_shader_parameter("recolor_enabled", not recolor.is_empty())
		for key in params:
			material.set_shader_parameter(key, params[key])
	var overlay_id := str(look.get("overlay", ""))
	_set_overlay(body.shader_material, OVERLAY_DIR + overlay_id + "_body.png" if not overlay_id.is_empty() else "")
	_set_overlay(_arm_material, OVERLAY_DIR + overlay_id + "_arm.png" if not overlay_id.is_empty() else "")
	_proportions = {}
	var props: Dictionary = character.get("proportions", {})
	for key in props:
		for bone_name in PROPORTION_BONES.get(key, []):
			if _b.has(bone_name):
				_proportions[_b[bone_name]] = _vec(props[key])


## Герой с собственным артом (кадры из концепт-листа): рига и перекраски нет, тело — покадровый
## спрайт с процедурными наклоном, сжатием и покачиванием; ствол держит нарисованная рука.
func _enter_hero(cfg: Dictionary) -> void:
	var path := str(cfg.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		_leave_hero()
		return
	if not _hero_textures.has(path):
		_hero_textures[path] = load(path)
	var texture: Texture2D = _hero_textures[path]
	_hero_cfg = cfg
	_hero_frames.clear()
	var cell_w := int(cfg.get("cell_w", 384))
	var cell_h := int(cfg.get("cell_h", 288))
	for i in int(cfg.get("cells", 4)):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * cell_w, 0, cell_w, cell_h)
		_hero_frames.append(atlas)
	var feet := SHADOW_OFFSET.y / SPRITE_SCALE
	hero.offset = Vector2(-cell_w * 0.5, -cell_h + feet)
	var sh: Array = cfg.get("shoulder", [26, -172])
	_hero_shoulder = Vector2(float(sh[0]), float(sh[1]) + feet)
	_hero_mode = true
	hero.visible = true
	body.visible = false
	arm.visible = false
	hero.texture = _hero_frames[1]
	_apply_rig()


func _leave_hero() -> void:
	if not _hero_mode:
		return
	_hero_mode = false
	hero.visible = false
	body.visible = true
	arm.visible = true
	_apply_rig()


func _hero_frame_index() -> int:
	var run: Array = _hero_cfg.get("run", [1, 2])
	if _run < 0.12:
		return int(run[0])
	return int(run[0]) if sin(_gait) >= 0.0 else int(run[1])


func _paw_at(local_angle: float) -> Vector2:
	if _hero_mode:
		var reach := float(_hero_cfg.get("arm_len", 66))
		return _sprite_xform() * (_hero_shoulder + Vector2.from_angle(clampf(local_angle, ARM_MIN, ARM_MAX)) * reach)
	return _arm_xform(local_angle) * _paw


static func build_recolor(recolor: Dictionary) -> Dictionary:
	var dark := PackedColorArray()
	var mid := PackedColorArray()
	var light := PackedColorArray()
	var ranges := PackedVector2Array()
	for i in REGIONS.size():
		var entry: Array = recolor.get(REGIONS[i], [])
		if entry.size() >= 4:
			dark.append(Color(str(entry[0])))
			mid.append(Color(str(entry[1])))
			var l := Color(str(entry[2]))
			l.a = float(entry[3])
			light.append(l)
			ranges.append(Vector2(float(entry[4]), float(entry[5])) if entry.size() >= 6 else REGION_RANGES[i])
		else:
			dark.append(Color.BLACK)
			mid.append(Color.GRAY)
			light.append(Color(1, 1, 1, 0))
			ranges.append(REGION_RANGES[i])
	return {"grad_dark": dark, "grad_mid": mid, "grad_light": light, "grad_range": ranges}


func _set_overlay(material: ShaderMaterial, path: String) -> void:
	var has := not path.is_empty() and ResourceLoader.exists(path)
	material.set_shader_parameter("overlay_enabled", has)
	if has:
		material.set_shader_parameter("overlay", load(path))


# --- Движение и события ----------------------------------------------------------------------------

func update_motion(velocity: Vector2, aim: Vector2, delta: float) -> void:
	_time += delta
	var accel := (velocity - _velocity) / maxf(delta, 0.001)
	_velocity = velocity
	var speed := velocity.length()
	_run = move_toward(_run, clampf(speed / 200.0, 0.0, 1.0), delta * 6.0)
	_gait += delta * (5.0 + 9.0 * _run) * (0.6 + 0.4 * clampf(speed / 240.0, 0.0, 1.4))
	_breath += delta * (2.4 + 2.0 * _run)
	_dash_blend = move_toward(_dash_blend, 1.0 if dashing else 0.0, delta * 12.0)
	aim_direction = aim
	var look_x := aim.x if absf(aim.x) > 0.05 else velocity.x
	if absf(look_x) > 0.05 and signf(look_x) != _facing:
		_facing = signf(look_x)
		_tail_spring.kick(-3.0)
		_ear_spring.kick(-2.5)
		_scarf_spring.kick(3.0)
	_flash = maxf(_flash - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_pickup = maxf(_pickup - delta, 0.0)
	_cheer = maxf(_cheer - delta, 0.0)
	_kick = lerpf(_kick, 0.0, clampf(KICK_DECAY * delta, 0.0, 1.0))
	_climb = lerpf(_climb, 0.0, clampf(10.0 * delta, 0.0, 1.0))
	_flash_t = maxf(_flash_t - delta, 0.0)
	_body_kick = _body_kick.lerp(Vector2.ZERO, clampf(KICK_DECAY * delta, 0.0, 1.0))
	var local_accel := accel.x * _facing
	_tail_spring.update(clampf(-local_accel * 0.0006, -0.35, 0.35), delta)
	_scarf_spring.update(clampf(-local_accel * 0.0005, -0.3, 0.3), delta)
	_ear_spring.update(0.0, delta)
	_head_spring.update(0.0, delta)
	_twitch_l.update(0.0, delta)
	_twitch_r.update(0.0, delta)
	_update_face(delta)
	_update_pose()
	var target := RELAXED_ANGLE
	if aiming and aim.length_squared() > 0.0001:
		target = _local_angle(aim)
	_gun_angle = lerp_angle(_gun_angle, target, clampf(AIM_SMOOTH * delta, 0.0, 1.0))
	_aim_local = lerpf(_aim_local, clampf(_gun_angle, -0.9, 0.9) if aiming else 0.0, clampf(8.0 * delta, 0.0, 1.0))
	_apply_rig()
	queue_redraw()
	_gun_layer.queue_redraw()
	_front_layer.queue_redraw()


## Свет окружения (EnvLights.sample) — плавно, без скачков при входе в пятно.
func set_env_light(light: Color, delta: float) -> void:
	_env = _env.lerp(light, clampf(delta * 8.0, 0.0, 1.0))
	var v := Vector3(_env.r, _env.g, _env.b)
	body.set_param("env_light", v)
	_arm_material.set_shader_parameter("env_light", v)


func flash() -> void:
	_flash = FLASH_TIME
	_hurt = HURT_TIME
	_head_spring.kick(-4.5)
	_ear_spring.kick(-6.0)
	_tail_spring.kick(2.5)


## Отдача: ствол уходит назад, тело — чуть против выстрела, голова кивает.
func kick(direction: Vector2, strength: float) -> void:
	_kick = minf(_kick + 8.0 * strength, 18.0)
	_climb = minf(_climb + 0.07 * strength, 0.22)
	_flash_t = 0.07
	_body_kick -= direction.normalized() * 2.5 * strength
	_head_spring.kick(-0.8 * strength)
	_ear_spring.kick(-0.6 * strength)


func pickup_pop() -> void:
	_pickup = PICKUP_TIME
	_ear_spring.kick(3.0)


## Радость: прыжок на месте, лапа вверх, довольные глаза (повышение уровня, волна очищена).
func cheer() -> void:
	_cheer = CHEER_TIME
	_tail_spring.kick(4.0)
	_ear_spring.kick(4.0)


func play_death() -> void:
	_dead = true
	var tween := create_tween()
	tween.tween_property(self, "_death_t", 1.0, 0.9).set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_method(func(_v: float) -> void: _refresh(), 0.0, 1.0, 0.9)
	var dizzy := create_tween()
	dizzy.tween_method(_redraw_dead, 0.0, 1.0, 30.0)


func _redraw_dead(_v: float) -> void:
	if _dead:
		_front_layer.queue_redraw()


## Возрождение: плавно поднимаем енота из позы смерти.
func revive() -> void:
	var tween := create_tween()
	tween.tween_property(self, "_death_t", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(func(_v: float) -> void: _refresh(), 0.0, 1.0, 0.45)
	tween.tween_callback(func() -> void:
		_dead = false
		_refresh()
		cheer())


func _refresh() -> void:
	_update_pose()
	_apply_rig()
	queue_redraw()
	_gun_layer.queue_redraw()


## Глобальная точка дула при выстреле в direction — отсюда летит пуля и вспыхивает выстрел.
func get_muzzle_global(direction: Vector2) -> Vector2:
	var dir := direction.normalized() if direction.length_squared() > 0.0 else Vector2(_facing, 0)
	if not _rig_ok:
		return to_global(dir * 44.0)
	var paw := _paw_at(_local_angle(dir))
	if _hero_mode and bool(_hero_cfg.get("baked_gun", false)):
		return to_global(paw)
	return to_global(_gun_center(paw, dir, 0.0) + _muzzle_offset(dir))


static func has_sprite() -> bool:
	return get_sprite_texture() != null


## Цельный кадр — для послеобразов рывка, аватарки и экрана загрузки.
static func get_sprite_texture() -> Texture2D:
	if _full_texture == null and ResourceLoader.exists(TEXTURE_PATH):
		_full_texture = load(TEXTURE_PATH)
	return _full_texture


static func _get_arm_texture() -> Texture2D:
	if _arm_texture == null and ResourceLoader.exists(ARM_PATH):
		_arm_texture = load(ARM_PATH)
	return _arm_texture


## Квадрат головы в raccoon.png для круглой аватарки.
static func get_avatar_rect() -> Rect2i:
	var rect: Array = (RigDB.get_rig(RIG_ID).get("extra", {}) as Dictionary).get("avatar_rect", [0, 0, 128, 128])
	return Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))


static func get_rig_pivot() -> Vector2:
	return RigDB.get_rig(RIG_ID).get("pivot", Vector2.ZERO)


func get_ghost_texture() -> Texture2D:
	if _hero_mode and not _hero_frames.is_empty():
		return hero.texture
	return get_sprite_texture()


func get_ghost_scale() -> Vector2:
	return Vector2(_facing * SPRITE_SCALE, SPRITE_SCALE)


## Смещение центра цельной текстуры от позиции игрока — послеобраз рисуется по центру текстуры.
func get_ghost_offset() -> Vector2:
	if _hero_mode:
		var half_h := float(_hero_cfg.get("cell_h", 288)) * 0.5
		return Vector2(0, (SHADOW_OFFSET.y / SPRITE_SCALE - half_h) * SPRITE_SCALE)
	var texture := get_sprite_texture()
	if texture == null:
		return Vector2(0, -20)
	var from_pivot := texture.get_size() * 0.5 - get_rig_pivot()
	return Vector2(from_pivot.x * _facing, from_pivot.y) * SPRITE_SCALE


# --- Лицо ------------------------------------------------------------------------------------------

func _update_face(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_double_blink = randf() < 0.2
		_blink_timer = randf_range(2.2, 5.0)
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t >= (0.3 if _double_blink else 0.14):
			_blink_t = -1.0
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(2.0, 6.0) * (0.5 if _run > 0.5 else 1.0)
		if randf() < 0.5:
			_twitch_l.kick(randf_range(-7.0, 7.0))
		else:
			_twitch_r.kick(randf_range(-7.0, 7.0))


func _blink_amount() -> float:
	if _dead:
		return clampf(_death_t * 2.0, 0.0, 1.0)
	if _blink_t < 0.0:
		return 0.0
	var t := fmod(_blink_t, 0.15) if _double_blink else _blink_t
	return sin(clampf(t / 0.14, 0.0, 1.0) * PI)


# --- Поза ------------------------------------------------------------------------------------------

func _update_pose() -> void:
	_bob = absf(sin(_gait)) * 3.5 * _run + sin(_breath) * 0.8 * (1.0 - _run)
	_squash = 1.0 + sin(_gait * 2.0) * 0.025 * _run
	if _pickup > 0.0:
		_squash += sin(_pickup / PICKUP_TIME * PI) * 0.1
	_stretch = 1.0 + 0.22 * _dash_blend
	_squash -= 0.14 * _dash_blend
	_sway = 0.03 * _facing * _run
	if _hurt > 0.0:
		_sway += sin(_hurt * 60.0) * 0.08 * (_hurt / HURT_TIME)
	_hop = 0.0
	if _cheer > 0.0:
		var c := 1.0 - _cheer / CHEER_TIME
		_hop = sin(clampf(c / 0.55, 0.0, 1.0) * PI) * 22.0
		if c < 0.1:
			_squash -= 0.12 * (1.0 - c / 0.1)
	if _dead:
		var launch := clampf(_death_t / 0.45, 0.0, 1.0)
		var settle := clampf((_death_t - 0.6) / 0.4, 0.0, 1.0)
		_bob = -34.0 * sin(launch * PI) - 7.0 * sin(settle * PI)
		_squash = 1.0 - 0.22 * ease(clampf(_death_t / 0.6, 0.0, 1.0), 0.4) + 0.12 * sin(settle * PI)
		_sway = _facing * ease(clampf(_death_t / 0.6, 0.0, 1.0), 0.6) * PI * 0.5


## Трансформ «пиксели текстуры относительно точки опоры → локальные координаты узла».
## Отражение по x (взгляд влево) зашито в масштаб: рука, аксессуары и кости отражаются с телом.
func _sprite_xform() -> Transform2D:
	var scale_vec := Vector2(_facing * SPRITE_SCALE * (2.0 - _squash) * _stretch, SPRITE_SCALE * _squash)
	return Transform2D(_sway, scale_vec, 0.0, Vector2(0, -_bob - _hop) + _body_kick)


func _apply_rig() -> void:
	if not _rig_ok:
		return
	if _hero_mode:
		_apply_hero()
		return
	body.transform = _sprite_xform()
	body.reset_pose()
	var r := _run
	var g := _gait
	var t := _time
	var idle := 1.0 - r
	var d := _dash_blend
	var cheer_amt := sin(clampf(1.0 - _cheer / CHEER_TIME, 0.0, 1.0) * PI) if _cheer > 0.0 else 0.0
	var torso := 0.07 * r + 0.025 * sin(g * 2.0) * r - 0.05 * d
	var head := -torso * 0.6 + 0.035 * sin(t * 0.8) * idle - 0.05 * sin(g * 2.0 + 0.6) * r
	head += _head_spring.value + _aim_local * 0.18 - 0.06 * d - 0.08 * cheer_amt
	var ears := _ear_spring.value - 0.2 * r - 0.4 * d + 0.18 * cheer_amt
	var ear_flap := 0.07 * sin(g * 2.0 + 1.2) * r
	var tail := _tail_spring.value
	_set_bone("torso", torso)
	_set_bone("head", head)
	_set_bone("ear_l", ears + ear_flap + _twitch_l.value * 0.06)
	_set_bone("ear_r", ears * 0.8 + ear_flap * 0.9 + _twitch_r.value * 0.06)
	_set_bone("scarf", 0.06 * sin(t * 1.7) + (0.25 + 0.14 * sin(g * 3.0)) * r + 0.45 * d + _scarf_spring.value)
	_set_bone("fist", 0.05 * sin(_breath) * idle + 0.5 * sin(g) * r - 0.6 * d + 1.5 * cheer_amt)
	_set_bone("tail_base", 0.07 * sin(t * 1.1) * idle + (0.13 * sin(g * 2.0 + 0.3) - 0.05) * r + 0.35 * d + tail + 0.35 * cheer_amt)
	_set_bone("tail_mid", 0.09 * sin(t * 1.1 - 0.9) * idle + 0.17 * sin(g * 2.0 - 0.5) * r + 0.2 * d + tail * 0.7)
	_set_bone("tail_tip", 0.12 * sin(t * 1.1 - 1.8) * idle + 0.22 * sin(g * 2.0 - 1.3) * r + 0.1 * d + tail * 0.45)
	_set_bone("leg_f", 0.45 * sin(g) * r + 0.55 * d - 0.25 * cheer_amt)
	_set_bone("leg_b", -0.45 * sin(g) * r - 0.5 * d + 0.25 * cheer_amt)
	_offset_bone("leg_f", Vector2(0, -9.0 * maxf(0.0, -cos(g)) * r))
	_offset_bone("leg_b", Vector2(0, -9.0 * maxf(0.0, cos(g)) * r))
	var breath := sin(_breath) * 0.02 * idle
	_stretch_bone("torso", Vector2(-breath * 0.5, breath))
	if _dead:
		var k := _death_t
		_add_bone("head", 0.4 * k)
		_add_bone("ear_l", -0.35 * k)
		_add_bone("ear_r", -0.35 * k)
		_add_bone("tail_base", -0.5 * k)
		_add_bone("tail_mid", -0.3 * k)
		_add_bone("leg_f", 0.35 * k)
		_add_bone("leg_b", -0.4 * k)
		_add_bone("fist", 0.9 * k)
	for index in _proportions:
		body.stretches[index] += _proportions[index]
	body.apply_pose()
	var squint := maxf(_hurt / HURT_TIME, 0.2 if aiming and _run < 0.9 else 0.0)
	body.set_param("blink", _blink_amount())
	body.set_param("squint", squint if not _dead else 0.0)
	body.set_param("happy", maxf(cheer_amt, sin(clampf(_pickup / PICKUP_TIME, 0.0, 1.0) * PI) * 0.8))
	var tint := _current_tint()
	var flash_amount := 1.0 if _flash > 0.0 else 0.0
	body.set_param("tint", tint)
	body.set_param("flash", flash_amount)
	_arm_material.set_shader_parameter("tint", tint)
	_arm_material.set_shader_parameter("flash", flash_amount)
	arm.transform = _arm_xform(ARM_REST + 1.1 if _dead else _gun_angle)


func _apply_hero() -> void:
	hero.transform = _sprite_xform()
	hero.texture = _hero_frames[_hero_frame_index()]
	var tint := _current_tint()
	var lit := Color(clampf(0.95 + _env.r * 0.35, 0.95, 1.3), clampf(0.95 + _env.g * 0.35, 0.95, 1.3), clampf(0.95 + _env.b * 0.35, 0.95, 1.3))
	hero.modulate = Color(tint.r * lit.r, tint.g * lit.g, tint.b * lit.b, tint.a)
	hero.self_modulate = Color(3.0, 3.0, 3.0) if _flash > 0.0 else Color.WHITE


func _set_bone(bone_name: String, angle: float) -> void:
	var i: int = _b.get(bone_name, -1)
	if i >= 0:
		body.angles[i] = angle


func _add_bone(bone_name: String, angle: float) -> void:
	var i: int = _b.get(bone_name, -1)
	if i >= 0:
		body.angles[i] += angle


func _offset_bone(bone_name: String, offset: Vector2) -> void:
	var i: int = _b.get(bone_name, -1)
	if i >= 0:
		body.offsets[i] = offset


func _stretch_bone(bone_name: String, stretch: Vector2) -> void:
	var i: int = _b.get(bone_name, -1)
	if i >= 0:
		body.stretches[i] = stretch


func _current_tint() -> Color:
	var tint := Color.WHITE
	if _hurt > 0.0 and _flash <= 0.0:
		tint = Color.WHITE.lerp(Color(1.0, 0.5, 0.5), _hurt / HURT_TIME * 0.6)
	if _dead:
		tint = tint.lerp(Color(0.85, 0.85, 0.95), _death_t * 0.35)
	return tint


## Угол направления в пространстве спрайта (без наклона тела и отражения).
func _local_angle(direction: Vector2) -> float:
	var local := direction.rotated(-_sway)
	local.x *= _facing
	return local.angle()


## Плечо следует за корпусом (наклон, дыхание): точка покоя плеча проходит через ту же
## деформацию, что и вершины корпуса в шейдере.
func _arm_xform(local_angle: float) -> Transform2D:
	var shoulder := _shoulder
	var torso_index: int = _b.get("torso", -1)
	if torso_index >= 0:
		shoulder = body.deform_point(_shoulder, {torso_index: 1.0})
	return _sprite_xform() * Transform2D(clampf(local_angle, ARM_MIN, ARM_MAX) - ARM_REST, shoulder)


## Мировое направление ствола из локального угла руки.
func _gun_direction(local_angle: float) -> Vector2:
	return Vector2(cos(local_angle) * _facing, sin(local_angle)).rotated(_sway)


func _gun_center(paw: Vector2, dir: Vector2, kick_amount: float) -> Vector2:
	var g := WeaponIcons.grip(weapon_icon)
	var grip := Vector2(g.x, g.y * (-1.0 if dir.x < 0.0 else 1.0)).rotated(dir.angle()) * _weapon_scale()
	return paw - grip - dir * kick_amount


func _weapon_scale() -> float:
	return GUN_SCALE * (melee_scale * 1.15 if melee_active else 1.0)


func _muzzle_offset(dir: Vector2) -> Vector2:
	var m := WeaponIcons.muzzle(weapon_icon)
	return Vector2(m.x, m.y * (-1.0 if dir.x < 0.0 else 1.0)).rotated(dir.angle()) * _weapon_scale()


# --- Отрисовка -------------------------------------------------------------------------------------

func _draw() -> void:
	var lift := 1.0 - _hop * 0.012
	draw_set_transform(Vector2(SHADOW_OFFSET.x * _facing, SHADOW_OFFSET.y), 0.0, Vector2(lift, 0.36 * lift))
	draw_circle(Vector2.ZERO, SHADOW_RADIUS, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if skin_effect == "aura":
		var pulse := 0.6 + 0.4 * sin(_time * 3.0)
		draw_circle(Vector2(0, -24), 50.0, Color(0.0, 0.96, 1.0, 0.08 * pulse))
		draw_arc(Vector2(0, SHADOW_OFFSET.y), 32.0, 0.0, TAU, 32, Color(0.0, 0.96, 1.0, 0.35 * pulse), 3.0, true)
	if not _rig_ok:
		draw_circle(Vector2(0, -20), 26.0, OUTLINE)
		draw_circle(Vector2(0, -20), 23.0, Color("#8e8aa6"))


func _hero_arm_texture() -> Texture2D:
	var path := str(_hero_cfg.get("arm", ""))
	if path.is_empty():
		return null
	if not _hero_textures.has(path):
		_hero_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _hero_textures[path]


func _draw_hero_arm(tex: Texture2D, shoulder: Vector2, paw: Vector2) -> void:
	var dir := paw - shoulder
	var k := float(_hero_cfg.get("arm_scale", 0.26)) * absf(_sprite_xform().get_scale().x)
	var flip := -1.0 if dir.x < 0.0 else 1.0
	var pivot_y := float(_hero_cfg.get("arm_pivot_y", tex.get_height() * 0.5))
	_gun_layer.draw_set_transform(shoulder, dir.angle(), Vector2(k, k * flip))
	_gun_layer.draw_texture(tex, Vector2(0.0, -pivot_y))
	_gun_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_gun_layer() -> void:
	if _dead or not _rig_ok:
		return
	if _hero_mode and bool(_hero_cfg.get("baked_gun", false)):
		return
	var dir := _gun_direction(_gun_angle)
	if melee_active:
		dir = dir.rotated(melee_offset)
	else:
		dir = dir.rotated(-_climb * _facing)
	var paw := _paw_at(_gun_angle)
	if _hero_mode:
		var shoulder := _sprite_xform() * _hero_shoulder
		var arm_tex := _hero_arm_texture()
		if arm_tex != null:
			_draw_hero_arm(arm_tex, shoulder, paw)
		else:
			var sleeve := Color(str(_hero_cfg.get("arm_color", "#4a4a55")))
			_gun_layer.draw_line(shoulder, paw, OUTLINE, 11.0, true)
			_gun_layer.draw_line(shoulder, paw, sleeve, 7.0, true)
			_gun_layer.draw_circle(paw, 6.5, OUTLINE)
			_gun_layer.draw_circle(paw, 4.5, sleeve.lightened(0.15))
	var center := _gun_center(paw, dir, _kick)
	WeaponIcons.draw(_gun_layer, weapon_icon, center, _weapon_scale(), dir.angle(), weapon_color, dir.x < 0.0)
	if show_aim_line and aiming and not melee_active:
		var from := center + _muzzle_offset(dir)
		var line_dir := _gun_direction(_gun_angle)
		_gun_layer.draw_dashed_line(from + line_dir * 20.0, from + line_dir * 320.0, Color(weapon_color, 0.14), 1.5, 14.0)
	if _flash_t > 0.0 and not melee_active:
		var muzzle := center + _muzzle_offset(dir)
		var f := _flash_t / 0.07
		var side := dir.orthogonal()
		_gun_layer.draw_colored_polygon(PackedVector2Array([muzzle + side * 7.0 * f, muzzle + dir * 30.0 * f, muzzle - side * 7.0 * f, muzzle - dir * 6.0]), Color(1.0, 0.9, 0.5, 0.9 * f))
		_gun_layer.draw_colored_polygon(PackedVector2Array([muzzle + side * 3.0 * f, muzzle + dir * 17.0 * f, muzzle - side * 3.0 * f, muzzle - dir * 3.0]), Color(1, 1, 1, f))
		_gun_layer.draw_circle(muzzle, 7.0 * f, Color(weapon_color, 0.55 * f))
	if glint > 0.0 and glint < 1.0:
		var tip := center + _muzzle_offset(dir)
		var shine := center.lerp(tip, glint)
		var strength := sin(glint * PI)
		_gun_layer.draw_circle(shine, 5.0 * strength, Color(1, 1, 1, 0.9 * strength))
		_gun_layer.draw_line(shine - dir.orthogonal() * 6.0 * strength, shine + dir.orthogonal() * 6.0 * strength, Color(1, 1, 1, 0.8 * strength), 2.0)


func _draw_death_marks() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var appear := clampf((_death_t - 0.55) / 0.3, 0.0, 1.0)
	if appear <= 0.0:
		return
	for i in 4:
		var a := t * 3.0 + TAU * i / 4.0
		var p := Vector2(_facing * 18.0 + cos(a) * 34.0, -14.0 + sin(a) * 9.0)
		_draw_star(p, 6.0 * appear, Color("#ffe27a"))
	var rise := fmod(t * 0.7, 1.0)
	var soul := Vector2(-_facing * 6.0 + sin(t * 2.0) * 6.0, -30.0 - 60.0 * rise)
	_front_layer.draw_circle(soul, 9.0 * appear, Color(1, 1, 1, 0.35 * (1.0 - rise)))
	_front_layer.draw_circle(soul + Vector2(-3, -2), 1.8, Color(0.1, 0.1, 0.2, 0.6 * (1.0 - rise)))
	_front_layer.draw_circle(soul + Vector2(3, -2), 1.8, Color(0.1, 0.1, 0.2, 0.6 * (1.0 - rise)))


func _draw_effect_front() -> void:
	if _dead:
		_draw_death_marks()
		return
	match skin_effect:
		"sparkle":
			for i in 3:
				var t := fmod(_time * 0.9 + i * 0.33, 1.0)
				var p := Vector2(sin(i * 2.1 + _time) * 30.0, -70.0 + i * 16.0 - t * 24.0 - _hop)
				var s := sin(t * PI) * 5.0
				_front_layer.draw_line(p - Vector2(s, 0), p + Vector2(s, 0), Color(1.0, 0.9, 0.5, 0.9), 2.0)
				_front_layer.draw_line(p - Vector2(0, s), p + Vector2(0, s), Color(1.0, 0.9, 0.5, 0.9), 2.0)
		"stars":
			for i in 3:
				var a := _time * 2.2 + TAU * i / 3.0
				var p := Vector2(cos(a) * 40.0, -34.0 + sin(a) * 12.0 - _hop)
				_draw_star(p, 5.0, Color("#e0b3ff"))


func _draw_star(p: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(p + Vector2.from_angle(-PI * 0.5 + TAU * i / 10.0) * rr)
	_front_layer.draw_colored_polygon(pts, color)
