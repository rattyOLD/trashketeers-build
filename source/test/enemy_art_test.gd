extends Node2D
var failures := 0
var frame_count := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("ENEMY_ART FAIL: " + message)


func _run() -> void:
	var art: Dictionary = ConfigLoader.load_json(EnemyArt.CONFIG)["assets"]
	var raw_sheets: Dictionary = ConfigLoader.load_json(FrameDB.CONFIG_PATH)["sheets"]
	var raw_rigs: Array = ConfigLoader.load_json(RigDB.CONFIG_PATH)["rigs"]
	var rigs: Dictionary = {}
	for rig: Dictionary in raw_rigs:
		rigs[str(rig["id"])] = rig
	var used: Dictionary = {}
	for entry: Dictionary in ConfigLoader.load_json("res://data/enemies.json")["enemies"]:
		var sheet_id := str(entry.get("frames", ""))
		var rig_id := str(entry.get("rig", ""))
		var path := str(entry["sprite"])
		if not sheet_id.is_empty():
			path = str(raw_sheets[sheet_id]["texture"])
		elif not rig_id.is_empty():
			path = str(rigs[rig_id]["texture"])
		used[path] = true
		for variant in entry.get("rig_variants", []):
			used[str(rigs[variant]["texture"])] = true
		if not str(entry.get("attack_sprite", "")).is_empty():
			used[str(entry["attack_sprite"])] = true
		_check(art.has(path), "covered enemy " + str(entry["enemy_id"]))
	for path: String in used:
		_check(art.has(path), "covered variant or attack " + path)
	for path: String in art:
		var texture: Texture2D = load(path)
		var logical: Array = art[path]["logical_size"]
		_check(texture.get_size() == Vector2(float(logical[0]), float(logical[1])) * 2.0, "texture density " + path)
		_check(EnemyArt.density(path) == 2.0, "density registry " + path)
	for sid: String in raw_sheets:
		var raw: Dictionary = raw_sheets[sid]
		if not art.has(raw["texture"]):
			continue
		var sheet := FrameDB.get_sheet(sid)
		var sprite := RigSprite.new()
		_check(sprite.setup_frames(sid, 0.0), "setup " + sid)
		var image: Image = sprite.texture.get_image()
		if image.is_compressed():
			image.decompress()
		for index in (raw["frames"] as Array).size():
			sprite.set_frame(index)
			var values: Array = raw["frames"][index]
			var rect := Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
			var pivot := Vector2(float(values[4]), float(values[5]))
			var arrays: Array = sprite.mesh.surface_get_arrays(0)
			var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			_check(vertices[0].is_equal_approx(-pivot) and vertices[2].is_equal_approx(rect.size - pivot), "world geometry " + sid + str(index))
			_check(uv[0].is_equal_approx(rect.position * 2.0 / sprite.texture.get_size()), "HD atlas UV " + sid + str(index))
			_check(not image.get_region(Rect2i(rect.position * 2.0, rect.size * 2.0)).is_invisible(), "nonempty pose " + sid + str(index))
			frame_count += 1
		var corpse := RigSprite.new()
		corpse.setup_frames(sid)
		corpse.copy_look(sprite)
		_check(corpse.shader_material.get_shader_parameter("sample_density") == 2.0, "corpse outline density " + sid)
		corpse.free()
		sprite.free()
	for rid: String in rigs:
		var raw: Dictionary = rigs[rid]
		if not art.has(raw["texture"]):
			continue
		var sprite := RigSprite.new()
		_check(sprite.setup(rid, 0.0, false), "rig setup " + rid)
		var bounds: AABB = sprite.mesh.get_aabb()
		var size := EnemyArt.logical_size(sprite.texture)
		var pivot := Vector2(float(raw["pivot"][0]), float(raw["pivot"][1]))
		_check(Vector2(bounds.position.x, bounds.position.y).is_equal_approx(-pivot), "rig pivot " + rid)
		_check(Vector2(bounds.size.x, bounds.size.y).is_equal_approx(size), "rig world size " + rid)
		sprite.free()
	var dragon := WhiteDragon._build_frames()
	for animation in dragon.get_animation_names():
		for index in dragon.get_frame_count(animation):
			var texture := dragon.get_frame_texture(animation, index) as AtlasTexture
			_check(texture.region.size == Vector2(640, 736), "dragon HD frame " + animation)
			_check(art.has(texture.atlas.resource_path), "dragon covered " + animation)
	_motion()
	if DisplayServer.get_name() != "headless":
		await _atlas_isolation()
	_check(art.size() == 51, "all 51 used enemy assets upgraded")
	_check(EnemyArt.density("res://assets/player/raccoon_body.png") == 1.0, "hero retains original scale")
	print("ENEMY_ART failures=", failures, " assets=", art.size(), " frames=", frame_count)
	get_tree().quit(0 if failures == 0 else 1)


func _motion() -> void:
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.activate(ContentDB.get_enemy(&"rat_punk"), Vector2.ZERO)
	enemy.set_physics_process(false)
	enemy._emerge = 0.0
	enemy._move_amount = 1.0
	for i in 30:
		enemy._animate(1.0 / 60.0, Vector2(enemy.data.move_speed, 0))
		_check(is_equal_approx(enemy._sprite.position.y, enemy._sprite_base_y()), "drawn feet stay grounded")
	enemy.deactivate()
	enemy.activate(ContentDB.get_enemy(&"spark_rat"), Vector2.ZERO)
	enemy.set_physics_process(false)
	enemy._emerge = 0.0
	enemy._target_pos = Vector2(100, 0)
	enemy._animate(1.0 / 60.0, Vector2.ZERO)
	enemy._target_pos = Vector2(-1, 0)
	enemy._animate(1.0 / 60.0, Vector2.ZERO)
	_check(not enemy._facing_left, "facing hysteresis prevents idle jitter")
	enemy._target_pos = Vector2(-100, 0)
	enemy._animate(1.0 / 60.0, Vector2.ZERO)
	_check(enemy._facing_left, "aim changes direction beyond the dead zone")
	var before := enemy._sprite.angles[Enemy.BONE_WEAPON]
	enemy._pose_auto(1.0, 0.0, 0.0, 1.0 / 60.0)
	_check(absf(enemy._sprite.angles[Enemy.BONE_WEAPON] - before) < 0.1, "weapon enters windup gradually")
	var texture: Texture2D = enemy.data.attack_texture
	var logical := EnemyArt.logical_size(texture)
	var expected_width := enemy.data.attack_width
	if expected_width <= 0.0:
		expected_width = logical.x * enemy.data.sprite_scale.x
	_check(is_equal_approx(enemy._alt_scale() * texture.get_width(), expected_width), "attack artwork retains world width")
	enemy.deactivate()
	enemy.activate(ContentDB.get_enemy(&"rat_punk"), Vector2.ZERO)
	_check(enemy._visual_lean == 0.0 and enemy._visual_squash == 1.0, "pool resets visual transitions")
	enemy.free()


func _atlas_isolation() -> void:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(2, 2, 12, 12), Color.RED)
	image.fill_rect(Rect2i(16, 2, 12, 12), Color.GREEN)
	var texture := ImageTexture.create_from_image(image)
	FrameDB._sheets["qa_frame_isolation"] = {"id": "qa_frame_isolation", "texture": texture,
		"density": 2.0, "regions": PackedStringArray(), "rects": [Rect2(1, 1, 6, 6), Rect2(8, 1, 6, 6)],
		"pivots": PackedVector2Array([Vector2(3, 3), Vector2(3, 3)])}
	var view := SubViewport.new()
	view.size = Vector2i(160, 160)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var sprite := RigSprite.new()
	view.add_child(sprite)
	sprite.setup_frames("qa_frame_isolation", 4)
	sprite.position = Vector2(80, 80)
	sprite.scale = Vector2.ONE * 10
	sprite.set_param("outline_px", 1.0)
	sprite.set_param("outline_color", Color.BLUE)
	for i in 3:
		await RenderingServer.frame_post_draw
	var pixels := view.get_texture().get_image()
	var red := 0
	var green := 0
	var blue := 0
	for y in 160:
		for x in 160:
			var c := pixels.get_pixel(x, y)
			if c.a > 0.9:
				red += int(c.r > 0.8 and c.g < 0.1)
				green += int(c.g > 0.8 and c.r < 0.1)
				blue += int(c.b > 0.8 and c.r < 0.1)
	_check(red > 100 and blue > 10, "frame keeps body and outer outline")
	_check(green == 0, "frame margin cannot reveal neighboring poses")
	view.free()
	FrameDB._sheets.erase("qa_frame_isolation")
