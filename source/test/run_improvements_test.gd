extends Node2D
var failures := 0
var output := ""

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("RUN_IMPROVEMENTS FAIL: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _settle() -> void:
	await get_tree().create_timer(0.6, true, false, true).timeout
	await RenderingServer.frame_post_draw

func _settle_popup(window: RunEncounter) -> void:
	await _settle()
	for i in 120:
		if window._panel.modulate.a >= 0.99 and window._panel.scale.is_equal_approx(Vector2.ONE):
			break
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _shot(path: String) -> void:
	if not output.is_empty():
		get_viewport().get_texture().get_image().save_png(output.path_join(path + ".png"))

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 0
	SaveService.data["tips_off"] = true
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	Controls.apply_keys()
	output = OS.get_environment("RUN_IMPROVEMENTS_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	_test_armor()
	_test_effects_and_report()
	_test_gestures()
	var game := Game.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.start()
	game.set_physics_process(false)
	game.director.set_physics_process(false)
	game.events.set_physics_process(false)
	game.player.set_physics_process(false)
	game._wave_task.start({})
	game.enemies.release_all()
	await _settle()
	await _test_activities(game)
	await _test_passages(game)
	await _test_windows(game)
	game.free()
	get_tree().paused = false
	print("RUN_IMPROVEMENTS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _test_armor() -> void:
	var enemy := Enemy.new()
	add_child(enemy)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))["enemies"][0]
	var data := EnemyData.from_dict(raw, func(path: String) -> Texture2D: return load(path) as Texture2D)
	data.max_hp = 200
	data.armor = 0.4
	enemy.activate(data, Vector2.ZERO)
	enemy.set_physics_process(false)
	var cracks := [0]
	enemy.armor_cracked.connect(func(_e: Enemy) -> void: cracks[0] += 1)
	for i in 3:
		enemy.take_damage(40)
	_check(cracks[0] == 1 and enemy.armor_broken and is_equal_approx(enemy.hp, 128), "plate cracks once after sustained physical hits")
	enemy._pop = Enemy.HIT_POP * 0.5
	enemy.take_damage(40)
	_check(is_equal_approx(enemy.hp, 96) and cracks[0] == 1, "cracked plate halves reduction on following hits")
	_check(enemy._pop == Enemy.HIT_POP * 0.5, "continuous fire does not restart the hit pose")
	enemy.activate(data, Vector2.ZERO)
	enemy._take_dot(100, "poison")
	_check(not enemy.armor_broken and enemy._armor_wear == 0, "poison does not break physical plates")
	enemy.activate(data, Vector2.ZERO)
	_check(not enemy.armor_broken and enemy._armor_wear == 0 and enemy.last_damage_kind == &"", "pooled enemy resets armor and death style")
	enemy.activate(ContentDB.get_enemy(&"junk_overlord"), Vector2.ZERO)
	enemy.take_damage(1000)
	_check(not enemy.armor_broken, "boss defenses keep their rules")
	enemy.free()

func _test_effects_and_report() -> void:
	var fx := FxManager.new()
	add_child(fx)
	fx.set_process(false)
	BattleQuality.configure(4, true)
	var allowed := 0
	for i in 100:
		allowed += 1 if fx.allow_defeat_fx() else 0
	_check(allowed == 6 and fx.allow_defeat_fx(true), "mass death has a limit, boss confirmation stays visible")
	fx._process(1.0)
	allowed = 0
	for i in 20:
		allowed += 1 if fx.allow_defeat_fx() else 0
	_check(allowed <= 1, "weak-phone death budget refills conservatively")
	fx.free()
	BattleQuality.configure(0, true)
	var report := CombatReport.new()
	report.record_enemy(200, -100, &"melee")
	report.record_enemy(50, 10, &"blast")
	report.record_enemy(20, 10, &"poison")
	report.record_enemy(5, 10, &"shock")
	var rows := report.damage_breakdown()
	_check(is_equal_approx(report.enemy_damage, 175) and rows.size() == 3, "damage excludes overkill and lists three main sources")
	_check(rows[0]["title"] == "ближний бой" and rows[0]["amount"] == 100, "main source uses actual damage")
	_check(report.lines(false).contains("57%"), "share includes smaller sources in total damage")

func _test_gestures() -> void:
	var visual := RaccoonVisual.new()
	add_child(visual)
	visual.aiming = false
	visual.play_action("ready")
	visual.update_motion(Vector2.ZERO, Vector2.RIGHT, 0.1)
	_check(visual._action_left > 0, "weapon preparation is animated")
	visual.kick(Vector2.RIGHT, 1)
	_check(visual._action_left == 0, "shooting cancels cosmetic preparation")
	visual.play_action("skill")
	visual.update_motion(Vector2.ZERO, Vector2.RIGHT, 0.1)
	_check(visual._action == "skill" and visual._action_left > 0, "skill has a short whole-pose response")
	visual._hero_id = "neon_hopper"
	visual.cheer()
	visual.update_motion(Vector2.ZERO, Vector2.RIGHT, 0.2)
	var hop := visual._hop
	visual._hero_id = "snow"
	visual.cheer()
	visual.update_motion(Vector2.ZERO, Vector2.RIGHT, 0.2)
	_check(visual._hop < hop, "hero celebrations differ")
	visual.free()

func _start_activity(job: WaveActivity, kind: WaveActivity.Kind) -> bool:
	for i in 12:
		if job.start(kind, 0):
			job.set_physics_process(false)
			return true
	_check(false, "event has accessible placement " + str(kind))
	return false

func _test_activities(game: Game) -> void:
	var job := game.events.activity
	var rewards := [0]
	job.completed.connect(func(coins: int) -> void: rewards[0] += coins)
	_check(MapEvents.scheduled_kind(13, false) == MapEvents.Kind.CARGO and MapEvents.scheduled_kind(3, true) == -1, "schedule repeats per chapter and skips mini-bosses")
	if _start_activity(job, WaveActivity.Kind.CARGO):
		game.player.position = job.global_position + Vector2(0, 300)
		var at := job.global_position
		job._physics_process(1)
		_check(job.progress == 0 and job.global_position == at, "unescorted cargo waits")
		game.player.position = job.global_position
		job._physics_process(1)
		var halfway := job.global_position
		game.player.position += Vector2(0, 300)
		job._physics_process(1)
		_check(job.progress == 1 and job.global_position == halfway, "abandoned cargo keeps its travelled distance")
		for i in 17:
			game.player.position = job.global_position
			job._physics_process(0.5)
		_check(not job.active and rewards[0] == 40, "escort delivers reward once")
		job._physics_process(0.5)
		_check(rewards[0] == 40, "completed event cannot pay twice")
	if _start_activity(job, WaveActivity.Kind.VALVE):
		game.player._invuln = 0
		game.player.position = job.global_position + Vector2(230, 0)
		var hp := game.player.hp
		job._physics_process(1)
		_check(game.player.hp == hp, "leak warning precedes damage")
		job._physics_process(2)
		_check(game.player.hp < hp, "leak damages inside its marked circle")
		game.player.position = job.global_position
		job._physics_process(3.1)
		_check(not job.active and rewards[0] == 80, "safe valve ends leak and pays reward")
	if _start_activity(job, WaveActivity.Kind.DEFENSE):
		game.player.position = job.global_position
		var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), job.global_position)
		enemy.set_physics_process(false)
		job._physics_process(1)
		_check(job.progress == 0 and job._contested, "living enemies contest defense")
		game.enemies.release(enemy)
		job._physics_process(1)
		_check(job.progress > 0, "cleared circle resumes hold")
		game.camera.position = job.position
		game.camera.reset_smoothing()
		await _settle()
		_shot("defense")
		job.set_physics_process(true)
		var age := job._age
		get_tree().paused = true
		await _settle()
		_check(job._age == age, "event clock freezes on pause")
		get_tree().paused = false
		job.set_physics_process(false)
		job.remaining = 0.1
		job._physics_process(0.2)
		_check(not job.active and rewards[0] == 80, "expired defense pays nothing")
	if _start_activity(job, WaveActivity.Kind.MEETING):
		job._waiting_choice = true
		job.choose_risk(true)
		_check(job.kind == WaveActivity.Kind.DEFENSE and job.reward == 70 and job.remaining == 25, "risky offer starts timed work without payout")
		game.events.on_wave_cleared()
		_check(not job.active and rewards[0] == 80, "unfinished offer ends with wave")
	if _start_activity(job, WaveActivity.Kind.MEETING):
		job._waiting_choice = true
		game.player.hp = 50
		job.choose_risk(false)
		_check(not job.active and rewards[0] == 95 and game.player.hp > 50, "safe offer pays supplies once")
	if _start_activity(job, WaveActivity.Kind.MEETING):
		game.player.position = job.global_position
		game._mouse_fire = true
		game.player.weapon_controller.trigger = true
		game.hud.joystick._touch_index = 2
		game.hud.joystick.output = Vector2.RIGHT
		game.hud.aim_stick._touch_index = 3
		game.hud.aim_stick.direction = Vector2.RIGHT
		job._physics_process(1.3)
		_check(not game._mouse_fire and not game.player.weapon_controller.trigger and game.hud.joystick.output == Vector2.ZERO and game.hud.aim_stick.direction == Vector2.ZERO, "encounter clears held movement and fire")
		await _settle()
		_check(get_tree().paused and job._waiting_choice, "approach opens encounter and pauses battle")
		var windows := game.find_children("*", "RunEncounter", true, false)
		_check(windows.size() == 1, "only one encounter opens")
		if windows.size() == 1:
			(windows[0] as RunEncounter)._resolve(true)
		await _settle()
		_check(not get_tree().paused and job.kind == WaveActivity.Kind.DEFENSE and rewards[0] == 95, "choice resumes battle without early payout")
		job.reset()

func _test_passages(game: Game) -> void:
	for theme in ["night_dump", "gold_vault", "pigeon_roofs", "bank"]:
		game.map.clear()
		await _settle()
		var chapter := ContentDB.get_chapter(3 if theme == "bank" else 0).duplicate(true)
		chapter["map_card"] = "" if theme == "bank" else theme
		seed(49317)
		game.map.build(game.layers, chapter)
		game.map.attach_player(game.player)
		_check(game.map.passages.size() > 0 and game.map.passages.size() <= 2, "bounded route features " + theme)
		var reached := game.map._reachable_from(game.map.world_to_cell(game.map.player_start))
		_check(game.map._first_isolated(reached) == Vector2i(-1, -1), "all walkable cells stay connected " + theme)
		if game.map.passages.is_empty():
			continue
		var passage := game.map.passages[0]
		if theme == "bank":
			_check(game.map.surface_at(passage.position) == &"stone", "bank doors stand on the stone floor")
		game.camera.position = passage.position
		game.camera.reset_smoothing()
		game.player.position = passage.position + Vector2(0, 90)
		await _settle()
		_shot("passage_" + theme)
		if theme == "pigeon_roofs":
			_check(passage.door == null and game.map.is_walkable(passage.position), "roof route remains open")
		else:
			_check(is_instance_valid(passage.door), "closed route has a real door " + theme)
		if theme != "pigeon_roofs" and is_instance_valid(passage.door):
			var door := passage.door
			var center := door.position + DestructibleObject.offset_for(door.kind, door.prop_id)
			_check(not game.map.is_walkable(center), "closed passage blocks navigation")
			if theme in ["gold_vault", "bank"]:
				game.player.position = passage.position + Vector2(0, 64)
				passage._process(2.1)
			else:
				door.take_damage(1000)
			_check(not door.is_intact() and game.map.is_walkable(center), "opened passage clears navigation " + theme)

func _rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform.origin, control.size * transform.get_scale())

func _test_windows(game: Game) -> void:
	for dimensions in [Vector2i(1280, 720), Vector2i(844, 390)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		for who in ["nell", "snyr"]:
			var window := RunEncounter.new(who, 70)
			var layer := CanvasLayer.new()
			layer.layer = 72
			layer.process_mode = Node.PROCESS_MODE_ALWAYS
			game.add_child(layer)
			layer.add_child(window)
			window.tree_exited.connect(layer.queue_free)
			window.begin()
			await _settle_popup(window)
			_check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1).encloses(_rect(window._panel)), "encounter fits " + who + str(dimensions))
			_check(window.visible and window._panel.modulate.a > 0.9 and layer.layer > game.hud.layer, "encounter is visible above HUD")
			_shot("encounter_" + who + "_" + str(dimensions.x))
			window._resolve(false)
			await _settle()
		var report := CombatReport.new()
		report.record_enemy(1000, 100, &"melee")
		report.record_enemy(350, 50, &"blast")
		report.record_enemy(130, 10, &"fire")
		for id in ["fist", "bullet", "heart", "mug"]:
			game.stats.equip_patch(id)
		game.hud.show_run_result({"wave": 7, "best_wave": 9, "kills": 65, "time": 210, "coins": 150, "combat_report": report.lines(false), "build_report": game._build_report()})
		await _settle()
		var result := game.hud._run_result
		_check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1).encloses(_rect(result._panel)), "expanded result keeps buttons on screen " + str(dimensions))
		_check(result._tip_label.text.contains("Залп") and result._tip_label.text.contains("Живучесть") and result._tip_label.text.contains("Нэлл"), "results show active combinations and next unlock")
		_shot("result_" + str(dimensions.x))
		result.hide()
