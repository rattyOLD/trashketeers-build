extends Node

var failures := 0


func _ready() -> void:
	WeaponController.force_auto = true
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("STORY_TESTER_START FAIL: " + label)


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["character"] = "pigeon_mafioso"
	SaveService.data["characters"] = ["raccoon", "pigeon_mafioso"]
	SaveService.add_weapon(&"golden_smg_v1", 1)
	SaveService.set_selected_weapon(&"golden_smg_v1")
	SaveService.data["quality"] = 0
	SaveService.data["fx_lite"] = true
	SaveService.data["tester"] = {"start_chapter": 1, "start_wave": 2}
	for mission_id in ["m1", "m2"]:
		var game := Game.new()
		game.story_mission = mission_id
		add_child(game)
		game.start()
		game.set_physics_process(false)
		game.story.set_physics_process(false)
		game.player.set_physics_process(false)
		var chapter := StoryRun.map_chapter(ContentDB.get_chapter(StoryRun.base_chapter_index(mission_id)), mission_id)
		var size: Array = chapter["size"]
		_check(game.map.grid_size == Vector2i(int(size[0]), int(size[1])), mission_id + " retains story size")
		_check(not game.map._story.is_empty(), mission_id + " retains story layout")
		_check(game.director.wave_number == 0, mission_id + " ignores survival wave override")
		_check(game.player.global_position == game.map.player_start, mission_id + " starts on its story map")
		await get_tree().process_frame
		await get_tree().process_frame
		for key in game.map.story_gates:
			var gate: Variant = game.map.story_gates[key]
			_check(is_instance_valid(gate) and gate.is_inside_tree(), mission_id + " live gate " + str(key))
		game.map.clear()
		_check(game.map.story_gates.is_empty() and game.map.story_cells.is_empty() and game.map._story_clear.is_empty(), "clear releases story references")
		await get_tree().process_frame
		game.queue_free()
		await get_tree().process_frame
	var survival := Game.new()
	add_child(survival)
	survival.start()
	survival.set_physics_process(false)
	_check(survival.director.wave_number == 11, "survival retains tester start")
	_check(survival.map._story.is_empty() and survival.map.story_gates.is_empty(), "survival map has no story gates")
	survival.queue_free()
	await get_tree().process_frame
	print("STORY_TESTER_START failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
