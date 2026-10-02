class_name WaveDirector
extends Node
## Сценарий забега по главам (data/chapters.json): в каждой главе 10 волн, босс — только на 10-й.
##   INTRO (заголовок волны, спавна нет) → FIGHT (бюджет count врагов пачками — из ворот арены
##   или из-за края экрана) → «Волна очищена!» → INTERMISSION (передышка) → следующая волна.
## После победы над боссом — PORTAL: ждём, пока Енот войдёт в портал; Game перестраивает арену
## следующей главы и зовёт next_chapter(). После последней главы — снова первая, круг жёстче.
## Сложность растёт внутри главы с каждой волной (HP и урон врагов, темп спавна из JSON),
## а каждый новый круг умножает HP/урон/численность.

signal boss_spawned(boss: Enemy)
signal wave_started(number: int, title: String, mood: String, is_boss: bool)
signal wave_cleared(number: int)
signal intermission_tick(seconds_left: int)
signal chapter_cleared(chapter_index: int)

enum Phase { WAITING, INTRO, FIGHT, INTERMISSION, PORTAL }

const FIRST_WAVE_DELAY := 0.8
const INTRO_TIME := 1.2
const SPAWN_MARGIN := 90.0
const SPAWN_DEPTH := 260.0
const GATE_SHARE := 0.45
const AHEAD_SHARE := 0.5
const SPEAKER_RING := 170.0
const SPEAKER_HP_SHARE := 0.06
const PACK_SPREAD := 110.0
const GATE_MIN_DISTANCE := 520.0
const ESCORT_GAP := 60.0
const BOSS_RETRY_DELAY := 0.5
const WAVES_PER_CHAPTER := 10
## Отставшие враги (застряли, убежали далеко) переносятся ближе к Еноту — иначе волна может
## не закончиться из-за одной потерянной крысы.
const LEASH_DISTANCE := 1500.0
const LEASH_INTERVAL := 2.0
const STUCK_RELOCATE := 4.0
const BOSS_TARGET_TIME := 75.0
const BOSS_PORTAL_DELAY := 3.0
## Хвост волны: бюджет исчерпан, живых ≤ STALL_ALIVE и никто не погиб STALL_TIME секунд —
## оставшихся приводит к Еноту (за кадром), чтобы волна не висела из-за одной крысы за пропом.
const STALL_ALIVE := 3
const STALL_TIME := 9.0

var elapsed := 0.0
var story_mode := false
var story_mini := false
var wave_number := 0
## Боссы были слишком жирными: общий коэффициент здоровья (−10%).
const BOSS_HP_TRIM := 0.9
var boss: Enemy
var phase: Phase = Phase.WAITING
var remaining_to_spawn := 0
var chapter_index := 0
var loop := 0

var _enemies: EnemyManager
var _player: Player
var _level: LevelSpawner
var _chapter: Dictionary = {}
var _difficulty: Dictionary = {}
var _wave: Dictionary = {}
var _phase_time := FIRST_WAVE_DELAY
var _spawn_timer := 0.0
var _escort_timer := 0.0
var _boss_retry := 0.0
var _boss_pending := false
var _softlock_timer := 0.0
const SOFTLOCK_TIME := 15.0
var _boss_dead_time := -1.0
var _hp_mult := 1.0
var _dmg_mult := 1.0
var _interval := 1.0
var _max_alive := 10
var _last_tick := -1
var _leash_timer := LEASH_INTERVAL
var _stall_timer := 0.0
var _stall_count := -1
var _stalled := false


func setup(enemies: EnemyManager, player: Player, level: LevelSpawner) -> void:
	_enemies = enemies
	_player = player
	_level = level
	_difficulty = ContentDB.get_difficulty()
	_chapter = ContentDB.get_chapter(0)


func attach_level(level: LevelSpawner) -> void:
	_level = level


func get_damage_mult() -> float:
	return _dmg_mult


func get_hp_mult() -> float:
	return _hp_mult


## Сколько врагов волны ещё не побеждено (живые + не вышедшие).
func get_enemies_left() -> int:
	return remaining_to_spawn + _enemies.get_active_count() + (1 if _boss_pending else 0)


## Босс убит: новых врагов больше не будет, через BOSS_PORTAL_DELAY открывается портал.
func on_boss_killed() -> void:
	boss = null
	_boss_pending = false
	if is_mini_wave():
		return
	remaining_to_spawn = 0
	_boss_dead_time = 0.0


func is_boss_wave() -> bool:
	return String(_wave.get("boss", "")) != ""


## Мини-босс посреди главы: выходит в начале волны, портал не открывает.
func is_mini_wave() -> bool:
	return story_mini or String(_wave.get("miniboss", "")) != ""


func _boss_key() -> String:
	var key := String(_wave.get("boss", ""))
	return key if not key.is_empty() else String(_wave.get("miniboss", ""))


## Номер волны внутри главы (1…10).
func chapter_wave() -> int:
	return (maxi(wave_number, 1) - 1) % WAVES_PER_CHAPTER + 1


func current_chapter() -> Dictionary:
	return _chapter


## Портал пройден: Game уже построил арену главы; первая волна главы — после короткой паузы.
func next_chapter() -> void:
	_boss_dead_time = -1.0
	phase = Phase.WAITING
	_phase_time = FIRST_WAVE_DELAY + 0.6
	boss = null


func _physics_process(delta: float) -> void:
	if story_mode or _player == null or _player.is_dead or _chapter.is_empty():
		return
	if phase != Phase.PORTAL:
		elapsed += delta
	match phase:
		Phase.WAITING:
			_phase_time -= delta
			if _phase_time <= 0.0:
				_start_wave(wave_number + 1)
		Phase.INTRO:
			_phase_time -= delta
			if _phase_time <= 0.0:
				phase = Phase.FIGHT
				_spawn_timer = 0.0
				_boss_pending = is_boss_wave() or is_mini_wave()
		Phase.FIGHT:
			_tick_boss(delta)
			_tick_spawns(delta)
			_tick_stall(delta)
			_tick_softlock(delta)
			_tick_leash(delta)
			if _boss_dead_time >= 0.0:
				_boss_dead_time += delta
			var boss_finished := _boss_dead_time >= BOSS_PORTAL_DELAY
			if boss_finished or (remaining_to_spawn <= 0 and not _boss_pending and _enemies.get_active_count() == 0):
				wave_cleared.emit(wave_number)
				if is_boss_wave():
					phase = Phase.PORTAL
					_boss_dead_time = -1.0
					chapter_cleared.emit(chapter_index)
				else:
					phase = Phase.INTERMISSION
					_phase_time = float(_difficulty["intermission"])
					_last_tick = -1
		Phase.INTERMISSION:
			_phase_time -= delta
			var seconds := int(ceil(_phase_time))
			if seconds != _last_tick and seconds > 0:
				_last_tick = seconds
				intermission_tick.emit(seconds)
			if _phase_time <= 0.0:
				_start_wave(wave_number + 1)


func _start_wave(number: int) -> void:
	wave_number = number
	var chapters := ContentDB.get_chapters().size()
	var chapter_number := (number - 1) / WAVES_PER_CHAPTER
	chapter_index = chapter_number % maxi(chapters, 1)
	loop = chapter_number / maxi(chapters, 1)
	_chapter = ContentDB.get_chapter(chapter_index)
	var waves: Array = _chapter.get("waves", [])
	var index := mini(chapter_wave() - 1, waves.size() - 1)
	_wave = waves[index]
	var step := float(chapter_wave() - 1)
	var d := _difficulty
	var power := float(_chapter.get("power", 1.0))
	_hp_mult = (1.0 + float(d["hp_per_wave"]) * step) * pow(float(d["loop_hp"]), loop) * power
	_dmg_mult = (1.0 + float(d["damage_per_wave"]) * step) * pow(float(d["loop_damage"]), loop) * pow(power, 0.6)
	# Дальше 20-й волны герои «выходят на плато» (потолки бонусов), поэтому враги продолжают расти сами, а не только по кругам.
	var late := maxf(float(number) - float(d["late_start"]), 0.0)
	_hp_mult *= 1.0 + late * float(d["late_hp"])
	_dmg_mult *= 1.0 + late * float(d["late_damage"])
	remaining_to_spawn = int(ceil(float(_wave["count"]) * pow(float(d["loop_count"]), loop) * float(_chapter.get("count_mult", 1.0))))
	_interval = maxf(float(_wave["spawn_interval"]) * pow(float(d["loop_interval"]), loop), 0.25)
	_max_alive = int(_wave["max_alive"]) + int(d["loop_max_alive"]) * loop
	_boss_pending = false
	phase = Phase.INTRO
	_phase_time = INTRO_TIME
	var title: String = _wave["title"]
	if loop > 0:
		title = "%s · круг %d" % [title, loop + 1]
	wave_started.emit(number, title, String(_wave["mood"]), is_boss_wave())


func _tick_spawns(delta: float) -> void:
	if remaining_to_spawn <= 0:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _interval
	var weights: Dictionary = _wave["weights"]
	if weights.is_empty():
		remaining_to_spawn = 0
		return
	var radius := _offscreen_radius()
	var batch: Array[EnemyData] = []
	for i in int(_wave["batch"]):
		if remaining_to_spawn - batch.size() <= 0 or _enemies.get_active_count() + batch.size() >= _max_alive:
			break
		var data := ContentDB.get_enemy(_pick_weighted(weights))
		if data != null:
			batch.append(data)
	if batch.is_empty():
		return
	var ranged := 0
	var clearance := 20.0
	for data in batch:
		if data.behavior == EnemyData.Behavior.RANGED:
			ranged += 1
		clearance = maxf(clearance, data.radius * 1.4 + 6.0)
	var anchor := _pick_pack_anchor(radius, clearance, ranged * 2 > batch.size())
	if anchor == Vector2.INF:
		return
	for i in batch.size():
		var data := batch[i]
		var at := anchor
		if i > 0:
			at = _level.find_spawn_point(anchor, 30.0, PACK_SPREAD, clearance)
			if at == Vector2.INF:
				continue
		if _enemies.spawn(data, at, _hp_mult, _dmg_mult) != null:
			remaining_to_spawn -= 1


## Волна приходит стаей: одна точка, вокруг неё группа. Стрелки заходят дальше и с более открытых мест,
## бойцы — из ворот и по ходу движения Енота, чтобы давление шло спереди, а не из-за спины.
func _pick_pack_anchor(radius: float, clearance: float, ranged_pack: bool) -> Vector2:
	var from := _player.global_position
	var ring := radius * (1.25 if ranged_pack else 1.0)
	if not ranged_pack and randf() < GATE_SHARE:
		var gate := _level.gate_spawn_point(from, GATE_MIN_DISTANCE, clearance)
		if gate != Vector2.INF:
			return gate
	if _player.velocity.length() > 60.0 and randf() < AHEAD_SHARE:
		var ahead := from + _player.velocity.normalized() * ring * 0.55
		for attempt in 4:
			var p := _level.find_spawn_point(ahead, ring * 0.55, ring * 0.55 + SPAWN_DEPTH, clearance)
			if p != Vector2.INF and p.distance_to(from) >= ring:
				return p
	return _level.find_spawn_point(from, ring, ring + SPAWN_DEPTH, clearance)


## Босс выходит на свой помост; эскорт подводится из ворот по таймеру главы.
func _tick_boss(delta: float) -> void:
	if _boss_pending:
		_boss_retry -= delta
		if _boss_retry > 0.0:
			return
		if _boss_key().is_empty():
			Platform.send_report("softlock", "boss pending without key wave=%d chapter=%d phase=%d" % [wave_number, chapter_index, phase])
			_boss_pending = false
			return
		var boss_data := ContentDB.get_enemy(StringName(_boss_key()))
		if boss_data == null:
			Platform.send_report("softlock", "boss data missing wave=%d key='%s'" % [wave_number, _boss_key()])
			_boss_pending = false
			return
		var boss_hp := pow(float(_difficulty["loop_hp"]), loop) * float(_chapter.get("power", 1.0)) * _adaptive_boss_mult(boss_data) * BOSS_HP_TRIM * (1.0 + maxf(float(wave_number) - float(_difficulty["late_start"]), 0.0) * float(_difficulty["late_hp"]))
		boss = _enemies.spawn(boss_data, _level.boss_point, boss_hp, _dmg_mult)
		if boss == null:
			_boss_retry = BOSS_RETRY_DELAY
			return
		_boss_pending = false
		_escort_timer = 4.0
		boss_spawned.emit(boss)
		return

	if boss != null and (boss.data == null or not boss.data.is_boss()):
		boss = null
	if boss == null or not boss.is_alive():
		return
	var escort: Dictionary = _chapter.get("escort", {})
	if escort.is_empty():
		return
	_escort_timer -= delta
	if _escort_timer > 0.0:
		return
	_escort_timer = float(escort.get("interval", 7.0)) * (0.7 if boss.hp < boss.max_hp * 0.5 else 1.0)
	var escort_data := ContentDB.get_enemy(StringName(escort.get("enemy", "rat_punk")))
	if escort_data == null:
		return
	for i in int(escort.get("count", 3)):
		if _enemies.get_active_count() >= _max_alive + 6:
			return
		var at := _level.gate_spawn_point(_player.global_position, 300.0, escort_data.radius)
		if at == Vector2.INF:
			var ring := boss.data.radius + ESCORT_GAP
			at = _level.find_spawn_point(boss.global_position, ring, ring + 140.0, escort_data.radius)
		if at != Vector2.INF:
			_enemies.spawn(escort_data, at, _hp_mult, _dmg_mult)


## Босс не должен таять за 15 секунд у раскачанного Енота: половина запаса HP подстраивается
## под текущий урон в секунду так, чтобы бой длился около BOSS_TARGET_TIME. Прокачка всё равно
## ускоряет бой — растёт только вторая половина.
func _adaptive_boss_mult(boss_data: EnemyData) -> float:
	if boss_data == null or _player == null:
		return 1.0
	var w := _player.weapon_controller.weapon
	if w == null:
		return 1.0
	var dps := w.damage * w.projectiles_per_shot / maxf(w.fire_interval, 0.02) * (1.0 + w.crit_chance * (w.crit_mult - 1.0))
	dps *= 1.0 + 0.35 * w.ricochet_count + (0.4 if w.piercing else 0.0)
	var wanted := dps * BOSS_TARGET_TIME / maxf(boss_data.max_hp, 1.0)
	return clampf(0.5 + 0.5 * wanted, 1.0, 4.0)


## Призыв босса: подручные текущей волны вокруг него (не больше лимита живых).
func summon_minions(count: int) -> void:
	if boss == null or not boss.is_alive():
		return
	var weights: Dictionary = _wave.get("weights", {})
	var escort: Dictionary = _chapter.get("escort", {})
	for i in count:
		if _enemies.get_active_count() >= _max_alive + 8:
			return
		var id := StringName(escort.get("enemy", "rat_punk"))
		if not weights.is_empty() and randf() < 0.6:
			id = _pick_weighted(weights)
		var data := ContentDB.get_enemy(id)
		if data == null:
			continue
		var ring := boss.data.radius + ESCORT_GAP
		var at := _level.find_spawn_point(boss.global_position, ring, ring + 160.0, data.radius)
		if at != Vector2.INF:
			_enemies.spawn(data, at, _hp_mult, _dmg_mult)


## Колонки трона Короля Хлама: стоят вокруг босса, HP — доля от HP босса.
func spawn_speakers(count: int) -> Array[Enemy]:
	var list: Array[Enemy] = []
	if boss == null or not boss.is_alive():
		return list
	var data := ContentDB.get_enemy(&"throne_speaker")
	if data == null:
		return list
	var base := randf() * TAU
	for i in count:
		var angle := base + TAU * float(i) / count
		var ring := boss.data.radius + SPEAKER_RING
		var want := boss.global_position + Vector2.from_angle(angle) * ring
		var at := _level.find_spawn_point(want, 0.0, 120.0, data.radius)
		if at == Vector2.INF:
			continue
		var speaker := _enemies.spawn(data, at, 1.0, 1.0)
		if speaker == null:
			continue
		speaker.max_hp = boss.max_hp * SPEAKER_HP_SHARE
		speaker.hp = speaker.max_hp
		list.append(speaker)
	return list


## Страховка от вечной волны: на арене никого, а «остались» враги или босс, и они не появляются 15 секунд.
func _tick_softlock(delta: float) -> void:
	if _enemies.get_active_count() > 0 or (remaining_to_spawn <= 0 and not _boss_pending):
		_softlock_timer = 0.0
		return
	_softlock_timer += delta
	if _softlock_timer < SOFTLOCK_TIME:
		return
	_softlock_timer = 0.0
	Platform.send_report("softlock", "wave=%d left_to_spawn=%d boss_pending=%s player=%s" % [wave_number, remaining_to_spawn, _boss_pending, str(_player.global_position)])
	remaining_to_spawn = 0
	_boss_pending = false


func _tick_stall(delta: float) -> void:
	var alive := _enemies.get_active_count() - (1 if boss != null and boss.is_alive() else 0)
	if remaining_to_spawn > 0 or alive <= 0 or alive > STALL_ALIVE or alive != _stall_count:
		_stall_count = alive
		_stall_timer = 0.0
		return
	_stall_timer += delta
	if _stall_timer >= STALL_TIME:
		_stall_timer = 0.0
		_stalled = true
		_leash_timer = 0.0


func _tick_leash(delta: float) -> void:
	_leash_timer -= delta
	if _leash_timer > 0.0:
		return
	_leash_timer = LEASH_INTERVAL
	var radius := _offscreen_radius()
	for enemy in _enemies.get_active():
		if enemy == boss or not enemy.is_alive():
			continue
		var dist := enemy.global_position.distance_to(_player.global_position)
		var far := dist > radius * 0.75
		var stuck := (_level.cell_type(_level.world_to_cell(enemy.global_position)) == LevelSpawner.CellType.WALL and not enemy.data.flying) \
			or (far and (enemy.stuck_time > STUCK_RELOCATE or _stalled))
		if not stuck and dist < LEASH_DISTANCE:
			continue
		var at := _level.find_spawn_point(_player.global_position, radius, radius + SPAWN_DEPTH, enemy.data.radius)
		if at != Vector2.INF:
			enemy.global_position = at
			enemy.velocity = Vector2.ZERO
			enemy.stuck_time = 0.0
	_stalled = false


func _pick_weighted(weights: Dictionary) -> StringName:
	if weights.is_empty():
		return &"rat_punk"
	var total := 0.0
	for key in weights:
		total += weights[key]
	var roll := randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return StringName(key)
	return StringName(weights.keys().back())


func _offscreen_radius() -> float:
	var zoom := 1.0 if Orient.portrait else BattleBase.LANDSCAPE_ZOOM
	return get_viewport().get_visible_rect().size.length() * 0.5 / zoom + SPAWN_MARGIN
