class_name BattleBase
extends Node2D
## Общая основа боевых режимов (Свалка и Налёт): игрок, камера, HUD, атмосфера, пауза,
## «сочность» (тряска, hitstop, отдача камеры, вспышки дула), взрывы, рывок, очистка.
## Режим-наследник строит арену и сценарий, затем вызывает _setup_common() и переопределяет
## хуки _on_player_died / _update_hud_timer / _run_summary_lines.
## BulletPool и SoundManager — автолоады и переживают бой, поэтому в _exit_tree их чистим.

signal exit_requested
signal restart_requested

const CAMERA_SMOOTHING := 9.0
const HIST_STEP := 5.0
const HIST_MAX := 24
const SHOT_STEP := 30.0
const ADAPT_WINDOW := 5.0
const ADAPT_FPS := 38.0
const ADAPT_MAX := 4
## Первые секунды боя (прогрев шейдеров и загрузка) FPS всегда низкий: не реагируем на них.
const ADAPT_WARMUP := 25.0
## Сколько окон подряд FPS должен быть ниже порога, чтобы снизить качество.
const ADAPT_STRIKES := 2
const ADAPT_HARD_FPS := 26.0
const PERF_SAMPLE_FRAMES := 1500
const SPIKE_MS := 140.0
const MAX_SPIKE_REPORTS := 3
const MAX_PERF_REPORTS := 10
const HITSTOP_SCALE := 0.05
const HITSTOP_COOLDOWN := 0.12
const CAMERA_KICK_DECAY := 16.0

const HIT_FX_PER_SEC := 45.0
const HIT_FX_BURST := 10.0
const MUZZLE_FLASH_GAP := 0.06
var _hit_fx_budget := HIT_FX_BURST
var _fx_scale := 1.0
var _flash_cd := 0.0
var stats := RunStats.new()
var finished := false

var layers: BiomeLayers
var entities: Node2D
var player: Player
var fx: FxManager
var hero_skills: HeroSkills
var _perf_last_usec := 0
var _perf_frames: PackedFloat32Array = PackedFloat32Array()
var _perf_age := 0.0
var _adapt_strikes := 0
var _perf_resume_guard := 0
var _context_timer := 0.0
var _spikes_sent := 0
static var _perfs_sent := 0
const LANDSCAPE_ZOOM := 1.3
var _hist_timer := 0.0
var _shot_timer := 20.0
var _fps_hist: Array[int] = []
var _adapt_time := 0.0
var _adapt_frames := 0
var meta_enabled := true
var _adapt_level := 0
var camera: Camera2D
var hud: Hud
var atmosphere: AtmosphereFX

var _shake := 0.0
var _hud_timer := 0.0
var _kick := Vector2.ZERO
var _hitstop_ready_ms := 0
var _hitstop_active := false


## Стек слоёв по паспорту: пол (z -10), декали (z -5), мир с Y-Sort (z 0), FX (z 10).
func _build_layers() -> BiomeLayers:
	layers = BiomeLayers.new()
	add_child(layers)
	entities = layers.world
	fx = FxManager.new()
	layers.fx.add_child(fx)
	fx.attach_ground(layers.decals)
	return layers


func _spawn_player(at: Vector2, weapon: WeaponData, target_finder: Callable) -> void:
	player = Player.new()
	player.position = at
	player.fx = fx
	var hero := SaveService.get_character_id()
	var hero_level := SaveService.get_hero_level(hero) - 1 if meta_enabled else 0
	var meta := 1.0 if meta_enabled else 0.0
	player.bonus_max_hp = SaveService.get_perk_bonus("stamina") * meta + Player.BASE_MAX_HP * (CharacterDB.get_stat(hero, "hp") + SaveService.HERO_HP_PER_LEVEL * hero_level)
	player.armor = SaveService.get_perk_bonus("armor") * meta
	player.vest = int(SaveService.get_perk_bonus("vest") * meta)
	player.dash_cooldown_mult = 1.0 + CharacterDB.get_stat(hero, "dash")
	stats.add_flat(&"damage_mult", SaveService.get_perk_bonus("power") * meta + SaveService.HERO_DAMAGE_PER_LEVEL * hero_level)
	stats.add_flat(&"crit_chance_add", SaveService.get_perk_bonus("eye") * meta)
	stats.add_flat(&"move_speed_mult", SaveService.get_perk_bonus("boots") * meta)
	stats.add_flat(&"magnet_mult", SaveService.get_perk_bonus("magnet") * meta)
	stats.add_flat(&"drone_count", SaveService.get_perk_bonus("drone") * meta)
	stats.add_flat(&"move_speed_mult", CharacterDB.get_stat(hero, "speed"))
	stats.add_flat(&"crit_chance_add", CharacterDB.get_stat(hero, "crit"))
	match hero:
		"raccoon":
			stats.add_flat(&"magnet_mult", 0.5)
		"red_panda":
			stats.add_flat(&"burn_chance", 0.25)
		"night":
			stats.add_flat(&"crit_chance_add", 0.1)
		"neon_hopper":
			stats.add_flat(&"fire_rate_mult", 0.12)
		"fluffy_chemist":
			stats.add_flat(&"poison_chance", 0.2)
			stats.add_flat(&"poison_power", 0.3)
	entities.add_child(player)
	player.setup(target_finder, weapon, stats)
	player.visual.apply_look(SaveService.get_character(), SaveService.get_skin())
	var tag := NameTag.new()
	tag.text = SaveService.get_display_nickname()
	player.add_child(tag)


func _setup_common(camera_bounds: Rect2, currency_icon: Texture2D) -> void:
	Platform.mark_battle(true, "%s q=%d lite=%s" % [get_script().get_global_name(), SaveService.get_quality(), SaveService.is_fx_lite()])
	get_tree().create_timer(15.0, false).timeout.connect(Platform.mark_battle.bind(false))
	SoftGlow.lite = SaveService.is_fx_lite()
	_fx_scale = 0.5 if SoftGlow.lite else 1.0
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = CAMERA_SMOOTHING
	camera.position = player.position
	add_child(camera)
	_apply_camera_zoom()
	get_window().size_changed.connect(_apply_camera_zoom)
	set_camera_bounds(camera_bounds)
	camera.make_current()
	camera.reset_smoothing()

	atmosphere = AtmosphereFX.new()
	add_child(atmosphere)
	atmosphere.build(self)

	hud = Hud.new()
	add_child(hud)
	hud.build(currency_icon, player.weapon_controller.base_weapon)

	player.health_changed.connect(hud.set_health)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.dashed.connect(_on_player_dashed)
	player.weapon_controller.fired.connect(_on_player_fired)
	player.weapon_controller.melee.swing_started.connect(_on_melee_swing)
	player.weapon_controller.melee.hit_resolved.connect(_on_melee_hit)
	player.weapon_controller.weapon_changed.connect(hud.set_weapon)
	BulletPool.bullet_hit.connect(_on_bullet_hit)
	BulletPool.exploded.connect(_on_explosion)
	hud.dash_pressed.connect(_request_dash)
	hud.skill_pressed.connect(_request_dash)
	hero_skills = HeroSkills.new()
	add_child(hero_skills)
	hero_skills.setup(SaveService.get_character_id(), player, fx, stats, add_shake)
	hud.set_skill(hero_skills.title() if hero_skills.has_skill() else "", Color(str(hero_skills.skill.get("color", "#ffcf3d"))))
	hud.pause_pressed.connect(_open_pause)
	hud.resume_pressed.connect(_close_pause)
	hud.restart_pressed.connect(func() -> void: restart_requested.emit())
	hud.menu_pressed.connect(_on_menu_pressed)
	hud.upgrade_pressed.connect(func() -> void:
		MainMenuUI.open_upgrades_next = true
		_on_menu_pressed())
	hud.set_health(player.hp, player.max_hp)


func _apply_camera_zoom() -> void:
	var z := 1.0 if Orient.portrait else LANDSCAPE_ZOOM
	camera.zoom = Vector2(z, z)


func set_camera_bounds(bounds: Rect2) -> void:
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)


func _exit_tree() -> void:
	Platform.mark_battle(false)
	if BulletPool.bullet_hit.is_connected(_on_bullet_hit):
		BulletPool.bullet_hit.disconnect(_on_bullet_hit)
	if BulletPool.exploded.is_connected(_on_explosion):
		BulletPool.exploded.disconnect(_on_explosion)
	BulletPool.release_all()
	BulletPool.clear_enemy_tint()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	Engine.time_scale = 1.0
	SaveService.apply_quality()
	Platform.take_snapshot()
	get_tree().paused = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_perf_last_usec = 0
		_perf_resume_guard = 2


func _process(delta: float) -> void:
	if _perf_resume_guard > 0:
		_perf_resume_guard -= 1
		_perf_last_usec = 0
		return
	if get_tree().paused:
		_perf_last_usec = 0
		return
	var now := Time.get_ticks_usec()
	if _perf_last_usec > 0:
		var ms := (now - _perf_last_usec) / 1000.0
		_perf_frames.append(ms)
		if ms > SPIKE_MS and _spikes_sent < MAX_SPIKE_REPORTS and _perf_age > 5.0:
			_spikes_sent += 1
			Platform.send_report("spike", "%.0f ms | %s" % [ms, _perf_context()])
	_perf_last_usec = now
	_perf_age += delta
	_adapt_quality(delta)
	_history_tick(delta)
	_context_timer -= delta
	if _context_timer <= 0.0:
		_context_timer = 4.0
		Platform.set_context(_perf_context())
	if _perf_frames.size() >= PERF_SAMPLE_FRAMES:
		_send_perf_report()


func _perf_context() -> String:
	return "%s hero=%s weapon=%s nick=%s q=%d lite=%s t=%.0fs fps=%d frame=%.1fms nodes=%d objs=%d draws=%d vram=%dMB heap=%dMB %s" % [
		get_script().get_global_name(), SaveService.get_character_id(), SaveService.get_selected_weapon(), SaveService.get_nickname(),
		SaveService.get_quality(), SaveService.is_fx_lite(), _perf_age, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(OS.get_static_memory_usage() / 1048576.0), _extra_context() + " fpshist=" + ",".join(_fps_hist.map(str))]


## Динамическое качество: если 5 секунд подряд средний FPS ниже порога — упрощаем эффекты, затем снижаем разрешение холста.
## Изменения действуют только в этом бою; настройки игрока не трогаем. На «Красиво» разрешение и FPS не снижаются: игрок выбрал максимум сам.
func _adapt_quality(delta: float) -> void:
	if _perf_age < ADAPT_WARMUP or _adapt_level >= ADAPT_MAX:
		return
	_adapt_time += delta
	_adapt_frames += 1
	if _adapt_time < ADAPT_WINDOW:
		return
	var fps := _adapt_frames / _adapt_time
	_adapt_time = 0.0
	_adapt_frames = 0
	if fps >= (ADAPT_FPS if _adapt_level < 2 else ADAPT_HARD_FPS):
		_adapt_strikes = 0
		return
	_adapt_strikes += 1
	if _adapt_strikes < ADAPT_STRIKES:
		return
	_adapt_strikes = 0
	_adapt_level += 1
	if SaveService.get_quality() >= 2 and _adapt_level != 1:
		return
	match _adapt_level:
		1:
			_fx_scale = 0.5
			SoftGlow.lite = true
		2:
			Platform.set_render_cap(1.0)
		3:
			_fx_scale = 0.25
			Engine.max_fps = 30
		_:
			Platform.set_render_cap(0.7)
	Platform.note_event("adapt level %d at fps %.0f" % [_adapt_level, fps])
	Platform.send_report("adapt", "level %d fps %.0f | %s" % [_adapt_level, fps, _perf_context()])


## История FPS раз в 5 секунд и уменьшенный снимок экрана раз в 30: снимок лежит в localStorage и уходит в отчёт только после вылета.
func _history_tick(delta: float) -> void:
	_hist_timer += delta
	if _hist_timer >= HIST_STEP:
		_hist_timer = 0.0
		_fps_hist.append(int(Engine.get_frames_per_second()))
		if _fps_hist.size() > HIST_MAX:
			_fps_hist.remove_at(0)
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_shot_timer = SHOT_STEP
		_store_snapshot()


func _store_snapshot() -> void:
	if not Platform.is_web or get_tree().paused:
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.resize(256, int(256.0 * image.get_height() / image.get_width()), Image.INTERPOLATE_NEAREST)
	Platform.store_snapshot(Marshalls.raw_to_base64(image.save_jpg_to_buffer(0.5)))


func _extra_context() -> String:
	return ""


func _send_perf_report() -> void:
	var sorted := Array(_perf_frames)
	_perf_frames.clear()
	sorted.sort()
	var total := 0.0
	for ms: float in sorted:
		total += ms
	var avg_ms := total / sorted.size()
	var worst_ms: float = sorted[int(sorted.size() * 0.99)]
	if _perfs_sent < MAX_PERF_REPORTS:
		_perfs_sent += 1
		Platform.send_report("perf", "fps avg %.0f, 1%% low %.0f | %s | %s" % [1000.0 / avg_ms, 1000.0 / worst_ms, _perf_context(), Platform.device_info()])


func _physics_process(delta: float) -> void:
	if player == null or hud == null:
		return
	_hit_fx_budget = minf(_hit_fx_budget + delta * HIT_FX_PER_SEC * _fx_scale, HIT_FX_BURST)
	_flash_cd = maxf(_flash_cd - delta, 0.0)
	var input := hud.joystick.output
	if not hud.joystick.is_active():
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	player.move_input = input
	camera.global_position = player.global_position
	hud.set_dash_cooldown(player.dash_fraction())
	hud.set_skill_cooldown(hero_skills.fraction())
	hud.set_dash_charges(player.dash_charges, player.dash_max_charges)

	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
		_update_hud_timer()
	_update_shake(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"dash"):
		_request_dash()
	elif event.is_action_pressed(&"ui_cancel") and not finished:
		_open_pause()


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


## Микропауза (hitstop) 30–60 мс: мир почти замирает, таймер идёт по реальному времени.
## Частые убийства не «залипают»: между стопами минимум HITSTOP_COOLDOWN.
func hitstop(duration: float) -> void:
	if finished or _hitstop_active or get_tree().paused:
		return
	var now := Time.get_ticks_msec()
	if now < _hitstop_ready_ms:
		return
	_hitstop_active = true
	_hitstop_ready_ms = now + int((duration + HITSTOP_COOLDOWN) * 1000.0)
	Engine.time_scale = HITSTOP_SCALE
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		_hitstop_active = false
		Engine.time_scale = 1.0)


## Хук: обновить таймер в HUD (вызывается 10 раз в секунду).
func _update_hud_timer() -> void:
	pass


## Хук: енот погиб.
func _on_player_died() -> void:
	pass


## Хук: строки статистики для окна паузы.
func _run_summary_lines() -> PackedStringArray:
	return PackedStringArray()


func _show_result(victory: bool, lines: PackedStringArray, title: String = "") -> void:
	finished = true
	Engine.time_scale = 1.0
	get_tree().paused = true
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	SoundManager.play(&"victory" if victory else &"defeat", 0.0, false)
	hud.show_result(victory, lines, title)


func _update_shake(delta: float) -> void:
	_kick = _kick.lerp(Vector2.ZERO, clampf(CAMERA_KICK_DECAY * delta, 0.0, 1.0))
	if _shake <= 0.0:
		camera.offset = _kick
		return
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var power := _shake * _shake * 18.0
	camera.offset = _kick + Vector2(randf_range(-power, power), randf_range(-power, power))


func _request_dash() -> void:
	if player == null or finished or get_tree().paused or RunMods.has(&"no_dash"):
		return
	if hero_skills != null and hero_skills.has_skill():
		hero_skills.try_use()
	else:
		player.request_dash()



func _open_pause() -> void:
	if finished or get_tree().paused:
		return
	get_tree().paused = true
	hud.show_pause(_run_summary_lines())


func _close_pause() -> void:
	get_tree().paused = false


## Выход в меню из паузы/результата. Наследник может сперва записать итоги забега.
func _on_menu_pressed() -> void:
	exit_requested.emit()


func _on_bullet_hit(bullet: Bullet, target: Node2D) -> void:
	if bullet.weapon == null:
		return
	var color := bullet.weapon.effect_color
	var crit := bullet.last_hit_crit
	if bullet.team == Bullet.Team.PLAYER:
		SoundManager.play(&"hit")
		if crit:
			fx.ring(bullet.global_position, Color("#ffb347"), 26.0)
			hitstop(0.035)
	# При плотном огне частицы попаданий идут по бюджету в секунду: 100 пуль/с не должны рождать 100 вспышек.
	if _hit_fx_budget < 1.0 and not crit:
		return
	_hit_fx_budget -= 1.0
	var dense := BulletPool.get_lod() > 0
	if bullet.team == Bullet.Team.PLAYER:
		var impact_tex := WeaponVfx.impact_for(bullet.weapon)
		if impact_tex != null:
			fx.sprite_flash(impact_tex, bullet.global_position, WeaponVfx.impact_width(bullet.weapon) * (1.25 if crit else 1.0), 0.14)
	if bullet.weapon.id == &"beer_jet_v1" or bullet.weapon.id == &"puke_v1":
		fx.burst_dir(bullet.global_position, -bullet.velocity.normalized(), color, 7, 1.1, 300.0, 3.5)
		fx.chunks(bullet.global_position, color.lightened(0.25), 3, 200.0, 3.0)
		return
	fx.burst_dir(bullet.global_position, -bullet.velocity.normalized(), color, 6 if crit else (2 if dense else 4), 0.8, 260.0, 3.0)
	if target is Enemy and not dense:
		fx.chunks(bullet.global_position, (target as Enemy).data.fx_color if (target as Enemy).data != null else color, 2, 140.0, 3.5)


func _on_melee_swing(weapon: WeaponData, origin: Vector2, direction: Vector2, _combo: int, heavy: bool, side: float) -> void:
	var slash := WeaponVfx.slash_for(weapon)
	if slash == null:
		return
	var reach := weapon.melee_reach * (1.15 if heavy else 1.0)
	fx.sprite_flash(slash, origin + direction * reach * 0.5, reach * 2.0, 0.16 + 0.03 * weapon.weight, direction.angle() + PI, Vector2(0.5, 0.5), side)


func _on_melee_hit(weapon: WeaponData, at: Vector2, count: int, finisher: bool, heavy: bool) -> void:
	var strong := finisher or heavy
	hitstop(0.025 + 0.012 * weapon.weight + (0.04 if strong else 0.0))
	add_shake(0.05 * weapon.weight + (0.15 if strong else 0.0) + 0.02 * mini(count, 4))
	if strong:
		fx.ring(at, weapon.effect_color, 70.0 + 14.0 * weapon.weight)


func _on_player_fired(weapon: WeaponData, origin: Vector2, direction: Vector2) -> void:
	if _flash_cd <= 0.0:
		_flash_cd = MUZZLE_FLASH_GAP / _fx_scale
		var flash_tex := WeaponVfx.muzzle_for(weapon)
		if flash_tex != null:
			fx.light_flash(origin, weapon.effect_color.lerp(Color("#fff2c0"), 0.4), 0.9, 150.0, 0.08)
			fx.sprite_flash(flash_tex, origin + direction * 2.0, WeaponVfx.muzzle_width(weapon), 0.09, direction.angle(), WeaponVfx.MUZZLE_PIVOT)
		else:
			fx.muzzle_flash(origin + direction * 4.0, direction.angle(), weapon.effect_color, 0.7 + 0.25 * weapon.recoil)
	_kick -= direction * 2.2 * weapon.recoil
	if weapon.recoil >= 1.8:
		add_shake(0.08 * weapon.recoil)


func _on_explosion(at: Vector2, radius: float, color: Color, _team: Bullet.Team) -> void:
	fx.light_flash(at, color.lerp(Color("#ffd27a"), 0.5), 1.8, radius * 2.6, 0.45)
	fx.burst(at, color, 26, 420.0, 5.0)
	fx.burst(at, Color("#fff2b0"), 14, 260.0, 4.0)
	fx.ring(at, color, radius)
	fx.chunks(at, Color("#3b3040"), 8, 260.0, 5.0)
	fx.splat(at, Color("#20141c"), radius * 0.55)
	fx.dust(at, 8, radius)
	SoundManager.play(&"explosion")
	add_shake(0.35 if player == null or player.global_position.distance_to(at) < 600.0 else 0.1)
	hitstop(0.04)


func _on_player_damaged(_amount: float) -> void:
	add_shake(0.4)
	fx.burst(player.global_position, UiStyle.DANGER, 10, 240.0, 3.5)
	atmosphere.flash(Color(1.0, 0.1, 0.15), 0.18, 0.25)
	atmosphere.hit_pulse(1.0)
	SoundManager.play(&"player_hurt")
	hitstop(0.05)


func _on_player_dashed() -> void:
	add_shake(0.06)


## round_up — для обратного отсчёта, чтобы «0:00» появлялось ровно в момент окончания.
static func format_time(seconds: float, round_up: bool = false) -> String:
	var s := maxi(int(ceil(seconds)) if round_up else int(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


## Ник над головой Енота, как в .io.
class NameTag:
	extends Node2D
	var text := ""

	func _ready() -> void:
		position = Vector2(0, -78)
		z_index = 5

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-120, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 20, 7, Color(0.06, 0.03, 0.1, 0.9))
		draw_string(font, Vector2(-120, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 20, Cosmetics.nick_color(Color(1, 1, 1, 0.95)))
