extends Node2D
var failures := 0
var output := ""


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("ENVIRONMENT_POLISH FAIL: " + message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _settle() -> void:
	await get_tree().create_timer(0.4, true, false, true).timeout
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	if not output.is_empty():
		get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 0
	SaveService.data["tips_off"] = true
	Orient.portrait = false
	Controls.apply_keys()
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	output = OS.get_environment("ENVIRONMENT_POLISH_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	_test_report()
	_test_audio()
	var game := Game.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.start()
	game.set_physics_process(false)
	game.director.set_physics_process(false)
	game.events.set_physics_process(false)
	game.hazards.set_physics_process(false)
	game.player.set_physics_process(false)
	game.enemies.release_all()
	game.hud._chapter_card.hide()
	await _settle()
	var preview := RaccoonVisual.new()
	_check(game.player.visual.battle_marker and not preview.battle_marker, "marker belongs to combat, not menu previews")
	preview.free()
	await _test_maps(game)
	_test_suppression(game)
	await _test_cache(game)
	await _test_result(game)
	game.free()
	get_tree().paused = false
	# Музыкальный автолоад переживает Game: дождаться остановки Ogg-декодера до quit.
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	# Даём отложенным освобождениям окон и GPU-ресурсов завершиться до выхода.
	for frame in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("ENVIRONMENT_POLISH failures=", failures)
	get_tree().quit.call_deferred(0 if failures == 0 else 1)


func _test_report() -> void:
	var report := CombatReport.new()
	report.record_received(30, &"acid")
	report.advance(4.1)
	report.record_received(12, &"shock")
	report.record_received(8, &"projectile")
	var recent := report.recent_damage()
	_check(recent.size() == 2 and recent[0]["amount"] == 12, "old damage excluded from the four-second death context")
	_check(report.lines(true).contains("Последний удар: пуля") and not report.lines(false).contains("Перед гибелью"), "death cause and recent context appear only on defeat")
	for i in 30:
		report.record_received(1, &"projectile")
	_check(report._recent.size() == CombatReport.RECENT_LIMIT, "recent damage buffer stays bounded")


func _test_audio() -> void:
	_check(SoundManager._streams.has(&"k_mat_metal") and SoundManager._streams.has(&"k_stick_crystal"), "material feedback uses existing imported audio")
	SoundManager.unlocked = true
	SoundManager._budget = SoundManager.SFX_BUDGET_BURST
	SoundManager._budget_ms = Time.get_ticks_msec()
	SoundManager._last_played_ms.clear()
	SoundManager._impact_ms = -100000
	SoundManager.play_impact(true)
	var budget := SoundManager._budget
	for i in 50:
		SoundManager.play_impact(false)
	_check(SoundManager._budget == budget and not SoundManager._last_played_ms.has(&"hit"), "mixed crowd impacts share one rate limit")
	SoundManager._impact_ms = -100000
	SoundManager.play_impact(false, true)
	_check(SoundManager._last_played_ms.has(&"hit"), "unarmored hits use the body sample")
	SoundManager._process(0.1)
	_check(SoundManager._duck_db < 0, "combat briefly lowers background audio")
	SoundManager._combat_left = 0
	SoundManager._process(1)
	_check(is_zero_approx(SoundManager._duck_db), "background recovers without changing user volume")
	SoundManager._last_warning_ms = -100000
	SoundManager.play_warning(&"beam_charge")
	var warning := SoundManager._players[-1].stream
	SoundManager._impact_ms = -100000
	SoundManager.play_impact(true)
	_check(SoundManager._players.size() == 12 and SoundManager._players[-1].stream == warning, "impacts preserve the warning channel and player pool")


func _test_maps(game: Game) -> void:
	for theme in ["night_dump", "acid_rain", "gold_vault", "pigeon_roofs", "bank"]:
		game.map.clear()
		await _settle()
		var chapter := ContentDB.get_chapter(3 if theme == "bank" else 0).duplicate(true)
		chapter["map_card"] = "" if theme == "bank" else theme
		var floor_path := "res://assets/maps/%s/floor.png" % theme
		if theme != "bank" and ResourceLoader.exists(floor_path):
			chapter["ground"] = floor_path
		seed(49317)
		game.map.build(game.layers, chapter)
		game.map.attach_player(game.player)
		_check(not game.map.route_caches.is_empty() and game.map.route_caches.size() <= 2, "bounded optional caches " + theme)
		var reached := game.map._reachable_from(game.map.world_to_cell(game.map.player_start))
		_check(game.map._first_isolated(reached) == Vector2i(-1, -1), "cache graphics do not block navigation " + theme)
		for cache in game.map.route_caches:
			cache.set_physics_process(false)
			_check(cache.enemies == game.enemies and game.map.is_area_clear(cache.position + cache.control_offset, 65), "control is accessible and trap knows enemy pool " + theme)
			_check(game.map.is_area_clear(cache.position + cache.cache_offset, 55), "reward sits on accessible ground " + theme)
			game.camera.position = cache.position
			game.camera.reset_smoothing()
			game.player.position = cache.position + Vector2(0, 60)
			await _settle()
			await _shot("route_" + theme)
			break


func _test_suppression(game: Game) -> void:
	var h := game.hazards
	h.clear()
	h._add_zone(HazardDirector.Kind.SHOCK, Vector2.ZERO, Vector2.ZERO, 1)
	h._add_zone(HazardDirector.Kind.COLLAPSE, Vector2.ZERO, Vector2.ZERO, 1)
	h.suppress_area(Vector2.ZERO, 320, 30)
	_check(h._life[0] < 0 and h._life[1] > 0, "switch removes electric zones but not falling debris")
	var next := h._next
	h._add_zone(HazardDirector.Kind.LASER, Vector2(1000, 0), Vector2.RIGHT, 1)
	_check(h._next == next, "switch rejects a laser crossing the safe area even with a distant origin")
	h._add_zone(HazardDirector.Kind.ACID, Vector2(700, 700), Vector2.ZERO, 1)
	_check(h._next != next, "remote hazards remain active")
	h._timer = 100
	h._physics_process(30.1)
	_check(h._suppressed.is_empty(), "safe area expires on gameplay time")
	h.clear()


func _test_cache(game: Game) -> void:
	if game.map.route_caches.is_empty():
		return
	var cache := game.map.route_caches[0]
	cache.set_physics_process(false)
	var rewards: Array[int] = []
	cache.rewarded.connect(func(coins: int) -> void: rewards.append(coins))
	game.player.position = cache.global_position + cache.control_offset
	for i in 21:
		cache._physics_process(0.1)
	_check(cache.control_used and cache.off_left > 29, "standing at switch disables the zone")
	game.player.position = cache.global_position + cache.cache_offset
	for i in 29:
		cache._physics_process(0.1)
	_check(rewards == [15], "safe approach pays fifteen once")
	for i in 35:
		cache._physics_process(0.1)
	_check(rewards == [15], "remaining near cache cannot duplicate payment")
	var risky := RouteCache.new()
	risky.player = game.player
	risky.enemies = game.enemies
	risky.position = cache.position
	game.layers.decals.add_child(risky)
	risky.set_physics_process(false)
	risky.rewarded.connect(func(coins: int) -> void: rewards.append(coins))
	game.player.position = risky.global_position + risky.cache_offset
	game.player._invuln = 0
	game.player.shield = 0
	game.player.vest = 0
	var hp := game.player.hp
	risky._physics_process(1.5)
	_check(game.player.hp == hp, "danger has a full warning before the first hit")
	risky._physics_process(0.2)
	_check(game.player.hp == hp, "opening remains safe until the risk is committed")
	for i in 15:
		risky._physics_process(0.1)
	_check(risky.alarm_started and rewards == [15], "risky approach starts defense before reward")
	risky._age = RouteCache.WARNING + 0.01
	risky._tick = 0.0
	risky._physics_process(0.1)
	_check(game.player.hp < hp, "active warned defense has a real cost")
	game.player._invuln = 100.0
	game.player.position = risky.global_position + risky.cache_offset + Vector2(150, 0)
	for i in 101:
		risky._physics_process(0.1)
	_check(rewards == [15, 40], "completed risky defense pays forty")
	var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), risky.global_position + risky.cache_offset)
	if enemy == null:
		var data := ContentDB.get_enemy(ContentDB.get_enemy_ids()[0])
		enemy = game.enemies.spawn(data, risky.global_position + risky.cache_offset)
	if enemy != null:
		enemy.set_physics_process(false)
		var before := enemy.hp
		risky._age = 0.0
		risky._apply_zone()
		_check(enemy.hp < before, "environment can be used against enemies")
		game.enemies.release_all()
	risky.set_physics_process(true)
	game.player.position = risky.global_position + Vector2(500, 500)
	await _settle()
	game.hud._root.visible = false
	get_tree().paused = true
	var age := risky._age
	var left := cache.off_left
	await _settle()
	await _shot("pause_before")
	var before_image := get_viewport().get_texture().get_image().get_data()
	risky.queue_redraw()
	await _settle()
	_check(risky._age == age and cache.off_left == left, "pause freezes danger and switch duration")
	await _shot("pause_after")
	_check(before_image == get_viewport().get_texture().get_image().get_data(), "forced redraw does not animate the paused map")
	get_tree().paused = false
	game.hud._root.visible = true
	risky.free()
	game.player.hp = game.player.max_hp
	game.player.is_dead = true
	var clock := game._combat_report._clock
	game._physics_process(1)
	_check(game._combat_report._clock == clock, "death animation does not age the final damage context")
	game.player.is_dead = false


func _test_result(game: Game) -> void:
	game._combat_report.record_received(12, &"acid")
	game._combat_report.record_received(8, &"projectile")
	game.player.is_dead = true
	_check(game._death_tip().contains("лини"), "defeat gives advice about the fatal source")
	var summary := game._run_summary()
	summary["tip"] = game._death_tip()
	summary["total_coins"] = 0
	for size in [Vector2i(1280, 720), Vector2i(844, 390)]:
		get_window().size = size
		get_window().content_scale_size = size
		game.hud.show_run_result(summary)
		await get_tree().create_timer(0.8, true, false, true).timeout
		await RenderingServer.frame_post_draw
		_check(game.hud._run_result._tip_label.text.contains("Перед гибелью"), "recent context appears in results " + str(size))
		await _shot("defeat_" + str(size.x))
	game.player.is_dead = false
