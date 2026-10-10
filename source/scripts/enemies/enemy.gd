class_name Enemy
extends CharacterBody2D
## Пулируемый враг. Жизненным циклом владеет EnemyManager: враг никогда не удаляет себя,
## а сообщает о смерти сигналом died, после которого менеджер возвращает его в пул.
## Физическое состояние переключается через set_deferred: смерть часто наступает внутри
## обработки попадания пули, где прямое изменение коллизий запрещено.
##
## Атаки идут через маленький автомат Act: у каждой есть телеграф (замах, прицельная линия,
## фитиль, круг удара), который рисуется в _draw() под спрайтом — игрок успевает среагировать.
##
## Визуал — RigSprite (shaders/rig2d.gdshader) в одном из режимов:
##   кадры (data/frames.json) — Scrappy Rat: клипы idle/run/windup/strike/hit/death с листа;
##   авто-риг (статичный спрайт с концепт-листа + веса костей ног, корпуса, головы, оружия):
##     вразвалку идут ноги, корпус качается, голова кивает, щит/ствол/бутылка/молот живут на
##     своей кости; удар или выстрел — отдельный кадр атаки с листа (attack_sprite).
## Составные части (EnemyParts) — базука босса, стволы меха. Боссы думают в BossBrain.
## Щит (свиньи): пули спереди почти не проходят, но щит поворачивается к Еноту с задержкой и
## опущен во время атаки — обходи сбоку, бей после замаха.

signal died(enemy: Enemy)
signal damaged(enemy: Enemy, amount: float, is_crit: bool, kind: StringName)
signal exploded(enemy: Enemy, at: Vector2, radius: float, damage: float)
signal blocked(enemy: Enemy, at: Vector2)
signal blinked(enemy: Enemy, from: Vector2, to: Vector2)
## Эффект по запросу сценария босса: "transform" | "stomp" | "muzzle".
signal fx_requested(enemy: Enemy, kind: String, at: Vector2, radius: float)
signal boss_phase(enemy: Enemy, phase: int)

enum Act { MOVE, WINDUP, LUNGE, AIM, DASH, RECOVER, FUSE, THROW, SLAM, VANISH }

const FLASH_TIME := 0.08
const STATUS_TICK := 0.5
const BOSS_DOT_SCALE := 0.55
const BOSS_DOT_CAP := 0.008
const BOSS_SLOW_CAP := 0.2
const STATUS_TINTS := {1: Color(0.55, 1.0, 0.45), 2: Color(1.0, 0.45, 0.5), 4: Color(0.55, 0.8, 1.0), 8: Color(1.0, 0.92, 0.45)}
const STUN_TIME := 1.2
const STUN_TIME_BOSS := 0.6
const STUN_BOSS_COOLDOWN := 8.0
const STUN_DAMAGE_MULT := 1.5
const STAGGER_DECAY := 8.0
## Выдержка босса (как в Sekiro): любой урон наполняет шкалу, на пороге босс замирает и получает ×1.5.
const POSTURE_FRACTION := 0.10
const POSTURE_DECAY := 0.02
const POSTURE_STUN := 2.5
const POSTURE_COOLDOWN := 12.0
signal posture_broken(enemy: Enemy)
const STAGGER_BOSS_RESIST := 0.25
const FLASH_GAP_BOSS := 0.18
const KNOCKBACK_FORCE := 260.0
const KNOCKBACK_DECAY := 9.0
const RANGED_BAND := 60.0
const NAV_DIRECT_DISTANCE := 72.0
const HOP_HEIGHT := 7.0
const LUNGE_TRIGGER := 125.0
const LUNGE_WINDUP := 0.36
const LUNGE_TIME := 0.22
const LUNGE_SPEED_MULT := 3.4
const LUNGE_COOLDOWN := 1.3
const AIM_TIME := 0.5
const DASH_WINDUP := 0.6
const DASH_TIME := 0.45
const DASH_BAND := 110.0
const RECOVER_TIME := 0.45
const FUSE_TRIGGER := 66.0
const FUSE_TIME := 0.62
const THROW_WINDUP := 0.5
const FLANK_ANGLE := 0.65
const FLANK_RELEASE := 170.0
const HIT_POP := 0.16
const ATTACK_POSE_TIME := 0.32
const ASSASSIN_WINDUP := 0.28
const VANISH_TIME := 0.5
const SLAM_LINE_STEP := 0.11
const CHARGE_BAND := Vector2(230.0, 470.0)
const CHARGE_COOLDOWN := 4.5
const BLINK_COOLDOWN := 3.0
const TELEGRAPH := Color("#ff2e4d")
const RIG_MARGIN := 8.0
const STUCK_SPEED_RATIO := 0.2
const STUCK_TRIGGER := 0.3
const DETOUR_TIME := 0.8
const BONE_HEAD := 2
const BONE_WEAPON := 3
const BONE_FIST := 4
const BONE_TORSO := 5
const BONE_LEG_L := 9
const BONE_LEG_R := 10

## Индивидуальные окрасы меха покадровых крыс: [вес, регион → градиент].
const FUR_VARIANTS := [
	[50.0, {}],
	[20.0, {"fur": ["#2a1a10", "#7a5a45", "#e0c8b0", 0.9]}],
	[15.0, {"fur": ["#08080d", "#35323f", "#9a94a8", 0.9]}],
	[15.0, {"fur": ["#3a2a14", "#a88a5c", "#f2e2c4", 0.9]}],
]

var data: EnemyData
var hp := 0.0
var max_hp := 0.0
var pool_index := -1
## Множитель урона атак от сложности волны.
var damage_mult := 1.0
## Возвышения: элита с особенностью ("fast", "armored", "explosive"; "" — обычный враг).
var elite := ""
## Появился, пока жив главный босс главы (миньон боя с боссом) — без опыта и монет.
var boss_minion := false
var elite_speed := 1.0
var elite_armor := 0.0
var _elite_ring: Sprite2D
## true — взорвался сам (Бомбо-Крыса у Енота): награды за такую смерть не даются.
var self_destructed := false
## Мародёр (событие карты): убегает от Енота, несёт добычу; при смерти из него сыплется loot монет.
var fleeing := false
var loot := 0
## Мягкое расталкивание от соседей и енота (EnemyManager считает каждый кадр).
var separation := Vector2.ZERO

var _sprite: RigSprite
var _alt: Sprite2D
var _alt_material: ShaderMaterial
var _parts: EnemyParts
var _shadow: Sprite2D
var _accessories: EnemyAccessories
var _shape: CircleShape2D
var _collision: CollisionShape2D
var _weapon: WeaponData
var _brain: BossBrain
var _knockback := Vector2.ZERO
var _flash := 0.0
var poison_stacks := 0
var poison_left := 0.0
var poison_dps := 0.0
## Яд рывка — один отдельный эффект, не усиливает стаки яда оружия.
var dash_poison_left := 0.0
var dash_poison_dps := 0.0
var bleed_left := 0.0
var bleed_dps := 0.0
var bleed_is_burn := false
var slow_left := 0.0
var slow_amount := 0.0
## Шкала «выдержки» (ближний бой): на пороге враг оглушён и получает ×1.5 урона.
var stagger := 0.0
var stun_left := 0.0
var posture := 0.0
var posture_stun := 0.0
var _posture_cd := 0.0
var _stun_cd := 0.0
var _status_tick := 0.0
var _status_key := 0
## Приёмник урона от статусов (обновляет цифры, лечение вампиризмом, полоску босса).
static var status_sink: Callable
## Тип урона следующего take_damage (fire, shock, poison, blast, ...): выставляет источник урона, враг сбрасывает.
static var next_kind: StringName = &""
## Общий множитель скорости крыс (набирается с волнами и включается на кемперов).
static var global_speed_mult := 1.0
static var mod_speed_mult := 1.0
var _pop := 0.0
## Появление: враг вырастает из-под земли с перебором масштаба и облачком пыли.
var _emerge := 0.0
const EMERGE_TIME := 0.42
var _attack_timer := 0.0
var _strafe_sign := 1.0
var _facing_left := false
var _flank := 0.0
var _step_down := false
var _size_mult := 1.0
var _act: Act = Act.MOVE
var _act_time := 0.0
var _act_total := 1.0
var _act_dir := Vector2.RIGHT
var _aim_target := Vector2.ZERO
var _visual_id := ""
var _framed := false
var _auto := false
var _run_phase := 0.0
var _idle_phase := 0.0
var _hit_variant := 0
var _gait := 0.0
var _time := 0.0
var _heal_timer := 1.0
var _move_amount := 0.0
var _recoil := 0.0
var _alt_time := 0.0
var _shield_dir := Vector2.RIGHT
var _block_cooldown := 0.0
var _target_pos := Vector2.ZERO
var _attack_count := 0
var _windup_to_dash := false
var _charge_cd := 0.0
var _line_left := 0
var _line_timer := 0.0
var _line_at := Vector2.ZERO
var _blink_cd := 0.0
var _blink_pending := false
var _alpha := 1.0
var _use_alt_weapon := false
## Секунды подряд, когда враг хочет идти, но почти не двигается (упёрся в угол пропа).
## WaveDirector переносит «залипших» надолго врагов к игроку, чтобы волна не зависала.
var stuck_time := 0.0
var _detour := Vector2.ZERO
var _detour_time := 0.0
var _detour_sign := 1.0

static var _shadow_texture: GradientTexture2D
static var _rig_shader: Shader


func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	visible = false

	_shadow = Sprite2D.new()
	_shadow.texture = _get_shadow_texture()
	add_child(_shadow)

	_sprite = RigSprite.new()
	add_child(_sprite)
	_parts = EnemyParts.new()
	_sprite.add_child(_parts)
	_accessories = EnemyAccessories.new()
	_sprite.add_child(_accessories)

	_alt = Sprite2D.new()
	_alt.visible = false
	_alt.centered = true
	if _rig_shader == null:
		_rig_shader = load(RigSprite.SHADER_PATH)
	_alt_material = ShaderMaterial.new()
	_alt_material.shader = _rig_shader
	_alt_material.set_shader_parameter("rig_enabled", false)
	_alt.material = _alt_material
	add_child(_alt)

	_shape = CircleShape2D.new()
	_collision = CollisionShape2D.new()
	_collision.shape = _shape
	_collision.disabled = true
	add_child(_collision)


func activate(enemy_data: EnemyData, at: Vector2, hp_mult: float = 1.0, dmg_mult: float = 1.0) -> void:
	data = enemy_data
	stuck_time = 0.0
	_detour_time = 0.0
	poison_stacks = 0
	poison_left = 0.0
	dash_poison_left = 0.0
	dash_poison_dps = 0.0
	bleed_left = 0.0
	slow_left = 0.0
	stagger = 0.0
	posture = 0.0
	posture_stun = 0.0
	_posture_cd = 0.0
	stun_left = 0.0
	_stun_cd = 0.0
	_status_tick = 0.0
	_status_key = 0
	max_hp = data.max_hp * hp_mult
	hp = max_hp
	damage_mult = dmg_mult
	elite = ""
	elite_speed = 1.0
	elite_armor = 0.0
	if _elite_ring != null:
		_elite_ring.visible = false
	self_destructed = false
	fleeing = false
	loot = 0
	global_position = at
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_flash = -1.0
	_pop = 0.0
	_emerge = 0.0 if data.is_boss() else EMERGE_TIME
	_recoil = 0.0
	_alt_time = 0.0
	_block_cooldown = 0.0
	_attack_count = 0
	_windup_to_dash = false
	_charge_cd = randf_range(1.5, CHARGE_COOLDOWN)
	_line_left = 0
	_blink_cd = 0.0
	_blink_pending = false
	_alpha = data.stealth_alpha
	_reset_alpha()
	_use_alt_weapon = false
	_attack_timer = randf_range(0.6, data.attack_cooldown)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_flank = (1.0 if randf() < 0.5 else -1.0) if randf() < data.flank_chance else 0.0
	_size_mult = 1.0 + randf_range(-data.size_variance, data.size_variance)
	_act = Act.MOVE
	_act_time = 0.0
	_weapon = WeaponDB.get_weapon(data.weapon_id) if data.weapon_id != &"" else null
	_brain = null
	if data.is_boss():
		_brain = BossBrain.new()

	_setup_visual()
	if _brain != null:
		_brain.setup(self)
	if _emerge > 0.0:
		request_fx("emerge", data.radius)
	_sprite.rotation = 0.0
	_sprite.position = Vector2(0, _sprite_base_y())
	_apply_sprite_scale(1.0, 1.0)
	var forced := data.behavior == EnemyData.Behavior.EXPLODER or data.behavior == EnemyData.Behavior.DASHER
	_accessories.setup(data.accessory_anchor, data.accessories, forced)
	_shadow.scale = Vector2(data.radius / 16.0, data.radius / 40.0) * _size_mult * (0.8 if data.flying else 1.0)
	_shadow.position = Vector2(0, data.radius * 0.75 * _size_mult)
	_shape.radius = data.radius * _size_mult
	_collision.position = Vector2(0, -data.hover) if data.flying else Vector2.ZERO

	collision_layer = PhysicsLayers.ENEMY
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENEMY
	if not data.flying:
		collision_mask |= PhysicsLayers.OBSTACLE | PhysicsLayers.TERRAIN
	visible = true
	_collision.set_deferred("disabled", false)
	queue_redraw()


## Пулированный враг наследует прозрачность прошлого жильца слота (Искро-Заточка): без сброса обычные враги и боссы выходили полупрозрачными.
func _reset_alpha() -> void:
	_sprite.set_param("alpha", _alpha)
	_parts.set_param("alpha", _alpha)
	_alt_material.set_shader_parameter("alpha", _alpha)
	_shadow.modulate.a = _alpha


func deactivate() -> void:
	data = null
	_weapon = null
	_brain = null
	visible = false
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	_collision.set_deferred("disabled", true)


## Смена главы: свободный экземпляр пула отпускает текстуры прошлой главы (иначе пул держит их в
## видеопамяти до конца забега). Следующий activate() соберёт картинку заново.
func drop_visual() -> void:
	_visual_id = ""
	_sprite.texture = null
	_sprite.rig = {}
	_sprite.frame_sheet = {}
	_sprite.frame_index = -1
	_sprite.shader_material.set_shader_parameter("regions0", null)
	_sprite.shader_material.set_shader_parameter("regions1", null)


func get_radius() -> float:
	return _shape.radius


func is_alive() -> bool:
	return data != null and hp > 0.0


func is_targetable() -> bool:
	return is_alive()


## Точка, в которую целится автоприцел (у летающих — корпус над тенью).
func get_aim_point() -> Vector2:
	return global_position + (Vector2(0, -data.hover) if data != null and data.flying else Vector2.ZERO)


func target_point() -> Vector2:
	return _target_pos


func get_texture() -> Texture2D:
	return _sprite.texture


func get_sprite() -> RigSprite:
	return _sprite


func is_framed() -> bool:
	return _framed


## Центр картинки для «падающего трупа» (у авто-ригов опора — ноги, а труп вращается вокруг центра).
func get_corpse_origin() -> Vector2:
	if _auto and _sprite.texture != null:
		var pivot: Vector2 = _sprite.rig.get("pivot", Vector2.ZERO)
		var center := _sprite.texture.get_size() * 0.5 - pivot
		return _sprite.global_transform * center
	return global_position + _sprite.position


func get_sprite_scale() -> Vector2:
	return _sprite.scale


func get_sprite_offset() -> Vector2:
	return _sprite.position


func get_hue_shift() -> float:
	return 0.0


func get_corpse_tint() -> Color:
	return data.sprite_modulate if data != null else Color.WHITE


# --- Внешность ---------------------------------------------------------------------------------

## Покадровые и авто-риги стоят опорой на земле (у тени), летающие — выше на hover.
func _sprite_base_y() -> float:
	return data.radius * 0.72 * _size_mult - (data.hover if data.flying else 0.0)


func _setup_visual() -> void:
	var rig_id := data.rig_id
	if not data.rig_variants.is_empty():
		rig_id = data.rig_variants[randi() % data.rig_variants.size()]
	var visual_id := ("frames:" + data.frames_id) if not data.frames_id.is_empty() else rig_id
	if _visual_id != visual_id:
		_visual_id = visual_id
		_framed = not data.frames_id.is_empty() and _sprite.setup_frames(data.frames_id, 6.0)
		_auto = false
		if not _framed:
			var margin := RIG_MARGIN
			if RigDB.has_rig(rig_id) and _sprite.setup(rig_id, margin, true):
				_auto = bool((_sprite.rig.get("extra", {}) as Dictionary).get("grounded", false))
			else:
				_sprite.setup_texture(data.texture, margin)
		_parts.setup(data.parts)
	var outline_px := data.outline_world / maxf(data.sprite_scale.x, 0.01)
	var rim := Color("#140a1e")
	rim.a = 0.9
	for target in [_sprite.shader_material, _alt_material]:
		target.set_shader_parameter("outline_color", rim)
		target.set_shader_parameter("outline_px", outline_px)
		target.set_shader_parameter("flash", 0.0)
		target.set_shader_parameter("tint", data.sprite_modulate)
	_alt_material.set_shader_parameter("outline_px", data.outline_world / maxf(_alt_scale(), 0.01))
	_parts.set_param("outline_color", rim)
	_parts.set_param("outline_px", outline_px * 0.8)
	_sprite.set_param("hue_shift", 0.0)
	_sprite.set_param("blink", 0.0)
	_sprite.set_param("squint", 0.0)
	_sprite.set_param("wheel_angle", 0.0)
	var recolor := data.recolor.duplicate()
	if _framed:
		if not data.accent_variants.is_empty():
			var accent: Dictionary = _pick_weighted(data.accent_variants)
			for region in accent:
				recolor[region] = accent[region]
		if data.variants:
			var fur: Dictionary = _pick_weighted(FUR_VARIANTS)
			for region in fur:
				if not recolor.has(region):
					recolor[region] = fur[region]
		recolor = _with_frame_ranges(recolor)
	# Перекраска работает только по картам регионов листа; у листов боссов их нет —
	# без этой проверки весь спрайт уезжал в градиент «меха» и выглядел сепией.
	var has_regions := _framed and not (_sprite.frame_sheet.get("regions", PackedStringArray()) as PackedStringArray).is_empty()
	if not has_regions:
		recolor.clear()
	var params := RaccoonVisual.build_recolor(recolor)
	_sprite.set_param("recolor_enabled", has_regions and not recolor.is_empty())
	for key in params:
		_sprite.set_param(key, params[key])
	_alt.texture = data.attack_texture
	_alt.visible = false
	_sprite.visible = true
	_gait = randf() * TAU
	_time = randf() * 10.0
	_move_amount = 0.0
	_run_phase = randf() * 4.0
	_idle_phase = randf() * 4.0
	_hit_variant = 0
	_shield_dir = Vector2.RIGHT


## Градиент региона на кадрах строится по диапазону яркости именно этого листа.
func _with_frame_ranges(recolor: Dictionary) -> Dictionary:
	var ranges: Dictionary = _sprite.frame_sheet.get("region_ranges", {})
	var out := {}
	for region in recolor:
		var entry: Array = (recolor[region] as Array).duplicate()
		if entry.size() == 4 and ranges.has(region):
			var r: Vector2 = ranges[region]
			entry.append(r.x)
			entry.append(r.y)
		out[region] = entry
	return out


static func _pick_weighted(table: Array) -> Dictionary:
	var total := 0.0
	for entry in table:
		total += float(entry[0])
	var roll := randf() * total
	for entry in table:
		roll -= float(entry[0])
		if roll <= 0.0:
			return entry[1]
	return table[0][1]


func _alt_scale() -> float:
	if data.attack_texture == null:
		return 1.0
	var width := data.attack_width if data.attack_width > 0.0 else data.attack_texture.get_width() * data.sprite_scale.x
	return width / data.attack_texture.get_width()


# --- Бой ----------------------------------------------------------------------------------------

## Разовый толчок (разлёт осколков при делении).
func push(impulse: Vector2) -> void:
	_knockback += impulse


func tick(delta: float, player: Player, nav: Callable = Callable()) -> void:
	_target_pos = player.global_position
	if data.heal_radius > 0.0:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = data.heal_interval
			request_fx("repair", data.heal_radius)
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player / dist if dist > 0.001 else Vector2.ZERO
	var path_dir := dir
	if nav.is_valid() and dist > NAV_DIRECT_DISTANCE and not data.flying:
		var step: Vector2 = nav.call(global_position)
		if step != Vector2.ZERO:
			path_dir = step
		elif dist > 160.0 and (data.behavior == EnemyData.Behavior.CHASER or data.behavior == EnemyData.Behavior.DASHER) and data.move_speed > 1.0:
			var lead := clampf(dist / data.move_speed, 0.0, 0.7)
			path_dir = ((player.global_position + player.velocity * lead - global_position).normalized() * 0.7 + dir * 0.3).normalized()
	if _flank != 0.0 and dist > FLANK_RELEASE:
		path_dir = path_dir.rotated(_flank * FLANK_ANGLE).normalized()
	if _detour_time > 0.0:
		_detour_time -= delta
		path_dir = (path_dir * 0.35 + _detour).normalized()

	_act_time -= delta
	_attack_timer -= delta
	_block_cooldown -= delta
	_charge_cd -= delta
	_blink_cd -= delta
	if _status_key != 0 or poison_left > 0.0 or dash_poison_left > 0.0 or bleed_left > 0.0 or slow_left > 0.0 or stagger > 0.0 or stun_left > 0.0 or posture_stun > 0.0 or posture > 0.0 or _posture_cd > 0.0 or _stun_cd > 0.0:
		_tick_status(delta)
		if data == null:
			return
	if _line_left > 0:
		_tick_slam_line(delta)
		if data == null:
			return
	if _blink_pending:
		_blink_pending = false
		_try_blink(dir)
	var desired: Vector2
	if _brain != null:
		desired = _brain.tick(player, dir, path_dir, dist, delta)
	elif fleeing:
		desired = (-dir + dir.orthogonal() * _strafe_sign * 0.6).normalized() * data.move_speed * 1.15
	elif stun_left > 0.0:
		desired = Vector2.ZERO
	else:
		desired = _run_act(player, dir, path_dir, dist)
	# Взрыв своего же удара может подорвать бочку рядом и убить врага посреди тика:
	# тогда он уже возвращён в пул (data = null) и дальше тик не идёт.
	if data == null:
		return
	if slow_left > 0.0:
		desired *= 1.0 - slow_amount
	if stun_left > 0.0 and not data.is_boss():
		desired = Vector2.ZERO
	if not data.is_boss():
		desired *= global_speed_mult * mod_speed_mult * elite_speed
	if data.shield and dir != Vector2.ZERO and _shield_up():
		var turned := rotate_toward(_shield_dir.angle(), dir.angle(), data.shield_turn * delta)
		_shield_dir = Vector2.from_angle(turned)
	_knockback = _knockback.lerp(Vector2.ZERO, clampf(KNOCKBACK_DECAY * delta, 0.0, 1.0))
	velocity = desired + _knockback + separation
	var before := global_position
	move_and_slide()
	_track_stuck(desired, global_position - before, delta)

	if not is_alive():
		return
	if not fleeing and stun_left <= 0.0 and not player.is_dead and data.contact_damage > 0.0 and dist < _shape.radius + Player.RADIUS and not data.flying:
		var bonus := 1.5 if _act == Act.LUNGE or _act == Act.DASH else 1.0
		Player.last_source = data.id
		player.take_damage(data.contact_damage * bonus * damage_mult, dir)
	_animate(delta, desired)


## Упёрся в угол коллизии (сетка поля потоков грубее реальных форм пропов): через
## STUCK_TRIGGER секунд почти без движения враг обходит препятствие вдоль стены,
## чередуя сторону обхода.
func _track_stuck(desired: Vector2, moved: Vector2, delta: float) -> void:
	var want := desired.length()
	if want < 30.0 or data.flying or delta <= 0.0:
		stuck_time = 0.0
		return
	if moved.length() / delta < want * STUCK_SPEED_RATIO:
		stuck_time += delta
		if stuck_time > STUCK_TRIGGER and _detour_time <= 0.0:
			var along := desired.normalized().orthogonal() * _detour_sign
			var wall := get_last_slide_collision()
			if wall != null:
				along = wall.get_normal().orthogonal() * _detour_sign
				if along.dot(desired) < -0.2 * want:
					along = -along
			_detour = along
			_detour_time = DETOUR_TIME
			_detour_sign = -_detour_sign
	else:
		stuck_time = maxf(stuck_time - delta * 2.0, 0.0)


## Попадание пули: щит спереди гасит почти весь урон (пробивающие пули его игнорируют).
func take_bullet(amount: float, direction: Vector2, knockback: float, is_crit: bool, piercing: bool) -> void:
	if not is_alive():
		return
	if data.shield and not piercing and _shield_up() and direction != Vector2.ZERO:
		var incoming := -direction
		if absf(incoming.angle_to(_shield_dir)) < data.shield_arc:
			amount *= 1.0 - data.shield_block
			knockback *= 0.25
			if _block_cooldown <= 0.0:
				_block_cooldown = 0.12
				blocked.emit(self, global_position + _shield_dir * data.radius * 1.1 + Vector2(0, -data.radius * 0.6))
	take_damage(amount, direction * knockback, is_crit)


## Элита (Возвышения): крепче втрое, крупнее, цветное кольцо под ногами и особенность.
func make_elite(kind: String) -> void:
	elite = kind
	max_hp *= 2.6
	hp = max_hp
	_size_mult *= 1.22
	_shape.radius = data.radius * _size_mult
	# Светящееся кольцо цвета особенности под ногами — элиту видно в толпе.
	if _elite_ring == null:
		_elite_ring = Sprite2D.new()
		_elite_ring.show_behind_parent = true
		add_child(_elite_ring)
		move_child(_elite_ring, 0)
	_elite_ring.visible = true
	_elite_ring.texture = ArenaProp.texture_of("res://assets/ui/ascension/elite_%s.png" % kind)
	_elite_ring.position = Vector2(0, data.radius * 0.75 * _size_mult)
	_elite_ring.scale = Vector2(data.radius * 3.2 / 128.0, data.radius * 1.6 / 64.0) * _size_mult
	_elite_ring.modulate = Color.WHITE
	match kind:
		"fast":
			elite_speed = 1.45
		"armored":
			elite_armor = 0.4


func take_damage(amount: float, direction: Vector2 = Vector2.ZERO, is_crit: bool = false) -> void:
	var kind := next_kind
	next_kind = &""
	if not is_alive():
		return
	if _brain != null and _brain.is_invulnerable():
		return
	if data.id == &"throne_speaker" and not BossBrain.speakers_open():
		return
	amount *= (1.0 - data.armor) * (1.0 - elite_armor)
	if stun_left > 0.0 or posture_stun > 0.0:
		amount *= STUN_DAMAGE_MULT
	if _brain != null:
		amount *= _brain.damage_taken_mult()
	hp -= amount
	if hp > 0.0 and data.is_boss():
		_add_posture(amount)
	if data.blink_distance > 0.0 and _blink_cd <= 0.0 and hp > 0.0 and hp < max_hp * 0.8:
		_blink_pending = true
		_blink_cd = BLINK_COOLDOWN
	# Под непрерывным огнём вспышка не перезапускается каждую пулю: у босса пауза между
	# вспышками, иначе он весь бой выглядит белым силуэтом.
	if _flash <= (-FLASH_GAP_BOSS if data.is_boss() else 0.0):
		_flash = FLASH_TIME
	_pop = HIT_POP
	if _framed:
		_hit_variant = randi() % maxi(FrameDB.clip_length(_sprite.frame_sheet, "hit"), 1)
	_knockback += direction * KNOCKBACK_FORCE * (1.0 - data.knockback_resist)
	damaged.emit(self, amount, is_crit, kind)
	if hp <= 0.0:
		if data.behavior == EnemyData.Behavior.EXPLODER:
			exploded.emit(self, global_position, data.explode_radius, data.explode_damage * damage_mult)
		died.emit(self)


func _add_posture(amount: float) -> void:
	if posture_stun > 0.0 or _posture_cd > 0.0:
		return
	posture += amount
	if posture >= max_hp * POSTURE_FRACTION:
		posture = 0.0
		posture_stun = POSTURE_STUN
		_posture_cd = POSTURE_COOLDOWN
		_status_key = -1
		posture_broken.emit(self)


func posture_fraction() -> float:
	if posture_stun > 0.0:
		return 1.0
	return clampf(posture / maxf(max_hp * POSTURE_FRACTION, 1.0), 0.0, 1.0)


## Удар ближнего боя отнимает выдержку. force_stun — финишер комбо, тяжёлый удар и парирование оглушают сразу.
func add_stagger(amount: float, force_stun: bool = false) -> void:
	if not is_alive() or data == null or stun_left > 0.0:
		return
	var boss := data.is_boss()
	if boss:
		amount *= STAGGER_BOSS_RESIST
		if _stun_cd > 0.0:
			return
	var threshold := 300.0 if boss else clampf(max_hp * 0.25, 20.0, 60.0)
	stagger += amount
	if force_stun or stagger >= threshold:
		stagger = 0.0
		stun_left = STUN_TIME_BOSS if boss else STUN_TIME
		if boss:
			_stun_cd = STUN_BOSS_COOLDOWN
		_status_key = -1


## Тяга к точке (гравитон): добавляется к отбросу, поэтому плавно затухает сама.
func pull_toward(point: Vector2, force: float) -> void:
	if not is_alive() or data == null:
		return
	var offset := point - global_position
	if offset.length_squared() < 4.0:
		return
	_knockback += offset.normalized() * minf(force, offset.length() * 6.0) * (1.0 - data.knockback_resist)


func is_poisoned() -> bool:
	return poison_stacks > 0 and poison_left > 0.0


func is_slowed() -> bool:
	return slow_left > 0.0


func add_poison(dps_per_stack: float, duration: float, max_stacks: int) -> void:
	poison_stacks = mini(poison_stacks + 1, max_stacks)
	poison_dps = maxf(poison_dps, dps_per_stack)
	poison_left = maxf(poison_left, duration)


func add_bleed(dps: float, duration: float, burn: bool = false) -> void:
	bleed_is_burn = burn
	bleed_dps = maxf(bleed_dps, dps)
	bleed_left = maxf(bleed_left, duration)


func add_slow(amount: float, duration: float) -> void:
	slow_amount = maxf(slow_amount, minf(amount, BOSS_SLOW_CAP if data.is_boss() else 0.7))
	slow_left = maxf(slow_left, duration)


func add_dash_poison(dps: float) -> void:
	dash_poison_dps = maxf(dash_poison_dps, clampf(dps, 0.0, 7.0))
	dash_poison_left = 3.0


func _tick_status(delta: float) -> void:
	dash_poison_left = maxf(dash_poison_left - delta, 0.0)
	if dash_poison_left <= 0.0:
		dash_poison_dps = 0.0
	if poison_left > 0.0:
		poison_left -= delta
		if poison_left <= 0.0:
			poison_stacks = 0
			poison_dps = 0.0
	if bleed_left > 0.0:
		bleed_left -= delta
		if bleed_left <= 0.0:
			bleed_dps = 0.0
	if slow_left > 0.0:
		slow_left -= delta
		if slow_left <= 0.0:
			slow_amount = 0.0
	if stun_left > 0.0:
		stun_left = maxf(stun_left - delta, 0.0)
	elif stagger > 0.0:
		stagger = maxf(stagger - STAGGER_DECAY * delta, 0.0)
	_stun_cd = maxf(_stun_cd - delta, 0.0)
	if data != null and data.is_boss():
		posture_stun = maxf(posture_stun - delta, 0.0)
		_posture_cd = maxf(_posture_cd - delta, 0.0)
		if posture_stun <= 0.0 and posture > 0.0:
			posture = maxf(posture - max_hp * POSTURE_DECAY * delta, 0.0)
	_status_tick -= delta
	if _status_tick <= 0.0:
		_status_tick = STATUS_TICK
		if poison_stacks > 0:
			_take_dot(poison_stacks * poison_dps * STATUS_TICK, "poison")
		if is_alive() and dash_poison_left > 0.0:
			_take_dot(dash_poison_dps * STATUS_TICK, "poison")
		if is_alive() and bleed_left > 0.0:
			_take_dot(bleed_dps * STATUS_TICK, "burn" if bleed_is_burn else "bleed")
		if data == null:
			return
	var key := (1 if poison_stacks > 0 or dash_poison_left > 0.0 else 0) | (2 if bleed_left > 0.0 else 0) | (4 if slow_left > 0.0 else 0) | (8 if stun_left > 0.0 or posture_stun > 0.0 else 0)
	if key != _status_key:
		_status_key = key
		var tint := data.sprite_modulate
		for bit in STATUS_TINTS:
			if key & bit:
				tint = tint.lerp(STATUS_TINTS[bit], 0.38)
		_sprite.set_param("tint", tint)
		_parts.set_param("tint", tint)


func _take_dot(amount: float, kind: String) -> void:
	if not is_alive() or (_brain != null and _brain.is_invulnerable()):
		return
	amount *= 1.0 - data.armor * 0.5
	if data.is_boss():
		amount = minf(amount * BOSS_DOT_SCALE, max_hp * BOSS_DOT_CAP)
	hp -= amount
	if status_sink.is_valid():
		status_sink.call(self, amount, kind)
	if hp <= 0.0:
		died.emit(self)


func _shield_up() -> bool:
	return _act == Act.MOVE or _act == Act.AIM


# --- Поведение ---------------------------------------------------------------------------------

func _run_act(player: Player, dir: Vector2, path_dir: Vector2, dist: float) -> Vector2:
	match _act:
		Act.WINDUP:
			queue_redraw()
			if _windup_to_dash:
				if _act_time <= 0.0:
					_enter(Act.DASH, DASH_TIME)
					SoundManager.play(&"wing_flap", -2.0)
				return Vector2.ZERO
			if dir != Vector2.ZERO:
				_act_dir = dir
			if _act_time <= 0.0:
				_enter(Act.LUNGE, LUNGE_TIME)
				_show_attack_pose()
			return Vector2.ZERO
		Act.LUNGE:
			if _act_time <= 0.0:
				if data.behavior == EnemyData.Behavior.ASSASSIN:
					_enter(Act.VANISH, VANISH_TIME)
					_attack_timer = data.attack_cooldown
				else:
					_enter(Act.RECOVER, RECOVER_TIME)
					_attack_timer = LUNGE_COOLDOWN
			return _act_dir * data.move_speed * LUNGE_SPEED_MULT
		Act.VANISH:
			if _act_time <= 0.0:
				_enter(Act.MOVE, 0.0)
			return (-dir).rotated(_strafe_sign * 0.7) * data.move_speed * 1.5
		Act.DASH:
			if _act_time <= 0.0 or (get_slide_collision_count() > 0 and _act_time < DASH_TIME - 0.08):
				_enter(Act.RECOVER, RECOVER_TIME + 0.2)
				_windup_to_dash = false
				if data.behavior == EnemyData.Behavior.DASHER:
					_attack_timer = data.attack_cooldown
			return _act_dir * (data.dash_speed if data.dash_speed > 0.0 else data.charge_speed)
		Act.AIM:
			_aim_target = player.global_position
			queue_redraw()
			if _act_time <= 0.0:
				_fire(dir)
				_enter(Act.MOVE, 0.0)
			return dir.orthogonal() * _strafe_sign * data.move_speed * 0.25
		Act.THROW:
			_aim_target = player.global_position + player.velocity * 0.5
			queue_redraw()
			if _act_time <= 0.0:
				if data.behavior == EnemyData.Behavior.TRAPPER:
					_deploy_trap(player)
				else:
					_throw_bomb(_aim_target)
				_enter(Act.RECOVER, RECOVER_TIME * 0.6)
			return Vector2.ZERO
		Act.SLAM:
			queue_redraw()
			if _act_time <= 0.0:
				_slam()
				if data == null:
					return Vector2.ZERO
				_enter(Act.RECOVER, RECOVER_TIME + 0.25)
				_attack_timer = data.attack_cooldown
			return Vector2.ZERO
		Act.RECOVER:
			if _act_time <= 0.0:
				_enter(Act.MOVE, 0.0)
			return path_dir * data.move_speed * 0.35
		Act.FUSE:
			queue_redraw()
			if _act_time <= 0.0 and is_alive():
				self_destructed = true
				hp = 0.0
				exploded.emit(self, global_position, data.explode_radius, data.explode_damage * damage_mult)
				died.emit(self)
			return Vector2.ZERO
	return _move(player, dir, path_dir, dist)


func _move(player: Player, dir: Vector2, path_dir: Vector2, dist: float) -> Vector2:
	match data.behavior:
		EnemyData.Behavior.RANGED:
			_try_aim(dist)
			return _keep_distance(dir, path_dir, dist, 0.5)
		EnemyData.Behavior.BOMBER:
			if _attack_timer <= 0.0 and dist < data.preferred_distance + 180.0 and not player.is_dead:
				_attack_timer = data.attack_cooldown
				_enter(Act.THROW, THROW_WINDUP)
				return Vector2.ZERO
			return _keep_distance(dir, path_dir, dist, 0.7)
		EnemyData.Behavior.SLAMMER:
			if _attack_timer <= 0.0 and dist < data.slam_radius * 0.95 + 20.0 and not player.is_dead:
				_act_dir = dir
				_enter(Act.SLAM, data.slam_windup)
				_alt_time = data.slam_windup + 0.3
				SoundManager.play(&"beam_charge", -8.0)
				return Vector2.ZERO
			if data.charge_speed > 0.0 and _charge_cd <= 0.0 and dist > CHARGE_BAND.x and dist < CHARGE_BAND.y and not player.is_dead:
				_charge_cd = CHARGE_COOLDOWN
				_act_dir = dir
				_windup_to_dash = true
				_enter(Act.WINDUP, DASH_WINDUP)
				return Vector2.ZERO
			return path_dir * data.move_speed
		EnemyData.Behavior.ASSASSIN:
			if _attack_timer <= 0.0 and dist < LUNGE_TRIGGER + 50.0 and not player.is_dead:
				_act_dir = dir
				_enter(Act.WINDUP, ASSASSIN_WINDUP)
				SoundManager.play(&"beam_charge", -10.0)
				return Vector2.ZERO
			return (path_dir + path_dir.orthogonal() * sin(_time * 5.0 + pool_index) * 0.55).normalized() * data.move_speed
		EnemyData.Behavior.TRAPPER:
			if _attack_timer <= 0.0 and dist < data.preferred_distance + 200.0 and not player.is_dead:
				_attack_count += 1
				if _attack_count % data.trap_every == 0:
					_attack_timer = data.attack_cooldown
					_show_attack_pose()
					_enter(Act.THROW, THROW_WINDUP)
					return Vector2.ZERO
				_try_aim(dist)
			return _keep_distance(dir, path_dir, dist, 0.55)
		EnemyData.Behavior.TRICKSTER:
			if _attack_timer <= 0.0 and _weapon != null and dist < _weapon.max_distance:
				_attack_count += 1
				_use_alt_weapon = data.alt_weapon_id != &"" and _attack_count % 2 == 0
				_enter(Act.AIM, AIM_TIME)
			return _keep_distance(dir, path_dir, dist, 0.85)
		EnemyData.Behavior.EXPLODER:
			if dist < FUSE_TRIGGER and not player.is_dead:
				_enter(Act.FUSE, FUSE_TIME)
				_accessories.fuse_lit = true
				SoundManager.play(&"beam_charge", -6.0)
				return Vector2.ZERO
			return path_dir * data.move_speed
		EnemyData.Behavior.DASHER:
			if _attack_timer <= 0.0 and absf(dist - data.preferred_distance) < DASH_BAND and not player.is_dead:
				_act_dir = dir
				_windup_to_dash = true
				_enter(Act.WINDUP, DASH_WINDUP)
				return Vector2.ZERO
			if dist > data.preferred_distance + DASH_BAND * 0.5:
				return path_dir * data.move_speed
			if dist < data.preferred_distance - DASH_BAND * 0.5:
				return -dir * data.move_speed * 0.8
			return dir.orthogonal() * _strafe_sign * data.move_speed * 0.6
		_:
			if data.lunge and _attack_timer <= 0.0 and dist < LUNGE_TRIGGER and not player.is_dead:
				_act_dir = dir
				_enter(Act.WINDUP, LUNGE_WINDUP)
				return Vector2.ZERO
			return path_dir * data.move_speed


func _keep_distance(dir: Vector2, path_dir: Vector2, dist: float, strafe: float) -> Vector2:
	if dist > data.preferred_distance + RANGED_BAND:
		return path_dir * data.move_speed
	if dist < data.preferred_distance - RANGED_BAND:
		return -dir * data.move_speed
	return dir.orthogonal() * _strafe_sign * data.move_speed * strafe


func _try_aim(dist: float) -> void:
	if _weapon == null or _attack_timer > 0.0 or dist > _weapon.max_distance:
		return
	_enter(Act.AIM, AIM_TIME)


func _fire(dir: Vector2) -> void:
	_attack_timer = data.attack_cooldown
	_recoil = 1.0
	if _weapon == null:
		return
	var origin := global_position + dir * data.radius * 0.9 + Vector2(0, -data.radius * 0.8)
	_knockback -= dir * 60.0 * (1.0 - data.knockback_resist)
	var weapon := _weapon
	if _use_alt_weapon:
		var alt := WeaponDB.get_weapon(data.alt_weapon_id)
		if alt != null:
			weapon = alt
	BulletPool.fire(weapon, origin, origin.direction_to(_aim_target), Bullet.Team.ENEMY, damage_mult)
	_show_attack_pose()


func _throw_bomb(target: Vector2) -> void:
	_recoil = 1.0
	if LobPool.active == null or data.bomb.is_empty():
		return
	var b := data.bomb
	var from := global_position + Vector2(0, -data.hover - data.radius)
	var blast := ArenaProp.texture_of(str(b.get("blast", "")))
	LobPool.active.throw(from, target, float(b.get("flight", 1.0)), float(b.get("height", 150.0)),
		float(b.get("radius", 80.0)), float(b.get("damage", 18.0)) * damage_mult, Color(str(b.get("color", "#ffd257"))),
		ArenaProp.texture_of(str(b.get("texture", ""))), blast, float(b.get("size", 40.0)), float(b.get("spin", 8.0)))
	SoundManager.play(&"wing_flap", -6.0)


## Удар по площади перед собой: взрыв-волна вражеской команды, пыль и тряска.
func _slam() -> void:
	var at := global_position + _act_dir * data.slam_radius * 0.45
	BulletPool.explode(at, data.slam_radius, data.slam_damage * damage_mult, Bullet.Team.ENEMY, Color("#ffcf5a"), 1.3)
	if data == null:
		return
	_show_attack_pose()
	_recoil = 1.0
	if data.slam_line > 0:
		_line_left = data.slam_line
		_line_at = at
		_line_timer = SLAM_LINE_STEP


## Трещина от удара Сейфолома: взрывы-волны по линии к Еноту через SLAM_LINE_STEP.
func _tick_slam_line(delta: float) -> void:
	_line_timer -= delta
	if _line_timer > 0.0:
		return
	_line_timer = SLAM_LINE_STEP
	_line_at += _act_dir * 88.0
	_line_left -= 1
	BulletPool.explode(_line_at, 64.0, data.slam_damage * 0.6 * damage_mult, Bullet.Team.ENEMY, Color("#ffcf5a"), 0.8)


func _deploy_trap(player: Player) -> void:
	if MagnetTraps.active == null:
		return
	var target := player.global_position + player.velocity * 0.6 + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0)
	MagnetTraps.active.deploy(global_position + Vector2(0, -data.radius), target, damage_mult)


## Трюк Крупье: исчезает в вихре карт и появляется сбоку от прежнего места.
func _try_blink(dir: Vector2) -> void:
	var side := dir.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	for attempt in 2:
		var offset := side * data.blink_distance - dir * 40.0
		if not test_move(global_transform, offset):
			var from := global_position
			global_position += offset
			reset_physics_interpolation()
			_knockback = Vector2.ZERO
			blinked.emit(self, from, global_position)
			return
		side = -side


func _show_attack_pose() -> void:
	if data.attack_texture != null:
		_alt_time = ATTACK_POSE_TIME


func _enter(act: Act, duration: float) -> void:
	_act = act
	_act_time = duration
	_act_total = maxf(duration, 0.001)
	queue_redraw()


# --- Анимация -----------------------------------------------------------------------------------

func _boss_footstep(step_wave: float) -> void:
	var down := step_wave < 0.12 and _move_amount > 0.35
	if down and not _step_down:
		request_fx("step", data.radius)
	_step_down = down


func _animate(delta: float, desired: Vector2) -> void:
	var speed := desired.length()
	var moving := speed > 5.0
	_time += delta
	_move_amount = move_toward(_move_amount, clampf(speed / maxf(data.move_speed, 1.0), 0.0, 1.0) if moving else 0.0, delta * 5.0)
	_gait += delta * (4.0 + 9.0 * _move_amount) * clampf(speed / 110.0, 0.6, 2.0)
	var step_wave := absf(sin(_gait))
	var hop := step_wave * HOP_HEIGHT * _move_amount * (0.5 if data.is_boss() else 1.0)
	var squash := 1.0 + (0.5 - step_wave) * 0.11 * _move_amount + sin(_time * 2.2) * 0.02 * (1.0 - _move_amount)
	var lean := 0.0
	var windup := 0.0
	var strike := 0.0
	match _act:
		Act.WINDUP, Act.THROW, Act.SLAM:
			windup = clampf(1.0 - _act_time / _act_total, 0.0, 1.0)
			squash = 1.0 - 0.12 * windup
			lean = -0.14 * windup
		Act.LUNGE, Act.DASH:
			strike = 1.0
			squash = 1.08
			lean = 0.26
		Act.RECOVER:
			strike = clampf(_act_time / RECOVER_TIME, 0.0, 1.0) * 0.5
		Act.FUSE:
			squash = 1.0 + 0.1 * sin(_act_time * 50.0)
	if _brain != null:
		windup = maxf(windup, _brain.windup)
		strike = maxf(strike, _brain.strike)
		squash = 1.0 - 0.13 * _brain.windup + 0.09 * _brain.strike + sin(_time * 1.8) * 0.025 + (0.5 - step_wave) * 0.06 * _move_amount
		lean -= 0.12 * _brain.windup
		lean += 0.2 * _brain.strike
		_boss_footstep(step_wave)
	_pop = maxf(_pop - delta, 0.0)
	var hurt := _pop / HIT_POP
	var pop := 1.0 + hurt * 0.2
	var rise := 0.0
	if _emerge > 0.0:
		_emerge = maxf(_emerge - delta, 0.0)
		# easeOutBack: вырастает с перебором и садится в обычный размер, поднимаясь из-под земли.
		var t := 1.0 - _emerge / EMERGE_TIME
		var back := 1.0 + 2.70158 * pow(t - 1.0, 3.0) + 1.70158 * pow(t - 1.0, 2.0)
		pop *= lerpf(0.25, 1.0, back)
		rise = 22.0 * pow(1.0 - t, 2.0)
	_recoil = move_toward(_recoil, 0.0, delta * 4.0)

	if data.shield:
		_facing_left = _shield_dir.x < 0.0
	elif _brain != null or data.behavior in [EnemyData.Behavior.RANGED, EnemyData.Behavior.BOMBER, EnemyData.Behavior.TRAPPER, EnemyData.Behavior.TRICKSTER]:
		_facing_left = _target_pos.x < global_position.x
	elif absf(desired.x) > 5.0 and _act != Act.WINDUP:
		_facing_left = desired.x < 0.0
	var hover_bob := sin(_time * 3.4) * 5.0 if data.flying else 0.0
	var tremble := Vector2.ZERO
	if _brain != null and windup > 0.2:
		tremble = Vector2(sin(_time * 70.0), cos(_time * 83.0)) * 3.0 * windup
	_sprite.position = Vector2(0, _sprite_base_y() + hover_bob - (0.0 if data.flying else hop) + rise) + tremble
	var sway := sin(_gait) * (0.025 if (_framed or _auto) else 0.06) * _move_amount
	if _act == Act.MOVE:
		lean += 0.16 * _move_amount
	if _framed:
		lean *= 0.5
		squash = 1.0 + (squash - 1.0) * 0.6
	_sprite.rotation = (sway + lean * 0.6) * (-1.0 if _facing_left else 1.0)
	_apply_sprite_scale((2.0 - squash) * pop, squash * pop)

	var visible_target := 1.0
	if data.stealth_alpha < 1.0 and (_act == Act.MOVE or _act == Act.VANISH) and hurt <= 0.0:
		visible_target = data.stealth_alpha
	_alpha = move_toward(_alpha, visible_target, delta * (6.0 if visible_target > _alpha else 2.2))
	if data.stealth_alpha < 1.0:
		_sprite.set_param("alpha", _alpha)
		_alt_material.set_shader_parameter("alpha", _alpha)
		_shadow.modulate.a = _alpha
	var flash := 0.0
	if _flash > -FLASH_GAP_BOSS:
		_flash -= delta
		if _flash > 0.0:
			flash = (0.55 + 0.45 * _flash / FLASH_TIME) * (0.5 if data.is_boss() else 1.0)
	if _act == Act.WINDUP or _act == Act.SLAM or (_act == Act.FUSE and int(_act_time * 16.0) % 2 == 0):
		flash = maxf(flash, 0.35)
	_sprite.set_param("flash", flash)
	_parts.set_param("flash", flash)
	if (Engine.get_physics_frames() + pool_index) % 6 == 0:
		var env := EnvLights.sample(global_position)
		var light := Vector3(env.r, env.g, env.b)
		_sprite.set_param("env_light", light)
		_parts.set_param("env_light", light)
		_alt_material.set_shader_parameter("env_light", light)
	if _framed:
		_pick_frame(delta, speed, hurt)
	elif _auto:
		_pose_auto(windup, strike, hurt)
	_parts.tick(delta)
	_update_alt(delta, flash)
	if _auto:
		_accessories.transform = _sprite.chain_transform([BONE_TORSO]) * Transform2D(0.0, Vector2.ONE * data.accessory_scale, 0.0, Vector2.ZERO)
	else:
		_accessories.transform = Transform2D(0.0, Vector2.ONE * data.accessory_scale, 0.0, Vector2.ZERO)


## Кадр атаки поверх тела (выстрел, удар щитом): на время позы тело прячется.
func _update_alt(delta: float, flash: float) -> void:
	if _alt_time <= 0.0 or data.attack_texture == null:
		if _alt.visible:
			_alt.visible = false
			_sprite.visible = true
		return
	_alt_time -= delta
	var s := _alt_scale() * _size_mult
	_alt.scale = Vector2(s * (-1.0 if _facing_left == data.faces_right else 1.0), s)
	_alt.position = Vector2(0, _sprite_base_y() - data.attack_texture.get_height() * s * 0.5)
	_alt_material.set_shader_parameter("flash", flash)
	_alt.visible = true
	_sprite.visible = false


## Кадр по состоянию: атака важнее попадания, бег — со скоростью, пропорциональной реальной.
func _pick_frame(delta: float, speed: float, hurt: float) -> void:
	var sheet := _sprite.frame_sheet
	var clip := ""
	var phase := 0.0
	if _brain != null:
		var pick: Array = _brain.clip(_move_amount > 0.2, hurt)
		clip = str(pick[0])
		phase = float(pick[1])
		if phase < 0.0:
			var fps := FrameDB.clip_fps(sheet, clip) if FrameDB.has_clip(sheet, clip) else 3.0
			_idle_phase += delta * fps
			phase = _idle_phase
		if FrameDB.has_clip(sheet, clip):
			_sprite.set_frame(FrameDB.clip_frame(sheet, clip, phase))
			return
		clip = ""
	match _act:
		Act.WINDUP, Act.AIM:
			clip = "windup"
		Act.LUNGE, Act.DASH:
			clip = "strike"
			phase = clampf(1.0 - _act_time / _act_total, 0.0, 0.999) * FrameDB.clip_length(sheet, "strike")
		Act.RECOVER:
			if _act_time > RECOVER_TIME - 0.14:
				clip = "strike"
				phase = 99.0
		Act.FUSE:
			clip = "taunt"
	if not clip.is_empty() and not FrameDB.has_clip(sheet, clip):
		clip = ""
	if clip.is_empty():
		if hurt > 0.0 and FrameDB.has_clip(sheet, "hit"):
			clip = "hit"
			phase = _hit_variant
		elif _move_amount > 0.2:
			clip = "run"
			_run_phase += delta * FrameDB.clip_fps(sheet, "run") * clampf(speed / maxf(data.move_speed, 1.0), 0.6, 1.8)
			phase = _run_phase
		else:
			clip = "idle"
			_idle_phase += delta * FrameDB.clip_fps(sheet, "idle")
			phase = _idle_phase
	_sprite.set_frame(FrameDB.clip_frame(sheet, clip, phase))


## Авто-риг: ноги вразвалку, корпус переваливается и наклоняется в атаку, голова кивает,
## оружие/щит/бутылка/молот на своих костях — замах назад, удар вперёд, отдача.
func _pose_auto(windup: float, strike: float, hurt: float) -> void:
	var m := _move_amount
	var g := _gait
	var t := _time
	_sprite.reset_pose()
	var step := sin(g)
	_sprite.angles[BONE_LEG_L] = 0.34 * step * m
	_sprite.angles[BONE_LEG_R] = -0.34 * step * m
	_sprite.offsets[BONE_LEG_L] = Vector2(0, -7.0 * maxf(0.0, step) * m)
	_sprite.offsets[BONE_LEG_R] = Vector2(0, -7.0 * maxf(0.0, -step) * m)
	_sprite.angles[BONE_TORSO] = 0.07 * step * m + 0.05 * m - 0.16 * windup + 0.2 * strike - 0.1 * hurt
	_sprite.offsets[BONE_TORSO] = Vector2(0, -4.0 * absf(step) * m)
	_sprite.stretches[BONE_TORSO] = Vector2(-0.02, 0.025) * sin(t * 2.1) * (1.0 - m)
	_sprite.angles[BONE_HEAD] = -0.05 * step * m + 0.04 * sin(t * 1.3) * (1.0 - m) - 0.25 * hurt + 0.08 * windup
	var weapon := 0.04 * sin(t * 2.0)
	var fist := 0.0
	match data.behavior:
		EnemyData.Behavior.RANGED, EnemyData.Behavior.TRAPPER, EnemyData.Behavior.TRICKSTER:
			weapon += -0.3 * _recoil + 0.06 * windup
		EnemyData.Behavior.BOMBER:
			weapon += -1.1 * windup + 0.9 * _recoil
		EnemyData.Behavior.SLAMMER:
			fist = -1.25 * windup + 1.1 * maxf(strike, _recoil)
			weapon += 0.25 * _recoil
		_:
			weapon += -0.5 * windup + 0.55 * strike
	if data.shield and _shield_up():
		weapon += -0.06
	if _brain != null:
		weapon = -0.3 * _brain.windup + 0.2 * _brain.strike
	_sprite.angles[BONE_WEAPON] = weapon
	_sprite.angles[BONE_FIST] = fist
	if data.behavior == EnemyData.Behavior.EXPLODER and _act == Act.FUSE:
		_sprite.angles[BONE_TORSO] += 0.08 * sin(t * 50.0)
		_sprite.angles[BONE_HEAD] += 0.12 * sin(t * 37.0)
	_sprite.apply_pose()


func _apply_sprite_scale(stretch_x: float, stretch_y: float) -> void:
	var facing := -1.0 if _facing_left == data.faces_right else 1.0
	_sprite.scale = Vector2(data.sprite_scale.x * stretch_x * facing, data.sprite_scale.y * stretch_y) * _size_mult


# --- Части (для BossBrain) ------------------------------------------------------------------------

func request_fx(kind: String, radius: float = 0.0, at: Vector2 = Vector2.INF) -> void:
	fx_requested.emit(self, kind, global_position if at == Vector2.INF else at, radius)


func attach_speakers(list: Array[Enemy]) -> void:
	if _brain != null:
		_brain.speakers = list


func phase_changed() -> void:
	boss_phase.emit(self, _brain.phase if _brain != null else 1)


func aim_parts(world_target: Vector2) -> void:
	_parts.aim(world_target)


## Дуло: составная часть или точка из enemies.json (muzzles, мир, зеркалится по взгляду).
func part_muzzle(index: int) -> Vector2:
	if index < _parts.count():
		return _parts.muzzle(index)
	if index < data.muzzles.size():
		var m: Vector2 = data.muzzles[index]
		return global_position + Vector2(-m.x if _facing_left else m.x, m.y) * _size_mult
	return global_position + Vector2(0, -data.radius)


func part_kick(index: int) -> void:
	_parts.kick(index)


# --- Телеграфы ----------------------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return
	if _brain != null:
		_brain.draw(self)
		return
	match _act:
		Act.WINDUP:
			if _windup_to_dash:
				_draw_dash_lane()
			_draw_alert()
		Act.AIM:
			_draw_aim()
		Act.THROW:
			_draw_alert()
		Act.SLAM:
			var t := clampf(1.0 - _act_time / _act_total, 0.0, 1.0)
			var at := _act_dir * data.slam_radius * 0.45
			draw_set_transform(at, 0.0, Vector2(1.0, 0.6))
			draw_circle(Vector2.ZERO, data.slam_radius * t, Color(TELEGRAPH, 0.16))
			draw_arc(Vector2.ZERO, data.slam_radius, 0.0, TAU, 48, Color(TELEGRAPH, 0.7), 4.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for k in data.slam_line:
				var p := at + _act_dir * 88.0 * (k + 1)
				draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
				draw_arc(Vector2.ZERO, 64.0, 0.0, TAU, 32, Color(TELEGRAPH, 0.25 + 0.35 * t), 3.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_alert()
		Act.FUSE:
			var t := clampf(1.0 - _act_time / FUSE_TIME, 0.0, 1.0)
			draw_circle(Vector2.ZERO, data.explode_radius * t, Color(TELEGRAPH, 0.16))
			draw_arc(Vector2.ZERO, data.explode_radius, 0.0, TAU, 48, Color(TELEGRAPH, 0.75), 3.0, true)


func _draw_dash_lane() -> void:
	var t := clampf(1.0 - _act_time / DASH_WINDUP, 0.0, 1.0)
	var length := (data.dash_speed if data.dash_speed > 0.0 else data.charge_speed) * DASH_TIME * 0.9
	var side := _act_dir.orthogonal() * _shape.radius
	var end := _act_dir * length
	draw_colored_polygon(PackedVector2Array([side, end + side, end - side, -side]), Color(TELEGRAPH, 0.12 + 0.18 * t))
	draw_line(Vector2.ZERO, end * t, Color(TELEGRAPH, 0.8), 4.0)
	draw_colored_polygon(PackedVector2Array([end + _act_dir * 26.0, end + side * 0.9, end - side * 0.9]), Color(TELEGRAPH, 0.55 + 0.4 * t))


func _draw_aim() -> void:
	var t := clampf(1.0 - _act_time / AIM_TIME, 0.0, 1.0)
	var from := Vector2(0, -data.radius * 0.8)
	var to := _aim_target - global_position
	var segments := maxi(int(from.distance_to(to) / 22.0), 1)
	for i in range(0, segments, 2):
		draw_line(from.lerp(to, float(i) / segments), from.lerp(to, float(i + 1) / segments), Color(TELEGRAPH, 0.35 + 0.55 * t), 2.5)
	draw_circle(from + (to - from).normalized() * data.radius, 5.0 + 5.0 * t, Color(0.5, 0.95, 1.0, 0.85))


## Восклицательный знак над головой на замахе.
func _draw_alert() -> void:
	var top := Vector2(0, -data.radius * 3.0 * _size_mult - 22.0 - (data.hover if data.flying else 0.0))
	var font := ThemeDB.fallback_font
	draw_string_outline(font, top + Vector2(-20, 0), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 40, 10, Color("#08151d"))
	draw_string(font, top + Vector2(-20, 0), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 40, Color("#ffe14d"))


static func _get_shadow_texture() -> GradientTexture2D:
	if _shadow_texture != null:
		return _shadow_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.45))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	_shadow_texture = GradientTexture2D.new()
	_shadow_texture.gradient = gradient
	_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	_shadow_texture.fill_from = Vector2(0.5, 0.5)
	_shadow_texture.fill_to = Vector2(1.0, 0.5)
	_shadow_texture.width = 32
	_shadow_texture.height = 32
	return _shadow_texture
