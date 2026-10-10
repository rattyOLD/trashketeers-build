extends Node
## Проверка отрисованного мира и мини-карты при паузе и смене раскладки HUD.
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("PAUSED_WORLD FAIL: " + message)


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw


func _frozen(battle: BattleBase, reason: String) -> void:
	# UI может анимироваться на паузе; сравнивается весь мир без слоя HUD.
	battle.hud.hide()
	await _frames(5)
	var baseline := get_viewport().get_texture().get_image().get_data()
	var light_time := battle.light_map._clock
	var shader_time := WorldClock.elapsed
	var minimap := battle.hud._minimap
	var minimap_time: float = minimap._time if minimap != null else 0.0
	for i in 12:
		if i % 3 == 0:
			battle.hud.apply_layout()
		await _frames(1)
		_check(battle.hud._minimap_slot.modulate.a == 0.0, reason + " layout cannot reveal minimap")
		var pixels := get_viewport().get_texture().get_image().get_data()
		_check(pixels == baseline, reason + " world pixels unchanged, frame " + str(i))
	_check(battle.light_map._clock == light_time, reason + " light clock frozen")
	_check(WorldClock.elapsed == shader_time, reason + " shader clock frozen")
	if minimap != null:
		_check(minimap._time == minimap_time, reason + " minimap markers frozen")
	battle.hud.show()


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["tips_off"] = true
	WeaponController.force_auto = true
	Controls.apply_keys()
	EnvLights.clear()
	var source_id := EnvLights.add(Vector2.ZERO, Color.RED, 100.0, 0.5)
	var buffer := EnvLights.LightBuffer.new()
	for i in 100:
		EnvLights.collect(Rect2(-200, -200, 400, 400), buffer)
		_check(buffer.positions.size() == 1 and buffer.colors.size() == 1 and buffer.radii.size() == 1, "light collection replaces prior frame")
		_check(buffer.positions[0] == Vector2.ZERO and buffer.colors[0].r == 0.5, "environment light reaches caller")
		buffer.positions.append(Vector2.ONE)
		buffer.colors.append(Color.WHITE)
		buffer.radii.append(420.0)
	EnvLights.remove(source_id)
	for case in [["survival", 0], ["survival", 1], ["story", 1], ["raid", 1]]:
		var mode: String = case[0]
		SaveService.data["quality"] = case[1]
		var battle: BattleBase = Raid.new() if mode == "raid" else Game.new()
		battle.process_mode = Node.PROCESS_MODE_PAUSABLE
		if mode == "story":
			(battle as Game).story_mission = "m1"
		add_child(battle)
		battle.start()
		await _frames(12)
		_check((battle.atmosphere._grade != null) == (int(case[1]) > 0), mode + " grade follows quality")
		Input.action_press(&"move_right")
		await _frames(12)
		battle.add_shake(0.6)
		await _frames(2)
		battle._open_pause()
		Input.action_release(&"move_right")
		_check(get_tree().paused and battle.hud.is_pause_open(), mode + " ordinary pause opens")
		await _frozen(battle, mode + " q=" + str(case[1]) + " pause")
		battle.hud._pause._resume()
		var before_resume := WorldClock.elapsed
		var before_light := battle.light_map._clock
		await _frames(6)
		_check(WorldClock.elapsed > before_resume and battle.light_map._clock > before_light, mode + " animation resumes")
		_check(battle.hud._minimap_slot.modulate.a == float(battle.hud._minimap_slot.get_meta("ui_alpha", 1.0)), mode + " minimap opacity restored")
		if mode == "survival":
			var game := battle as Game
			game._pending_levelups = 1
			game._level_up_open = true
			game._open_level_up()
			_check(get_tree().paused and game.hud._level_up.visible, "level-up opens paused")
			await _frozen(battle, "level-up")
			get_window().size = Vector2i(960, 540)
			await _frozen(battle, "resized level-up")
			game.hud._level_up._armed_at = 0
			game.hud._level_up._pick(0)
			_check(not get_tree().paused, "upgrade choice resumes")
		battle.queue_free()
		get_tree().paused = false
		await _frames(3)
	print("PAUSED_WORLD failures=", failures)
	get_tree().quit(1 if failures else 0)
