extends Node
## Новый и существующий профиль запускают выживание без сюжетного прогресса и флага тестера.
var failures := 0
var launches := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("SURVIVAL_ACCESS FAIL: " + message)

func _run() -> void:
	Orient.portrait = false
	Controls.apply_keys()
	Cloud.waiting_choice = true
	for profile in [{"runs":0,"missions":0},{"runs":20,"missions":0},{"runs":20,"missions":6}]:
		SaveService.data = SaveService.DEFAULTS.duplicate(true)
		SaveService._sanitize_arsenal()
		SaveService.data["runs"] = profile["runs"]
		SaveService.data["stats"]["story_missions"] = profile["missions"]
		SaveService.data["tester"]["survival_open"] = false
		SaveService.data["whatsnew_seen"] = ChangelogPopup.latest_key()
		SaveService.data["acct_hint"] = true
		var menu := MainMenuUI.new()
		add_child(menu)
		await get_tree().process_frame
		_check(menu._mode == MainMenuUI.Mode.SURVIVAL, "survival selected by default " + str(profile))
		_check(menu._mode_buttons[0].text == "ВЫЖИВАНИЕ" and not menu._mode_buttons[0].disabled, "survival button available")
		_check(menu._mode_buttons[0].get_child_count() == 0, "survival has no lock overlay")
		menu._on_mode_pressed(MainMenuUI.Mode.RAID)
		menu._on_mode_pressed(MainMenuUI.Mode.SURVIVAL)
		_check(menu._mode == MainMenuUI.Mode.SURVIVAL, "player can select survival without campaign")
		menu._mode_intro.close()
		menu.start_requested.connect(func(_weapon: StringName) -> void: launches += 1)
		var before := launches
		menu._on_play()
		_check(menu._objects_intro.visible, "new profile retains arena onboarding")
		menu._objects_intro._done()
		_check(launches == before + 1, "onboarding starts survival")
		SaveService.data["objects_intro_count"] = ObjectsIntroPopup.SHOWS
		menu._on_play()
		_check(launches == before + 2, "returning player starts survival directly")
		_check(SaveService.get_stat("story_missions") == int(profile["missions"]), "access does not forge campaign progress")
		menu.free()
		await get_tree().process_frame
	SaveService.data["stats"]["story_missions"] = 0
	var game := Game.new()
	add_child(game)
	game.start()
	await get_tree().create_timer(0.5).timeout
	_check(game.story_mission.is_empty() and game.player != null and is_instance_valid(game.hud), "survival battle starts without campaign progress")
	game.free()
	print("SURVIVAL_ACCESS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
