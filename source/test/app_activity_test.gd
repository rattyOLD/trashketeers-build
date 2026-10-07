extends Node

var failures := 0

class Probe extends Node:
	var ticks := 0
	var physics_ticks := 0

	func _process(_delta: float) -> void:
		ticks += 1

	func _physics_process(_delta: float) -> void:
		physics_ticks += 1


func _ready() -> void:
	WeaponController.force_auto = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("APP_ACTIVITY FAIL: " + label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	Controls.apply_keys()
	var always := Probe.new()
	always.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(always)
	var normal := Probe.new()
	add_child(normal)
	var only_paused := Probe.new()
	only_paused.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(only_paused)
	await _frames(3)
	var cap := Engine.max_fps
	var rendering := RenderingServer.is_render_loop_enabled()
	AppActivity._set_backgrounded(true)
	_check(get_tree().paused and AppActivity.backgrounded, "menu sleeps")
	_check(not RenderingServer.is_render_loop_enabled() and Engine.max_fps == 5, "hidden rendering off and idle cap")
	_check(AudioServer.is_bus_mute(0), "hidden audio muted")
	await _frames(2)
	var counts := [always.ticks, always.physics_ticks, normal.ticks, normal.physics_ticks, only_paused.ticks]
	await _frames(3)
	_check(counts == [always.ticks, always.physics_ticks, normal.ticks, normal.physics_ticks, only_paused.ticks], "all process modes and physics stop")
	var late := Probe.new()
	late.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(late)
	await _frames(2)
	_check(late.process_mode == Node.PROCESS_MODE_DISABLED, "new root service sleeps after ready")
	always.queue_free()
	await _frames(1)
	AppActivity._set_backgrounded(true)
	AppActivity._set_backgrounded(false)
	_check(not get_tree().paused, "menu returns without a stuck pause")
	_check(late.process_mode == Node.PROCESS_MODE_ALWAYS and only_paused.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "original modes restored and freed nodes ignored")
	_check(Engine.max_fps == cap and RenderingServer.is_render_loop_enabled() == rendering, "foreground render settings restored")
	_check(not AudioServer.is_bus_mute(0), "foreground audio restored")
	_check(AppActivity._suspended.is_empty(), "suspension references cleared")
	late.queue_free()
	var native := Platform.is_native_app
	Platform.is_native_app = true
	AppActivity.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	AppActivity.notification(NOTIFICATION_APPLICATION_PAUSED)
	AppActivity.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(AppActivity.backgrounded, "focus-in alone cannot override Android pause")
	AppActivity.notification(NOTIFICATION_APPLICATION_RESUMED)
	_check(not AppActivity.backgrounded and not get_tree().paused, "Android resumes after both states clear")
	AppActivity.notification(NOTIFICATION_APPLICATION_PAUSED)
	AppActivity.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	AppActivity.notification(NOTIFICATION_APPLICATION_RESUMED)
	_check(AppActivity.backgrounded, "resume alone cannot override Android focus loss")
	AppActivity.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not AppActivity.backgrounded, "reverse notification order restores foreground")
	Platform.is_native_app = false
	AppActivity.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not AppActivity.backgrounded, "web/desktop blur is ignored")
	Platform.is_native_app = native
	for mode in ["survival", "story", "raid", "mod:blast"]:
		SaveService.data["run_mod"] = "blast" if mode == "mod:blast" else ""
		var battle: BattleBase = Raid.new() if mode == "raid" else Game.new()
		if mode == "story":
			(battle as Game).story_mission = "m1"
		add_child(battle)
		battle.start()
		await _frames(2)
		Input.action_press(&"move_right")
		battle.hud.joystick.output = Vector2.RIGHT
		battle.hud._slot_bar._hold_index = 0
		battle.hud._interact._touch = 1
		battle.hud._hold._index = 0
		AppActivity._set_backgrounded(true)
		_check(battle.hud.is_pause_open(), mode + " opens ordinary pause")
		_check(not Input.is_action_pressed(&"move_right") and battle.hud.joystick.output == Vector2.ZERO, mode + " clears held input")
		_check(battle.hud._slot_bar._hold_index == -1 and battle.hud._interact._touch == -1 and battle.hud._hold._index == -1, mode + " clears pending touch holds")
		var pos := battle.player.global_position
		var hp := battle.player.hp
		var age := battle._perf_age
		await _frames(3)
		_check(battle.player.global_position == pos and battle.player.hp == hp and battle._perf_age == age, mode + " battle does not advance hidden")
		AppActivity._set_backgrounded(false)
		_check(get_tree().paused and battle.hud.is_pause_open(), mode + " waits for explicit continue")
		battle.hud._pause._resume()
		_check(not get_tree().paused, mode + " continue works")
		if mode == "survival":
			var game := battle as Game
			game._pending_levelups = 1
			game._level_up_open = true
			game._open_level_up()
			_check(game._level_up_open and get_tree().paused, "level-up starts paused")
			AppActivity._set_backgrounded(true)
			AppActivity._set_backgrounded(false)
			_check(game._level_up_open and get_tree().paused and not game.hud.is_pause_open(), "level-up preserved without extra pause window")
			game.hud._level_up._armed_at = 0
			game.hud._level_up._pick(0)
			_check(not get_tree().paused, "upgrade choice still resumes battle")
		battle.queue_free()
		await _frames(2)
	get_tree().paused = false
	print("APP_ACTIVITY_TEST failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
