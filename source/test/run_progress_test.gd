extends Node
var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("RUN_PROGRESS: " + label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var snapshot := SaveService.progress_snapshot()
	SaveService.add_stat("kills", 1, false)
	var text := SaveService.progress_report(snapshot)
	_check(text.contains("Первая кровь") and text.contains("Аккаунт:") and text.contains("Пропуск:"), "report remembers live achievement and shows both progress systems")
	SaveService.data["stats"]["kills"] = 290
	var closest := SaveService._closest_progress_goal()
	_check(closest.get("id") == "exterminator", "nearest visible goal reflects actual account counters")
	_check(not bool(closest.get("hidden", false)), "hidden objectives are not spoiled")
	SaveService.data["bp"] = {"season": 9, "start": SaveService.today(), "points": 3000, "claimed": [], "premium": false}
	var maximum := SaveService.progress_snapshot()
	SaveService.data["bp"]["points"] = 3400
	_check(SaveService.progress_report(maximum).contains("бонусы готовы: 1"), "completed pass points lead to the real bonus")
	var previous_season := maximum.duplicate(true)
	previous_season["season"] = 8
	previous_season["pass"] = 9000
	SaveService.data["bp"]["points"] = 50
	var rolled := SaveService.progress_report(previous_season)
	_check(rolled.contains("Новый сезон пропуска") and rolled.contains("+50 очков"), "season change reports new points without a negative delta")
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	var game := Game.new()
	add_child(game)
	game.start()
	for node: Node in [game, game.director, game.events, game.hazards, game.player, game.player.weapon_controller, game.enemies, game.tactics, game.status, game.pickups]:
		node.set_physics_process(false)
	game.enemies.release_all()
	SaveService.add_stat("kills", 1, false)
	game.kills = 1
	game.nuts = 100
	game.director._start_wave(1)
	game._on_wave_cleared(1)
	game.director.phase = WaveDirector.Phase.INTERMISSION
	_check(int(SaveService.data["best_wave"]) == 1, "wave clear has already stored the new record")
	var coins_before := SaveService.get_coins()
	var preview := int(game._run_summary()["coins"])
	game._finish()
	var panel := game.hud._run_result
	var credited := SaveService.get_coins() - coins_before
	_check(panel._title.text == "НОВЫЙ РЕКОРД!", "new record survives the earlier wave-clear save")
	_check(credited == preview and panel._reward_coins == credited, "preview, actual payout and doubling base agree")
	_check(panel._tip_label.text.contains("Аккаунт:") and panel._tip_label.text.contains("Пропуск:") and panel._tip_label.text.contains("Первая кровь"), "actual result displays credited progress and live achievements")
	var xp_after := int(SaveService.data["account_xp"])
	var pass_after := BattlePass.points()
	var wallet_after := SaveService.get_coins()
	game._finish()
	game._record()
	_check(xp_after == int(SaveService.data["account_xp"]) and pass_after == BattlePass.points() and wallet_after == SaveService.get_coins(), "repeat finish and record cannot duplicate progress or rewards")
	get_tree().paused = false
	for resolution in [Vector2i(1280, 720), Vector2i(923, 420)]:
		get_window().size = resolution
		for frame in 6: await get_tree().process_frame
		await get_tree().create_timer(0.7, true, false, true).timeout
		panel._fit_result()
		var rect := panel._panel.get_global_rect()
		var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		_check(view.grow(1.0).encloses(rect), "progress result fits the viewport at " + str(resolution))
		var bar := panel._report_scroll.get_v_scroll_bar()
		_check(bar.max_value > bar.page, "long report remains scrollable at " + str(resolution))
		panel._report_scroll.scroll_vertical = int(bar.max_value)
		for frame in 3: await get_tree().process_frame
		_check(panel._report_scroll.scroll_vertical > 0, "report bottom is reachable at " + str(resolution))
		panel._report_scroll.scroll_vertical = 0
		for frame in 3: await get_tree().process_frame
		var output := OS.get_environment("RUN_PROGRESS_OUT")
		if not output.is_empty():
			DirAccess.make_dir_recursive_absolute(output)
			get_viewport().get_texture().get_image().save_png(output.path_join("result_%dx%d.png" % [resolution.x, resolution.y]))
	game.free()
	BulletPool.release_all()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("RUN_PROGRESS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
