class_name BossBrain
extends RefCounted
## Сценарии боссов (Enemy делегирует сюда поведение BOSS). У каждого — две фазы и комбо;
## каждая атака — телеграф → удар → пауза. Переход фаз — короткая неуязвимая сцена.
##
## Король Хлама (overlord)
##   Фаза 1 «Трон»: трон медленно ползёт; залпы навесных ракет по Еноту (круги на земле,
##   с упреждением), «звуковая волна» из колонок трона — кольцо снарядов (в серии — два со
##   сдвигом), комбо «ракеты → волна».
##   Фаза 2 (50% HP) «Трон развалился»: взрыв трона, крыса бегает сама — в 1.8 раза быстрее,
##   прыжки-плюхи с ударной волной и кольцом хлама, «истерика» — три быстрых кольца подряд.
## Грязный Магнат (magnate)
##   Фаза 1 «Мех-сейф»: гатлинг-очередь монетами веером из двух стволов, денежный дождь —
##   мешки монет по площади вокруг Енота, топот меха вблизи — грязевая волна.
##   Фаза 2 (40% HP) «Мех разбит»: свин выпрыгивает — быстрый, швыряет мешки сериями,
##   делает таранный рывок и «сигарный» веер монет.
## Общее для обоих: призыв подручных (SUMMON), спираль снарядов (SPIRAL), ковровая бомбардировка
## линией телеграфов (CARPET), во второй фазе — хлам/монеты с неба вокруг Енота, через
## ENRAGE_TIME секунд боя — ярость: атаки чаще, снарядов больше.

enum State { WALK, ROCKETS, RING_CHARGE, RING_FIRE, LEAP_WINDUP, LEAP, GATLING_SPIN, GATLING, RAIN, STOMP_WINDUP,
	TRANSFORM, DASH_WINDUP, DASH, FAN, SUMMON, SPIRAL, CARPET,
	BEAM_WINDUP, BEAM, PRESS_WINDUP, PRESS, SMASH_WINDUP, SMASH_LUNGE, VOMIT_WINDUP, VOMIT,
	BOLT_WINDUP, BOLT, GRID, ARC_WINDUP, BASS_WINDUP, BASS, CRANE_WINDUP, CRANE_PULL }

const TELEGRAPH := Color("#ff2e4d")
## Пассивки боссов: Король — «Свита» (регулярно зовёт подручных), Магнат — «Золотая корка»
## (на 75/50/25% здоровья покрывается золотом и несколько секунд получает вдвое меньше урона).
const SPEAKER_COUNT := 3
const SPEAKER_MULT := 0.4
## Колонки неуязвимы, пока Король не выпустит подручных: после призыва они открыты это время.
const SPEAKER_OPEN_TIME := 9.0
const BASS_INTERVAL := 8.0
const BASS_WINDUP_TIME := 0.9
const BASS_BULLETS := 12
const MUTE_TIME := 4.0
static var mute_bonus := 0.0
const SUITE_INTERVAL := 12.0
const SUITE_COUNT := 2.0
const GOLD_SHELL_TIME := 4.0
const GOLD_SHELL_MULT := 0.5
const GOLD_SHELL_STEPS: Array[float] = [0.75, 0.5, 0.25]
const FOAM_MULT := 0.75
const BEAM_WINDUP_TIME := 0.62
const BEAM_LOCK_TIME := 0.45
const BEAM_LENGTH := 620.0
const BEAM_HALF_WIDTH := 30.0
const PRESS_PUSH := 1150.0
const SMASH_RANGE := 175.0
const STUN_TIME := 1.15
const HANGOVER_TIME := 2.2
const VOMIT_TIME := 1.4
const TRANSFORM_TIME := 1.6
const OVERLORD_PHASE := 0.5
const BARON_PHASE := 0.5
const SHAMAN_PHASE := 0.5
const GRID_RADIUS := 100.0
const GRID_TIME := 1.15
const ARC_RADIUS := 200.0
const SHAMAN_TELEGRAPH := Color("#5be7ff")
const MAGNATE_PHASE := 0.4
const ENRAGE_TIME := 75.0
const HAZARD_INTERVAL := 5.0
const SPIRAL_TIME := 2.6
const CARPET_STEP := 0.13
const CRANE_WINDUP_TIME := 1.0
const CRANE_PULL_TIME := 1.7
const CRANE_PULL_SPEED := 340.0
const CRANE_SLAM_RANGE := 150.0
const CRANE_SLAM_RADIUS := 210.0
const COLLAPSE_PHASE := 0.25
const COLLAPSE_INTERVAL := 2.6
const COLLAPSE_ZONES := 5
const MAGNET := Color("#b46bff")

## Сюжетные фазы Короля (кран-магнит и обвал) включает StoryRun; в обычных забегах Король прежний.
static var story_phases := false

var enemy: Enemy
var pattern := "overlord"
var state: State = State.WALK
var state_time := 0.0
var windup := 0.0
var strike := 0.0
var phase := 1

var _cooldown := 2.2
var _step := 0
var _shots_left := 0
var _shot_timer := 0.0
var _ring_offset := 0.0
var _leap_dir := Vector2.ZERO
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _suite_timer := SUITE_INTERVAL
var shell_left := 0.0
var _shell_step := 0
## Траектория рывка фиксируется до его начала: игрок видит полосу и успевает уйти вбок.
const LEAP_WINDUP_TIME := 0.85
const LEAP_LOCK_TIME := 0.4
const LEAP_MIN := 320.0
const LEAP_MAX := 660.0
const DASH_WINDUP_TIME := 0.7
const DASH_LOCK_TIME := 0.3
const DASH_LENGTH := 320.0
var _sweep := 0.0
var _gun_side := 0
var _flash_clip := 0.0
var _rocket_tex: Texture2D
var _blast_tex: Texture2D
var _bag_tex: Texture2D
var _mud_tex: Texture2D
var _bullet: WeaponData
var _ring_bullet: WeaponData
var enraged := false
var _fight_time := 0.0
var _hazard_timer := HAZARD_INTERVAL
var _carpet_from := Vector2.ZERO
var _carpet_dir := Vector2.ZERO
const BEER_STREAM_LIMIT := 110
var _beer: WeaponData
var _puke: WeaponData
var _beer_count := 0
var _smash_hit := false
var _aim_dir := Vector2.RIGHT
var _grid_points: Array[Vector2] = []
var _shaman_bolt: WeaponData
var speakers: Array[Enemy] = []
var _speakers_spawned := false
var _speakers_alive := 0
var _bass_cd := 5.0
var _pulled: Player
var _collapse := false
static var speaker_window := 0.0
var _collapse_timer := 0.0


func setup(owner: Enemy) -> void:
	enemy = owner
	pattern = owner.data.boss_pattern
	state = State.WALK
	state_time = 0.0
	phase = 1
	_cooldown = 2.4
	_step = 0
	windup = 0.0
	strike = 0.0
	enraged = false
	_fight_time = 0.0
	_hazard_timer = HAZARD_INTERVAL
	_suite_timer = SUITE_INTERVAL
	shell_left = 0.0
	_shell_step = 0
	_rocket_tex = ArenaProp.texture_of("res://assets/bosses/rocket.png")
	_blast_tex = ArenaProp.texture_of("res://assets/props/ch1/fx_explosion.png")
	_bag_tex = ArenaProp.texture_of("res://assets/bosses/coin_bag.png")
	_mud_tex = ArenaProp.texture_of("res://assets/bosses/mud_wave.png")
	_bullet = WeaponDB.get_weapon(&"coin_shot_v1")
	_ring_bullet = WeaponDB.get_weapon(&"speaker_wave_v1")
	_beer = WeaponDB.get_weapon(&"beer_jet_v1")
	_puke = WeaponDB.get_weapon(&"puke_v1")
	_shaman_bolt = WeaponDB.get_weapon(&"shaman_bolt_v1")
	_grid_points.clear()
	_smash_hit = false
	speakers = []
	_speakers_spawned = false
	_speakers_alive = 0
	_bass_cd = 5.0
	_pulled = null
	_collapse = false
	_collapse_timer = 0.0
	speaker_window = 0.0


## Снимает притяжение магнита с Енота (конец атаки, смерть Короля).
func release() -> void:
	if _pulled != null and is_instance_valid(_pulled):
		_pulled.external_pull = Vector2.ZERO
	_pulled = null


## Порог второй фазы (доля HP).
func phase_threshold() -> float:
	match pattern:
		"overlord":
			return OVERLORD_PHASE
		"baron":
			return BARON_PHASE
	return MAGNATE_PHASE


func is_invulnerable() -> bool:
	return state == State.TRANSFORM


static func passive_text(boss_pattern: String) -> String:
	match boss_pattern:
		"overlord":
			return "Колонки трона неуязвимы, пока Король не выпустит свиту: после зова они открыты %d с. Пока колонки стоят, Король получает на 60%% меньше урона" % int(SPEAKER_OPEN_TIME)
		"magnate":
			return "Золотая корка: на 75/50/25%% здоровья получает вдвое меньше урона %d с" % int(GOLD_SHELL_TIME)
		"baron":
			return "Пивная пена: пока льёт пиво, получает на четверть меньше урона"
	return ""


## Множитель входящего урона (пассивка Магната).
func damage_taken_mult() -> float:
	if pattern == "baron" and (state == State.BEAM or state == State.PRESS):
		return FOAM_MULT
	if pattern == "overlord" and _speakers_alive > 0:
		return SPEAKER_MULT
	return GOLD_SHELL_MULT if shell_left > 0.0 else 1.0


## Колонки трона получают урон только в окне после призыва подручных.
static func speakers_open() -> bool:
	return speaker_window > 0.0


func _tick_passive(delta: float) -> void:
	if pattern == "overlord":
		speaker_window = maxf(speaker_window - delta, 0.0)
		_tick_speakers(delta)
		_suite_timer -= delta
		if _suite_timer <= 0.0 and state == State.WALK:
			_suite_timer = SUITE_INTERVAL * _tempo()
			enemy.request_fx("summon", SUITE_COUNT + (1.0 if phase == 2 else 0.0))
			speaker_window = SPEAKER_OPEN_TIME
	elif pattern == "magnate":
		shell_left = maxf(shell_left - delta, 0.0)
		if _shell_step < GOLD_SHELL_STEPS.size() and enemy.hp <= enemy.max_hp * GOLD_SHELL_STEPS[_shell_step]:
			_shell_step += 1
			shell_left = GOLD_SHELL_TIME
			enemy.request_fx("stomp", 120.0)


func _is_speaker(speaker: Enemy) -> bool:
	return is_instance_valid(speaker) and speaker.pool_index >= 0 and speaker.data != null and speaker.data.id == &"throne_speaker" and speaker.hp > 0.0


func _count_speakers() -> int:
	var alive := 0
	for speaker in speakers:
		if _is_speaker(speaker):
			alive += 1
	return alive


## Колонки трона: пока хоть одна стоит, Король защищён; последняя упала — оглушение музыкой.
func _tick_speakers(delta: float) -> void:
	_bass_cd = maxf(_bass_cd - delta, 0.0)
	if phase != 1:
		_speakers_alive = 0
		return
	if not _speakers_spawned:
		_speakers_spawned = true
		enemy.request_fx("speakers", float(SPEAKER_COUNT))
		_speakers_alive = _count_speakers()
		return
	var alive := _count_speakers()
	if alive < _speakers_alive:
		if alive == 0:
			enemy.posture_stun = MUTE_TIME + mute_bonus
			enemy.request_fx("muted")
		else:
			enemy.request_fx("speaker_down", float(alive))
	_speakers_alive = alive


func _break_speakers() -> void:
	for speaker in speakers:
		if _is_speaker(speaker):
			speaker.take_damage(speaker.max_hp * 2.0)
	speakers.clear()
	_speakers_alive = 0


func fury() -> bool:
	return phase == 2


## Скорость движения с учётом фазы (во второй фазе боссы налегке).
func speed() -> float:
	var boost := 1.3 if pattern == "shaman" else 1.8
	return enemy.data.move_speed * (boost if phase == 2 else 1.0) * (1.2 if enraged else 1.0)


## Темп атак: ярость ускоряет всё на треть.
func _tempo() -> float:
	var base := 0.8 if pattern == "baron" else 1.0
	return base * (0.72 if enraged else 1.0)


## Желаемая скорость босса на этот кадр.
func tick(player: Player, dir: Vector2, path_dir: Vector2, dist: float, delta: float) -> Vector2:
	if _pulled != null and (state != State.CRANE_PULL or enemy.posture_stun > 0.0 or player.is_dead):
		release()
	if enemy.posture_stun > 0.0:
		return Vector2.ZERO
	state_time += delta
	_flash_clip = maxf(_flash_clip - delta, 0.0)
	windup = move_toward(windup, 0.0, delta * 2.0)
	strike = move_toward(strike, 0.0, delta * 3.0)
	if phase == 1 and state != State.TRANSFORM and enemy.hp < enemy.max_hp * phase_threshold():
		_begin_transform()
	if player.is_dead:
		return Vector2.ZERO
	_fight_time += delta
	if not enraged and _fight_time >= ENRAGE_TIME:
		enraged = true
		enemy.request_fx("enrage")
	if phase == 2 and state != State.TRANSFORM and pattern != "shaman":
		if _collapse_active():
			_tick_collapse(player, delta)
		else:
			_hazard_timer -= delta
			if _hazard_timer <= 0.0:
				_hazard_timer = HAZARD_INTERVAL * _tempo()
				_sky_drop(player)
	_tick_passive(delta)
	match state:
		State.TRANSFORM:
			if state_time >= TRANSFORM_TIME:
				phase = 2
				_rest(0.6)
				enemy.phase_changed()
			return Vector2.ZERO
		State.WALK:
			_cooldown -= delta
			if _cooldown <= 0.0:
				_next_attack(dist)
			var keep := 210.0 if phase == 1 else 150.0
			if dist > keep + 60.0:
				return path_dir * speed()
			if dist < keep - 80.0:
				return -dir * speed() * 0.6
			return dir.orthogonal() * speed() * 0.45
		State.ROCKETS:
			_shot_timer -= delta
			if _shot_timer <= 0.0 and _shots_left > 0:
				_shots_left -= 1
				_shot_timer = 0.22 * _tempo()
				_throw_rocket(player, _shots_left)
			if _shots_left <= 0 and _shot_timer <= 0.0:
				if _step % 3 == 0:
					_enter(State.RING_CHARGE)
					SoundManager.play(&"beam_charge", -4.0)
				else:
					_rest()
			return path_dir * speed() * 0.2
		State.BASS_WINDUP:
			windup = clampf(state_time / BASS_WINDUP_TIME, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= BASS_WINDUP_TIME:
				_fire_bass()
				_enter(State.BASS)
			return Vector2.ZERO
		State.BASS:
			if state_time >= 0.5:
				_rest(0.4)
			return Vector2.ZERO
		State.CRANE_WINDUP:
			windup = clampf(state_time / CRANE_WINDUP_TIME, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= CRANE_WINDUP_TIME:
				_enter(State.CRANE_PULL)
				_pulled = player
				enemy.request_fx("crane", CRANE_SLAM_RADIUS)
			return Vector2.ZERO
		State.CRANE_PULL:
			var to_boss := enemy.global_position - player.global_position
			player.external_pull = to_boss.normalized() * CRANE_PULL_SPEED
			enemy.queue_redraw()
			if state_time >= CRANE_PULL_TIME or to_boss.length() < CRANE_SLAM_RANGE:
				release()
				_land(CRANE_SLAM_RADIUS, 32.0)
				_rest(0.7)
			return Vector2.ZERO
		State.RING_CHARGE:
			windup = clampf(state_time / 0.8, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= 0.8:
				_enter(State.RING_FIRE)
				_shots_left = 3 if phase == 2 else 2
				_shot_timer = 0.0
			return Vector2.ZERO
		State.RING_FIRE:
			_shot_timer -= delta
			if _shot_timer <= 0.0 and _shots_left > 0:
				_shots_left -= 1
				_shot_timer = 0.3 * _tempo()
				_fire_ring((18 if phase == 1 else 16) + (4 if enraged else 0))
			if _shots_left <= 0 and _shot_timer <= 0.0:
				_rest()
			return Vector2.ZERO
		State.LEAP_WINDUP:
			windup = clampf(state_time / LEAP_WINDUP_TIME, 0.0, 1.0)
			_leap_from = enemy.global_position
			if state_time < LEAP_LOCK_TIME:
				_leap_dir = _leap_from.direction_to(player.global_position + player.velocity * 0.3)
				var reach := clampf(_leap_from.distance_to(player.global_position), LEAP_MIN, LEAP_MAX)
				_leap_to = _leap_from + _leap_dir * reach
			enemy.queue_redraw()
			if state_time >= LEAP_WINDUP_TIME:
				_enter(State.LEAP)
			return Vector2.ZERO
		State.LEAP:
			strike = 1.0
			enemy.queue_redraw()
			var total := clampf(_leap_from.distance_to(_leap_to) / 620.0, 0.25, 0.6)
			if state_time >= total:
				_land(170.0, 34.0)
				_fire_ring(16)
				_rest(0.6)
				return Vector2.ZERO
			return _leap_dir * _leap_from.distance_to(_leap_to) / total
		State.GATLING_SPIN:
			windup = clampf(state_time / 0.55, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= 0.55:
				_enter(State.GATLING)
				_shot_timer = 0.0
				_sweep = randf() * TAU
			return Vector2.ZERO
		State.GATLING:
			_shot_timer -= delta
			_sweep += delta * 3.2
			while _shot_timer <= 0.0:
				_shot_timer += 1.0 / (16.0 if not enraged else 20.0)
				_fire_gun(player, 0.42)
			if state_time >= 2.6:
				_rest()
			return dir.orthogonal() * speed() * 0.3
		State.RAIN:
			_shot_timer -= delta
			if _shot_timer <= 0.0 and _shots_left > 0:
				_shots_left -= 1
				_shot_timer = (0.09 if phase == 2 else 0.12) * _tempo()
				_throw_coin_bag(player, _shots_left % 3 == 0)
			if _shots_left <= 0 and _shot_timer <= 0.0:
				_rest()
			return Vector2.ZERO if phase == 1 else dir.orthogonal() * speed() * 0.5
		State.STOMP_WINDUP:
			windup = clampf(state_time / 0.75, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= 0.75:
				_land(200.0, 38.0)
				_fire_ring(20)
				_rest()
			return Vector2.ZERO
		State.DASH_WINDUP:
			windup = clampf(state_time / DASH_WINDUP_TIME, 0.0, 1.0)
			if state_time < DASH_LOCK_TIME:
				_leap_dir = dir
			_leap_from = enemy.global_position
			enemy.queue_redraw()
			if state_time >= DASH_WINDUP_TIME:
				_enter(State.DASH)
				SoundManager.play(&"wing_flap", -2.0)
			return Vector2.ZERO
		State.DASH:
			strike = 1.0
			if state_time >= 0.5:
				_enter(State.FAN)
				_shots_left = 3
				_shot_timer = 0.15
			return _leap_dir * 640.0
		State.FAN:
			_shot_timer -= delta
			if _shot_timer <= 0.0 and _shots_left > 0:
				_shots_left -= 1
				_shot_timer = 0.2 * _tempo()
				for i in 9:
					_fire_gun(player, 0.0, -0.8 + 0.2 * i)
			if _shots_left <= 0 and _shot_timer <= 0.0:
				_rest()
			return Vector2.ZERO
		State.SUMMON:
			windup = clampf(state_time / 0.7, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= 0.7:
				enemy.request_fx("summon", 3.0 + (2.0 if phase == 2 else 0.0) + (2.0 if enraged else 0.0))
				if pattern == "overlord":
					speaker_window = SPEAKER_OPEN_TIME
				_rest(0.2)
			return Vector2.ZERO
		State.BOLT_WINDUP:
			windup = clampf(state_time / 0.7, 0.0, 1.0)
			if state_time < 0.45:
				_aim_dir = enemy.part_muzzle(0).direction_to(player.global_position + player.velocity * 0.15)
			enemy.queue_redraw()
			if state_time >= 0.7:
				_enter(State.BOLT)
				_shots_left = 3
				_shot_timer = 0.0
			return Vector2.ZERO
		State.BOLT:
			_shot_timer -= delta
			if _shot_timer <= 0.0 and _shots_left > 0:
				_shots_left -= 1
				_shot_timer = 0.3 * _tempo()
				_aim_dir = enemy.part_muzzle(0).direction_to(player.global_position + player.velocity * 0.15)
				var fan := 3 if phase == 1 else 5
				for i in fan:
					_fire_shaman(_aim_dir.rotated((float(i) - float(fan - 1) * 0.5) * 0.2))
				SoundManager.play(&"enemy_shot", -6.0)
			if _shots_left <= 0 and _shot_timer <= 0.0:
				_rest(0.3)
			return Vector2.ZERO
		State.GRID:
			enemy.queue_redraw()
			if state_time >= GRID_TIME * (1.0 if phase == 1 else 0.85):
				for point in _grid_points:
					BulletPool.explode(point, GRID_RADIUS, 24.0 * enemy.damage_mult, Bullet.Team.ENEMY, SHAMAN_TELEGRAPH, 1.4)
				_grid_points.clear()
				_rest(0.5)
			return Vector2.ZERO
		State.ARC_WINDUP:
			windup = clampf(state_time / 0.55, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= 0.55:
				_shock_burst()
				_rest(0.6)
			return Vector2.ZERO
		State.SPIRAL:
			_shot_timer -= delta
			_ring_offset += delta * (2.4 if phase == 1 else -3.0)
			while _shot_timer <= 0.0:
				_shot_timer += 0.085 * _tempo()
				for arm in (3 if phase == 1 else 4):
					_fire_bullet(_ring_bullet, _ring_offset + TAU * arm / (3 if phase == 1 else 4))
			if state_time >= SPIRAL_TIME:
				_rest(0.3)
			return Vector2.ZERO
		State.BEAM_WINDUP:
			windup = clampf(state_time / BEAM_WINDUP_TIME, 0.0, 1.0)
			if pattern == "baron" and int(state_time * 9.0) != int((state_time - delta) * 9.0):
				enemy.request_fx("beer_puke", 0.0, enemy.part_muzzle(0))
			if state_time < BEAM_LOCK_TIME:
				_aim_dir = enemy.part_muzzle(0).direction_to(player.global_position + player.velocity * 0.15)
			enemy.queue_redraw()
			if state_time >= BEAM_WINDUP_TIME:
				_enter(State.BEAM)
				_shot_timer = 0.0
				SoundManager.play(&"beam_charge", -2.0)
			return Vector2.ZERO
		State.BEAM:
			_shot_timer -= delta
			var sweep_angle := sin(state_time * 2.4) * 0.5 if phase == 2 else 0.0
			while _shot_timer <= 0.0:
				_shot_timer += 0.05 * _tempo()
				_fire_beer(_beer, _aim_dir.rotated(sweep_angle + randf_range(-0.05, 0.05)), 0.0)
			enemy.request_fx("muzzle", 0.0, enemy.part_muzzle(0))
			if state_time >= (2.3 if phase == 2 else 1.8):
				_rest(0.4)
			return -_aim_dir * (230.0 if phase == 2 else 180.0)
		State.PRESS_WINDUP:
			windup = clampf(state_time / 0.6, 0.0, 1.0)
			enemy.queue_redraw()
			if state_time >= 0.6:
				_enter(State.PRESS)
				_shot_timer = 0.0
				SoundManager.play(&"beam_charge", -2.0)
			return Vector2.ZERO
		State.PRESS:
			_shot_timer -= delta
			_aim_dir = _aim_dir.lerp(dir, clampf(delta * 4.0, 0.0, 1.0)).normalized()
			while _shot_timer <= 0.0:
				_shot_timer += 0.07 * _tempo()
				_fire_beer(_beer, _aim_dir.rotated(randf_range(-0.28, 0.28)), 0.0)
			if not player.is_dead and _in_cone(player.global_position, _aim_dir, 0.5, 520.0):
				player.apply_knockback(_aim_dir * PRESS_PUSH * delta)
			if state_time >= (2.6 if phase == 2 else 2.1):
				_rest(0.5)
			return dir * (95.0 if phase == 1 else 130.0)
		State.SMASH_WINDUP:
			windup = clampf(state_time / 0.75, 0.0, 1.0)
			if state_time < 0.4:
				_leap_dir = dir
			_leap_from = enemy.global_position
			enemy.queue_redraw()
			if state_time >= 0.75:
				_enter(State.SMASH_LUNGE)
				_smash_hit = false
				SoundManager.play(&"wing_flap", -2.0)
			return Vector2.ZERO
		State.SMASH_LUNGE:
			strike = 1.0
			if state_time >= 0.32:
				_smash_impact(player)
			return _leap_dir * 560.0
		State.VOMIT_WINDUP:
			windup = clampf(state_time / 0.5, 0.0, 1.0)
			if int(state_time * 9.0) != int((state_time - delta) * 9.0):
				enemy.request_fx("beer_puke", 0.0, enemy.part_muzzle(0))
			_aim_dir = enemy.global_position.direction_to(player.global_position)
			enemy.queue_redraw()
			if state_time >= 0.5:
				_enter(State.VOMIT)
				_shot_timer = 0.0
			return Vector2.ZERO
		State.VOMIT:
			_shot_timer -= delta
			var want := enemy.global_position.direction_to(player.global_position)
			_aim_dir = Vector2.from_angle(rotate_toward(_aim_dir.angle(), want.angle(), delta * 1.3))
			while _shot_timer <= 0.0:
				_shot_timer += 0.055 * _tempo()
				_fire_beer(_puke, _aim_dir.rotated(randf_range(-0.38, 0.38)), 0.0)
			if state_time >= VOMIT_TIME:
				_rest(0.7)
			return Vector2.ZERO
		State.CARPET:
			_shot_timer -= delta
			if _shots_left > 0 and _shot_timer <= 0.0:
				_shot_timer = CARPET_STEP * _tempo()
				_shots_left -= 1
				var at := _carpet_from + _carpet_dir * 110.0 * (8 - _shots_left)
				_lob(at, 0.75, 92.0, 24.0)
			if _shots_left <= 0 and _shot_timer <= 0.0:
				_rest()
			return Vector2.ZERO
	return Vector2.ZERO


func _collapse_active() -> bool:
	return story_phases and pattern == "overlord" and enemy.hp < enemy.max_hp * COLLAPSE_PHASE


## Обвал: потолок трона сыплется плитами — пять кругов по арене, один под Енотом.
func _tick_collapse(player: Player, delta: float) -> void:
	if not _collapse:
		_collapse = true
		_collapse_timer = 0.8
		enemy.request_fx("collapse", 0.0)
	_collapse_timer -= delta
	if _collapse_timer > 0.0:
		return
	_collapse_timer = COLLAPSE_INTERVAL * _tempo()
	for i in COLLAPSE_ZONES:
		var at := player.global_position + player.velocity * 0.45
		if i > 0:
			at = player.global_position + Vector2.from_angle(TAU * float(i) / COLLAPSE_ZONES + randf() * 0.6) * randf_range(120.0, 330.0)
		_lob(at, 1.25, 96.0, 24.0, at + Vector2(randf_range(-80.0, 80.0), -700.0))


func _begin_transform() -> void:
	_break_speakers()
	_enter(State.TRANSFORM)
	windup = 0.0
	strike = 1.0
	var at := enemy.global_position
	BulletPool.explode(at, 210.0, 0.0, Bullet.Team.PLAYER, Color("#ffd257"), 2.2)
	enemy.request_fx("transform")
	SoundManager.play(&"comet_impact", 0.0, false)


func _next_attack(dist: float) -> void:
	_step += 1
	if pattern == "baron":
		_next_baron_attack()
		return
	if pattern == "shaman":
		_next_shaman_attack(dist)
		return
	if pattern == "overlord" and phase == 1 and _speakers_alive > 0 and _bass_cd <= 0.0:
		_bass_cd = BASS_INTERVAL * _tempo()
		_enter(State.BASS_WINDUP)
		SoundManager.play(&"beam_charge", -2.0)
		return
	# Каждая пятая атака — общая «специальная»: призыв, спираль или ковёр по очереди.
	if _step % 5 == 0:
		match (_step / 5) % 3:
			0:
				_enter(State.SUMMON)
				SoundManager.play(&"boss_spawn", -8.0)
			1:
				_enter(State.SPIRAL)
				_shot_timer = 0.0
				SoundManager.play(&"beam_charge", -4.0)
			_:
				_start_carpet()
		return
	if pattern == "magnate":
		if phase == 1:
			if dist < 230.0 and _step % 2 == 0:
				_enter(State.STOMP_WINDUP)
				SoundManager.play(&"beam_charge", -4.0)
			elif _step % 3 == 2:
				_enter(State.RAIN)
				_shots_left = 9
				_shot_timer = 0.0
			else:
				_enter(State.GATLING_SPIN)
				SoundManager.play(&"beam_charge", -6.0)
		else:
			match _step % 3:
				0:
					_enter(State.DASH_WINDUP)
				1:
					_enter(State.RAIN)
					_shots_left = 13
					_shot_timer = 0.0
				_:
					_enter(State.GATLING_SPIN)
		return
	if phase == 1:
		if _step % 3 == 2:
			_enter(State.RING_CHARGE)
			SoundManager.play(&"beam_charge", -4.0)
		else:
			_enter(State.ROCKETS)
			_shots_left = 5
			_shot_timer = 0.0
	elif story_phases and pattern == "overlord" and _step % 4 == 2:
		_enter(State.CRANE_WINDUP)
		SoundManager.play(&"beam_charge", -2.0)
	else:
		match _step % 3:
			0:
				_enter(State.RING_CHARGE)
			_:
				_enter(State.LEAP_WINDUP)


## Барон: цикл «струя → прижим → удар». Удар с оглушением ведёт к рвоте, если Енот не увернулся.
func _next_baron_attack() -> void:
	if _step % 5 == 0:
		_enter(State.SUMMON)
		SoundManager.play(&"boss_spawn", -8.0)
		return
	var cycle: Array = [0, 1, 2, 0, 2] if phase == 1 else [0, 2, 1, 2, 0]
	match cycle[(_step - 1) % cycle.size()]:
		0:
			_enter(State.BEAM_WINDUP)
			SoundManager.play(&"beam_charge", -4.0)
		1:
			_enter(State.PRESS_WINDUP)
			_aim_dir = enemy.global_position.direction_to(enemy.target_point())
			SoundManager.play(&"beam_charge", -4.0)
		_:
			_enter(State.SMASH_WINDUP)


## Шаман: молнии веером → электро-поле под ногами → ударная дуга вблизи; каждая пятая атака — призыв.
func _next_shaman_attack(dist: float) -> void:
	if _step % 5 == 0:
		_enter(State.SUMMON)
		SoundManager.play(&"boss_spawn", -8.0)
		return
	if dist < 240.0 and _step % 2 == 0:
		_enter(State.ARC_WINDUP)
		SoundManager.play(&"beam_charge", -4.0)
	elif _step % 2 == 1:
		_enter(State.BOLT_WINDUP)
		_aim_dir = enemy.part_muzzle(0).direction_to(enemy.target_point())
		SoundManager.play(&"beam_charge", -4.0)
	else:
		_start_grid()


func _start_grid() -> void:
	_enter(State.GRID)
	_grid_points.clear()
	var center := enemy.target_point()
	_grid_points.append(center)
	var extra := 4 if phase == 1 else 8
	for i in extra:
		_grid_points.append(center + Vector2.from_angle(TAU * float(i) / extra + randf() * 0.6) * randf_range(120.0, 320.0))
	SoundManager.play(&"beam_charge", -3.0)


func _shock_burst() -> void:
	BulletPool.explode(enemy.global_position, ARC_RADIUS, 30.0 * enemy.damage_mult, Bullet.Team.ENEMY, SHAMAN_TELEGRAPH, 1.6)
	enemy.request_fx("stomp", ARC_RADIUS)
	strike = 1.0
	var count := 10 if phase == 1 else 14
	_ring_offset += 0.4
	for i in count:
		_fire_shaman(Vector2.from_angle(_ring_offset + TAU * float(i) / count))


func _fire_shaman(direction: Vector2) -> void:
	if _shaman_bolt == null:
		return
	var bullet := BulletPool.spawn(_shaman_bolt, enemy.part_muzzle(0), direction, Bullet.Team.ENEMY)
	if bullet != null:
		bullet.damage_scale = enemy.damage_mult


func _smash_impact(player: Player) -> void:
	_smash_hit = true
	_land(SMASH_RANGE, 0.0)
	var hit := not player.is_dead and enemy.global_position.distance_to(player.global_position) < SMASH_RANGE + 40.0
	if hit:
		var before := player.hp
		Player.last_source = enemy.data.id
		player.take_damage(30.0 * enemy.damage_mult, _leap_dir)
		if player.hp < before:
			player.stun(STUN_TIME)
			player.apply_knockback(_leap_dir * 260.0)
			_enter(State.VOMIT_WINDUP)
			enemy.request_fx("muzzle", 0.0, enemy.global_position)
			return
	_hangover()


## Уклонился от удара бочкой: Барон теряет равновесие и стоит открытым (урон x1.5), пока «похмелье» не пройдёт.
func _hangover() -> void:
	enemy.posture_stun = HANGOVER_TIME
	enemy.posture = 0.0
	enemy.posture_broken.emit(enemy)
	_rest(0.4)


func _fire_beer(weapon: WeaponData, angle_dir: Vector2, spread: float) -> void:
	if weapon == null:
		return
	if BulletPool.get_active_count() > BEER_STREAM_LIMIT and randf() < 0.5:
		return
	var from := enemy.part_muzzle(0)
	var bullet := BulletPool.spawn(weapon, from, angle_dir.rotated(spread), Bullet.Team.ENEMY)
	if bullet != null:
		bullet.damage_scale = enemy.damage_mult
	_beer_count += 1
	if _beer_count % 5 == 0:
		enemy.request_fx("beer_puke" if weapon == _puke else "beer", 0.0, from + angle_dir * randf_range(260.0, 560.0))


func _in_cone(point: Vector2, dir: Vector2, half_angle: float, length: float) -> bool:
	var to := point - enemy.global_position
	return to.length() < length and absf(dir.angle_to(to)) < half_angle


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
	enemy.queue_redraw()


func _rest(extra: float = 0.0) -> void:
	_enter(State.WALK)
	_cooldown = ((0.6 if phase == 2 else 1.0) + randf_range(0.0, 0.3) + extra) * _tempo()


## Ковёр: линия из восьми разрывов от босса через Енота — уходить поперёк линии.
func _start_carpet() -> void:
	_enter(State.CARPET)
	_carpet_from = enemy.global_position
	_carpet_dir = enemy.global_position.direction_to(enemy.target_point())
	_shots_left = 8
	_shot_timer = 0.35
	SoundManager.play(&"beam_charge", -6.0)


## Хлам (у Магната — мешки монет) падает с неба вокруг Енота: три круга, один — точно под ним.
func _sky_drop(player: Player) -> void:
	for i in 3:
		var at := player.global_position + player.velocity * 0.4
		if i > 0:
			at += Vector2.from_angle(randf() * TAU) * randf_range(90.0, 200.0)
		_lob(at, 1.1, 78.0, 20.0, at + Vector2(randf_range(-60.0, 60.0), -620.0))


func _lob(at: Vector2, flight: float, radius: float, damage: float, from: Vector2 = Vector2.INF) -> void:
	if LobPool.active == null:
		return
	var start := from if from != Vector2.INF else enemy.global_position + Vector2(0, -enemy.data.radius * 2.0)
	var tex := _bag_tex if pattern == "magnate" else _rocket_tex
	var color := Color("#ffd257") if pattern == "magnate" else Color("#ff5a1f")
	LobPool.active.throw(start, at, flight, 220.0, radius, damage * enemy.damage_mult, color, tex, _blast_tex, 40.0, 0.0 if pattern != "magnate" else 5.0)


func _fire_bullet(weapon: WeaponData, angle: float) -> void:
	if weapon == null:
		return
	var bullet := BulletPool.spawn(weapon, enemy.global_position + Vector2(0, -24), Vector2.from_angle(angle), Bullet.Team.ENEMY)
	if bullet != null:
		bullet.damage_scale = enemy.damage_mult


func _land(radius: float, damage: float) -> void:
	strike = 1.0
	BulletPool.explode(enemy.global_position, radius, damage * enemy.damage_mult, Bullet.Team.ENEMY, Color("#c9a26a"), 1.5)
	enemy.request_fx("stomp", radius)


func _throw_rocket(player: Player, index: int) -> void:
	if LobPool.active == null:
		return
	var target := player.global_position + player.velocity * 0.5
	if index > 0:
		target += Vector2.from_angle(randf() * TAU) * randf_range(70.0, 160.0)
	LobPool.active.throw(enemy.part_muzzle(0), target, 0.95, 200.0, 88.0, 26.0 * enemy.damage_mult, Color("#ff5a1f"), _rocket_tex, _blast_tex, 44.0, 0.0)
	strike = 0.7
	_flash_clip = 0.14
	enemy.request_fx("muzzle", 0.0, enemy.part_muzzle(0))
	SoundManager.play(&"shot_launcher", -4.0)


func _throw_coin_bag(player: Player, exact: bool) -> void:
	if LobPool.active == null:
		return
	var target := player.global_position + player.velocity * 0.45
	if not exact:
		target = player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(80.0, 300.0)
	var from := enemy.global_position + Vector2(0, -enemy.data.radius * 2.0)
	LobPool.active.throw(from, target, 1.05, 260.0, 84.0, 24.0 * enemy.damage_mult, Color("#ffd257"), _bag_tex, _blast_tex, 44.0, 5.0)


func _fire_bass() -> void:
	if _ring_bullet == null:
		return
	_ring_offset += 0.35
	for speaker in speakers:
		if not _is_speaker(speaker):
			continue
		var origin := speaker.global_position + Vector2(0, -20)
		for i in BASS_BULLETS:
			var bullet := BulletPool.spawn(_ring_bullet, origin, Vector2.from_angle(_ring_offset + TAU * float(i) / BASS_BULLETS), Bullet.Team.ENEMY)
			if bullet != null:
				bullet.damage_scale = enemy.damage_mult
		enemy.request_fx("bass", 160.0, speaker.global_position)
	SoundManager.play(&"enemy_shot")
	strike = 1.0
	_flash_clip = 0.12


func _fire_ring(count: int) -> void:
	if _ring_bullet == null:
		return
	_ring_offset += 0.5
	for i in count:
		var angle := _ring_offset + TAU * float(i) / count
		var bullet := BulletPool.spawn(_ring_bullet, enemy.global_position + Vector2(0, -24), Vector2.from_angle(angle), Bullet.Team.ENEMY)
		if bullet != null:
			bullet.damage_scale = enemy.damage_mult
	SoundManager.play(&"enemy_shot")
	strike = 1.0
	_flash_clip = 0.12


func _fire_gun(player: Player, sweep_amount: float, fixed: float = 0.0) -> void:
	if _bullet == null:
		return
	_gun_side = 1 - _gun_side
	var index := 1 + _gun_side
	var from := enemy.part_muzzle(index)
	var aim := from.direction_to(player.global_position + player.velocity * 0.2)
	aim = aim.rotated(sin(_sweep) * sweep_amount + fixed)
	var bullet := BulletPool.spawn(_bullet, from, aim, Bullet.Team.ENEMY)
	if bullet != null:
		bullet.damage_scale = enemy.damage_mult
	if _gun_side == 0:
		SoundManager.play(&"enemy_shot", -6.0)
		enemy.request_fx("muzzle", 0.0, from)


## Клип покадровой анимации по состоянию: [имя, фаза в кадрах].
func clip(moving: bool, hurt: float) -> Array:
	var p2 := phase == 2
	if pattern == "shaman":
		match state:
			State.BOLT_WINDUP:
				return ["aim", 0.0]
			State.BOLT:
				return ["beam", state_time * 12.0]
			State.GRID, State.SUMMON:
				return ["taunt", state_time * 8.0]
			State.ARC_WINDUP:
				return ["windup", 0.0]
			State.TRANSFORM:
				return ["stun", state_time * 6.0]
		if hurt > 0.5:
			return ["hit", 0.0]
		return ["run", -1.0] if moving else ["idle", -1.0]
	if pattern == "baron":
		if enemy.posture_stun > 0.0:
			return ["stun", -1.0]
		match state:
			State.BEAM_WINDUP:
				return ["aim", 0.0]
			State.BEAM, State.PRESS:
				return ["beam", state_time * 12.0]
			State.PRESS_WINDUP:
				return ["windup", state_time * 3.0]
			State.SMASH_WINDUP:
				return ["windup", state_time * 3.0]
			State.SMASH_LUNGE:
				return ["swing", state_time * 18.0]
			State.VOMIT_WINDUP, State.VOMIT:
				return ["vomit", 0.0]
	match state:
		State.TRANSFORM:
			return ["hit" if pattern == "overlord" else "wreck", 0.0]
		State.ROCKETS:
			return ["strike" if _flash_clip > 0.0 else "aim", 0.0]
		State.BASS_WINDUP, State.BASS:
			return ["windup" if state == State.BASS_WINDUP else "strike", 0.0]
		State.RING_CHARGE, State.GATLING_SPIN, State.STOMP_WINDUP, State.CRANE_WINDUP, State.CRANE_PULL:
			return ["p2_windup" if p2 else "windup", 0.0]
		State.LEAP_WINDUP, State.DASH_WINDUP:
			return ["p2_windup", 0.0]
		State.RING_FIRE:
			return ["p2_hit" if p2 else "strike", 0.0]
		State.LEAP, State.DASH:
			return ["p2_run", state_time * 10.0]
		State.GATLING:
			return ["p2_windup" if p2 else "strike", state_time * 10.0]
		State.RAIN:
			return ["p2_windup" if p2 else "rain", 0.0]
		State.FAN:
			return ["p2_windup", 0.0]
		State.SUMMON, State.CARPET:
			return ["p2_windup" if p2 else "windup", 0.0]
		State.SPIRAL:
			return ["p2_hit" if p2 else "strike", state_time * 8.0]
	if hurt > 0.5:
		return ["p2_hit" if p2 else "hit", 0.0]
	if moving:
		return ["p2_run" if p2 else "run", -1.0]
	return ["p2_idle" if p2 else "idle", -1.0]


## Полоса рывка: тёмная дорожка по всей траектории, заливка растёт от босса к концу, бегущие
## шевроны показывают направление, после фиксации цель мигает жёлтым. end_radius > 0 рисует
## круг приземления в конце полосы. Ширина = размер тела босса: уйти нужно поперёк полосы.
func _draw_lane(canvas: Node2D, from_world: Vector2, dir: Vector2, length: float, t: float, locked: bool, end_radius: float, fade: float = 1.0) -> void:
	if dir == Vector2.ZERO:
		return
	var clock := Time.get_ticks_msec() * 0.001
	var a := canvas.to_local(from_world)
	var b := canvas.to_local(from_world + dir * length)
	var forward := (b - a).normalized()
	var side := forward.orthogonal() * (enemy.data.radius * 0.95 + 8.0)
	var hot := locked and t > 0.8 and int(clock * 16.0) % 2 == 0
	var tint := Color(1.0, 0.92, 0.35) if hot else TELEGRAPH
	canvas.draw_colored_polygon(PackedVector2Array([a + side, b + side, b - side, a - side]), Color(0.08, 0.0, 0.04, (0.22 + 0.1 * t) * fade))
	var reach := a.lerp(b, maxf(t, 0.05))
	canvas.draw_colored_polygon(PackedVector2Array([a + side, reach + side, reach - side, a - side]), Color(tint, (0.16 + 0.2 * t) * fade))
	var edge := Color(tint, (0.55 if locked else 0.3) * fade)
	canvas.draw_line(a + side, b + side, edge, 3.0, true)
	canvas.draw_line(a - side, b - side, edge, 3.0, true)
	var spacing := 64.0
	var count := int(length / spacing)
	var shift := fmod(clock * 180.0, spacing)
	for i in count:
		var d := i * spacing + shift
		if d > length - 26.0:
			continue
		var c := a + forward * d
		var w := side.length() * 0.6
		var chev := Color(tint.lightened(0.3), (0.35 + 0.4 * t) * fade)
		canvas.draw_polyline(PackedVector2Array([c - forward * 14.0 + forward.orthogonal() * w, c + forward * 6.0, c - forward * 14.0 - forward.orthogonal() * w]), chev, 4.0, true)
	var head := b + forward * 10.0
	var wing := side.length() * 1.15
	canvas.draw_colored_polygon(PackedVector2Array([head + forward * 46.0, head + forward.orthogonal() * wing, head - forward.orthogonal() * wing]), Color(tint, (0.45 + 0.3 * t) * fade))
	if end_radius > 0.0:
		SoftGlow.pool(canvas, b, end_radius, 0.58, Color(tint, (0.12 + 0.14 * t) * fade))
		SoftGlow.rim(canvas, b, end_radius * 1.1, 0.58, Color(tint, (0.35 + 0.3 * t) * fade))


func _draw_strip(canvas: Node2D, from_world: Vector2, dir: Vector2, length: float, half_width: float, t: float, locked: bool) -> void:
	var a := canvas.to_local(from_world)
	var side := dir.orthogonal() * half_width
	var b := a + dir * length
	var hot := locked and t > 0.8 and int(Time.get_ticks_msec() * 0.016) % 2 == 0
	var tint := Color(1.0, 0.92, 0.35) if hot else TELEGRAPH
	canvas.draw_colored_polygon(PackedVector2Array([a + side, b + side, b - side, a - side]), Color(tint, 0.1 + 0.2 * t))
	canvas.draw_line(a + side, b + side, Color(tint, 0.6), 3.0, true)
	canvas.draw_line(a - side, b - side, Color(tint, 0.6), 3.0, true)


func _draw_cone(canvas: Node2D, from_world: Vector2, dir: Vector2, half_angle: float, length: float, t: float) -> void:
	var a := canvas.to_local(from_world)
	var pts := PackedVector2Array([a])
	for i in 9:
		pts.append(a + dir.rotated(-half_angle + half_angle * 2.0 * float(i) / 8.0) * length)
	canvas.draw_colored_polygon(pts, Color(TELEGRAPH, 0.08 + 0.2 * t))
	canvas.draw_line(a, a + dir.rotated(-half_angle) * length, Color(TELEGRAPH, 0.7), 3.0, true)
	canvas.draw_line(a, a + dir.rotated(half_angle) * length, Color(TELEGRAPH, 0.7), 3.0, true)


## Единый вид опасной зоны: тёмная подложка, нарастающая заливка, бегущий пунктир, прицел.
func _draw_zone(canvas: Node2D, at: Vector2, radius: float, t: float) -> void:
	var clock := Time.get_ticks_msec() * 0.001
	var hot := t > 0.75 and int(clock * 18.0) % 2 == 0
	var ring := Color(1.0, 0.92, 0.35, 0.95) if hot else Color(TELEGRAPH, 0.95)
	canvas.draw_set_transform(at, 0.0, Vector2(1.0, 0.58))
	canvas.draw_circle(Vector2.ZERO, radius, Color(0.08, 0.0, 0.04, 0.2 + 0.14 * t))
	canvas.draw_circle(Vector2.ZERO, radius * t, Color(TELEGRAPH, 0.3 + 0.22 * (0.5 + 0.5 * sin(clock * 20.0))))
	for d in 16:
		var a0 := clock * 1.6 + TAU * float(d) / 16.0
		canvas.draw_arc(Vector2.ZERO, radius, a0, a0 + TAU / 16.0 * 0.6, 4, ring, 5.0, true)
	var cr := radius * 0.28
	canvas.draw_line(Vector2(-cr, 0), Vector2(cr, 0), ring, 3.0)
	canvas.draw_line(Vector2(0, -cr), Vector2(0, cr), ring, 3.0)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Золотые нити от Короля к колонкам: видно, что именно даёт ему защиту.
## Магнит на тросе: подкова с полюсами и дугами притяжения.
func _draw_magnet(canvas: Node2D, head: Vector2, t: float) -> void:
	canvas.draw_line(head + Vector2(0, -900.0), head, Color("#2a2838"), 7.0)
	canvas.draw_arc(head + Vector2(0, 6), 30.0, 0.0, PI, 20, Color("#d63a4f"), 12.0, true)
	canvas.draw_rect(Rect2(head + Vector2(-36, 4), Vector2(14, 22)), Color("#eefbff"), true)
	canvas.draw_rect(Rect2(head + Vector2(22, 4), Vector2(14, 22)), Color("#eefbff"), true)
	for k in 3:
		canvas.draw_arc(head + Vector2(0, 26), 34.0 + 18.0 * k * t, 0.2, PI - 0.2, 16, Color(MAGNET, 0.6 - 0.15 * k), 3.0, true)


func _draw_speaker_links(canvas: Node2D) -> void:
	var pulse := 0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.006)
	var from := Vector2(0, -enemy.data.radius)
	for speaker in speakers:
		if _is_speaker(speaker):
			var to := canvas.to_local(speaker.global_position) + Vector2(0, -24)
			canvas.draw_line(from, to, Color(1.0, 0.82, 0.25, pulse), 3.0)
			canvas.draw_circle(to, 7.0, Color(1.0, 0.82, 0.25, pulse + 0.2))


## Телеграфы в локальных координатах врага (Enemy._draw вызывает под спрайтом).
func draw(canvas: Node2D) -> void:
	if pattern == "overlord" and _speakers_alive > 0:
		_draw_speaker_links(canvas)
	match state:
		State.BASS_WINDUP:
			var t := clampf(state_time / BASS_WINDUP_TIME, 0.0, 1.0)
			for speaker in speakers:
				if _is_speaker(speaker):
					var at := canvas.to_local(speaker.global_position)
					canvas.draw_arc(at, 50.0 + 120.0 * t, 0.0, TAU, 40, Color(TELEGRAPH, 0.3 + 0.6 * t), 5.0, true)
					canvas.draw_arc(at, 50.0, 0.0, TAU, 24, Color(1.0, 0.92, 0.35, 0.8), 3.0, true)
		State.CRANE_WINDUP:
			var t := clampf(state_time / CRANE_WINDUP_TIME, 0.0, 1.0)
			var head := Vector2(0.0, -enemy.data.radius * 3.4 * (1.0 - t * 0.35))
			_draw_magnet(canvas, head, t)
			canvas.draw_arc(Vector2.ZERO, CRANE_PULL_SPEED * 0.9 * (1.4 - t * 0.4), 0.0, TAU, 56, Color(MAGNET, 0.25 + 0.5 * t), 4.0, true)
		State.CRANE_PULL:
			var head := Vector2(0.0, -enemy.data.radius * 2.2)
			_draw_magnet(canvas, head, 1.0)
			if _pulled != null and is_instance_valid(_pulled):
				var target := canvas.to_local(_pulled.global_position)
				var flick := 0.5 + 0.5 * sin(state_time * 40.0)
				canvas.draw_line(head, target, Color(MAGNET, 0.35 + 0.4 * flick), 6.0)
				canvas.draw_line(head, target, Color(1, 1, 1, 0.5 * flick), 2.0)
				canvas.draw_arc(target, 44.0 + 10.0 * flick, 0.0, TAU, 24, Color(MAGNET, 0.9), 3.0, true)
		State.RING_CHARGE:
			var t := clampf(state_time / 0.8, 0.0, 1.0)
			canvas.draw_arc(Vector2.ZERO, enemy.data.radius * (1.1 + 0.9 * t), 0.0, TAU, 48, Color(TELEGRAPH, 0.35 + 0.5 * t), 6.0, true)
		State.LEAP_WINDUP:
			_draw_lane(canvas, _leap_from, _leap_dir, _leap_from.distance_to(_leap_to), clampf(state_time / LEAP_WINDUP_TIME, 0.0, 1.0), state_time >= LEAP_LOCK_TIME, 170.0)
		State.LEAP:
			var fade := clampf(1.0 - state_time / 0.5, 0.0, 1.0)
			_draw_lane(canvas, _leap_from, _leap_dir, _leap_from.distance_to(_leap_to), 1.0, true, 170.0, fade)
		State.STOMP_WINDUP:
			var t := clampf(state_time / 0.75, 0.0, 1.0)
			_draw_zone(canvas, Vector2.ZERO, 190.0, t)
		State.GATLING_SPIN:
			var t := clampf(state_time / 0.55, 0.0, 1.0)
			for index in [1, 2]:
				var from := canvas.to_local(enemy.part_muzzle(index))
				var to := canvas.to_local(enemy.target_point())
				canvas.draw_line(from, from.lerp(to, t), Color(TELEGRAPH, 0.25 + 0.5 * t), 3.0)
		State.SUMMON:
			var t := clampf(state_time / 0.7, 0.0, 1.0)
			for k in 3:
				canvas.draw_arc(Vector2.ZERO, enemy.data.radius * (1.2 + k * 0.5) * t, 0.0, TAU, 40, Color("#ffd257", 0.6 * (1.0 - t * 0.5)), 4.0, true)
		State.CARPET:
			for k in _shots_left:
				var at := canvas.to_local(_carpet_from + _carpet_dir * 110.0 * (8 - _shots_left + k + 1))
				_draw_zone(canvas, at, 92.0, clampf(state_time / 0.4, 0.3, 1.0))
		State.BEAM_WINDUP:
			var t := clampf(state_time / BEAM_WINDUP_TIME, 0.0, 1.0)
			_draw_strip(canvas, enemy.part_muzzle(0), _aim_dir, BEAM_LENGTH, BEAM_HALF_WIDTH, t, state_time >= BEAM_LOCK_TIME)
		State.PRESS_WINDUP:
			_draw_cone(canvas, enemy.global_position, _aim_dir, 0.5, 520.0, clampf(state_time / 0.6, 0.0, 1.0))
		State.VOMIT_WINDUP:
			_draw_cone(canvas, enemy.global_position, _aim_dir, 0.42, 480.0, clampf(state_time / 0.5, 0.0, 1.0))
		State.SMASH_WINDUP:
			_draw_lane(canvas, _leap_from, _leap_dir, 320.0, clampf(state_time / 0.75, 0.0, 1.0), state_time >= 0.4, SMASH_RANGE)
		State.SMASH_LUNGE:
			_draw_lane(canvas, _leap_from, _leap_dir, 320.0, 1.0, true, SMASH_RANGE, clampf(1.0 - state_time / 0.32, 0.0, 1.0))
		State.DASH_WINDUP:
			_draw_lane(canvas, _leap_from, _leap_dir, DASH_LENGTH, clampf(state_time / DASH_WINDUP_TIME, 0.0, 1.0), state_time >= DASH_LOCK_TIME, 0.0)
