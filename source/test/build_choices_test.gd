extends Node
var failures := 0
var measurements: Array = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("BUILD_CHOICES: " + label)

func _pick(id: String) -> UpgradeData:
	for upgrade in ContentDB.get_upgrades():
		if String(upgrade.id) == id: return upgrade
	return null

func _tactic(id: String) -> UpgradeData:
	return _pick("tactic_" + id)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	_test_draft()
	await _test_game_choices()
	await _test_turret()
	await _test_layout()
	for player in SoundManager._players: player.stop()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	var output := OS.get_environment("BUILD_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(measurements, "\t"))
	print("BUILD_CHOICES failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)

func _test_draft() -> void:
	var pool := ContentDB.get_upgrades()
	var first_picks := {}
	for sample in 100:
		seed(sample + 71)
		var run := RunStats.new()
		var choices := run.roll_choices(pool, 3, 0.0, 0, [], true)
		_check(choices.size() == 3 and choices[0].category == "tactic", "milestone offers a tactic")
		_check(choices.filter(func(u: UpgradeData) -> bool: return u.category != "tactic").size() == 2, "two ordinary alternatives remain")
		_check(choices[0].id != choices[1].id and choices[0].id != choices[2].id and choices[1].id != choices[2].id, "three distinct choices")
		first_picks[choices[0].id] = true
		for u in choices: _check(run.is_available(u), "offered card is usable")
		_check(choices[0].id != &"tactic_switcher", "single weapon cannot offer switching")
	_check(first_picks.size() == 5, "first tactic has variety across seeds")
	for pair: Dictionary in CombatTactics.PAIRS:
		for order in 2:
			var first: String = pair["ids"][order]
			var second: String = pair["ids"][1 - order]
			var run := RunStats.new()
			run.multi_weapon_context = true
			run.apply(_tactic(first))
			for sample in 30:
				seed(sample + 300)
				var choices := run.roll_choices(pool, 3, 0.0, 0, [], true)
				_check(not CombatTactics.preview_pair(run, String(choices[0].id).trim_prefix("tactic_")).is_empty(), "partner offer completes a real synergy")
			var candidate := _tactic(second)
			var avoid: Array[StringName] = [candidate.id]
			var reroll := run.roll_choices(pool, 3, 0.0, 0, avoid, true)
			_check(reroll[0].id != candidate.id, "reroll changes the tactical option when alternatives exist")
			run.apply(candidate)
			_check(CombatTactics.active_pairs(run).size() == 1, "both choice orders activate the same pair")
			for sample in 10:
				var choices := run.roll_choices(pool, 3, 0.0, 0, [], true)
				_check(CombatTactics.selected(run).has(String(choices[0].id).trim_prefix("tactic_")), "two-tactic limit keeps rank choices inside the build")
			for tier in 2:
				run.apply(_tactic(first))
				run.apply(candidate)
			var complete := run.roll_choices(pool, 3, 0.0, 0, [], true)
			_check(complete.size() == 3 and complete.all(func(u: UpgradeData) -> bool: return u.category != "tactic"), "completed build returns to regular choices")
	for sample in 80:
		var run := RunStats.new()
		var reward := run.roll_choices(pool, 3, 0.0, 1, [], true)
		_check(reward.any(func(u: UpgradeData) -> bool: return u.rarity_rank >= 1), "boss reward preserves its rarity guarantee")

func _new_game() -> Game:
	var game := Game.new()
	add_child(game)
	game.start()
	game.finished = true
	game.set_physics_process(false)
	game.director.set_physics_process(false)
	game.events.set_physics_process(false)
	game.hazards.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.weapon_controller.set_physics_process(false)
	game.enemies.set_physics_process(false)
	game.tactics.set_physics_process(false)
	game.status.set_physics_process(false)
	game.enemies.release_all()
	return game

func _test_game_choices() -> void:
	var game := _new_game()
	game.finished = false
	game.player.weapon_controller.set_slot(1, WeaponDB.get_weapon(&"smg_v1"))
	game.level = 8
	game._pending_levelups = 6
	_check(game._tactic_offer_due(false), "queued XP uses actual choice level three")
	game._pending_levelups = 5
	_check(not game._tactic_offer_due(false) and not game._tactic_offer_due(true), "ordinary and boss choices keep separate cadence")
	game.story_mission = "m1"
	game._pending_levelups = 6
	_check(not game._tactic_offer_due(false), "story rewards are not changed")
	game.story_mission = ""
	game.level = 2
	game._pending_levelups = 1
	_check(game._draft_pool().any(func(u: UpgradeData) -> bool: return u.category != "tactic"), "first upgrade is not forced to take a tactic")
	game.level = 3
	game._open_level_up()
	var choices: Array[UpgradeData] = game.hud._level_up._choices
	_check(choices[0].category == "tactic" and choices.size() == 3, "real level-up window receives the milestone offer")
	game._on_upgrade_chosen(choices[0])
	_check(CombatTactics.selected(game.stats).size() == 1 and not get_tree().paused, "real card choice starts one tactic and resumes combat")
	_check(game._build_report().contains("Следующий забег:"), "incomplete build gives a concrete idea for another run")
	game.hud._hide_toast_now()
	game.level = 6
	game._pending_levelups = 1
	game._open_level_up()
	var second: UpgradeData = game.hud._level_up._choices[0]
	var preview := CombatTactics.preview_pair(game.stats, String(second.id).trim_prefix("tactic_"))
	_check(not preview.is_empty(), "level six proposes the missing partner")
	game._on_upgrade_chosen(second)
	_check(CombatTactics.active_pairs(game.stats).size() == 1, "real selection activates the advertised pair")
	_check(game.hud._toast_title.text.contains(str(preview["title"])) or game.hud._toast_queue.any(func(item: Array) -> bool: return str(item[0]).contains(str(preview["title"]))), "activation identifies the build")
	_check(game._build_report().contains(str(preview["title"])) and not game._build_report().contains("Следующий забег:"), "run report remembers the completed build")
	game.free()
	get_tree().paused = false
	BulletPool.release_all()
	await get_tree().process_frame

func _shot(tactics: CombatTactics, target: Enemy) -> float:
	BulletPool.release_all()
	tactics._turret_shot = 0.0
	var before := target.hp
	tactics._tick_sentry(0.01)
	_check(BulletPool.get_active_count() == 1, "turret emits one real projectile")
	await get_tree().create_timer(0.45).timeout
	return before - target.hp

func _test_turret() -> void:
	var game := _new_game()
	game.player.global_position = Vector2(10000,10000)
	var wc := game.player.weapon_controller
	var target := game.enemies.spawn(ContentDB.get_enemy(&"dropper"), game.player.global_position + Vector2(200,46), 1000.0)
	target.set_physics_process(false)
	game.tactics._find_target = func(_at: Vector2, _range: float) -> Node2D: return target
	game.tactics._still = 1.3
	for frame in 3: await get_tree().physics_frame
	for tier in [1,5]:
		game.tactics._still = 1.3
		game.tactics._last_pos = game.player.global_position
		game.stats = RunStats.new()
		game.stats.multi_weapon_context = true
		game.tactics.stats = game.stats
		game.stats.apply(_tactic("sentry"))
		for rank_index in 3: game.stats.apply(_tactic("switcher"))
		var pistol := WeaponDB.get_weapon(&"pistol_v1").with_tier(tier)
		var sniper := WeaponDB.get_weapon(&"sniper_v1").with_tier(tier)
		pistol.crit_chance = 0.0
		sniper.crit_chance = 0.0
		wc.setup(game.tactics._find_target, pistol, game.stats)
		wc.set_physics_process(false)
		wc.set_slot(1, sniper)
		game.tactics._swap_left = 0.0
		var ordinary: float = await _shot(game.tactics, target)
		_check(ordinary > 0.0, "turret aims at a flying enemy's body")
		wc.switch_slot(1)
		_check(game.stats.switch_boost_left > 0.0, "real swap starts the temporary window")
		var expected := clampf(sniper.with_run_stats(game.stats).damage * 0.25, 8.0,35.0)
		var hp := target.hp
		game.tactics._turret_shot = 0.0
		game.tactics._tick_sentry(0.01)
		var in_flight: Bullet = BulletPool._active.back()
		_check(is_equal_approx(in_flight.weapon.damage * in_flight.damage_scale, expected * 1.4), "turret adds forty percent without double-counting player's swap multiplier")
		game.tactics._turret_shot = 99.0
		game.tactics._physics_process(2.5)
		_check(game.stats.switch_boost_left <= 0.0 and is_equal_approx(in_flight.weapon.damage * in_flight.damage_scale, expected * 1.4), "expiry preserves the boost on a projectile already in flight")
		await get_tree().create_timer(0.45).timeout
		var boosted := hp - target.hp
		var normal: float = await _shot(game.tactics, target)
		_check(is_equal_approx(normal, expected) and absf(boosted / maxf(normal, 0.001) - 1.4) < 0.001, "actual landed damage returns to normal after the timed window")
		measurements.append({"weapon_tier":tier,"turret_normal":normal,"turret_boosted":boosted,"ratio":boosted/maxf(normal,0.001)})
		print("BUILD_MEASURE ",measurements.back())
	game.free()
	BulletPool.release_all()
	await get_tree().process_frame

func _test_layout() -> void:
	var output := OS.get_environment("BUILD_OUT")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var panel := LevelUpPanel.new()
	add_child(panel)
	for dimensions in [Vector2i(960,540),Vector2i(1280,720)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		for pair: Dictionary in CombatTactics.PAIRS:
			var run := RunStats.new()
			run.multi_weapon_context = true
			run.apply(_tactic(pair["ids"][0]))
			var choices: Array[UpgradeData] = [_tactic(pair["ids"][1]),_pick("damage_up"),_pick("move_speed")]
			panel.open(choices,6,run,false,"ПЕРЕБРОСИТЬ",true)
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
			_check(panel._holder.scale.x >= 0.75, "synergy descriptions retain readable scale")
			for card: Control in panel._cards.get_children():
				_check(bounds.grow(1).encloses(card.get_global_rect()), "all three cards stay on screen")
			_check(bounds.grow(1).encloses(panel._reroll.get_global_rect()), "reroll stays on screen")
			var labels := panel._cards.get_child(0).find_children("*","Label",true,false)
			_check(labels.any(func(label: Label) -> bool: return label.text == "СИНЕРГИЯ · ОТКРЫТЬ"), "completing card has an explicit milestone label")
			if not output.is_empty(): get_viewport().get_texture().get_image().save_png(output.path_join("pair-%d-%s-%s.png" % [dimensions.x,pair["ids"][0],pair["ids"][1]]))
	panel.queue_free()
	for frame in 4: await get_tree().process_frame
