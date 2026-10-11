extends Node
var failures := 0
var output := ""
var baseline := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("SCENERY_GRAPHICS FAIL: " + message)


func _settle() -> void:
	await get_tree().create_timer(0.25, true, false, true).timeout
	await RenderingServer.frame_post_draw


func _run() -> void:
	output = OS.get_environment("SCENERY_GRAPHICS_OUT")
	baseline = OS.get_environment("SCENERY_BASELINE") == "1"
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["tips_off"] = true
	SaveService.data["quality"] = 0
	Orient.portrait = false
	Controls.apply_keys()
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
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
	game.hud.hide()
	for quality in [0, 2]:
		SaveService.data["quality"] = quality
		for id in ["night_dump", "acid_rain", "gold_vault", "pigeon_roofs", "default_junk", "default_bank"]:
			game.map.clear()
			await _settle()
			var chapter := ContentDB.get_chapter(3 if id == "default_bank" else 0).duplicate(true)
			if not id.begins_with("default"):
				chapter["map_card"] = id
				chapter["ground"] = "res://assets/maps/%s/floor.png" % id
			seed(51951)
			game.map.build(game.layers, chapter)
			game.map.attach_player(game.player)
			for cache in game.map.route_caches:
				cache.set_physics_process(false)
			await _settle()
			var anchors: Array = game.map.get("_scenery_anchors")
			var focus: Vector2 = anchors[0] if not anchors.is_empty() else game.map.player_start
			if not baseline:
				var landmarks: Array = game.map.get("landmarks")
				var live := landmarks.filter(func(p: ArenaProp) -> bool: return is_instance_valid(p) and not p.is_queued_for_deletion())
				_check(not live.is_empty() and live.size() <= 3, "bounded landmarks " + id + " quality " + str(quality))
				if not live.is_empty():
					focus = live[0].position
				for prop: ArenaProp in live:
					_check(prop._light == null and prop._light_id >= 0, "baked light uses existing light map, not PointLight2D")
					_check(not prop.is_processing() and prop.collision_layer == PhysicsLayers.OBSTACLE, "static landmark has a physical base")
					_check(prop.sprite.texture.get_size() == Vector2(512, 512), "bounded texture dimensions")
				var reached := game.map._reachable_from(game.map.world_to_cell(game.map.player_start))
				_check(game.map._first_isolated(reached) == Vector2i(-1, -1), "landmark placement preserves navigation " + id)
			game.player.position = focus + Vector2(0, 145)
			game.player.reset_physics_interpolation()
			game.camera.position = focus + Vector2(0, -15)
			game.camera.reset_smoothing()
			game.camera.reset_physics_interpolation()
			await _settle()
			get_tree().paused = true
			await _settle()
			for i in 5:
				await RenderingServer.frame_post_draw
			var pixels := get_viewport().get_texture().get_image()
			if not output.is_empty():
				pixels.save_png(output.path_join(id + "_q" + str(quality) + ".png"))
			if not baseline:
				for node in get_tree().get_nodes_in_group(&"scenery_ground"):
					node.queue_redraw()
				await _settle()
				var redrawn := get_viewport().get_texture().get_image()
				if pixels.get_data() != redrawn.get_data() and not output.is_empty():
					redrawn.save_png(output.path_join(id + "_redraw_q" + str(quality) + ".png"))
				_check(pixels.get_data() == redrawn.get_data(), "scenery pixels frozen under pause " + id)
			get_tree().paused = false
	game.free()
	if not baseline:
		await _test_seams()
		await _test_shadow_lifetime()
	print("SCENERY_GRAPHICS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_seams() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(512, 512)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var ground := Sprite2D.new()
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.centered = false
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 1024, 1024)
	ground.scale = Vector2.ONE * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = LevelSpawner._calm_shader()
	mat.set_shader_parameter("mirror_tiles", true)
	ground.material = mat
	view.add_child(ground)
	for id in ["night_dump", "acid_rain", "gold_vault", "pigeon_roofs"]:
		ground.texture = load("res://assets/maps/%s/floor.png" % id)
		await _settle()
		var img := view.get_texture().get_image()
		var worst := 0.0
		for i in range(4, 508, 8):
			for pair in [[Vector2i(255, i), Vector2i(256, i)], [Vector2i(i, 255), Vector2i(i, 256)]]:
				var a := img.get_pixelv(pair[0])
				var b := img.get_pixelv(pair[1])
				worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
		_check(worst <= 3.0 / 255.0, "mirrored floor has no hard seams " + id)
	view.free()


func _test_shadow_lifetime() -> void:
	for quality in [0, 2]:
		SaveService.data["quality"] = quality
		var shadows := ShadowDecals.new()
		add_child(shadows)
		var obstacle := Node2D.new()
		add_child(obstacle)
		shadows.add_rect(Rect2(20, 20, 80, 40), 60, obstacle)
		shadows.add_circle(Vector2(160, 80), 30, 40, obstacle)
		await _settle()
		_check(shadows._mesh != null and not shadows._dirty, "shadow geometry is cached")
		_check(shadows._layers == (2 if quality == 0 else 4), "low quality uses fewer shadow triangles")
		var cached := shadows._mesh
		shadows.queue_redraw()
		await _settle()
		_check(shadows._mesh == cached, "redraw reuses static shadow mesh")
		obstacle.free()
		await _settle()
		_check(shadows._rect_active[0] == 0 and shadows._circle_active[0] == 0 and shadows._mesh == null, "removed obstacle leaves no ghost shadow")
		shadows.free()
