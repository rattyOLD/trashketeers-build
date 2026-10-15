extends Node2D
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("RISK_REWARD: " + label)
func _snap(game: Game, label: String, at: Vector2) -> void:
	var output := OS.get_environment("RISK_OUT")
	if output.is_empty(): return
	game.hud._clear_wave_titles()
	game.hud._chapter_card.visible = false
	game.camera.global_position = at
	game.camera.reset_smoothing()
	for frame in 8: await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	SaveService.data["objects_intro_count"] = 2
	SaveService.data["survival_intro_seen"] = true
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var game := Game.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.start()
	for node: Node in [game,game.director,game.events,game.hazards,game.player,game.player.weapon_controller,game.enemies,game.tactics,game.status,game.pickups,BulletPool]:
		node.set_physics_process(false)
	game.enemies.release_all()
	_check(not game.map.route_caches.is_empty() and game.map.route_caches.size() <= 2,"bounded optional route caches exist")
	var safe := game.map.route_caches[0]
	safe.set_physics_process(false)
	game.player.hp = game.player.max_hp * 0.5
	var wallet := game.nuts
	game.player.position = safe.global_position + safe.control_offset
	await _snap(game,"before-choice",safe.global_position + safe.control_offset * 0.35)
	for i in 21: safe._physics_process(0.1)
	_check(safe.control_used and not safe.alarm_started,"safe path chooses switch")
	safe.off_left = 0.0
	game.player._invuln = 100.0
	game.player.position = safe.global_position + safe.cache_offset
	for i in 29: safe._physics_process(0.1)
	_check(safe.claimed and game.nuts == wallet + 15 and is_equal_approx(game.player.hp,game.player.max_hp * 0.75),"safe reward remains healing and fifteen after timer expires")
	var cache_goal: Dictionary = {}
	for row: Dictionary in game._optional_goal_rows():
		if row.get("tag", "") == "СКЛАДЫ ГЛАВЫ": cache_goal = row
	_check(cache_goal.get("progress",0) == 1 and cache_goal.get("goal",0) == game.map.route_caches.size(),"optional chapter goal reports real claimed caches")
	for i in 100: safe._physics_process(0.1)
	_check(game.nuts == wallet + 15 and is_equal_approx(game.player.hp,game.player.max_hp * 0.75),"safe claim cannot duplicate healing or coins")
	var risk := RouteCache.new()
	risk.cache_offset = Vector2.ZERO
	risk.control_offset = Vector2(240,0)
	risk.position = safe.position + Vector2(0,500)
	risk.player = game.player
	risk.enemies = game.enemies
	game.layers.decals.add_child(risk)
	risk.set_physics_process(false)
	risk.resolved.connect(game._on_route_cache_resolved)
	game.player.position = risk.global_position
	wallet = game.nuts
	game.player._invuln = 0.0
	game.player.shield = 0.0
	game.player.vest = 0
	var hp_before_opening := game.player.hp
	for i in 29: risk._physics_process(0.1)
	_check(game.player.hp == hp_before_opening,"opening has no unavoidable pulse damage")
	risk._age = RouteCache.WARNING - 0.1
	risk._tick = 0.0
	risk._physics_process(0.05)
	_check(game.player.hp == hp_before_opening,"committing gives a full warning before damage")
	risk._physics_process(0.1)
	_check(game._combat_report.last_source == &"route_cache" and game._combat_report.received > 0.0,"real cache damage reaches the distinct death report")
	game.player._invuln = 100.0
	_check(risk.alarm_started and not risk.claimed and game.nuts == wallet,"risk requires defense before reward")
	risk._age = 1.7
	risk.queue_redraw()
	await _snap(game,"center-pulse",risk.global_position + risk.control_offset * 0.35)
	risk._age = RouteCache.CYCLE + 1.7
	risk.queue_redraw()
	await _snap(game,"outer-pulse",risk.global_position + risk.control_offset * 0.35)
	var progress_before_leaving := risk.defense_progress
	risk._age = 0.0
	_check(risk._in_danger(risk.global_position) and not risk._in_danger(risk.global_position + Vector2(150,0)), "inner warning identifies center danger")
	risk._age = RouteCache.CYCLE + 0.2
	_check(not risk._in_danger(risk.global_position) and risk._in_danger(risk.global_position + Vector2(150,0)), "next warning moves real danger to outer ring")
	risk._age = 0.0
	game.player.position = risk.global_position + Vector2(600,0)
	for i in 120: risk._physics_process(0.1)
	_check(risk.defense_progress == progress_before_leaving,"leaving suspends defense without hidden progress")
	game.player.position = risk.global_position + risk.control_offset
	for i in 21: risk._physics_process(0.1)
	_check(not risk.control_used,"committed risk cannot switch to free safe supplies")
	game.player.position = risk.global_position + Vector2(150,0)
	for i in 79: risk._physics_process(0.1)
	if not risk.claimed: risk._physics_process(0.1)
	_check(risk.claimed and game.nuts == wallet + 40,"ten active seconds finish defense once")
	_check(game._bonus_open and get_tree().paused and game.hud._level_up._choices.size() == 3,"danger reward opens actual three-way upgrade choice")
	await _snap(game,"reward-choice",risk.global_position)
	var choice: UpgradeData = game.hud._level_up._choices[0]
	var before := game.stats.get_stat(choice.stat)
	var level_before := game.level
	game.hud._level_up._armed_at = 0
	game.hud._level_up._pick(0)
	_check(game.stats.get_stat(choice.stat) > before and game.level == level_before and not get_tree().paused,"chosen firmware affects run without consuming a level")
	for i in 100: risk._physics_process(0.1)
	_check(game.nuts == wallet + 40 and not game._bonus_open and game._bonus_queue.is_empty(),"risk cannot duplicate bonus or coins")
	var arc_cache_before := PolyBatch._arcs.size()
	for i in 10000:
		risk._progress_arc(Vector2.ZERO, 105.0 if i % 2 == 0 else 245.0, float(i) / 9999.0, Color.RED, 4.0)
		risk._batch.points.clear()
		risk._batch.colors.clear()
	_check(PolyBatch._arcs.size() - arc_cache_before <= 130,"ten thousand distinct timer samples keep the global arc cache bounded")
	risk.free()
	game.free()
	BulletPool.release_all()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1,true,false,true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("RISK_REWARD failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
