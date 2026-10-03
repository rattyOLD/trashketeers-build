class_name Game
extends BattleBase
## Основной режим: главы-арены по концепт-листам (Неоновая Свалка → Золотой Банк → круг
## заново жёстче), 10 волн в главе, босс — только на 10-й. После босса на его помосте
## открывается портал: Енот входит — арена перестраивается под следующую главу без смены сцены
## (уровень, стволы, прокачка забега сохраняются). Автострельба, прокачка 1-из-3, стволы из
## ящиков, возрождение за рекламу или неонит. Все пулы создаются в start() — до геймплея.

const ENEMY_CAPACITY := 90
const WEAPON_PICKUPS := 6
const XP_BASE := 5
const XP_STEP := 5
const ADRENALINE_TIME := 20.0
const ADRENALINE_FIRE := 0.35
const ADRENALINE_SPEED := 0.15
const WAVE_CLEAR_HEAL := 0.15
const PICKUP_COMBO_WINDOW := 0.45
const KILL_HITSTOP := 0.03
const BOSS_HITSTOP := 0.14
const LEVEL_UP_DELAY := 0.35
const DEATH_DELAY := 1.1
const WEAPON_SWAP_DELAY := 1.2
const TIER_CHANCE_BASE := 0.08
const TIER_CHANCE_PER_WAVE := 0.035
const REVIVE_HP := 0.6
const REVIVE_INVULN := 2.5
const REVIVE_BLAST := 260.0

var level := 1
var xp := 0
var kills := 0
var nuts := 0
var _start_cash := 0
var bosses_killed := 0
var run_loot: Array = []
## Награды боссов за забег: неонит и чертежи (зачисляются в record_run).
var run_gems := 0
var run_blueprints: Array = []
var revives_used := 0
var _damage_acc := {}
const DAMAGE_MERGE_TIME := 0.07

var map: LevelSpawner
var pickups: PickupManager
var enemies: EnemyManager
var director: WaveDirector
var minimap: Minimap
var events: MapEvents
var lobs: LobPool
var traps: MagnetTraps
const DAMAGE_NUMBERS_PER_SEC := 22.0
const REROLL_BASE_COST := 220.0
const DEATH_TIP_NEWBIE := 6
const DEATH_TIP_EVERY := 3
const DEATH_FAST_TIME := 100.0
const REROLL_GROWTH := 1.55
const QUICK_CLEAR_TIME := 10.0
const GOLD_CLEAR_TIME := 5.0
const CLEAN_SWEEP_MIN := 8
const CLEAN_SWEEP_RATIO := 0.35
const CLEAN_SWEEP_XP := 3
const QUICK_CLEAR_RATIO := 0.6
var _number_budget := 10.0
var status: StatusSystem
var _rail_combo := 0
var _rail_timer := 0.0
const RAIL_COMBO_WINDOW := 4.0
const RAIL_COMBO_MEGA := 25
var hazards: HazardDirector

var _pending_levelups := 0
var _level_up_open := false
var _rerolls_free := 0
var _current_bonus := false
var _rerolls_paid := 0
var _reroll_deal := false
var _loot_at_clear := 0
var _last_choices: Array[StringName] = []
var _bonus_choices := 0
var _drones: Array[JunkDrone] = []
var _arrow: TargetArrow
var _last_marker: LastEnemyMarker
var _weapon_pickups: Array[WeaponPickup] = []
var _adrenaline_left := ADRENALINE_TIME
var _combo := 0
## Серия убийств подряд (окно MULTI_WINDOW): на порогах — выкрик над енотом, звук и встряска.
const MULTI_WINDOW := 0.55
const MULTI_CALLS := {3: "ТРОЙНОЕ!", 5: "РЕЗНЯ!", 8: "МЯСОРУБКА!", 12: "АПОКАЛИПСИС!"}
var _multi := 0
## Для отчёта о забеге (баланс): здоровье в % на старте каждой волны и полученный урон по источникам.
var _wave_hp := PackedStringArray()
var _damage_by := {}
var _multi_left := 0.0
var _combo_timer := 0.0
var _recorded := false
var _portal: Portal
var story_mission := ""
var story: StoryRun
var radio: SurvivalRadio
var wanted: Wanted
var liquids: LiquidFx
var story_target: Node2D
var _switching := false
var _boss_started := 0.0


## Текстуры врагов главы грузятся под загрузочным экраном (или затемнением смены главы), а не при
## первом появлении крысы: синхронная загрузка листа посреди боя на телефоне — фриз до секунды.
## Только враги этой главы: все листы разом — лишние ~50 МБ видеопамяти на слабых телефонах.
static func warm_chapter(chapter: Dictionary) -> void:
	var ids := {}
	for wave: Dictionary in chapter.get("waves", []):
		for id in (wave.get("weights", {}) as Dictionary):
			ids[str(id)] = true
		for key in ["boss", "miniboss"]:
			if not str(wave.get(key, "")).is_empty():
				ids[str(wave[key])] = true
	if not str(chapter.get("boss", "")).is_empty():
		ids[str(chapter["boss"])] = true
	var escort: Dictionary = chapter.get("escort", {})
	if escort.has("enemy"):
		ids[str(escort["enemy"])] = true
	for id: String in ids:
		var data := ContentDB.get_enemy(StringName(id))
		if data == null:
			continue
		var _texture := data.texture
		var _attack := data.attack_texture
		if not data.frames_id.is_empty():
			var sheet := FrameDB.get_sheet(data.frames_id)
			for path in sheet.get("regions", PackedStringArray()):
				RigDB.data_texture(path)


func start(_weapon_id: StringName = &"") -> void:
	randomize()
	RunMods.clear()
	if story_mission.is_empty():
		RunMods.resolve()
		Enemy.mod_speed_mult = RunMods.ENEMY_SPEED if RunMods.has(&"fast_enemies") else 1.0
	for id in ContentDB.get_enemy_ids():
		var enemy_data := ContentDB.get_enemy(id)
		if enemy_data == null or not enemy_data.frames_id.is_empty():
			continue
		RigSprite.prewarm(enemy_data.rig_id, Enemy.RIG_MARGIN)
		for variant in enemy_data.rig_variants:
			RigSprite.prewarm(variant, Enemy.RIG_MARGIN)
	if story_mission.is_empty():
		warm_chapter(ContentDB.get_chapter(0))
	_build_layers()
	liquids = LiquidFx.new()
	layers.decals.add_child(liquids)
	map = LevelSpawner.new()
	layers.floor_layer.add_child(map)
	pickups = PickupManager.new()
	layers.decals.add_child(pickups)
	var chapter := ContentDB.get_chapter(0)
	if not story_mission.is_empty():
		chapter = StoryRun.map_chapter(ContentDB.get_chapter(StoryRun.base_chapter_index(story_mission)), story_mission)
	map.build(layers, chapter)

	meta_enabled = story_mission.is_empty()
	var loadout := SaveService.get_loadout()
	if not story_mission.is_empty() and SaveService.camp_has("shotgun"):
		loadout = WeaponDB.get_weapon(&"double_v1").with_tier(1)
	if not RunMods.only_shotguns(loadout):
		loadout = WeaponDB.get_weapon(RunMods.SHOTGUN_IDS[0]).with_tier(1)
	_spawn_player(map.player_start, loadout, _find_target)
	map.attach_player(player)
	enemies = EnemyManager.new()
	add_child(enemies)
	enemies.setup(player, entities, ENEMY_CAPACITY, map.nav_direction)
	pickups.setup(player)
	for i in WEAPON_PICKUPS:
		var pickup := WeaponPickup.new()
		pickup.setup(player)
		pickup.picked.connect(_on_weapon_picked)
		entities.add_child(pickup)
		_weapon_pickups.append(pickup)
	lobs = LobPool.new()
	lobs.fx = fx
	layers.fx.add_child(lobs)
	traps = MagnetTraps.new()
	traps.player = player
	layers.decals.add_child(traps)
	BulletPool.homing_target = player

	director = WaveDirector.new()
	add_child(director)
	director.setup(enemies, player, map)
	director.run_stats = stats
	director.story_mode = not story_mission.is_empty()

	_arrow = TargetArrow.new()
	layers.fx.add_child(_arrow)
	_last_marker = LastEnemyMarker.new()
	layers.fx.add_child(_last_marker)

	_setup_common(map.bounds, pickups.nut_texture)
	light_map.set_layout(map.layout)
	_last_marker.setup(director, enemies, camera)
	minimap = Minimap.new()
	minimap.setup(map, player, enemies, director)
	hud.set_minimap(minimap)
	if SaveService.is_glow_enabled() and not SaveService.is_fx_lite():
		add_child(_make_glow())
	_apply_chapter_look(chapter)

	hazards = HazardDirector.new()
	hazards.setup(player, director, map, fx)
	layers.decals.add_child(hazards)
	status = StatusSystem.new()
	status.setup(stats, player, enemies, fx)
	add_child(status)
	Enemy.status_sink = _on_enemy_status
	events = MapEvents.new()
	add_child(events)
	events.setup(player, director, enemies, map, pickups, fx, status, atmosphere, layers.decals)
	events.announced.connect(func(title: String, text: String, color: Color) -> void: hud.toast(title, text, color))
	minimap.events = events
	minimap.pickups = pickups
	events.loot_count.connect(hud.set_loot_left)
	events.event_started.connect(func(_kind: int) -> void: _reroll_deal = true)
	enemies.enemy_died.connect(_on_enemy_died)
	enemies.enemy_damaged.connect(_on_enemy_damaged)
	enemies.enemy_exploded.connect(_on_enemy_exploded)
	enemies.enemy_blocked.connect(_on_enemy_blocked)
	enemies.enemy_blinked.connect(_on_enemy_blinked)
	enemies.enemy_fx.connect(_on_enemy_fx)
	enemies.boss_phase.connect(_on_boss_phase)
	pickups.collected.connect(_on_nuts_collected)
	pickups.xp_collected.connect(_on_xp_collected)
	map.object_destroyed.connect(_on_object_destroyed)
	map.crate_landed.connect(_on_crate_landed)
	director.boss_spawned.connect(_on_boss_spawned)
	director.wave_started.connect(_on_wave_started)
	director.wave_cleared.connect(_on_wave_cleared)
	director.chapter_cleared.connect(_on_chapter_cleared)
	director.intermission_tick.connect(func(seconds: int) -> void: hud.show_countdown(seconds))
	hud.upgrade_chosen.connect(_on_upgrade_chosen)
	hud.reroll_requested.connect(_on_reroll_requested)
	_rerolls_free = 1 + int(SaveService.get_perk_bonus("reroll") * (1.0 if meta_enabled else 0.0)) + Premium.reroll_bonus()
	WeaponPickup.auto_pick = bool(Controls.get_value("auto_pick"))
	for pickup in _weapon_pickups:
		pickup.expired.connect(_on_pickup_expired)
	player.weapon_controller.slots_changed.connect(_refresh_slots)
	player.damaged.connect(func(amount: float) -> void:
		_damage_by[Player.last_source] = float(_damage_by.get(Player.last_source, 0.0)) + amount)
	hero_skills.used.connect(func(_id: String) -> void: player.weapon_controller.charge_overdrive())
	player.weapon_controller.overdrive_changed.connect(_on_overdrive_changed)
	player.weapon_controller.overdrive_fired.connect(_on_overdrive_fired)
	hud.slot_pressed.connect(_switch_slot)
	hud.orders_requested.connect(_open_orders)
	hud.interact_pressed.connect(_try_pick)
	hud.weapon_swiped.connect(_cycle_weapon)
	_refresh_slots()
	_apply_tester_flags()
	_apply_tester_start()
	hud.revive_requested.connect(_on_revive_requested)
	hud.revive_declined.connect(_finish)
	restart_requested.connect(func() -> void: _record())
	SaveService.achievement_unlocked.connect(_on_achievement)

	stats.add_flat(&"fire_rate_mult", ADRENALINE_FIRE)
	if RunMods.has(&"debt"):
		stats.add_flat(&"damage_mult", RunMods.DEBT_DAMAGE)
	player.set_speed_buff(ADRENALINE_SPEED)
	_apply_camp_pack()
	player.apply_run_stats(stats)
	hud.set_xp(xp, _xp_needed(level), level)
	hud.set_nuts(nuts)
	_apply_run_start_perks()
	hud.set_kills(kills)
	hud.set_time(0.0)
	hud.show_chapter(str(chapter.get("subtitle", "")), str(chapter.get("title", "")))
	if story_mission.is_empty():
		get_tree().create_timer(5.2, false).timeout.connect(func() -> void: hud.toast("АДРЕНАЛИН!", "+35% скорострельности и +15% скорости на 20 с", Color("#ff7a3d")))
		if RunMods.active != RunMods.NONE:
			hud.show_mod_badge(str(RunMods.info(RunMods.active)["title"]))
			get_tree().create_timer(3.0, false).timeout.connect(func() -> void: hud.toast("МОДИФИКАТОР: %s" % str(RunMods.info(RunMods.active)["title"]).to_upper(), "%s. Монеты ×%.1f" % [RunMods.info(RunMods.active)["desc"], RunMods.mult_of(RunMods.active)], Color("#ff9a3d")))
			SaveService.add_stat("mod_runs", 1, false)
	SoundManager.play_music(StringName(str(chapter.get("music", "battle"))))
	SoundManager.start_ambient()
	if story_mission.is_empty():
		radio = SurvivalRadio.new()
		add_child(radio)
		radio.setup(self, player)
		wanted = Wanted.new()
		add_child(wanted)
		wanted.setup(self)
		wanted.level_changed.connect(_on_wanted_level)
		wanted.chief_arrived.connect(radio.on_chief)
	if not story_mission.is_empty():
		story = StoryRun.new()
		add_child(story)
		if story.setup(self, story_mission):
			player.weapon_controller.slot_count = 1
			_refresh_slots()
			hud.set_story_mode()
			hud.set_story_layout(minimap)
			minimap.set_story(story)
			story.on_start()
			var resume := SaveService.story_resume(story_mission) if SaveService.resume_requested else {}
			SaveService.resume_requested = false
			if not resume.is_empty():
				story.resume_from(resume)
		else:
			story.queue_free()
			story = null


func _exit_tree() -> void:
	BossBrain.story_phases = false
	Enemy.status_sink = Callable()
	Enemy.global_speed_mult = 1.0
	Enemy.mod_speed_mult = 1.0
	RunMods.clear()
	if SaveService.achievement_unlocked.is_connected(_on_achievement):
		SaveService.achievement_unlocked.disconnect(_on_achievement)
	super._exit_tree()


## Приоритет автоприцела: ближайший враг, если его нет — ближайший разрушаемый объект.
var _target_nearest := bool(SaveService.data.get("target_nearest", false))


func _find_target(from: Vector2, max_distance: float) -> Node2D:
	var enemy := enemies.find_nearest(from, max_distance) if _target_nearest else enemies.find_priority(from, max_distance)
	if enemy != null:
		return enemy
	if story != null:
		var secret := story.nearest_secret(from, max_distance)
		if secret != null:
			return secret
	return map.find_nearest_destructible(from, max_distance)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _rail_combo > 0:
		_rail_timer -= delta
		if _rail_timer <= 0.0:
			_rail_combo = 0
			hud.set_rail_combo(0)
	_number_budget = minf(_number_budget + DAMAGE_NUMBERS_PER_SEC * _fx_scale * delta, DAMAGE_NUMBERS_PER_SEC * 0.5)
	_flush_damage_numbers(delta)
	if player == null or player.is_dead:
		return
	_update_interact()
	map.update_ripples(player, fx, delta)
	var target: Node2D = director.boss if director.boss != null and director.boss.is_alive() else null
	if story_target != null:
		target = story_target
	if target == null and _portal != null and _portal.visible:
		target = _portal
	if target != null and target is Enemy:
		hud.set_boss_posture((target as Enemy).posture_fraction(), (target as Enemy).posture_stun > 0.0)
	_arrow.track(camera.get_screen_center_position(), get_viewport_rect().size / camera.zoom, target)
	_combo_timer -= delta
	if _combo_timer <= 0.0:
		_combo = 0
	_multi_left -= delta
	if _adrenaline_left > 0.0:
		_adrenaline_left -= delta
		if _adrenaline_left <= 0.0:
			stats.add_flat(&"fire_rate_mult", -ADRENALINE_FIRE)
			player.set_speed_buff(0.0)
			player.apply_run_stats(stats)


func _update_hud_timer() -> void:
	hud.set_time(director.elapsed)
	if story != null:
		hud.set_story_status(story.score, story.lives, story.zone_number(), story.zone_count(), story.zone_name(), -1, SaveService.nell_order(), story.goal_rows())
		_tick_order()
		return
	hud.set_wave(maxi(director.wave_number, 1), director.get_enemies_left(), director.chapter_index + 1, director.get_alive_count())
	hud.set_survival_order(SaveService.nell_order())
	_tick_order()


func _tick_order() -> void:
	var done := SaveService.nell_order_tick()
	if not done.is_empty():
		hud.order_completed(done)
		hud.toast("ЗАКАЗ НЭЛЛ ВЫПОЛНЕН", "%s. Награда: +%d монет, +%d неонита" % [done["title"], done["nuts"], done["dust"]], Color("#5ff2ff"))
		SoundManager.play(&"level_up", -4.0, false)


func _run_summary() -> Dictionary:
	return {
		"wave": _waves_cleared(),
		"best_wave": maxi(int(SaveService.data["best_wave"]), _waves_cleared()),
		"kills": kills,
		"level": level,
		"time": director.elapsed,
		"coins": RunMods.reward(_earned()),
		"gems": run_gems,
		"bosses": bosses_killed,
		"chapter": str(director.current_chapter().get("title", "")),
		"weapon": player.weapon_controller.base_weapon.get_title(),
		"loot": run_loot,
		"blueprints": run_blueprints,
	}


## Подсказка после смерти: короткая, по причине; новичкам — почти всегда, остальным — раз в три смерти.
func _death_tip() -> String:
	if bosses_killed > 0 and not player.is_dead:
		return ""
	var count := int(SaveService.data.get("death_tips", 0))
	SaveService.data["death_tips"] = count + 1
	if count >= DEATH_TIP_NEWBIE and count % DEATH_TIP_EVERY != 0:
		return ""
	var boss := director.boss
	var text: String
	if boss != null and boss.is_alive() and boss.hp > boss.max_hp * 0.55:
		text = ["Босс слишком жирный для твоего урона. Прокачай урон или скорость атаки.",
			"Босс почти не поцарапан. Ты точно в него стрелял, а не рядом?",
			"Босс сказал, что ему было щекотно. Прокачай урон."].pick_random()
	elif director.elapsed < DEATH_FAST_TIME:
		text = ["Тебя слишком быстро убивают. Рекорд скорости, но не тот. Качни здоровье и броню.",
			"Это был не забег, а пробежка. Прокачка поможет дожить до второй волны."].pick_random()
	else:
		text = ["Ты опять отлетел. Иди качнись, пока крысы не заскучали.",
			"Снова отлетел. В Прокачке лечат и не такое.",
			"Слабовато. Иди качнись, Нэлл ставила на тебя.",
			"Не получается? Прокачка есть, смущаться не надо.",
			"Умираешь часто: качни выживаемость. Долго бьёшь босса: качни урон.",
			"Ты умер красиво. Теперь умри чуть дальше: качни броню.",
			"Крысы просили передать: «Спасибо за развлечение». Иди качнись.",
			"Игрок, мы всё видели. Прокачка в меню, не стесняйся."].pick_random()
	var cheapest := 1 << 30
	for perk_id in SaveService.PERKS:
		if not SaveService.is_perk_maxed(perk_id):
			cheapest = mini(cheapest, SaveService.get_perk_cost(perk_id))
	if SaveService.get_nuts() + nuts >= cheapest:
		text += " Монет уже хватает на улучшение."
	return text


func _run_summary_lines() -> PackedStringArray:
	if story != null:
		return PackedStringArray([
			"%s · зона %d/%d" % [story.mission.get("title", ""), story.zone_number(), story.zone_count()],
			"Очки: %d · Жизни: %d" % [story.score, story.lives],
			"Убито: %d · Спасено: %d" % [story.kills, story.rescued],
			"Время: %s · Детали ствола: %d/%d" % [BattleBase.format_time(director.elapsed), story.barrel.parts, HeavyBarrel.TOTAL_PARTS],
		])
	return PackedStringArray([
		"Волна %d · %s" % [maxi(director.wave_number, 1), director.current_chapter().get("title", "")],
		"Убито: %d · Уровень %d" % [kills, level],
		"Время: %s · Монеты: %d%s" % [BattleBase.format_time(director.elapsed), RunMods.reward(_earned()), " (×%.1f)" % RunMods.mult_of(RunMods.active) if RunMods.active != RunMods.NONE else ""],
		"Розыск: %s" % ("★".repeat(wanted.level) if wanted != null and wanted.level > 0 else "не искали"),
	])


# --- Главы и волны --------------------------------------------------------------------------------

func _apply_chapter_look(chapter: Dictionary) -> void:
	var grade: Dictionary = chapter.get("grade", {})
	if not grade.is_empty():
		var sh: Array = grade.get("shadow", [0.1, 0.02, 0.16])
		var hi: Array = grade.get("highlight", [0.06, 0.03, -0.02])
		atmosphere.set_grade(Vector3(sh[0], sh[1], sh[2]), Vector3(hi[0], hi[1], hi[2]))


func _on_wave_started(number: int, title: String, mood: String, is_boss: bool) -> void:
	Platform.note_event("wave %d %s boss=%s" % [number, title, is_boss])
	if story_mission.is_empty() and player != null:
		_wave_hp.append("%d:%d" % [number, int(100.0 * player.hp / maxf(player.max_hp, 1.0))])
	_last_marker.reset_hunt()
	atmosphere.set_mood(mood)
	_check_clean_sweep()
	events.on_wave_started(is_boss)
	if radio != null:
		radio.on_wave(is_boss)
	atmosphere.letterbox(true)
	get_tree().create_timer(1.9, false).timeout.connect(func() -> void: atmosphere.letterbox(false))
	if director.elapsed < 4.0:
		get_tree().create_timer(2.8, false).timeout.connect(func() -> void: hud.show_wave_intro(maxi(director.wave_number, 1), title, is_boss, director.chapter_index + 1))
	else:
		hud.show_wave_intro(maxi(director.wave_number, 1), title, is_boss, director.chapter_index + 1)
	SoundManager.play(&"boss_spawn" if is_boss else &"ui_confirm", -2.0, false)
	if director.chapter_wave() >= 2 and not is_boss:
		map.airdrop(player.global_position)


func _on_wave_cleared(number: int) -> void:
	Platform.note_event("wave %d cleared" % number)
	events.on_wave_cleared()
	_loot_at_clear = pickups.get_count()
	if player != null and not player.is_dead:
		player.visual.cheer()
	var bonus := Economy.wave_bonus(director.chapter_wave(), director.loop)
	nuts += bonus
	hud.set_nuts(nuts)
	hud.punch_nuts()
	hud.show_wave_cleared(bonus)
	if _last_marker.hunt_time > 0.0 and _last_marker.hunt_time <= QUICK_CLEAR_TIME and not director.is_boss_wave():
		var golden := _last_marker.hunt_time <= GOLD_CLEAR_TIME
		var quick := maxi(int(bonus * QUICK_CLEAR_RATIO * (1.8 if golden else 1.0)), 10)
		nuts += quick
		hud.set_nuts(nuts)
		hud.toast("ЗОЛОТАЯ ЗАЧИСТКА!" if golden else "БЫСТРАЯ ЗАЧИСТКА!", "Последние враги за %.1f с: +%d" % [_last_marker.hunt_time, quick], Color("#5cf3ff"))
	player.heal(player.max_hp * WAVE_CLEAR_HEAL)
	fx.confetti(player.global_position + Vector2(0, -40), 70)
	fx.ring(player.global_position, Color("#7cff6b"), 160.0)
	atmosphere.flash(Color(0.6, 1.0, 0.6), 0.2, 0.4)
	SoundManager.play(&"level_up", 0.0, false)
	if number > int(SaveService.data["best_wave"]):
		SaveService.data["best_wave"] = number
		SaveService.check_achievements()


## Босс главы повержен и все враги добиты: на помосте открывается портал.
func _on_chapter_cleared(_chapter_index: int) -> void:
	pickups.vacuum()
	if story != null:
		story.finish()
		return
	var next := ContentDB.get_chapter(director.chapter_index + 1)
	_portal = map.open_portal(Color("#b84dff"), Color("#00f5ff") if next.get("layout", "") != "bank" else Color("#ffd257"))
	if not _portal.entered.is_connected(_enter_portal):
		_portal.entered.connect(_enter_portal)
	hud.show_banner("ПОРТАЛ ОТКРЫТ!\nВперёд — %s" % str(next.get("title", "")).to_upper(), Color("#b8f0ff"), 3.2)
	SoundManager.play(&"shield_up", 0.0, false)


## Переход в следующую главу: затемнение, перестройка арены, Енот — у нижнего входа.
func _enter_portal() -> void:
	if _switching or player.is_dead:
		return
	_switching = true
	SoundManager.play(&"comet_impact", -2.0, false)
	Platform.haptic("heavy")
	var tween := create_tween()
	atmosphere.fade(1.0, 0.45)
	tween.tween_interval(0.5)
	tween.tween_callback(_switch_chapter)
	tween.tween_interval(0.25)
	tween.tween_callback(func() -> void:
		atmosphere.fade(0.0, 0.6)
		_switching = false)


func _switch_chapter(index: int = -1) -> void:
	var chapter := ContentDB.get_chapter(director.chapter_index + 1 if index < 0 else index)
	warm_chapter(chapter)
	enemies.release_all()
	BulletPool.release_all()
	lobs.clear()
	traps.clear()
	for pickup in _weapon_pickups:
		pickup.clear()
	pickups.clear()
	map.clear()
	map.build(layers, chapter)
	hazards.attach_level(map)
	light_map.set_layout(map.layout)
	_portal = null
	player.global_position = map.player_start
	player.reset_physics_interpolation()
	player.velocity = Vector2.ZERO
	set_camera_bounds(map.bounds)
	camera.global_position = player.global_position
	camera.reset_smoothing()
	camera.reset_physics_interpolation()
	minimap.rebuild()
	events.reset()
	_apply_chapter_look(chapter)
	director.next_chapter()
	player.heal(player.max_hp)
	SoundManager.play_music(StringName(str(chapter.get("music", "battle"))))
	hud.show_chapter(str(chapter.get("subtitle", "")), str(chapter.get("title", "")))


# --- Враги ---------------------------------------------------------------------------------------

func _on_bullet_hit(bullet: Bullet, target: Node2D) -> void:
	super._on_bullet_hit(bullet, target)
	if bullet.team == Bullet.Team.PLAYER and target is Enemy:
		status.on_player_hit(bullet, target as Enemy)
	if bullet.weapon.pierce_ramp > 0.0 and target is Enemy:
		_bump_rail_combo(bullet.pierced)
		if bullet.pierced == 3 or bullet.pierced == 5 or bullet.pierced == 8 or bullet.pierced == 12:
			fx.popup(bullet.global_position + Vector2(0, -70), "КАССА ×%d" % bullet.pierced, Color("#ffc93c"), 30.0)
			fx.burst(bullet.global_position, Color("#ffe27a"), 8, 260.0, 3.5)
			add_shake(0.2)


func _on_enemy_status(enemy: Enemy, amount: float, kind: String) -> void:
	status.on_status_damage(enemy, amount, kind)
	if enemy.data.is_boss():
		hud.update_boss(maxf(enemy.hp, 0.0), enemy.max_hp)


## Урон по одному врагу за 0.07 с складывается в одну цифру: залп дробовика показывает сумму, а не одну дробинку.
func _flush_damage_numbers(delta: float, force: bool = false) -> void:
	if _damage_acc.is_empty():
		return
	for key in _damage_acc.keys():
		var enemy: Enemy = key if is_instance_valid(key) else null
		var acc: Dictionary = _damage_acc[key]
		acc["age"] += delta
		if acc["age"] < DAMAGE_MERGE_TIME and not force:
			continue
		_damage_acc.erase(key)
		if enemy == null or enemy.data == null:
			continue
		if _number_budget >= 1.0 or acc["crit"] or acc["kind"] == &"melee":
			_number_budget -= 1.0
			var jitter := Vector2(randf_range(-enemy.data.radius, enemy.data.radius) * 0.6, 0.0)
			fx.number(enemy.get_aim_point() + Vector2(0, -enemy.data.radius * 1.6) + jitter, acc["amount"], FxManager.kind_color(acc["kind"]), acc["crit"], FxManager.kind_scale(acc["kind"]))


func _on_enemy_damaged(enemy: Enemy, amount: float, is_crit: bool, kind: StringName) -> void:
	if kind == &"melee":
		var spread := enemy.data.radius * 0.6
		fx.number(enemy.get_aim_point() + Vector2(randf_range(-spread, spread), -enemy.data.radius * 1.6), amount, FxManager.kind_color(kind), is_crit, FxManager.kind_scale(kind))
		if is_crit:
			SaveService.add_stat("crits", 1, false)
			if radio != null:
				radio.on_first_crit()
		if enemy.data.is_boss():
			hud.update_boss(maxf(enemy.hp, 0.0), enemy.max_hp)
		return
	var acc: Dictionary = _damage_acc.get(enemy, {})
	if acc.is_empty():
		acc = {"amount": 0.0, "crit": false, "kind": kind, "age": 0.0}
		_damage_acc[enemy] = acc
	acc["amount"] += amount
	acc["crit"] = acc["crit"] or is_crit
	if is_crit:
		SaveService.add_stat("crits", 1, false)
		if radio != null:
			radio.on_first_crit()
	if enemy.data.is_boss():
		hud.update_boss(maxf(enemy.hp, 0.0), enemy.max_hp)


## Пуля в щит: искры, звон, короткое «БЛОК» — игрок сразу понимает, что надо зайти сбоку.
func _on_enemy_blocked(_enemy: Enemy, at: Vector2) -> void:
	fx.burst(at, Color("#ffe27a"), 8, 260.0, 3.0)
	if randf() < 0.35:
		fx.popup(at + Vector2(0, -16), "БЛОК", Color("#ffe27a"), 24.0)
	SoundManager.play_pitched(&"hit", 1.7, -4.0)


## Крупье исчезает в вихре карт: вспышка там и тут, чтобы глаз успел за ним.
func _on_enemy_blinked(_enemy: Enemy, from: Vector2, to: Vector2) -> void:
	for at in [from, to]:
		fx.burst(at + Vector2(0, -24), Color("#ff2e4d"), 12, 300.0, 4.0)
		fx.burst(at + Vector2(0, -24), Color.WHITE, 8, 220.0, 3.0)
		fx.ring(at, Color("#ffd257"), 46.0)
	SoundManager.play(&"wing_flap", -4.0)


func _on_enemy_fx(_enemy: Enemy, kind: String, at: Vector2, radius: float) -> void:
	match kind:
		"transform":
			fx.burst(at + Vector2(0, -60), Color("#ffd257"), 60, 520.0, 5.0)
			fx.chunks(at, Color("#6a6070"), 26, 420.0, 6.0)
			fx.chunks(at, Color("#ffd257"), 14, 380.0, 5.0)
			fx.ring(at, Color.WHITE, 260.0)
			fx.sprite_flash(ArenaProp.texture_of("res://assets/props/ch1/fx_explosion.png"), at + Vector2(0, -60), 320.0, 0.55)
			atmosphere.flash(Color.WHITE, 0.55, 0.5)
			add_shake(1.0)
			hitstop(0.12)
		"stomp":
			fx.sprite_flash(ArenaProp.texture_of("res://assets/bosses/mud_wave.png"), at, radius * 2.2, 0.55)
			fx.dust(at, 16, radius)
			fx.ring(at, Color("#c9a26a"), radius)
			add_shake(0.6)
		"step":
			fx.dust(at + Vector2(0, 26), 3, radius * 0.9)
			if at.distance_to(player.global_position) < 700.0:
				add_shake(0.09)
		"beer", "beer_puke":
			var foamy := kind == "beer_puke"
			fx.burst(at, Color("#ffcf4a") if not foamy else Color("#f6e3a0"), 4, 200.0, 3.0)
			fx.burst(at, Color("#fff6dc"), 3, 140.0, 2.4)
			liquids.splash(at, 1 if foamy else 0, 44.0 if not foamy else 56.0)
			liquids.puddle(at, 1 if foamy else 0, 34.0 if not foamy else 46.0, 2.8)
			if not foamy:
				liquids.foam(at + Vector2(0, -8), 38.0)
		"muzzle":
			fx.muzzle_flash(at, (player.global_position - at).angle(), Color("#ffb347"), 1.4)
		"summon":
			# Мини-босс середины главы зовёт на одного меньше: бой не превращается в бесконечную толпу.
			director.summon_minions(int(radius) - (1 if director.is_mini_wave() else 0))
			fx.ring(at, Color("#ffd257"), 200.0)
			fx.dust(at, 14, 160.0)
			hud.show_banner("ПОДМОГА!", Color("#ffd257"), 1.4)
		"speakers":
			var list := director.spawn_speakers(int(radius))
			_enemy.attach_speakers(list)
			for speaker in list:
				fx.ring(speaker.global_position, Color("#ffd257"), 120.0)
				fx.dust(speaker.global_position, 8, 90.0)
			hud.show_banner("ЛОМАЙ КОЛОНКИ ТРОНА!", Color("#ffd257"), 2.0)
		"bass":
			fx.ring(at, Color("#ff2e4d"), radius)
			add_shake(0.18)
		"speaker_down":
			hud.show_banner("КОЛОНКА РАЗБИТА · ОСТАЛОСЬ %d" % int(radius), Color("#ffd257"), 1.2)
		"muted":
			if story != null:
				story.on_boss_break()
			hud.show_banner("ОГЛУШЕНИЕ МУЗЫКОЙ! БЕЙ КОРОЛЯ", Color("#5ff2ff"), 2.4)
			atmosphere.flash(Color("#5ff2ff"), 0.3, 0.4)
			add_shake(0.5)
		"repair":
			var healer := _enemy
			var healed := 0
			for other in enemies.get_active():
				if other == healer or not other.is_alive() or other.data.is_boss() or other.hp >= other.max_hp:
					continue
				if other.global_position.distance_to(at) > radius:
					continue
				other.hp = minf(other.max_hp, other.hp + other.max_hp * healer.data.heal_pct)
				healed += 1
				fx.burst(other.global_position + Vector2(0, -20), Color("#5ff2ff"), 5, 160.0, 2.5)
			if healed > 0:
				fx.ring(at, Color("#5ff2ff"), radius * 0.6)
		"crane":
			hud.show_banner("МАГНИТ! УБЕГАЙ ИЗ КРУГА", Color("#b46bff"), 1.4)
			atmosphere.flash(Color("#b46bff"), 0.25, 0.3)
			add_shake(0.4)
		"collapse":
			hud.show_banner("ОБВАЛ! ПОТОЛОК ТРОНА СЫПЛЕТСЯ", UiStyle.DANGER, 2.4)
			atmosphere.flash(Color(1.0, 0.6, 0.2), 0.45, 0.5)
			fx.dust(player.global_position, 18, 420.0)
			add_shake(1.0)
			SoundManager.play(&"comet_impact", -2.0, false)
		"enrage":
			hud.show_banner("ЯРОСТЬ! БОСС УСКОРИЛСЯ", UiStyle.DANGER, 2.2)
			atmosphere.flash(Color(1.0, 0.2, 0.2), 0.4, 0.6)
			hud.set_boss_fury()
			add_shake(0.6)
			SoundManager.play(&"boss_spawn", 0.0, false)


func _on_boss_phase(boss: Enemy, phase: int) -> void:
	if phase < 2:
		return
	if story != null and not director.is_mini_wave():
		story.on_boss_phase(phase)
	hud.set_boss_fury()
	var text := "МЕХ РАЗБИТ! МАГНАТ В ЯРОСТИ"
	match boss.data.boss_pattern:
		"overlord":
			text = "ТРОН РАЗВАЛИЛСЯ! КОРОЛЬ В ЯРОСТИ"
		"baron":
			text = "БАРОН ПЬЯН В ХЛАМ! ПИВОМЁТ НА ПОЛНУЮ"
		"shaman":
			text = "ГРОЗА НАБИРАЕТ СИЛУ! ШАМАН В ЯРОСТИ"
	hud.show_banner(text, UiStyle.DANGER, 2.4)
	SoundManager.play(&"boss_spawn", 0.0, false)
	Platform.haptic("heavy")


func _split_enemy(enemy: Enemy, at: Vector2) -> void:
	var data := enemy.data
	if data.split_into == &"":
		return
	var child := ContentDB.get_enemy(data.split_into)
	if child == null:
		return
	for i in data.split_count:
		var angle := TAU * (float(i) + randf() * 0.4) / data.split_count
		var spawned := enemies.spawn(child, at + Vector2.from_angle(angle) * data.radius * 0.7, enemy.max_hp / maxf(data.max_hp, 1.0), enemy.damage_mult)
		if spawned != null:
			spawned.push(Vector2.from_angle(angle) * 260.0)


var _torch_depth := 0


func _count_multikill() -> void:
	_multi = _multi + 1 if _multi_left > 0.0 else 1
	_multi_left = MULTI_WINDOW
	if not MULTI_CALLS.has(_multi):
		return
	var heat := minf(_multi / 12.0, 1.0)
	fx.callout(player.global_position + Vector2(0, -175), MULTI_CALLS[_multi], Color("#ffd257").lerp(Color("#ff3b30"), heat), 30.0 + 8.0 * heat)
	SoundManager.play(&"k_perfect")
	add_shake(0.12)


func _on_enemy_died(enemy: Enemy) -> void:
	var data := enemy.data
	if data.is_boss():
		player.external_pull = Vector2.ZERO
	var at := enemy.global_position
	var fall_dir := 1.0 if randf() < 0.5 else -1.0
	if enemy.is_framed():
		fx.frame_corpse(enemy.get_sprite(), at + enemy.get_sprite_offset(), enemy.get_sprite_scale())
	else:
		fx.corpse(enemy.get_texture(), enemy.get_corpse_origin(), enemy.get_sprite_scale(), fall_dir, enemy.get_corpse_tint())
	var body := enemy.get_aim_point()
	fx.burst(body, data.fx_color, 16 if not data.is_boss() else 70, 340.0, 4.5)
	fx.chunks(body, data.fx_color, 7 if not data.is_boss() else 30, 240.0, 5.0)
	fx.chunks(body, Color("#8e8aa6"), 4, 180.0, 4.0)
	fx.splat(at + Vector2(0, 6), data.fx_color.darkened(0.2), data.radius * 1.3)
	fx.ring(at, data.fx_color, data.radius * 2.2)
	_split_enemy(enemy, at)
	if enemy.self_destructed:
		return
	if RunMods.has(&"blast") and not data.is_boss():
		var wave := maxi(director.wave_number, 1)
		BulletPool.explode(at, RunMods.BLAST_RADIUS, RunMods.BLAST_DAMAGE_BASE + RunMods.BLAST_DAMAGE_PER_WAVE * wave, Bullet.Team.ENEMY, Color("#ff7a3d"), 1.0)
	kills += 1
	hero_skills.on_kill()
	fx.hitmarker(body, 2)
	SoundManager.play(&"k_combo")
	if not data.is_boss() and data.max_hp >= 120.0:
		hitstop(0.04)
		add_shake(0.15)
	_count_multikill()
	if SaveService.get_character_id() == "red_panda" and enemy.bleed_left > 0.0 and _torch_depth < 2:
		_torch_depth += 1
		BulletPool.explode(at, 95.0, 38.0 * (1.0 + stats.get_stat(&"damage_mult")), Bullet.Team.PLAYER, Color("#ff8a2a"), 1.0, &"fire")
		_torch_depth -= 1
	if story != null:
		story.on_kill(data)
	hud.set_kills(kills)
	if radio != null:
		radio.on_kill()
		if not data.is_boss() and data.max_hp >= 120.0:
			radio.on_elite()
	SaveService.add_stat("kills", 1, false)
	SaveService.add_stat("k_" + String(data.id), 1, false)
	if wanted != null:
		var bounty := wanted.on_kill(data)
		if bounty > 0:
			pickups.spawn(at + Vector2(0, -8), bounty)
			fx.popup(at + Vector2(0, -60), "РОЗЫСК +%d" % bounty, Color("#ff7a7a"), 26.0)
	status.on_enemy_died(enemy, at)
	pickups.spawn_xp(at, data.xp)
	if enemy.loot > 0:
		pickups.spawn(at, enemy.loot)
		pickups.spawn_xp_gold(at + Vector2(0, -10), 6 + director.chapter_wave())
		SaveService.add_stat("marauders", 1, false)
		hud.toast("МАРОДЁР ПОЙМАН!", "+%d монет добычи" % enemy.loot, Color("#ffd23f"))
		fx.confetti(at, 40)
	if randf() < data.nut_drop_chance and data.nut_drop > 0:
		pickups.spawn(at, data.nut_drop * (2 if randf() < stats.get_stat(&"double_drop") else 1))
	if data.is_boss():
		_on_boss_killed(enemy, at)
		return
	SoundManager.play(&"enemy_death")
	add_shake(0.1)
	hitstop(KILL_HITSTOP)


func _on_wanted_level(level: int) -> void:
	hud.set_wanted(level)
	hud.toast("РОЗЫСК %s" % "★".repeat(level), "Бюро ликвидации выслало агентов. За каждого платят награду.", Color("#ff5a5a"))
	if level >= 5:
		SaveService.add_stat("wanted_max", 1)
	if radio != null:
		radio.on_wanted(level)


func _on_enemy_exploded(_enemy: Enemy, at: Vector2, radius: float, damage: float) -> void:
	BulletPool.explode(at, radius, damage, Bullet.Team.ENEMY, Color("#b6ff00"), 1.2)


func _on_posture_broken(boss: Enemy) -> void:
	fx.popup(boss.global_position + Vector2(0, -boss.data.radius * 2.0), "ВЫДЕРЖКА СЛОМЛЕНА", Color("#ffe27a"), 34.0)
	fx.ring(boss.global_position, Color("#ffe27a"), boss.data.radius * 2.2)
	add_shake(0.5)
	Platform.haptic("medium")
	SoundManager.play(&"boss_spawn", -4.0, false)


## Отладка: #boss:<id> в адресе сразу выводит босса рядом с Енотом.
func debug_boss(enemy_id: StringName) -> void:
	var data := ContentDB.get_enemy(enemy_id)
	if data == null:
		return
	player.max_hp = 99999.0
	player.hp = 99999.0
	var boss := enemies.spawn(data, player.global_position + Vector2(260, -40), 1.0, 1.0)
	if boss != null:
		director.boss = boss
		_on_boss_spawned(boss)


func _on_boss_spawned(boss: Enemy) -> void:
	Platform.note_event("boss spawned")
	if story != null:
		story.on_boss_spawned(director.is_mini_wave())
	hud.show_boss(boss.data.display_name, boss.hp, boss.max_hp)
	if not director.is_mini_wave():
		_boss_started = director.elapsed
	if not boss.posture_broken.is_connected(_on_posture_broken):
		boss.posture_broken.connect(_on_posture_broken)
	hud.show_banner("БОСС: %s!" % boss.data.display_name.to_upper(), UiStyle.DANGER)
	var passive := BossBrain.passive_text(boss.data.boss_pattern)
	if not passive.is_empty():
		hud.toast("ПАССИВКА БОССА", passive, Color("#ff9a3d"))
	add_shake(0.6)
	fx.ring(boss.global_position, UiStyle.DANGER, 180.0)
	fx.dust(boss.global_position + Vector2(0, 30), 16, 140.0)
	SoundManager.play(&"boss_spawn", 0.0, false)
	Platform.haptic("heavy")


func _on_miniboss_killed(boss: Enemy, at: Vector2) -> void:
	add_shake(0.8)
	hitstop(BOSS_HITSTOP * 0.7)
	atmosphere.flash(Color.WHITE, 0.4, 0.5)
	hud.hide_boss()
	hud.show_banner("%s ПОВЕРЖЕН!" % boss.data.display_name.to_upper(), UiStyle.GOLD, 2.2)
	if story != null:
		story.on_miniboss_killed()
	SoundManager.play(&"comet_impact", 0.0, false)
	pickups.spawn(at, boss.data.nut_drop)
	pickups.spawn_xp_gold(at, 30 + director.chapter_wave() * 4)
	var reward := Economy.boss_reward(director.chapter_index, director.loop)
	run_gems += int(int(reward["gems"]) * 0.5)
	hud.toast("МИНИ-БОСС", "+%s" % Economy.format_gems(int(int(reward["gems"]) * 0.5)), Color("#ff7ae0"))
	fx.confetti(at, 30)
	if story != null:
		_drop_weapon(_roll_weapon("epic" if randf() < 0.5 else "rare"), at, true)
	else:
		_offer_mini_choice(boss, at, 0)
		if radio != null:
			radio.on_mini_boss(String(player.weapon_controller.base_weapon.id), String(boss.data.id))


const SPEED_KILL_TIME := 60.0
const MINI_CHOICE_RETRIES := 12


## Мини-босс на коленях: пощадить (полное лечение, реролл, редкий ствол) или ограбить (эпик, +50% неонита).
func _offer_mini_choice(boss: Enemy, at: Vector2, attempt: int) -> void:
	get_tree().create_timer(1.4 if attempt == 0 else 0.7, true, false, true).timeout.connect(func() -> void:
		if finished or player == null or player.is_dead:
			return
		if (_level_up_open or get_tree().paused) and attempt < MINI_CHOICE_RETRIES:
			_offer_mini_choice(boss, at, attempt + 1)
			return
		_show_mini_card(boss.data.display_name, String(boss.data.id), at))


func _show_mini_card(name: String, boss_id: String, at: Vector2) -> void:
	var panel := ChoiceCard.new()
	add_child(panel)
	panel.chosen.connect(func(index: int) -> void: _on_mini_choice(index, name, at, boss_id))
	panel.open({
		"title": "%s на коленях" % name,
		"text": "«Не добивай! Заплачу! Или скажу, где пиво!»",
		"color": "#ffb020",
		"image": _surrender_art(boss_id),
		"options": [
			{"label": "ПОЩАДИТЬ", "icon": "res://assets/story/surrender/choice_spare.png", "bullets": ["Полное лечение", "Бесплатный реролл", "Редкий ствол"]},
			{"label": "ОГРАБИТЬ", "icon": "res://assets/story/surrender/choice_loot.png", "bullets": ["Эпический ствол", "+50% неонита", "-Без лечения"]},
		]})


func _surrender_art(boss_id: String) -> String:
	var who := "baron" if boss_id == "beer_baron" else ("shaman" if boss_id == "electric_shaman" else ("magnate" if boss_id == "pig_magnate" else ""))
	return "" if who.is_empty() else "res://assets/story/surrender/%s_surrender.png" % who


func _on_mini_choice(index: int, name: String, at: Vector2, boss_id: String) -> void:
	SaveService.add_stat("spared" if index == 0 else "robbed", 1)
	if index == 0:
		player.heal(player.max_hp)
		_rerolls_free += 1
		_drop_weapon(_roll_weapon("rare"), at, true)
		hud.toast("ПОЩАДА", "Полное лечение и редкий ствол", Color("#5ff2ff"))
		hud.radio().push_named("НЭЛЛ", "#5ff2ff", "Ты его пожалел? Он тебя бы нет. Но ладно, красиво.", 6.0)
	else:
		var extra := int(int(Economy.boss_reward(director.chapter_index, director.loop)["gems"]) * 0.25)
		run_gems += extra
		_drop_weapon(_roll_weapon("epic"), at, true)
		pickups.spawn_xp_gold(at, 20)
		hud.toast("ГРАБЁЖ", "+%s" % Economy.format_gems(extra), Color("#ffb020"))
		hud.radio().push_named("НЭЛЛ", "#5ff2ff", "Грабёж! Мне нравится. Записала.", 5.0)
		_show_looted(boss_id)


func _show_looted(boss_id: String) -> void:
	var path := _surrender_art(boss_id).replace("_surrender", "_looted")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var picture := TextureRect.new()
	picture.texture = load(path) as Texture2D
	picture.set_anchors_preset(Control.PRESET_CENTER)
	picture.custom_minimum_size = Vector2(300, 300)
	picture.size = Vector2(300, 300)
	picture.position = Vector2(-150, -190)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.modulate.a = 0.0
	layer.add_child(picture)
	var tween := create_tween()
	tween.tween_property(picture, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.6)
	tween.tween_property(picture, "modulate:a", 0.0, 0.4)
	tween.tween_callback(layer.queue_free)


func _on_boss_killed(boss: Enemy, at: Vector2) -> void:
	# Узел босса вернётся в пул и достанется обычному врагу — ссылку снимаем сразу,
	# иначе эскорт, стрелка и мини-карта «увидят босса» в случайной крысе.
	var mini := director.is_mini_wave()
	if radio != null:
		radio.on_boss_down(player.weapon_controller.base_weapon.id)
	director.on_boss_killed()
	if mini:
		_on_miniboss_killed(boss, at)
		return
	_clear_remaining_enemies()
	if story != null:
		story.on_king_killed()
	bosses_killed += 1
	SaveService.add_boss_kill()
	add_shake(1.0)
	hitstop(BOSS_HITSTOP)
	atmosphere.flash(Color.WHITE, 0.6, 0.6)
	hud.hide_boss()
	hud.show_banner("%s ПОВЕРЖЕН!" % boss.data.display_name.to_upper(), UiStyle.GOLD, 2.6)
	SoundManager.play(&"comet_impact", 0.0, false)
	pickups.spawn(at, boss.data.nut_drop)
	var reward := Economy.boss_reward(director.chapter_index, director.loop)
	run_gems += int(reward["gems"])
	var shards: Array = reward["blueprints"]
	for shard in shards:
		run_blueprints.append(shard)
	var shard_text := Economy.blueprint_title(shards[0]) if not shards.is_empty() else "—"
	hud.toast("НАГРАДА БОССА", "+%s · чертёж: %s" % [Economy.format_gems(int(reward["gems"])), shard_text], Color("#ff7ae0"))
	_drop_weapon(_roll_weapon("legendary" if randf() < Economy.BOSS_LEGENDARY_CHANCE else "epic"), at, true)
	fx.confetti(at, 45)
	if story != null:
		return
	if director.elapsed - _boss_started <= SPEED_KILL_TIME:
		SaveService.add_stat("speed_bosses", 1)
		_drop_weapon(_roll_weapon("legendary"), at + Vector2(70.0, 0.0), true, 0.9)
		hud.toast("СЕКРЕТНЫЙ СТВОЛ", "Босс за минуту!", Color("#ffd23f"))
		hud.radio().push_named("НЭЛЛ", "#5ff2ff", "Я это не запишу, мне не поверят.", 5.0)
	_bonus_choices += 1
	_pending_levelups += 1
	if not _level_up_open:
		_level_up_open = true
		get_tree().create_timer(1.8, false).timeout.connect(_after_boss_ad)


## Межстраничная реклама после босса (игра на паузе); VIP 2+ и «Без рекламы» её отключают.
func _after_boss_ad() -> void:
	if Premium.ads_removed() or story != null:
		_open_level_up()
		return
	get_tree().paused = true
	Platform.show_interstitial(func() -> void:
		get_tree().paused = false
		_open_level_up())


## Смерть босса гасит эскорт и миньонов: рассыпаются в опыт без урона игроку.
func _clear_remaining_enemies() -> void:
	for e in enemies.get_active().duplicate():
		if e == null or e.data == null or e.data.is_boss():
			continue
		pickups.spawn_xp(e.global_position, e.data.xp)
		fx.burst(e.global_position, e.data.fx_color, 8, 220.0, 3.5)
		enemies.release(e)


# --- Лут -----------------------------------------------------------------------------------------

func _on_object_destroyed(object: DestructibleObject) -> void:
	pickups.spawn(object.global_position + Vector2(0, -10), object.nut_reward)
	object.play_break_fx(fx)
	SoundManager.play(object.get_sound())
	add_shake(0.15)
	if object.kind == DestructibleObject.Kind.WEAPON_CRATE:
		SaveService.add_stat("crates", 1, false)
		fx.burst(object.global_position + Vector2(0, -24), object.get_rarity_color(), 20, 320.0, 4.5)
		fx.ring(object.global_position, object.get_rarity_color(), 70.0)
		_drop_weapon(_roll_weapon(object.loot_rarity), object.global_position + Vector2(0, 4), true)


func _on_crate_landed(crate: DestructibleObject) -> void:
	fx.dust(crate.global_position, 12, 70.0)
	fx.ring(crate.global_position, crate.get_rarity_color(), 80.0)
	add_shake(0.2)
	SoundManager.play(&"crate_break", -6.0)


## Ствол заданной редкости (или ближайшей ниже) с тиром, растущим от номера волны.
func _roll_weapon(rarity: String) -> WeaponData:
	var start := WeaponData.RARITIES.find(rarity)
	for r in range(maxi(start, 0), -1, -1):
		var pool: Array[WeaponData] = []
		var total := 0.0
		for weapon in WeaponDB.get_player_weapons():
			if weapon.rarity == WeaponData.RARITIES[r] and weapon.loot_weight > 0.0 and RunMods.only_shotguns(weapon):
				pool.append(weapon)
				total += weapon.loot_weight
		if pool.is_empty():
			continue
		var roll := randf() * total
		var chosen: WeaponData = pool.back()
		for weapon in pool:
			roll -= weapon.loot_weight
			if roll <= 0.0:
				chosen = weapon
				break
		var tier := 1
		var chance := TIER_CHANCE_BASE + TIER_CHANCE_PER_WAVE * director.chapter_wave() + 0.1 * director.chapter_index
		while tier < 3 and randf() < chance:
			tier += 1
			chance *= 0.4
		return chosen.with_tier(tier)
	return WeaponDB.get_weapon(RunMods.SHOTGUN_IDS[0] if RunMods.has(&"shotguns") else StringName(SaveService.START_WEAPON)).with_tier(1)


## Ящик сюжета открыт пробкой-ключом: тяжёлый легендарный ствол рядом с Енотом.
func open_story_crate() -> void:
	var crate := map.airdrop(player.global_position)
	if crate != null:
		crate.loot_rarity = "epic"
	hud.toast("ЯЩИК СБРОШЕН", "Открой его пробкой-ключом: стреляй по ящику", Color("#ffd257"))


## Сюжет: жизнь потрачена, Рико возвращается на последний чекпоинт.
func story_respawn(at: Vector2) -> void:
	if finished or player == null:
		return
	player.global_position = at
	player.reset_physics_interpolation()
	player.velocity = Vector2.ZERO
	player.revive(0.7, REVIVE_INVULN)
	BulletPool.release_all()
	lobs.clear()
	traps.clear()
	camera.global_position = player.global_position
	camera.reset_smoothing()
	camera.reset_physics_interpolation()
	BulletPool.explode(at, REVIVE_BLAST, 0.0, Bullet.Team.PLAYER, Color("#7df9ff"), 2.4)
	fx.ring(at, Color("#7df9ff"), REVIVE_BLAST)
	SoundManager.play(&"shield_up", 0.0, false)


func announce_boss(boss: Enemy) -> void:
	_on_boss_spawned(boss)


## Миссия пройдена: итоговый экран боя (победа).
func story_finished() -> void:
	if finished:
		return
	story_result(true, story.result_lines(true))


func story_result(victory: bool, lines: PackedStringArray) -> void:
	if finished:
		return
	hud.hide_revive()
	Platform.send_report("story", "mission=%s victory=%s score=%d kills=%d lives=%d time=%ds killed_by=%s" % [story_mission, victory, story.score, story.kills, story.lives, int(director.elapsed), Player.last_source])
	_show_result(victory, lines, "МИССИЯ ВЫПОЛНЕНА" if victory else "МИССИЯ ПРОВАЛЕНА", false)


func _drop_weapon(weapon: WeaponData, at: Vector2, loot: bool, delay: float = 0.4) -> void:
	for pickup in _weapon_pickups:
		if not pickup.active:
			pickup.drop(weapon, at, loot, delay)
			return
	_weapon_pickups[0].drop(weapon, at, loot, delay)


func _open_orders() -> void:
	if player == null or player.is_dead or get_tree().paused:
		return
	var screen := OrdersScreen.new()
	add_child(screen)
	screen.open(SaveService.nell_order(), story.goal_rows() if story != null else [])


func _refresh_slots() -> void:
	var wc := player.weapon_controller
	var close := false
	var rail := false
	for i in wc.slot_count:
		if wc.slots[i] != null:
			close = close or wc.slots[i].is_close_range()
			rail = rail or wc.slots[i].dash_charge
	stats.close_context = close
	stats.rail_context = rail
	hud.set_slots(wc.slots.slice(0, wc.slot_count), wc.active_slot, wc.slot_count)


func _switch_slot(index: int) -> void:
	if player.is_dead or get_tree().paused:
		return
	if player.weapon_controller.switch_slot(index):
		_after_switch()


func _cycle_weapon() -> void:
	if player.is_dead or get_tree().paused:
		return
	if player.weapon_controller.cycle_slot():
		_after_switch()


func _after_switch() -> void:
	var weapon := player.weapon_controller.base_weapon
	SoundManager.play(&"weapon_pickup", -6.0, false)
	fx.popup(player.global_position + Vector2(0, -90), weapon.short_name.to_upper(), weapon.get_rarity_color(), 28.0)
	fx.ring(player.global_position, weapon.get_rarity_color(), 44.0)
	player.visual.pickup_pop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		_try_pick()
	elif event.is_action_pressed(&"weapon_next"):
		_cycle_weapon()
	elif event.is_action_pressed(&"weapon_1"):
		_switch_slot(0)
	elif event.is_action_pressed(&"weapon_2"):
		_switch_slot(1)
	elif event.is_action_pressed(&"weapon_3"):
		_switch_slot(2)
	else:
		super._unhandled_input(event)


func _nearest_pickup() -> WeaponPickup:
	var best: WeaponPickup = null
	var best_d := WeaponPickup.INTERACT_RADIUS * WeaponPickup.INTERACT_RADIUS
	for pickup in _weapon_pickups:
		if not pickup.active:
			continue
		var d := pickup.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = pickup
	return best


func _update_interact() -> void:
	var target := _nearest_pickup()
	for pickup in _weapon_pickups:
		pickup.focused = pickup == target and pickup.can_pick()
	if target == null or not target.can_pick():
		hud.set_interact(null)
		return
	var wc := player.weapon_controller
	var note := "в пустой слот %d" % (wc.first_empty_slot() + 1) if wc.first_empty_slot() >= 0 else "заменит: %s" % wc.base_weapon.short_name
	hud.set_interact(target.weapon, note)


func _try_pick() -> void:
	if player.is_dead or get_tree().paused:
		return
	var target := _nearest_pickup()
	if target != null and target.can_pick():
		_on_weapon_picked(target)


func _on_pickup_expired(pickup: WeaponPickup) -> void:
	if pickup.weapon == null:
		pickup.clear()
		return
	fx.burst(pickup.global_position + Vector2(0, -30), pickup.weapon.get_rarity_color(), 10, 200.0, 3.0)
	pickup.clear()


## Каждый враг, пробитый лучом рельсотрона, растит комбо; навык-овердрайв даёт самые длинные цепочки.
func _bump_rail_combo(pierced: int) -> void:
	_rail_combo += 1
	_rail_timer = RAIL_COMBO_WINDOW
	hud.set_rail_combo(_rail_combo)
	if _rail_combo % RAIL_COMBO_MEGA == 0:
		fx.popup(player.global_position + Vector2(0, -130), "МЕГА-КАССА!", Color("#ff4fd8"), 46.0)
		fx.confetti(player.global_position, 30)
		add_shake(0.6)
		player.heal(player.max_hp * 0.03)
		SoundManager.play(&"level_up", -3.0, false)


## Тестер: старт с выбранной главы и волны (в том числе сразу на босса).
func _apply_tester_start() -> void:
	var chapter_number := Tester.start_chapter()
	var wave := Tester.start_wave()
	if chapter_number == 0 and wave == 1:
		return
	if chapter_number > 0:
		_switch_chapter(chapter_number)
	director.wave_number = chapter_number * WaveDirector.WAVES_PER_CHAPTER + wave - 1


func _apply_tester_flags() -> void:
	if Tester.flag("dmg"):
		stats.add_flat(&"damage_mult", 9.0)
	if Tester.flag("speed"):
		stats.add_flat(&"move_speed_mult", 0.6)
	player.apply_run_stats(stats)
	if Tester.flag("levels"):
		_pending_levelups += 10
		_level_up_open = true
		get_tree().create_timer(1.5, false).timeout.connect(_open_level_up)


func _on_overdrive_changed(active: bool) -> void:
	if not active:
		return
	fx.ring(player.global_position, Color("#ffc93c"), 70.0)
	fx.burst(player.global_position + Vector2(0, -20), Color("#ffe27a"), 10, 260.0, 3.5)
	fx.popup(player.global_position + Vector2(0, -100), "ЗАРЯЖЕН!", Color("#ffe27a"), 30.0)
	SoundManager.play(&"dash_ready", -2.0, false)


func _on_overdrive_fired() -> void:
	add_shake(0.55)
	hitstop(0.05)
	atmosphere.flash(Color("#ffd257"), 0.3, 0.3)
	fx.popup(player.global_position + Vector2(0, -110), "РЕЛЬСА!", Color("#fff2b0"), 44.0)


func _on_weapon_picked(pickup: WeaponPickup) -> void:
	if story != null and story.barrel.active:
		return
	var wc := player.weapon_controller
	var found := pickup.weapon
	var was_loot := pickup.is_loot
	if radio != null and found.rarity == "legendary":
		radio.on_legendary()
	pickup.clear()
	var slot := wc.first_empty_slot()
	var old: WeaponData = null
	if slot >= 0:
		wc.set_slot(slot, found)
		wc.switch_slot(slot)
	else:
		old = wc.base_weapon
		wc.set_slot(wc.active_slot, found)
	if was_loot and story == null:
		var kept := randf() < Economy.keep_chance(found.rarity)
		if kept:
			run_loot.append([String(found.id), found.tier])
		var fate := "★ останется в арсенале" if kept else "только на этот забег"
		hud.toast(found.get_title(), "%s · %s" % [WeaponData.RARITY_NAMES[found.rarity], fate], found.get_rarity_color())
	if old != null and not (old.id == found.id and old.tier == found.tier):
		_drop_weapon(old, player.global_position + Vector2(0, 6), false, WEAPON_SWAP_DELAY)
	if story != null:
		story.tip_weapon(found)
	player.visual.pickup_pop()
	fx.popup(player.global_position + Vector2(0, -90), found.short_name.to_upper(), found.get_rarity_color(), 30.0)
	fx.ring(player.global_position, found.get_rarity_color(), 60.0)
	SoundManager.play(&"weapon_pickup", 0.0, false)


## Награда за чистый сбор: на зачистке волны на полу лежало много лута, а к началу следующей его почти нет.
func _check_clean_sweep() -> void:
	var was := _loot_at_clear
	_loot_at_clear = 0
	if was < CLEAN_SWEEP_MIN or pickups.get_count() > 1:
		return
	var bonus := maxi(int(Economy.wave_bonus(maxi(director.chapter_wave() - 1, 1), director.loop) * CLEAN_SWEEP_RATIO), 10)
	nuts += bonus
	hud.set_nuts(nuts)
	_on_xp_collected(CLEAN_SWEEP_XP + level)
	hud.toast("ЧИСТЫЙ СБОР!", "Весь лут подобран: +%d монет и опыт" % bonus, Color("#5cf3ff"))
	fx.popup(player.global_position + Vector2(0, -100), "+%d" % bonus, Color("#ffd23f"), 30.0)


func _apply_camp_pack() -> void:
	if story_mission.is_empty():
		return
	if SaveService.camp_has("vest"):
		player.vest += 1
	if SaveService.camp_has("thermos"):
		stats.add_flat(&"max_hp_add", Player.BASE_MAX_HP * 0.4)
	if SaveService.camp_has("whetstone"):
		stats.add_flat(&"damage_mult", 0.2)
	(SaveService.data["camp_pack"] as Dictionary).clear()
	SaveService.save_data()


func _earned() -> int:
	return maxi(nuts - _start_cash, 0)


func _apply_run_start_perks() -> void:
	if story != null or not story_mission.is_empty():
		return
	_start_cash = int(SaveService.get_perk_bonus("cash"))
	nuts += _start_cash
	hud.set_nuts(nuts)
	_sync_drones()
	var boost := int(SaveService.get_perk_bonus("headstart"))
	if boost > 0:
		level += boost
		_pending_levelups += boost
		_level_up_open = true
		hud.set_xp(xp, _xp_needed(level), level)
		get_tree().create_timer(7.5, false).timeout.connect(_open_level_up)


func _on_nuts_collected(amount: int) -> void:
	if SaveService.get_character_id() == "pigeon_mafioso":
		amount = int(amount * 1.2 + randf())
	nuts += int(amount * events.coin_mult + randf()) if events.coin_mult > 1.0 else amount
	hud.set_nuts(nuts)
	hud.punch_nuts()
	_combo = mini(_combo + 1, 14)
	_combo_timer = PICKUP_COMBO_WINDOW
	SoundManager.play_pitched(&"nut_pickup", 1.0 + 0.045 * _combo)
	player.visual.pickup_pop()


func _on_xp_collected(amount: int) -> void:
	hud.flash_xp()
	fx.ring(player.global_position + Vector2(0, 10), Color("#00f5ff"), 30.0)
	SoundManager.play_pitched(&"nut_pickup", 1.35 + 0.03 * _combo, -4.0)
	_gain_xp(amount)


# --- Опыт и прокачка -----------------------------------------------------------------------------

func _gain_xp(amount: int) -> void:
	if finished or story != null:
		return
	xp += int(round(amount * (1.0 + SaveService.get_perk_bonus("logistics"))))
	var needed := _xp_needed(level)
	var leveled := false
	while xp >= needed:
		xp -= needed
		level += 1
		_pending_levelups += 1
		needed = _xp_needed(level)
		leveled = true
	hud.set_xp(xp, needed, level)
	if leveled:
		_celebrate_level_up()
	if _pending_levelups > 0 and not _level_up_open:
		_level_up_open = true
		get_tree().create_timer(LEVEL_UP_DELAY, false).timeout.connect(_open_level_up)


## Яркий момент левел-апа до паузы: вспышка, кольца, конфетти и надпись над Енотом.
func _celebrate_level_up() -> void:
	if player != null and not player.is_dead:
		player.visual.cheer()
	var at := player.global_position
	atmosphere.flash(Color(0.6, 1.0, 1.0), 0.35, 0.45)
	fx.ring(at, Color("#00f5ff"), 120.0)
	fx.ring(at, Color.WHITE, 70.0)
	fx.burst(at + Vector2(0, -30), Color("#00f5ff"), 30, 380.0, 4.5)
	fx.confetti(at + Vector2(0, -30), 30)
	fx.popup(at + Vector2(0, -110), "УРОВЕНЬ %d!" % level, Color("#7df9ff"), 42.0)
	SoundManager.play(&"level_up", -9.0, false)


func _extra_context() -> String:
	if director == null or player == null:
		return ""
	return "wave=%d enemies=%d lvl=%d hp=%d/%d pos=(%d,%d)" % [director.wave_number, enemies.get_active_count(), level, int(player.hp), int(player.max_hp), int(player.global_position.x), int(player.global_position.y)]


func _xp_needed(for_level: int) -> int:
	return XP_BASE + XP_STEP * for_level


func _open_level_up() -> void:
	if finished or _pending_levelups <= 0 or player.is_dead:
		_level_up_open = false
		return
	var bonus := _bonus_choices > 0
	var luck := clampf(float(level) * 0.015, 0.0, 0.35) + (0.3 if bonus else 0.0)
	var choices := stats.roll_choices(ContentDB.get_upgrades(), 3, luck, 1 if bonus else 0)
	if choices.is_empty():
		_pending_levelups = 0
		_level_up_open = false
		return
	get_tree().paused = true
	_show_choices(choices, bonus)
	if bonus:
		_bonus_choices -= 1


func _reroll_cost() -> int:
	var early := clampf(1.2 - float(level) * 0.025, 0.55, 1.2)
	var deal := 0.5 if _reroll_deal else 1.0
	return maxi(int(round(REROLL_BASE_COST * pow(REROLL_GROWTH, _rerolls_paid) * early * deal / 5.0)) * 5, 5)


func _reroll_label() -> String:
	if _rerolls_free > 0:
		return "РЕРОЛЛ  ·  бесплатно ×%d  (R)" % _rerolls_free
	return "РЕРОЛЛ  ·  %d орехов%s  (R)" % [_reroll_cost(), " -50%" if _reroll_deal else ""]


func _show_choices(choices: Array[UpgradeData], bonus: bool) -> void:
	_current_bonus = bonus
	_last_choices.clear()
	for u in choices:
		_last_choices.append(u.id)
	hud.show_level_up(choices, level - _pending_levelups + 1, stats, bonus, _reroll_label(), _rerolls_free > 0 or nuts >= _reroll_cost())


func _on_reroll_requested() -> void:
	if not _level_up_open:
		return
	if _rerolls_free > 0:
		_rerolls_free -= 1
	else:
		var cost := _reroll_cost()
		if nuts < cost:
			SoundManager.play(&"ui_click", -4.0)
			return
		nuts -= cost
		_rerolls_paid += 1
		_reroll_deal = false
		hud.set_nuts(nuts)
	SoundManager.play(&"merge", -4.0, false)
	var luck := clampf(float(level) * 0.015, 0.0, 0.35) + (0.3 if _current_bonus else 0.0)
	var choices := stats.roll_choices(ContentDB.get_upgrades(), 3, luck, 1 if _current_bonus else 0, _last_choices)
	if not choices.is_empty():
		_show_choices(choices, _current_bonus)


func _on_upgrade_chosen(upgrade: UpgradeData) -> void:
	SaveService.add_stat("picks", 1, false)
	SoundManager.play(&"ui_confirm")
	stats.apply(upgrade)
	if upgrade.stat == &"heal_pct":
		player.heal(player.max_hp * upgrade.value)
	player.apply_run_stats(stats)
	_sync_drones()
	_pending_levelups -= 1
	if _pending_levelups > 0:
		_open_level_up()
	else:
		_level_up_open = false
		get_tree().paused = false


func _sync_drones() -> void:
	var wanted := int(stats.get_stat(&"drone_count"))
	while _drones.size() < wanted:
		var drone := JunkDrone.new()
		drone.setup(player, enemies, stats, _drones.size())
		drone.global_position = player.global_position
		layers.fx.add_child(drone)
		_drones.append(drone)


func _on_achievement(achievement: Dictionary) -> void:
	var reward := "+" + SaveService.format_coins(int(achievement["nuts"])) if int(achievement["nuts"]) > 0 else "+" + Economy.format_gems(int(achievement["dust"]))
	hud.toast("АЧИВКА: %s" % achievement["title"], "%s · %s" % [achievement["description"], reward], UiStyle.GOLD)
	SoundManager.play(&"achievement", 0.0, false)


# --- Смерть, возрождение, конец забега -----------------------------------------------------------

func _on_player_died() -> void:
	Platform.note_event("player died lvl=%d" % level)
	fx.burst(player.global_position, UiStyle.DANGER, 50, 380.0, 5.0)
	fx.chunks(player.global_position, Color("#8e8aa6"), 14, 260.0, 5.0)
	add_shake(1.0)
	atmosphere.flash(Color(1.0, 0.1, 0.1), 0.5, 0.8)
	if radio != null:
		radio.on_death()
	SaveService.add_stat("deaths", 1)
	if story != null and story.try_respawn():
		return
	get_tree().create_timer(DEATH_DELAY, false).timeout.connect(_offer_revive)


## Окно второго шанса: 10 секунд, реклама (раз за забег) или неонит (цена растёт).
func _offer_revive() -> void:
	if finished:
		return
	get_tree().paused = true
	hud.show_revive(Economy.revive_cost(revives_used), SaveService.get_gems(), revives_used == 0, _run_summary())


func _on_revive_requested(with_ad: bool) -> void:
	if with_ad:
		Platform.show_rewarded_ad(func(ok: bool) -> void:
			if ok:
				_revive()
			else:
				hud.revive_failed("Реклама не досмотрена"))
		return
	if SaveService.spend_gems(Economy.revive_cost(revives_used)):
		_revive()
	else:
		hud.revive_failed("Не хватает неонита")


func _revive() -> void:
	revives_used += 1
	hud.hide_revive()
	get_tree().paused = false
	player.revive(REVIVE_HP, REVIVE_INVULN)
	BulletPool.release_all()
	lobs.clear()
	traps.clear()
	BulletPool.explode(player.global_position, REVIVE_BLAST, 0.0, Bullet.Team.PLAYER, Color("#7df9ff"), 2.4)
	fx.ring(player.global_position, Color("#7df9ff"), REVIVE_BLAST)
	fx.confetti(player.global_position + Vector2(0, -30), 50)
	atmosphere.flash(Color(0.6, 1.0, 1.0), 0.5, 0.6)
	SoundManager.play(&"level_up", 0.0, false)
	hud.toast("ВТОРОЙ ШАНС!", "60% здоровья и 2.5 с неуязвимости", Color("#7df9ff"))


func _on_menu_pressed() -> void:
	if story_mission.is_empty() and not finished:
		_send_run_report("quit", director.wave_number, str(director.chapter_index + 1), false)
	_record()
	super._on_menu_pressed()


## Итог забега выживания в общий журнал: и при смерти/финише, и при выходе в меню посреди забега.
func _send_run_report(outcome: String, wave: Variant, chapter: Variant, record: bool) -> void:
	var damage := PackedStringArray()
	for source: Variant in _damage_by:
		damage.append("%s:%d" % [source, int(_damage_by[source])])
	Platform.send_report("run", "mode=survival outcome=%s hero=%s weapon=%s wave=%s chapter=%s level=%d kills=%d time=%ds coins=%d bosses=%d revives=%d killed_by=%s record=%s mod=%s power=%.2f adapt=%.2f | hp %s | dmg %s" % [outcome, SaveService.get_character_id(), player.weapon_controller.base_weapon.id, str(wave), str(chapter), level, kills, int(director.elapsed), nuts, bosses_killed, revives_used, Player.last_source, record, RunMods.active, stats.power(), director.adapt, " ".join(_wave_hp), " ".join(damage)])


func _waves_cleared() -> int:
	return maxi(director.wave_number - (0 if director.phase == WaveDirector.Phase.INTERMISSION or director.phase == WaveDirector.Phase.PORTAL else 1), 0)


func _record() -> Dictionary:
	if _recorded:
		return {}
	_recorded = true
	return SaveService.record_run({
		"nuts": RunMods.reward(_earned()),
		"time": director.elapsed,
		"wave": _waves_cleared(),
		"kills": kills,
		"loot": run_loot,
		"gems": run_gems,
		"blueprints": run_blueprints,
		"bosses": bosses_killed,
	})


func _finish() -> void:
	Platform.note_event("run finished")
	if finished:
		return
	hud.hide_revive()
	var summary := _run_summary()
	summary["tip"] = _death_tip()
	var previous_best := SaveService.get_stat("best_wave")
	var result := _record()
	summary["friend"] = SaveService.friend_wave_line(int(summary["wave"]), previous_best)
	_send_run_report("died" if player.is_dead else "finished", summary["wave"], summary["chapter"], result.get("record", false))
	summary["record"] = result.get("record", false)
	summary["total_coins"] = SaveService.get_coins()
	finished = true
	Engine.time_scale = 1.0
	get_tree().paused = true
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	SoundManager.play(&"victory" if bosses_killed > 0 else &"defeat", 0.0, false)
	hud.show_run_result(summary)


func _make_glow() -> WorldEnvironment:
	var node := WorldEnvironment.new()
	var env := RaidEnvironment.build_environment()
	env.glow_hdr_threshold = 0.72
	env.glow_intensity = 1.25
	env.glow_strength = 1.0
	node.environment = env
	return node


## Неоновая стрелка у края экрана к боссу или открытому порталу.
class TargetArrow:
	extends Node2D

	const EDGE_MARGIN := 64.0
	const COLOR := Color("#ff2ea6")

	var _pulse := 0.0

	func track(screen_center: Vector2, view_size: Vector2, target: Node2D) -> void:
		if target == null or not is_instance_valid(target):
			visible = false
			return
		var half := view_size * 0.5 - Vector2.ONE * EDGE_MARGIN
		var offset := target.global_position - screen_center
		if absf(offset.x) < half.x + EDGE_MARGIN and absf(offset.y) < half.y + EDGE_MARGIN:
			visible = false
			return
		var scale_to_edge := minf(half.x / maxf(absf(offset.x), 0.001), half.y / maxf(absf(offset.y), 0.001))
		global_position = screen_center + offset * scale_to_edge
		rotation = offset.angle()
		modulate = Color("#b8f0ff") if target is Portal else Color.WHITE
		visible = true

	func _process(delta: float) -> void:
		if visible:
			_pulse += delta * 6.0
			queue_redraw()

	func _draw() -> void:
		var grow := 1.0 + 0.12 * sin(_pulse)
		var tip := PackedVector2Array([Vector2(26, 0) * grow, Vector2(-14, -18) * grow, Vector2(-6, 0) * grow, Vector2(-14, 18) * grow])
		draw_colored_polygon(tip, Color(COLOR, 0.35))
		draw_polyline(PackedVector2Array([tip[0], tip[1], tip[2], tip[3], tip[0]]), COLOR, 4.0, true)
		draw_circle(Vector2(-26, 0), 7.0, Color(COLOR, 0.8))
