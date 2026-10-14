extends Node2D
var failures := 0
var generated := 0
var styles: Dictionary = {}
var signatures: Dictionary = {}
var captured: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("MAP_GENERATION: " + label)


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 0 if OS.get_environment("MAP_GENERATION_OUT").is_empty() else 2
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	await _test_repair()
	_test_plan_repeat()
	await _test_story_roundtrip()
	for chapter_index in 6:
		for map_seed in 8:
			seed(1000 * chapter_index + map_seed + 1)
			await _test_map(ContentDB.get_chapter(chapter_index).duplicate(true), "chapter%d-seed%d" % [chapter_index, map_seed])
	for map_id: String in MapCards.CATALOG:
		var chapter := ContentDB.get_chapter(0).duplicate(true)
		chapter["map_card"] = map_id
		var floor_path := "res://assets/maps/%s/floor.png" % map_id
		if ResourceLoader.exists(floor_path):
			chapter["floor"] = floor_path
		await _test_map(chapter, map_id)
	_check(styles.size() == 3, "all three combat layouts occur")
	_check(signatures.size() >= 40, "independent runs change routes and real cover positions")
	print("MAP_GENERATION maps=", generated, " styles=", styles.keys(), " unique=", signatures.size())
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("MAP_GENERATION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_plan_repeat() -> void:
	var first := CombatMapPlan.new()
	var second := CombatMapPlan.new()
	var inner := Rect2(-1700, -2000, 3400, 4200)
	var boss := Rect2(-500, -1900, 1000, 500)
	var river_points := PackedVector2Array([Vector2(-1300, -2000), Vector2(-1100, 0), Vector2(-1300, 2200)])
	first.build(Vector2(0, 1900), boss, inner, river_points, 473)
	second.build(Vector2(0, 1900), boss, inner, river_points, 473)
	_check(first.style == second.style and first.routes == second.routes and first.clearings == second.clearings, "same plan seed reproduces tactical geometry")


func _body(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.position = at
	body.add_child(collision)
	add_child(body)
	return body


func _blocked_at(at: Vector2, excluded: Array[RID] = []) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = Player.RADIUS
	query.shape = shape
	query.transform = Transform2D(0, at)
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.OBSTACLE | PhysicsLayers.PROP | PhysicsLayers.TERRAIN
	query.exclude = excluded
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _test_repair() -> void:
	var map := LevelSpawner.new()
	map.grid_size = Vector2i(9, 9)
	map.cells.resize(81)
	map.cells.fill(LevelSpawner.CellType.WALL)
	for y in range(1, 8):
		for x in range(1, 8):
			map.cells[y * 9 + x] = LevelSpawner.CellType.EMPTY
	for y in range(1, 7):
		map.cells[y * 9 + 4] = LevelSpawner.CellType.WALL
	map.player_start = map.cell_to_world(Vector2i(2, 2))
	var wall := _body(Vector2(4.5, 4) * LevelSpawner.CELL, Vector2(1, 6) * LevelSpawner.CELL)
	var cover := _body(map.cell_to_world(Vector2i(4, 7)), Vector2.ONE * LevelSpawner.CELL)
	map.cells[7 * 9 + 4] = LevelSpawner.CellType.COVER
	map._wall_nodes[7 * 9 + 4] = cover
	var original := map.cells.duplicate()
	await get_tree().physics_frame
	map._ensure_connectivity()
	await get_tree().physics_frame
	var walls_preserved := true
	for i in original.size():
		if original[i] == LevelSpawner.CellType.WALL and map.cells[i] != LevelSpawner.CellType.WALL:
			walls_preserved = false
	_check(walls_preserved, "connectivity repair never changes permanent walls")
	_check(map.cells[2 * 9 + 4] == LevelSpawner.CellType.WALL and _blocked_at(map.cell_to_world(Vector2i(4, 2))), "repair preserves actual terrain instead of opening only its grid")
	_check(not is_instance_valid(cover) and not _blocked_at(map.cell_to_world(Vector2i(4, 7))), "repair opens a real detour by removing its cover collider")
	_check(map._first_isolated(map._reachable_from(Vector2i(2, 2))) == Vector2i(-1, -1), "actual detour connects both sides")
	map._clear_cell(Vector2i(4, 2))
	_check(map.cells[2 * 9 + 4] == LevelSpawner.CellType.WALL, "wall cannot be silently erased")
	_check(map._reachable_from(Vector2i(-1, -1)).count(1) == 0, "out-of-bounds start is handled")
	wall.free()
	map.free()


func _test_story_roundtrip() -> void:
	var layers := BiomeLayers.new()
	var map := LevelSpawner.new()
	add_child(layers)
	layers.floor_layer.add_child(map)
	for mission_id in ["m1", "m2"]:
		map.build(layers, StoryRun.map_chapter(ContentDB.get_chapter(StoryRun.base_chapter_index(mission_id)), mission_id))
		_check(map.combat_plan == null and map._route_mask.count(1) == 0, "survival routes do not change story rooms " + mission_id)
		_check(not map.story_cells.is_empty(), "story gates retained " + mission_id)
		map.clear()
		await get_tree().process_frame
	map.build(layers, ContentDB.get_chapter(0))
	_check(map._boss_cells == Vector2i(16, 8) and map.combat_plan != null, "story to survival rebuild resets arena geometry")
	map.clear()
	map.free()
	layers.free()
	await get_tree().process_frame


func _test_map(chapter: Dictionary, label: String) -> void:
	var layers := BiomeLayers.new()
	var map := LevelSpawner.new()
	add_child(layers)
	layers.floor_layer.add_child(map)
	map.build(layers, chapter)
	map.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	generated += 1
	_check(map.combat_plan != null, "procedural survival plan " + label)
	styles[map.combat_plan.style] = true
	var signature := str(map.combat_plan.routes) + str(map._cover_spots)
	signatures[signature] = true
	_check(map.is_area_clear(map.player_start, 110) and not _blocked_at(map.player_start), "free player start " + label)
	_check(map.is_area_clear(map.boss_point, 120) and not _blocked_at(map.boss_point), "free boss arena " + label)
	var reached := map._reachable_from(map.world_to_cell(map.player_start))
	_check(map._first_isolated(reached) == Vector2i(-1, -1), "all structural walkable cells connected " + label)
	var excluded: Array[RID] = []
	for object in map.destructibles:
		if object.kind == DestructibleObject.Kind.WEAPON_CRATE:
			excluded.append(object.get_rid())
	var route_ok := true
	for line in map.combat_plan.routes:
		for segment in range(1, line.size()):
			var side := (line[segment] - line[segment - 1]).normalized().orthogonal() * 40.0
			var steps := ceili(line[segment - 1].distance_to(line[segment]) / 32.0)
			for step in range(steps + 1):
				var at := line[segment - 1].lerp(line[segment], float(step) / steps)
				if _blocked_at(at, excluded) or _blocked_at(at + side, excluded) or _blocked_at(at - side, excluded):
					route_ok = false
	_check(route_ok, "all reserved routes have real player clearance " + label)
	_check(not map.passages.is_empty() and not map.route_caches.is_empty(), "optional route choices retained " + label)
	_check(map.towers.size() >= 2 and map.shrines.size() == 5, "important exploration objects retained " + label)
	var live_landmarks := map.landmarks.filter(func(p: ArenaProp) -> bool: return is_instance_valid(p) and not p.is_queued_for_deletion())
	_check(not live_landmarks.is_empty() and live_landmarks.size() <= 3, "large physical landmarks retained outside routes " + label)
	for cache in map.route_caches:
		_check(not _blocked_at(cache.position + cache.control_offset, excluded) and not _blocked_at(cache.position + cache.cache_offset, excluded), "cache and control physically accessible " + label)
	print("MAP_SAMPLE ", label, " style=", map.combat_plan.style, " covers=", map._cover_spots.size(), " passages=", map.passages.size(), " caches=", map.route_caches.size())
	var output := OS.get_environment("MAP_GENERATION_OUT")
	var capture_id := str(chapter["id"]) + "-" + str(map.combat_plan.style)
	if not output.is_empty() and str(chapter["id"]) in ["junkyard", "bank"] and not captured.has(capture_id):
		captured[capture_id] = true
		DirAccess.make_dir_recursive_absolute(output)
		var camera := Camera2D.new()
		add_child(camera)
		camera.position = map.bounds.get_center()
		var view := get_viewport().get_visible_rect().size
		var zoom_factor := minf(view.x / map.bounds.size.x, view.y / map.bounds.size.y)
		camera.zoom = Vector2.ONE * zoom_factor
		for frame in 3: await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(capture_id + ".png"))
		camera.free()
	map.clear()
	map.free()
	layers.free()
	await get_tree().process_frame
