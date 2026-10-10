extends Node2D
## Выбор реальной цели, работа метки на паузе и компоновка карточек сочетаний.
var failures := 0
var output := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("NAVIGATION_CHOICES FAIL: " + message)


func _settle() -> void:
	await get_tree().create_timer(0.7, true, false, true).timeout
	await RenderingServer.frame_post_draw


func _run() -> void:
	SaveService._apply_text('{"objects_intro_count":2,"survival_unlock_seen":true,"survival_intro_seen":true}')
	_check(int(SaveService.data.get("objects_intro_count", 0)) == 2 and bool(SaveService.data.get("survival_unlock_seen", false)) and bool(SaveService.data.get("survival_intro_seen", false)), "survival introductions retain their completed state after reload")
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 0
	SaveService.data["nell_orders_completed"] = 8
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	Controls.apply_keys()
	output = OS.get_environment("NAVIGATION_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	_test_targets()
	_test_pairs()
	await _test_arrow()
	await _test_live_goal()
	await _test_layout()
	print("NAVIGATION_CHOICES failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_targets() -> void:
	var task := WaveTask.new()
	task.start({"kind": "tower", "title": "Вышка", "count": 1, "reward": 25})
	var first := ChargeTower.new()
	var second := ChargeTower.new()
	add_child(first)
	add_child(second)
	first.set_process(false)
	second.set_process(false)
	first.position = Vector2(100, 0)
	second.position = Vector2(95, 0)
	_check(task.nearest_target(Vector2.ZERO, [first, second], first) == first, "nearby targets do not alternate")
	second.position = Vector2(50, 0)
	_check(task.nearest_target(Vector2.ZERO, [first, second], first) == second, "closer route replaces a distant target")
	second.used = true
	_check(task.nearest_target(Vector2.ZERO, [first, second], second) == first, "charged towers leave the route")
	var game := Game.new()
	game.map = LevelSpawner.new()
	game.player = Player.new()
	add_child(game.player)
	game.player.set_physics_process(false)
	game.map.towers.assign([first])
	game._wave_task.start({"kind": "tower", "count": 1})
	game._task_nav_target = first
	first.free()
	game.map.towers.clear()
	game._update_task_navigation()
	_check(game._task_nav_target == null, "freed target does not survive a chapter transition")
	game.player.free()
	game.map.free()
	game.free()
	second.free()
	var correct := Enemy.new()
	var wrong := Enemy.new()
	add_child(correct)
	add_child(wrong)
	correct.visible = false
	wrong.visible = false
	correct.data = ContentDB.get_enemy(&"rat_punk")
	wrong.data = ContentDB.get_enemy(&"pig_sniper")
	correct.hp = 10
	wrong.hp = 10
	task.start({"kind": "kill", "enemy": "rat_punk", "count": 1})
	_check(task.nearest_target(Vector2.ZERO, [wrong, correct]) == correct, "only the required enemy is marked")
	correct.boss_minion = true
	_check(task.nearest_target(Vector2.ZERO, [wrong, correct]) == null, "boss minions never become task targets")
	correct.boss_minion = false
	correct.hp = 0
	_check(task.nearest_target(Vector2.ZERO, [correct]) == null, "dead targets are discarded")
	correct.free()
	wrong.free()
	var prop := DestructibleObject.new()
	add_child(prop)
	prop.visible = false
	task.start({"kind": "break", "count": 1})
	_check(task.accepts_target(prop), "intact scenery can be marked")
	prop.kind = DestructibleObject.Kind.WEAPON_CRATE
	_check(not task.accepts_target(prop), "weapon crates are excluded")
	prop.kind = DestructibleObject.Kind.ART
	prop.drop_height = 10.0
	_check(not task.accepts_target(prop), "falling objects are not marked")
	prop.drop_height = 0.0
	task.event(&"break")
	_check(not task.accepts_target(prop), "completed task clears all targets")
	prop.free()


func _test_pairs() -> void:
	var stats := RunStats.new()
	stats.patch_context = true
	stats.equip_patch("fist")
	var power := stats.power()
	_check(Patches.pair_preview("bullet", stats)["state"] == &"completes", "new patch reveals an immediately available pair")
	_check(stats.power() == power and stats.patch_ids == ["fist"], "preview does not apply bonuses or occupy slots")
	var bullet: UpgradeData
	for card in Patches.cards():
		if card.id == &"patch_bullet":
			bullet = card
	stats.apply(bullet)
	_check(stats.patch_set_titles().has("Залп") and stats.get_stat(&"damage_mult") == 0.1, "taking the previewed card grants its pair")
	_check(Patches.pair_preview("bullet", stats)["state"] == &"active", "upgrading an active pair does not promise a second bonus")
	stats.apply(bullet)
	_check(stats.get_stat(&"damage_mult") == 0.1, "pair is not granted again by another patch level")
	_check(Patches.pair_preview("heart", stats)["state"] == &"missing", "missing partner is identified")
	_check(Patches.pair_preview("skull", stats).is_empty(), "unpaired patch has no invented combination")


func _test_arrow() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(600, 400)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var crowd := ColorRect.new()
	crowd.size = Vector2(view.size)
	crowd.color = Color("#25201c")
	crowd.z_index = 25
	view.add_child(crowd)
	var target := Node2D.new()
	view.add_child(target)
	var arrow := Game.TargetArrow.new()
	arrow.process_mode = Node.PROCESS_MODE_PAUSABLE
	view.add_child(arrow)
	target.position = Vector2(300, 200)
	arrow.track(Vector2(300, 200), Vector2(view.size), target, true)
	_check(arrow.visible and arrow._on_screen, "visible objective gets a small world marker")
	await _settle()
	var image := view.get_texture().get_image()
	_check(image.get_pixel(300, 170).r > 0.6, "objective marker remains above the crowd")
	if not output.is_empty():
		image.save_png(output.path_join("objective_marker.png"))
	arrow.track(Vector2(300, 200), Vector2(view.size), target)
	_check(not arrow.visible, "visible boss does not add a second marker")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2.ONE]:
		target.position = Vector2(300, 200) + direction * 2000.0
		arrow.track(Vector2(300, 200), Vector2(view.size), target, true)
		_check(arrow.visible and not arrow._on_screen, "distant objective gets an edge arrow")
		_check(Rect2(64, 64, 472, 272).grow(0.1).has_point(arrow.position), "arrow stays within screen edges")
	await _settle()
	var pulse := arrow._pulse
	get_tree().paused = true
	await _settle()
	var frozen := view.get_texture().get_image()
	await _settle()
	_check(arrow._pulse == pulse and frozen.get_data() == view.get_texture().get_image().get_data(), "arrow and world pixels stay still on pause")
	get_tree().paused = false
	target.free()
	arrow.track(Vector2.ZERO, Vector2(view.size), null)
	_check(not arrow.visible, "removed target hides the arrow")
	view.free()


func _test_live_goal() -> void:
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	SaveService.data["tester"]["god"] = true
	var game := Game.new()
	add_child(game)
	game.start()
	await get_tree().create_timer(3.5, true, false, true).timeout
	game.director._start_wave(6)
	game._update_task_navigation()
	_check(game._wave_task.kind == &"tower" and is_instance_valid(game._task_nav_target), "real wave provides an eligible tower")
	if is_instance_valid(game._task_nav_target):
		game.player.position = game._task_nav_target.global_position - Vector2(360, 0)
		game.camera.position = game.player.position
		game.camera.reset_smoothing()
		await _settle()
		_check(game._arrow.visible and game._arrow._objective, "live game displays its current objective")
		if not output.is_empty():
			get_viewport().get_texture().get_image().save_png(output.path_join("live_tower_goal.png"))
	var priority := Node2D.new()
	game.add_child(priority)
	priority.position = game.player.position + Vector2(2000, 0)
	game.story_target = priority
	game._physics_process(1.0 / 60.0)
	_check(not game._arrow._objective, "mission target takes priority over optional task")
	game.story_target = null
	game._physics_process(1.0 / 60.0)
	game._advance_wave_task(&"tower")
	_check(not game._arrow.visible and game._task_nav_target == null, "completion clears its marker before a reward pauses the world")
	for id in ["fist", "bullet", "heart", "mug"]:
		game.stats.equip_patch(id)
	game._open_orders()
	await _settle()
	if not output.is_empty():
		get_viewport().get_texture().get_image().save_png(output.path_join("orders_details.png"))
	get_tree().paused = false
	game.free()


func _rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform.origin, control.size * transform.get_scale())


func _test_layout() -> void:
	var stats := RunStats.new()
	stats.patch_context = true
	stats.equip_patch("fist")
	stats.equip_patch("boot")
	var choices: Array[UpgradeData] = []
	for card in Patches.cards():
		if card.id in [&"patch_bullet", &"patch_bolt", &"patch_skull"]:
			choices.append(card)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(844, 390)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		var panel := LevelUpPanel.new()
		add_child(panel)
		panel.open(choices, 10, stats)
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bounds.grow(1.0).encloses(_rect(panel._box)), "patch choices fit the landscape screen " + str(dimensions))
		_check(panel._holder.scale.x >= 0.68, "patch choices remain readable " + str(dimensions))
		for card: Button in panel._cards.get_children():
			var card_bounds := _rect(card)
			for column in card.get_children():
				if column is VBoxContainer:
					for label_node: Label in column.get_children():
						_check(card_bounds.encloses(_rect(label_node)), "card text remains inside the frame")
		if not output.is_empty():
			get_viewport().get_texture().get_image().save_png(output.path_join("patch_choices_%d.png" % dimensions.x))
		panel.free()
	var font := ThemeDB.fallback_font
	var shortened := OrderCard._fit_text(font, "Очень длинная цель волны со счётчиком", 120.0, 12)
	_check(font.get_string_size(shortened, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 120.0, "task title leaves reserved space for its counter")
