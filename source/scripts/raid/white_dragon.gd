class_name WhiteDragon
extends CharacterBody2D
## Древний Белый Дракон «Сириус»: полная стейт-машина босса (документ геометрии рейда).
##
##   INTRO → AERIAL_PATROL → DESCENDING → LANDED_ATTACK → ASCENDING → AERIAL_PATROL …
##   ХП ≤ 30% → FURY: навсегда на земле, лазер 0.8 рад/с, атаки ×1.4, космос багровеет,
##   все вражеские снаряды в пуле розовеют (#FF00FF), кристаллы больше не спавнятся.
##   DEAD — повержен. LEAVING — улетает, если Енот продержался 2 минуты.
##
## Лазер: угол _aim поворачивается к Еноту не быстрее LASER_ROTATION_SPEED рад/с
## (0.5, в ярости 0.8). Каждый кадр WhiteDragonLaser.cast() трассирует луч: если он
## пересёк купол кристалла, конец луча фиксируется на границе купола и кристалл теряет
## CRYSTAL_DPS * delta. Урон Еноту: расстояние от центра Енота до отрезка луча меньше
## BEAM_HALF_WIDTH + радиус Енота И Енот не в геометрической тени ни одного кристалла.
##
## Ледяной веер: 24 снаряда с шагом TAU/24 (15°). Время вылета i-го снаряда
## t_i = BARRAGE_SPIRAL * i/24 + BARRAGE_WOBBLE * sin(2·TAU·i/24) — синусоидальная задержка
## даёт спираль, между витками которой нужно проскальзывать.
##
## Неуязвимость в воздухе — collision_layer = 0: пули Енота пролетают сквозь, автоприцел
## не видит дракона. В полёте z_index = 5 (над кристаллами и Енотом), тень — на z -9
## и догоняет дракона с запаздыванием (иллюзия высоты). На полу — зеркальное отражение.

signal health_changed(hp: float, max_hp: float)
signal state_changed(state: State)
signal slammed(position: Vector2)
signal fury_started
signal died(position: Vector2)
signal phase_changed(index: int, title: String)
signal ultimate_warning
signal ultimate_started
signal ultimate_finished
signal exhausted_started

enum State { INTRO, AERIAL_PATROL, DESCENDING, LANDED_ATTACK, ASCENDING, FURY, DEAD, LEAVING }
enum Attack { COLD_BLAST, BEAM, COMET_VOLLEY, TAIL_SWEEP, ULTIMATE }
enum Phase { GAP, WINDUP, ACTIVE }

const MAX_HP := 4200.0
const HP_PER_DPS := 85.0
const HP_CAP := 90000.0
const FURY_THRESHOLD := 0.3
const PHASE2_THRESHOLD := 0.65
const PHASE_TITLES := ["Хозяин Озера", "Гнев Метели", "Абсолютная Стужа"]
const ULT_TELEGRAPH := 1.5
const ULT_BLIZZARD := 6.0
const EXHAUST_TIME := 4.0
const EXHAUST_DAMAGE_MULT := 2.0
const TAIL_COMBO_GAP := 0.55
const FURY_ATTACK_MULT := 1.4

const BODY_RADIUS := 86.0
const MOUTH_DISTANCE := 150.0
const CONTACT_DAMAGE := 15.0
const SLAM_DAMAGE := 35.0
const SLAM_KNOCKBACK := 500.0

const INTRO_TIME := 2.4
const AERIAL_DURATION := 9.0
const AERIAL_ALTITUDE := 150.0
const AERIAL_ALPHA := 0.4
const AERIAL_Z := 5
const PATROL_SPEED := 0.95
const PATROL_RADIUS_MIN := 280.0
const PATROL_RADIUS_MAX := 560.0
const PATROL_BREATH := 0.7
const COMET_INTERVAL := 0.42
const COMET_FALL_TIME := 1.25
const COMET_DAMAGE := 18.0
const COMET_AIM_CHANCE := 0.65
const DESCEND_TIME := 1.1
const ASCEND_TIME := 1.0
const LEAVE_TIME := 2.0
const SHADOW_LAG := 6.0

const LANDED_SEQUENCE: Array[Attack] = [Attack.TAIL_SWEEP, Attack.BEAM, Attack.COLD_BLAST, Attack.TAIL_SWEEP]
const PHASE2_SEQUENCE: Array[Attack] = [Attack.BEAM, Attack.TAIL_SWEEP, Attack.COLD_BLAST, Attack.ULTIMATE]
const FURY_SEQUENCE: Array[Attack] = [Attack.BEAM, Attack.TAIL_SWEEP, Attack.ULTIMATE, Attack.COMET_VOLLEY, Attack.COLD_BLAST, Attack.TAIL_SWEEP]
const ATTACK_GAP := 1.3
const IDLE_TURN_SPEED := 1.4

const LASER_ROTATION_SPEED := 0.5
const LASER_ROTATION_SPEED_FURY := 0.8
const BEAM_TELEGRAPH := 0.9
const BEAM_DURATION := 3.6
const BREATH_HALF_ANGLE := 0.27
const BREATH_REACH := 660.0
const TAIL_TELEGRAPH := 1.0
const TAIL_ACTIVE := 0.85
const TAIL_HALF_ANGLE := 1.75
const TAIL_RADIUS_START := 110.0
const TAIL_RADIUS_END := 640.0
const TAIL_BAND := 46.0
const TAIL_DAMAGE := 26.0
const TAIL_KNOCKBACK := 420.0
const TAIL_TURN_SPEED := 3.2
const BEAM_DAMAGE := 14.0
const CRYSTAL_DPS := 45.0

const BARRAGE_COUNT := 24
const BARRAGE_STEP := TAU / 24.0
const BARRAGE_WINDUP := 0.5
const BARRAGE_SPIRAL := 0.6
const BARRAGE_WOBBLE := 0.08
const VOLLEY_COMETS := 6
const VOLLEY_RADIUS := 130.0

const COLOR_NORMAL := Color("#8fe3ff")
const COLOR_FURY := Color("#c7a6ff")
const PROJECTILE_FURY := Color("#c7a6ff")
const SHARD_WEAPON := &"frost_shard_v1"
const OBSIDIAN_SHARD := Color("#5aa9d6")

const STRIP_PATHS := {
	&"idle": "res://assets/bosses/ice_dragon_idle.png",
	&"fly": "res://assets/bosses/ice_dragon_fly.png",
	&"breath": "res://assets/bosses/ice_dragon_breath.png",
	&"tail": "res://assets/bosses/ice_dragon_tail.png",
	&"death": "res://assets/bosses/ice_dragon_death.png",
}
const STRIP_CELL := Vector2i(320, 368)
const STRIP_FRAMES := 4
const SPRITE_SCALE := 1.0
## Торс в листе чуть выше центра кадра: сдвигаем спрайт, чтобы вращение шло вокруг тела.
const SPRITE_TORSO_OFFSET := Vector2(0, -24)
const SHOCKWAVES := 3

var max_hp := MAX_HP
var hp := MAX_HP
var state: State = State.INTRO
var facing := PI * 0.5
var altitude := AERIAL_ALTITUDE
var is_fury := false
var phase_index := 1
var exhausted := false

var _player: Player
var _arena: DragonArena
var _comets: CometPool
var _laser: WhiteDragonLaser
var _fx: FxManager

var _sprite: AnimatedSprite2D
var _shadow: Sprite2D
var _reflection: Sprite2D
var _collision: CollisionShape2D
var _shockwaves: Array[ShockwaveRing] = []
var _obsidian_burst: GPUParticles2D
var _state_time := 0.0
var _patrol_angle := -PI * 0.5
var _comet_timer := 0.0
var _move_from := Vector2.ZERO
var _move_to := Vector2.ZERO
var _sequence_index := 0
var _attack: Attack = Attack.COLD_BLAST
var _phase: Phase = Phase.GAP
var _phase_timer := 0.0
var _aim := 0.0
var _beam_channel := -1
var _barrage: Array[Vector2] = []
var _barrage_clock := 0.0
var _flash := 0.0
var _flap_timer := 0.0
var _tail_fx: TailWaveFx
var _tail_hit := false
var _tail_dir := 0.0
var _tail_combo := 0

## Дыхание сейчас задевает Енота: Raid добавляет ему озноб.
var breath_hitting := false


func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_frames()
	_sprite.scale = Vector2.ONE * SPRITE_SCALE
	_sprite.offset = SPRITE_TORSO_OFFSET
	add_child(_sprite)
	_sprite.play(&"idle")
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	add_child(_collision)


func setup(player: Player, arena: DragonArena, comets: CometPool, laser: WhiteDragonLaser, fx: FxManager, layers: BiomeLayers) -> void:
	_player = player
	_arena = arena
	_comets = comets
	_laser = laser
	_fx = fx

	_shadow = Sprite2D.new()
	_shadow.texture = _make_shadow_texture()
	_shadow.modulate = Color(0, 0, 0, 0.3)
	_shadow.z_index = -9
	_shadow.z_as_relative = false
	layers.decals.add_child(_shadow)

	_reflection = Sprite2D.new()
	_reflection.flip_v = true
	_reflection.z_index = -9
	_reflection.z_as_relative = false
	var mirror := ShaderMaterial.new()
	mirror.shader = load("res://shaders/mirror_reflection.gdshader")
	_reflection.material = mirror
	layers.decals.add_child(_reflection)

	for smooth: Node in [self, _shadow, _reflection]:
		smooth.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_tail_fx = TailWaveFx.new()
	layers.fx.add_child(_tail_fx)
	for i in SHOCKWAVES:
		var ring := ShockwaveRing.new()
		layers.fx.add_child(ring)
		_shockwaves.append(ring)
	_obsidian_burst = ParticleFactory.burst(ParticleFactory.tex_shard(), 36, 1.0, ParticleFactory.material({
		"spread": 180.0, "velocity": Vector2(220, 520), "radial_accel": Vector2(120, 260), "damping": Vector2(60, 140),
		"gravity": Vector2(0, 380), "spin": Vector2(-720, 720), "angle": Vector2(0, 360), "scale": Vector2(0.9, 1.9),
		"colors": [OBSIDIAN_SHARD, Color("#4b3d6e"), Color("#9ff6ff")], "fade_from": 0.6,
	}))
	layers.fx.add_child(_obsidian_burst)

	global_position = Vector2(0, -1350)
	_shadow.global_position = global_position
	_move_from = global_position
	_move_to = Vector2.from_angle(_patrol_angle) * PATROL_RADIUS_MIN
	_enter(State.INTRO)
	SoundManager.play(&"dragon_roar", 0.0, false)


## Здоровье масштабируется под урон в секунду оружия игрока: сильный ствол не должен снимать босса за пару секунд.
func scale_health(weapon_dps: float) -> void:
	max_hp = clampf(weapon_dps * HP_PER_DPS, MAX_HP, HP_CAP)
	hp = max_hp


func is_targetable() -> bool:
	return hp > 0.0 and (state == State.LANDED_ATTACK or state == State.FURY)


func is_beam_active() -> bool:
	return _phase == Phase.ACTIVE and _attack == Attack.BEAM and is_targetable()


func get_effect_color() -> Color:
	return COLOR_FURY if is_fury else COLOR_NORMAL


func get_mouth_position() -> Vector2:
	return global_position + Vector2.from_angle(facing) * MOUTH_DISTANCE


func take_damage(amount: float, _direction: Vector2 = Vector2.ZERO, _is_crit: bool = false) -> void:
	if not is_targetable():
		return
	hp = maxf(hp - amount * (EXHAUST_DAMAGE_MULT if exhausted else 1.0), 0.0)
	_flash = 0.07
	health_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()
		return
	if phase_index == 1 and hp <= max_hp * PHASE2_THRESHOLD:
		_start_phase2()
	if not is_fury and hp <= max_hp * FURY_THRESHOLD:
		_start_fury()


## Енот продержался 2 минуты: дракон прекращает атаки и улетает.
func retreat() -> void:
	if state == State.DEAD or state == State.LEAVING:
		return
	_cancel_ultimate()
	_stop_beam()
	_barrage.clear()
	_move_from = global_position
	_move_to = global_position + Vector2(0, -1600)
	_enter(State.LEAVING)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_state_time += delta
	match state:
		State.INTRO:
			_tick_travel(INTRO_TIME, AERIAL_ALTITUDE, AERIAL_ALTITUDE)
			if _state_time >= INTRO_TIME:
				_enter(State.AERIAL_PATROL)
		State.AERIAL_PATROL:
			_tick_patrol(delta)
		State.DESCENDING:
			_tick_travel(DESCEND_TIME, AERIAL_ALTITUDE, 0.0)
			if _state_time >= DESCEND_TIME:
				_land()
		State.ASCENDING:
			_tick_travel(ASCEND_TIME, 0.0, AERIAL_ALTITUDE)
			if _state_time >= ASCEND_TIME:
				_enter(State.AERIAL_PATROL)
		State.LANDED_ATTACK, State.FURY:
			_tick_grounded(delta)
		State.LEAVING:
			_tick_travel(LEAVE_TIME, altitude, AERIAL_ALTITUDE * 2.0)
		State.DEAD:
			_tick_death(delta)
	_tick_barrage(delta)
	_update_visuals(delta)


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	match new_state:
		State.AERIAL_PATROL:
			_patrol_angle = global_position.angle() if global_position.length() > 1.0 else facing
			_comet_timer = 0.6
		State.DESCENDING:
			_move_from = global_position
			_move_to = Vector2.ZERO
		State.ASCENDING:
			_move_from = global_position
			_move_to = Vector2.from_angle(facing) * PATROL_RADIUS_MIN
			SoundManager.play(&"wing_flap", 2.0)
		State.LANDED_ATTACK, State.FURY:
			_sequence_index = 0
			_phase = Phase.GAP
			_phase_timer = 0.9
	collision_layer = PhysicsLayers.ENEMY if (new_state == State.LANDED_ATTACK or new_state == State.FURY) else 0
	state_changed.emit(new_state)


# --- Полёт ---------------------------------------------------------------------------------

## Перелёт по прямой из _move_from в _move_to с плавным набором или сбросом высоты.
func _tick_travel(duration: float, from_altitude: float, to_altitude: float) -> void:
	var t := clampf(_state_time / duration, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var previous := global_position
	global_position = _move_from.lerp(_move_to, eased)
	altitude = lerpf(from_altitude, to_altitude, eased)
	var motion := global_position - previous
	if motion.length_squared() > 0.01:
		facing = lerp_angle(facing, motion.angle(), 0.2)


## Спираль патруля: радиус «дышит» между MIN и MAX, угол растёт с PATROL_SPEED.
func _tick_patrol(delta: float) -> void:
	_patrol_angle += PATROL_SPEED * delta
	var breath := 0.5 - 0.5 * cos(_state_time * PATROL_BREATH)
	var radius := lerpf(PATROL_RADIUS_MIN, PATROL_RADIUS_MAX, breath)
	var previous := global_position
	global_position = Vector2.from_angle(_patrol_angle) * radius
	altitude = AERIAL_ALTITUDE
	facing = lerp_angle(facing, (global_position - previous).angle(), 0.25)

	_comet_timer -= delta
	if _comet_timer <= 0.0:
		_comet_timer = COMET_INTERVAL
		_drop_comet()
	_flap_timer -= delta
	if _flap_timer <= 0.0:
		_flap_timer = 1.1
		SoundManager.play(&"wing_flap")
	if _state_time >= AERIAL_DURATION:
		_enter(State.DESCENDING)


## Комета с упреждением: целимся туда, где Енот окажется через 0.55 с.
func _drop_comet() -> void:
	var target: Vector2
	if randf() < COMET_AIM_CHANCE:
		var lead := _player.velocity * 0.55
		target = _player.global_position + lead + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 45.0)
	else:
		target = _arena.random_point(Comet.IMPACT_RADIUS)
	_comets.spawn(_arena.clamp_inside(target, 40.0), COMET_FALL_TIME, COMET_DAMAGE, get_effect_color())


## Приземление в ядро: Енот внутри CORE_RADIUS получает максимальный урон и радиальный
## отброс (player - центр).normalized() * 500; ударные волны и осколки обсидиана.
func _land() -> void:
	altitude = 0.0
	global_position = Vector2.ZERO
	var to_player := _player.global_position - global_position
	if _arena.is_in_core(_player.global_position):
		var push_dir := to_player.normalized() if to_player.length() > 1.0 else Vector2.DOWN
		_player.take_damage(SLAM_DAMAGE, push_dir)
		_player.apply_knockback(push_dir * SLAM_KNOCKBACK)
	for i in _shockwaves.size():
		_shockwaves[i].play(global_position, DragonArena.CORE_RADIUS * (1.1 + i * 0.5), Color.WHITE, i * 0.09)
	_obsidian_burst.global_position = global_position
	_obsidian_burst.restart()
	SoundManager.play(&"dragon_land", 0.0, false)
	slammed.emit(global_position)
	_enter(State.FURY if is_fury else State.LANDED_ATTACK)


# --- Земля: атаки --------------------------------------------------------------------------

func _tick_grounded(delta: float) -> void:
	var to_player := _player.global_position - global_position
	if to_player.length() < BODY_RADIUS + Player.RADIUS:
		_player.take_damage(CONTACT_DAMAGE, to_player.normalized())

	match _phase:
		Phase.GAP:
			if not exhausted:
				facing = _rotate_towards(facing, to_player.angle(), IDLE_TURN_SPEED * _attack_mult(), delta)
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				exhausted = false
				_begin_next_attack()
		Phase.WINDUP:
			_tick_windup(delta)
		Phase.ACTIVE:
			_tick_active(delta)


func _begin_next_attack() -> void:
	_sprite.speed_scale = 1.0
	var sequence := _current_sequence()
	if _sequence_index >= sequence.size():
		if is_fury:
			_sequence_index = 0
		else:
			_enter(State.ASCENDING)
			return
	_attack = sequence[_sequence_index]
	_sequence_index += 1
	_phase = Phase.WINDUP
	_tail_combo = 0
	match _attack:
		Attack.COLD_BLAST:
			_phase_timer = BARRAGE_WINDUP / _attack_mult()
			_sprite.speed_scale = 2.5
			SoundManager.play(&"wing_flap", 2.0)
		Attack.BEAM:
			_phase_timer = BEAM_TELEGRAPH / _attack_mult()
			_aim = (_player.global_position - get_mouth_position()).angle()
			facing = _aim
			_laser.show_telegraph(get_effect_color())
			SoundManager.play(&"beam_charge")
		Attack.COMET_VOLLEY:
			_phase_timer = 0.3
			SoundManager.play(&"dragon_roar", -6.0)
		Attack.TAIL_SWEEP:
			_phase_timer = TAIL_TELEGRAPH / _attack_mult()
			_tail_dir = facing + PI
			SoundManager.play(&"wing_flap", 2.0)
		Attack.ULTIMATE:
			_phase_timer = ULT_TELEGRAPH / _attack_mult()
			_sprite.speed_scale = 2.0
			SoundManager.play(&"dragon_roar", 4.0, false)
			_fx.ring(global_position, get_effect_color(), BODY_RADIUS * 3.0)
			ultimate_warning.emit()


func _tick_windup(delta: float) -> void:
	_phase_timer -= delta
	if _attack == Attack.BEAM:
		_tick_laser(delta, false)
	elif _attack == Attack.TAIL_SWEEP:
		_tick_tail_windup(delta)
	if _phase_timer > 0.0:
		return
	_phase = Phase.ACTIVE
	match _attack:
		Attack.COLD_BLAST:
			_schedule_barrage()
			_finish_attack()
		Attack.BEAM:
			_phase_timer = BEAM_DURATION
			_laser.show_fire()
			_beam_channel = SoundManager.play_loop(&"beam_loop")
		Attack.COMET_VOLLEY:
			_fire_comet_volley()
			_finish_attack()
		Attack.TAIL_SWEEP:
			_phase_timer = TAIL_ACTIVE / _attack_mult()
			_tail_hit = false
			SoundManager.play(&"ice_blast", 0.0, false)
			_fx.ring(global_position, get_effect_color(), BODY_RADIUS * 2.0)
		Attack.ULTIMATE:
			_phase_timer = ULT_BLIZZARD
			SoundManager.play(&"ice_blast", 3.0, false)
			ultimate_started.emit()


func _tick_active(delta: float) -> void:
	if _attack == Attack.TAIL_SWEEP:
		_tick_tail_wave(delta)
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_tail_fx.clear()
			if phase_index >= 2 and _tail_combo == 0:
				_tail_combo = 1
				_phase = Phase.WINDUP
				_phase_timer = TAIL_COMBO_GAP / _attack_mult()
			else:
				_finish_attack()
		return
	if _attack == Attack.ULTIMATE:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_end_ultimate()
		return
	if _attack != Attack.BEAM:
		_finish_attack()
		return
	_tick_laser(delta, true)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_stop_beam()
		_finish_attack()


func _finish_attack() -> void:
	_phase = Phase.GAP
	_phase_timer = ATTACK_GAP / _attack_mult()
	_sprite.speed_scale = 1.0


## Лазер: доворот к Еноту не быстрее rotation_speed рад/с, трассировка, урон, тень.
func _tick_laser(delta: float, damaging: bool) -> void:
	var speed := LASER_ROTATION_SPEED_FURY if is_fury else LASER_ROTATION_SPEED
	var mouth := get_mouth_position()
	_aim = _rotate_towards(_aim, (_player.global_position - mouth).angle(), speed, delta)
	facing = _aim
	mouth = get_mouth_position()
	var hit := _laser.cast(mouth, _aim, delta)
	var end: Vector2 = hit["end"]
	_arena.set_shadow_source(mouth)
	if not damaging:
		return

	var collider: Object = hit["collider"]
	if collider is Area2D:
		var crystal := (collider as Area2D).get_parent() as PrismCrystal
		if crystal != null:
			crystal.absorb_laser(CRYSTAL_DPS, delta)

	var offset := _player.global_position - mouth
	var reach := minf(BREATH_REACH, mouth.distance_to(end))
	var inside := offset.length() < reach + Player.RADIUS and absf(wrapf(offset.angle() - _aim, -PI, PI)) < BREATH_HALF_ANGLE + Player.RADIUS / maxf(offset.length(), 60.0)
	breath_hitting = inside and not _arena.is_shielded(_player.global_position, mouth, Player.RADIUS)
	if breath_hitting:
		_player.take_damage(BEAM_DAMAGE, Vector2.from_angle(_aim))


## Ледяной веер: 24 снаряда через TAU/24, вылет по синусоидальной задержке → спираль.
func _schedule_barrage() -> void:
	_barrage.clear()
	_barrage_clock = 0.0
	var offset := randf() * TAU
	var spiral := BARRAGE_SPIRAL / _attack_mult()
	for i in BARRAGE_COUNT:
		var fraction := float(i) / BARRAGE_COUNT
		var delay := maxf(spiral * fraction + BARRAGE_WOBBLE * sin(2.0 * TAU * fraction), 0.0)
		_barrage.append(Vector2(delay, offset + BARRAGE_STEP * i))
	SoundManager.play(&"ice_blast", 0.0, false)
	_fx.ring(global_position, get_effect_color(), BODY_RADIUS * 2.4)


func _tick_barrage(delta: float) -> void:
	if _barrage.is_empty():
		return
	_barrage_clock += delta
	var weapon := WeaponDB.get_weapon(SHARD_WEAPON)
	var i := _barrage.size() - 1
	while i >= 0:
		var shot := _barrage[i]
		if shot.x <= _barrage_clock:
			var dir := Vector2.from_angle(shot.y)
			BulletPool.spawn(weapon, global_position + dir * BODY_RADIUS * 0.6, dir, Bullet.Team.ENEMY)
			_barrage.remove_at(i)
		i -= 1
	if _barrage.is_empty():
		_fx.burst(global_position, Color("#f0ffff"), 16, 360.0, 4.0)


func _fire_comet_volley() -> void:
	var center := _player.global_position
	var fall := COMET_FALL_TIME * 0.85
	_comets.spawn(_arena.clamp_inside(center, 40.0), fall, COMET_DAMAGE, get_effect_color())
	for i in VOLLEY_COMETS - 1:
		var p := center + Vector2.from_angle(TAU * i / float(VOLLEY_COMETS - 1)) * VOLLEY_RADIUS
		_comets.spawn(_arena.clamp_inside(p, 40.0), fall, COMET_DAMAGE, get_effect_color())


## Хвост: дракон разворачивается спиной к Еноту, сектор позади него подсвечен.
func _tick_tail_windup(delta: float) -> void:
	_tail_dir = _rotate_towards(_tail_dir, (_player.global_position - global_position).angle(), TAIL_TURN_SPEED, delta)
	facing = _tail_dir + PI
	var total := (TAIL_COMBO_GAP if _tail_combo > 0 else TAIL_TELEGRAPH) / _attack_mult()
	_tail_fx.telegraph(global_position, _tail_dir, TAIL_HALF_ANGLE, TAIL_RADIUS_END, 1.0 - clampf(_phase_timer / total, 0.0, 1.0))


## Волна льда расходится от дракона кольцевым сектором; урон один раз, кристаллы-щиты закрывают.
func _tick_tail_wave(delta: float) -> void:
	var total := TAIL_ACTIVE / _attack_mult()
	var t := 1.0 - clampf(_phase_timer / total, 0.0, 1.0)
	var radius := lerpf(TAIL_RADIUS_START, TAIL_RADIUS_END, t)
	_tail_fx.wave(global_position, _tail_dir, TAIL_HALF_ANGLE, radius, TAIL_BAND, t)
	if _tail_hit:
		return
	var offset := _player.global_position - global_position
	var diff := absf(wrapf(offset.angle() - _tail_dir, -PI, PI))
	if absf(offset.length() - radius) < TAIL_BAND + Player.RADIUS and diff < TAIL_HALF_ANGLE:
		if not _arena.is_shielded(_player.global_position, global_position, Player.RADIUS):
			_tail_hit = true
			_player.take_damage(TAIL_DAMAGE, offset.normalized())
			_player.apply_knockback(offset.normalized() * TAIL_KNOCKBACK)
			_fx.burst(_player.global_position, get_effect_color(), 14, 300.0, 4.0)


func _stop_beam() -> void:
	breath_hitting = false
	_laser.hide_beam()
	_arena.set_shadow_source(Vector2.INF)
	SoundManager.stop_loop(_beam_channel)
	_beam_channel = -1


## Конец метели: Raid наказывает тех, кто остался вне тёплого круга; дракон выдыхается и открыт.
func _end_ultimate() -> void:
	ultimate_finished.emit()
	_finish_attack()
	exhausted = true
	_phase_timer = EXHAUST_TIME
	_sprite.speed_scale = 0.5
	_fx.burst(global_position, get_effect_color(), 20, 300.0, 4.0)
	SoundManager.play(&"dragon_land", -2.0, false)
	exhausted_started.emit()


func _cancel_ultimate() -> void:
	if _attack == Attack.ULTIMATE and _phase != Phase.GAP:
		ultimate_finished.emit()
	exhausted = false


func _current_sequence() -> Array[Attack]:
	if is_fury:
		return FURY_SEQUENCE
	return PHASE2_SEQUENCE if phase_index >= 2 else LANDED_SEQUENCE


func _start_phase2() -> void:
	phase_index = 2
	_arena.min_alive_crystals = 2
	_arena.shrink_to(DragonArena.SAFE_RADIUS_PHASE2)
	phase_changed.emit(2, PHASE_TITLES[1])
	SoundManager.play(&"dragon_roar", 1.0, false)


# --- Ярость и смерть --------------------------------------------------------------------------

func _start_fury() -> void:
	_cancel_ultimate()
	is_fury = true
	phase_index = 3
	_arena.enter_fury()
	_arena.shrink_to(DragonArena.SAFE_RADIUS_PHASE3)
	phase_changed.emit(3, PHASE_TITLES[2])
	BulletPool.set_enemy_tint(PROJECTILE_FURY)
	fury_started.emit()
	SoundManager.play(&"dragon_roar", 2.0, false)
	match state:
		State.LANDED_ATTACK:
			_stop_beam()
			state = State.FURY
			_phase = Phase.GAP
			_phase_timer = 0.8
			_sequence_index = 0
			_sprite.speed_scale = 1.0
			state_changed.emit(state)
		State.INTRO, State.AERIAL_PATROL, State.ASCENDING:
			_enter(State.DESCENDING)


func _die() -> void:
	_cancel_ultimate()
	_tail_fx.clear()
	_stop_beam()
	_barrage.clear()
	_enter(State.DEAD)
	_sprite.speed_scale = 1.0
	_sprite.play(&"death")
	SoundManager.play(&"dragon_roar", 3.0, false)
	died.emit(global_position)


func _tick_death(delta: float) -> void:
	var t := clampf(_state_time / 2.4, 0.0, 1.0)
	var flash := clampf(1.0 - _state_time * 2.5, 0.0, 1.0)
	var fade := clampf((t - 0.55) / 0.45, 0.0, 1.0)
	_sprite.modulate = Color(1.0 + 2.0 * flash, 1.0 + 2.0 * flash, 1.0 + 2.0 * flash, 1.0 - fade)
	_sprite.position = Vector2(0, -altitude + 30.0 * t)
	_sprite.scale = Vector2.ONE * SPRITE_SCALE * (1.0 - 0.18 * t)
	_shadow.modulate.a = 0.3 * (1.0 - fade)
	_sync_reflection(1.0 - fade)
	if not _sprite.is_playing() and _sprite.animation == &"death":
		_sprite.frame = STRIP_FRAMES - 1
	if int(_state_time * 10.0) != int((_state_time - delta) * 10.0) and t < 1.0:
		_fx.burst(global_position + Vector2(randf_range(-120, 120), randf_range(-90, 90)), Color.WHITE, 10, 300.0, 4.0)


# --- Математика и визуал ----------------------------------------------------------------------

## Поворот угла from к to не больше чем на speed * delta, по кратчайшей дуге.
static func _rotate_towards(from: float, to: float, speed: float, delta: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	var step := speed * delta
	return from + clampf(diff, -step, step)


func _attack_mult() -> float:
	return FURY_ATTACK_MULT if is_fury else 1.0


func _update_visuals(delta: float) -> void:
	var lift := clampf(altitude / AERIAL_ALTITUDE, 0.0, 2.0)
	_shadow.global_position = _shadow.global_position.lerp(global_position, clampf(SHADOW_LAG * delta, 0.0, 1.0))
	_shadow.scale = Vector2(9.0, 3.2) * (1.0 - clampf(lift, 0.0, 1.0) * 0.35)
	if state == State.DEAD:
		return
	_update_animation()
	_sprite.rotation = facing + PI * 0.5
	_sprite.position = Vector2(0, -altitude)
	_sprite.scale = Vector2.ONE * SPRITE_SCALE * (1.0 + lift * 0.18)
	z_index = AERIAL_Z if altitude > 20.0 else 0

	var alpha := lerpf(1.0, AERIAL_ALPHA, clampf(lift, 0.0, 1.0))
	_flash = maxf(_flash - delta, 0.0)
	var base := Color(2.0, 2.0, 2.0) if _flash > 0.0 else Color.WHITE
	if is_fury and _flash <= 0.0:
		base = Color(1.0, 0.82 + 0.1 * sin(_state_time * 8.0), 0.95)
	if exhausted and _flash <= 0.0:
		base = Color(0.72, 0.8, 0.95) * (0.9 + 0.1 * sin(_state_time * 10.0))
	_sprite.modulate = Color(base, alpha)

	_sync_reflection(1.0 - clampf(lift, 0.0, 1.0) * 0.6)


## Отражение строго повторяет позу, кадр и поворот дракона, только зеркально по горизонтали.
func _sync_reflection(alpha: float) -> void:
	_reflection.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	_reflection.global_position = global_position + Vector2(0, 64.0 + altitude * 0.9)
	_reflection.rotation = -_sprite.rotation
	_reflection.scale = _sprite.scale * 0.94
	_reflection.offset = Vector2(SPRITE_TORSO_OFFSET.x, -SPRITE_TORSO_OFFSET.y)
	_reflection.modulate.a = alpha


static func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim in STRIP_PATHS:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 2.5 if anim == &"death" else (7.0 if anim == &"idle" else 8.0))
		frames.set_animation_loop(anim, anim != &"death")
		var sheet := load(STRIP_PATHS[anim]) as Texture2D
		for i in STRIP_FRAMES:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(Vector2(i * STRIP_CELL.x, 0), Vector2(STRIP_CELL))
			frames.add_frame(anim, atlas)
	return frames


## Поза по состоянию: полёт - fly, дыхание и хвост - кадры по фазам атаки, остальное - idle.
func _update_animation() -> void:
	var wanted := &"idle"
	var frame := -1
	match state:
		State.INTRO, State.DESCENDING, State.ASCENDING, State.LEAVING:
			wanted = &"fly"
		State.LANDED_ATTACK, State.FURY:
			if _phase == Phase.WINDUP and _attack == Attack.BEAM:
				wanted = &"breath"
				frame = 0 if _phase_timer > BEAM_TELEGRAPH * 0.35 else 1
			elif _phase == Phase.ACTIVE and _attack == Attack.BEAM:
				wanted = &"breath"
				frame = 1 + int(_state_time * 9.0) % 2
			elif _attack == Attack.ULTIMATE and _phase != Phase.GAP:
				wanted = &"fly"
			elif _phase == Phase.WINDUP and _attack == Attack.TAIL_SWEEP:
				wanted = &"tail"
				frame = 0
			elif _phase == Phase.ACTIVE and _attack == Attack.TAIL_SWEEP:
				wanted = &"tail"
				var total := TAIL_ACTIVE / _attack_mult()
				frame = 1 if _phase_timer > total * 0.5 else 2
	if frame < 0:
		if _sprite.animation != wanted or not _sprite.is_playing():
			_sprite.play(wanted)
	else:
		if _sprite.animation != wanted:
			_sprite.animation = wanted
		_sprite.pause()
		_sprite.frame = frame


static func _make_shadow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


## Хвостовая волна: подсветка сектора перед ударом и расходящееся кольцо-серп.
class TailWaveFx:
	extends Node2D
	var _origin := Vector2.ZERO
	var _dir := 0.0
	var _half := 1.0
	var _radius := 0.0
	var _band := 40.0
	var _progress := 0.0
	var _mode := 0

	func _init() -> void:
		z_index = 3
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive

	func telegraph(origin: Vector2, dir: float, half: float, radius: float, progress: float) -> void:
		_origin = origin
		_dir = dir
		_half = half
		_radius = radius
		_progress = progress
		_mode = 1
		queue_redraw()

	func wave(origin: Vector2, dir: float, half: float, radius: float, band: float, progress: float) -> void:
		_origin = origin
		_dir = dir
		_half = half
		_radius = radius
		_band = band
		_progress = progress
		_mode = 2
		queue_redraw()

	func clear() -> void:
		_mode = 0
		queue_redraw()

	func _draw() -> void:
		if _mode == 0:
			return
		var a0 := _dir - _half
		var a1 := _dir + _half
		if _mode == 1:
			var fill := PackedVector2Array([_origin])
			for i in 33:
				fill.append(_origin + Vector2.from_angle(lerpf(a0, a1, i / 32.0)) * _radius)
			var blink := 0.5 + 0.5 * sin(_progress * 26.0)
			draw_colored_polygon(fill, Color(0.35, 0.8, 1.0, 0.05 + 0.12 * _progress))
			draw_arc(_origin, _radius, a0, a1, 48, Color(0.7, 0.95, 1.0, 0.35 + 0.45 * blink), 4.0, true)
			draw_line(_origin, _origin + Vector2.from_angle(a0) * _radius, Color(0.7, 0.95, 1.0, 0.5), 3.0, true)
			draw_line(_origin, _origin + Vector2.from_angle(a1) * _radius, Color(0.7, 0.95, 1.0, 0.5), 3.0, true)
			draw_arc(_origin, _radius * _progress, a0, a1, 48, Color(0.7, 0.95, 1.0, 0.5), 3.0, true)
			return
		var fade := 1.0 - _progress * 0.6
		for layer in 4:
			var width := _band * (2.0 - layer * 0.45)
			var alpha := (0.18 + layer * 0.16) * fade
			var col := Color(0.45, 0.85, 1.0, alpha) if layer < 3 else Color(1, 1, 1, 0.9 * fade)
			draw_arc(_origin, _radius, a0, a1, 64, col, width, true)
