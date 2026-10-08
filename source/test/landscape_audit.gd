extends Node

var failures := 0
var main: Node
var output := ""


func _ready() -> void:
	WeaponController.force_auto = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("LANDSCAPE_AUDIT FAIL: " + label)


func _settle() -> void:
	await get_tree().create_timer(0.8, true).timeout
	for i in 8:
		await get_tree().process_frame


func _inside(control: Control, label: String) -> void:
	var area := get_viewport().get_visible_rect().grow(2.0)
	_check(area.encloses(control.get_global_rect()), label + " fits " + str(control.get_global_rect()))


func _shot(label: String) -> void:
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))


func _run() -> void:
	output = OS.get_environment("LANDSCAPE_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2(390, 844), Vector2(844, 390), Vector2(1280, 720), Vector2(720, 1280)]:
		_check(not Orient.wants_portrait(size.x, size.y), "horizontal at " + str(size))
	_check(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == DisplayServer.SCREEN_SENSOR_LANDSCAPE, "APK uses sensor landscape")
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	SaveService.data["whatsnew_seen"] = "v35"
	var previous := Controls.default_config(true)
	previous["layout_v"] = 9
	previous["layout"]["dash"] = {"x": 0.2, "y": 0.3, "s": 1.2}
	previous["keys"] = {"dash": [KEY_X]}
	previous["auto_pick"] = true
	SaveService.data["controls"] = previous
	var migrated := Controls.config()
	_check(int(migrated["layout_v"]) == 12 and migrated.has("portrait_layout_backup"), "old layout backed up and migrated")
	_check(bool(migrated["left_handed"]) and bool(migrated["auto_pick"]) and int(migrated["keys"]["dash"][0]) == KEY_X, "preferences and bindings preserved")
	_check(float(migrated["portrait_layout_backup"]["layout"]["dash"]["s"]) == 1.2, "custom portrait layout remains in backup")
	Controls.apply_preset(false)
	_check(Controls.config().has("portrait_layout_backup"), "changing handedness preserves backup")
	for left in [false, true]:
		for big in [false, true]:
			if big:
				Controls.apply_big(left)
			else:
				Controls.apply_preset(left)
			for count in [2, 3]:
				var areas: Array[Rect2] = []
				for id in Controls.ELEMENTS:
					var control := Control.new()
					var base := BattleControls.slots_base_size(count) if id == "slots" else Vector2.ZERO
					Controls.place(control, id, Vector2(1280, 720), base)
					var area := Rect2(control.position, control.size)
					_check(Rect2(0, 0, 1280, 720).encloses(area), "preset button fits " + id)
					for previous_area in areas:
						_check(not previous_area.intersects(area), "preset buttons do not overlap " + id)
					areas.append(area)
					control.free()
	SaveService.data["controls"] = Controls.default_config()
	Controls.apply_keys()
	Cloud.waiting_choice = false
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	add_child(main)
	await _settle()
	var intro := main.get_node_or_null("OrientationIntro") as OrientationIntro
	if intro == null:
		for child in main.get_children():
			if child is OrientationIntro:
				intro = child as OrientationIntro
	_check(is_instance_valid(intro), "native startup guidance is visible")
	if is_instance_valid(intro):
		_inside(intro._cover, "startup guidance")
		await _shot("orientation-intro")
		AppActivity._set_backgrounded(true)
		await get_tree().create_timer(2.3, true).timeout
		_check(is_instance_valid(intro), "startup animation waits while backgrounded")
		AppActivity._set_backgrounded(false)
	await get_tree().create_timer(1.5, true).timeout
	_check(not is_instance_valid(intro), "startup guidance removes itself")
	_check(not Orient.portrait and get_window().content_scale_size == Orient.LANDSCAPE_SIZE, "main uses horizontal viewport")
	var menu := main._screen as MainMenuUI
	await _shot("menu")
	for id in ["_settings", "_camp", "_shop", "_armory", "_upgrades", "_account", "_tester"]:
		var popup := menu.get(id) as GlassPopup
		popup.open()
		await get_tree().create_timer(0.85).timeout
		await _settle()
		_inside(popup._panel, id)
		await _shot(id.trim_prefix("_"))
		popup.visible = false
		GlassPopup._open_stack.erase(popup)
	var loading := LoadingScreen.new()
	main.add_child(loading)
	loading.set_progress(78.0)
	await _settle()
	_inside(loading._title, "native loading title")
	_inside(loading._bar, "native loading progress")
	await _shot("loading")
	loading.queue_free()
	var editor := ControlEditor.new()
	menu.add_child(editor)
	editor.open()
	await _settle()
	_inside(editor._panel, "control editor")
	await _shot("editor")
	editor.queue_free()
	for mode in ["survival", "story", "raid"]:
		var battle: BattleBase = Raid.new() if mode == "raid" else Game.new()
		if mode == "story":
			(battle as Game).story_mission = "m1"
		main._swap_screen(battle)
		battle.start()
		await _settle()
		_inside(battle.hud._skill, mode + " skill")
		_inside(battle.hud._dash, mode + " dash")
		_inside(battle.hud._slot_bar, mode + " weapon slots")
		_inside(battle.hud._interact, mode + " pickup")
		_check(is_equal_approx(battle.camera.zoom.x, BattleBase.LANDSCAPE_ZOOM) and BattleBase.LANDSCAPE_ZOOM < 1.0, mode + " camera shows more arena")
		await _shot(mode)
		await get_tree().create_timer(3.0).timeout
		battle.hud._barks.say("heal", true)
		battle.hud.toast("АДРЕНАЛИН!", "+35% скорострельности и +15% скорости на 20 с")
		await _settle()
		await _shot(mode + "-combat")
		var dash_touch := InputEventScreenTouch.new()
		dash_touch.pressed = true
		dash_touch.index = 1
		dash_touch.position = battle.hud._dash.get_global_rect().get_center()
		battle.player.dash_remaining = 0.0
		battle.hud._dash._input(dash_touch)
		_check(battle.player.dash_remaining > 0.0, mode + " dash touch activates")
		battle._open_pause()
		await _settle()
		_inside(battle.hud._pause._panel, mode + " pause")
		await _shot(mode + "-pause")
		battle.hud._pause._resume()
		if mode == "survival":
			var game := battle as Game
			game._pending_levelups = 1
			game._level_up_open = true
			game._open_level_up()
			await _settle()
			_inside(game.hud._level_up._box, "upgrade choices")
			await _shot("level-up")
			game.hud._level_up._armed_at = 0
			game.hud._level_up._pick(0)
			var dash_choices: Array[UpgradeData] = []
			for upgrade in ContentDB.get_upgrades():
				if upgrade.category in ["dash", "dash_element"]:
					dash_choices.append(upgrade)
			for group in [dash_choices.slice(0, 3), dash_choices.slice(3, 6)]:
				game.hud._level_up.open(group, 8, game.stats)
				await _settle()
				for card in game.hud._level_up._cards.get_children():
					_inside(card, "dash upgrade card")
					for label in card.get_child(0).get_children():
						_check(card.get_global_rect().grow(1.0).encloses(label.get_global_rect()), "dash card text fits " + label.text + " " + str(label.get_global_rect()) + " inside " + str(card.get_global_rect()))
				await _shot("dash-perks-" + str(group[0].id))
			game.hud._level_up.visible = false
		battle._show_result(false, PackedStringArray(["Тест результата", "Врагов: 123", "Монет: 42", "Уровень: 8", "Время: 10:30", "Совет: продолжай играть"]))
		await _settle()
		_inside(battle.hud._result._panel, mode + " result")
		await _shot(mode + "-result")
		main._show_menu()
		await _settle()
	print("LANDSCAPE_AUDIT failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
