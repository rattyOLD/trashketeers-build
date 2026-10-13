extends Node
## Exercise both Baron phases and the actual textured liquid renderer.
var game: Game
var baron: Enemy
var elapsed := 0.0
var seen := {}
var counts := {1: {"beer_jet_v1": 0, "puke_v1": 0}, 2: {"beer_jet_v1": 0, "puke_v1": 0}}
var captured := false
var phase_two := false
var _started_ms := Time.get_ticks_msec()
var _trace_ms := 0
var _bonus_injected := false
var _bonus_handled := false
func _process(_delta: float) -> void:
	if OS.get_environment("BARON_TRACE") != "1" or baron == null:
		return
	var now := Time.get_ticks_msec()
	if now - _trace_ms < 10000:
		return
	_trace_ms = now
	print("BARON_TRACE wall=", (now - _started_ms) / 1000.0, " elapsed=", elapsed, " paused=", get_tree().paused, " bonus=", game._bonus_open, " levelup=", game._level_up_open, " dead=", game.player.is_dead, " finished=", game.finished, " bullets=", BulletPool.get_active_count(), " fps=", Engine.get_frames_per_second())
func _ready() -> void:
	Controls.apply_keys()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 1
	SaveService.data["tips_off"] = true
	SaveService.data["tester"]["god"] = true
	game = Game.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(2.0).timeout
	game.director.set_physics_process(false)
	game.enemies.release_all()
	baron = game.enemies.spawn(ContentDB.get_enemy(&"beer_baron"), game.player.global_position + Vector2(350, 0))
	game._on_boss_spawned(baron)
	if OS.get_environment("BARON_TEST_DELAY") == "1":
		# Детерминированно воспроизвести задержанный цикл, который обрывал прежний тест.
		baron.posture_stun = 12.0
func _physics_process(delta: float) -> void:
	if baron == null:
		return
	if game.hud._level_up.visible:
		game.hud._level_up._armed_at = 0
		if game._dealer_open:
			game._on_reroll_requested()
		else:
			game.hud._level_up._pick(0)
		if _bonus_injected and not get_tree().paused:
			_bonus_handled = true
	if get_tree().paused:
		return
	elapsed += delta
	if OS.get_environment("BARON_TEST_BONUS") == "1" and not _bonus_injected and elapsed >= 21.0:
		_bonus_injected = true
		game._queue_bonus(game.stats.roll_choices(game._upgrade_pool(), 3), "ПРОВЕРКА БОНУСНОГО ВЫБОРА")
	game.player.hp = game.player.max_hp
	# Не обрывать первую фазу раньше, чем она действительно показала обе атаки.
	if not phase_two and elapsed >= 20.0 and _phase_complete(1):
		phase_two = true
		print("BARON_STREAM phase1_complete t=", elapsed, " brain_t=", baron._brain._fight_time)
	baron.hp = baron.max_hp * (0.4 if phase_two else 1.0)
	var live_beer := 0
	for bullet: Bullet in BulletPool._active:
		if bullet.weapon.id not in [&"beer_jet_v1", &"puke_v1"]:
			continue
		var key := str(bullet.get_instance_id()) + ":" + str(bullet.spawn_frame)
		if not seen.has(key):
			seen[key] = true
			counts[baron._brain.phase][str(bullet.weapon.id)] += 1
		if bullet.weapon.id == &"beer_jet_v1":
			live_beer += 1
	if live_beer >= 6 and not captured:
		captured = true
		_snapshot.call_deferred()
	if elapsed >= 75.0 or (elapsed >= 45.0 and captured and _phase_complete(1) and _phase_complete(2)):
		print("BARON_STREAM counts=", counts, " captured=", captured, " bonus_handled=", _bonus_handled)
		var passed := captured and (OS.get_environment("BARON_TEST_BONUS") != "1" or _bonus_handled)
		for phase: int in counts:
			for weapon: String in counts[phase]:
				passed = passed and counts[phase][weapon] > 0
		print("BARON_STREAM failures=0" if passed else "BARON_STREAM failures=1")
		get_tree().quit(0 if passed else 1)
func _phase_complete(phase: int) -> bool:
	return counts[phase]["beer_jet_v1"] > 0 and counts[phase]["puke_v1"] > 0
func _snapshot() -> void:
	await RenderingServer.frame_post_draw
	if not OS.get_environment("OUT").is_empty():
		get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
