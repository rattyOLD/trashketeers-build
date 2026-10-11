extends Node2D

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHARACTER_MOTION FAIL: " + message)


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 2
	_test_springs()
	_test_heroes()
	_test_enemies()
	await _wall()
	await _atlas_isolation()
	await _hand_depth()
	if not OS.get_environment("MOTION_OUT").is_empty():
		await _gallery()
	print("CHARACTER_MOTION failures=", failures, " enemies=", ContentDB.get_enemy_ids().size())
	get_tree().quit(0 if failures == 0 else 1)


func _test_springs() -> void:
	for settings in [Vector2(140, 11), Vector2(38, 4.5), Vector2(100, 20), Vector2(100, 35)]:
		var reference := Vector2.ZERO
		for fps in [30, 60, 120]:
			var spring := SpringValue.new(settings.x, settings.y)
			spring.kick(4.0)
			for tick in fps:
				spring.update(0.2, 1.0 / fps)
			var pose := Vector2(spring.value, spring.velocity)
			if fps == 30:
				reference = pose
			_check(pose.distance_to(reference) < 0.00001, "spring matches at 30/60/120 FPS")
			var before := pose
			spring.update(1.0, 0.0)
			_check(before == Vector2(spring.value, spring.velocity), "paused spring stays still")
			spring.update(0.2, 0.2)
			_check(is_finite(spring.value) and absf(spring.value) < 1.0, "long frame remains stable")


func _test_heroes() -> void:
	for character: Dictionary in ConfigLoader.load_json("res://data/characters.json").get("characters", []):
		if not character.has("sprite") or str(character["sprite"].get("clips", "")).is_empty():
			continue
		var reference := 0.0
		for fps in [30, 60, 120]:
			var actor := RaccoonVisual.new()
			add_child(actor)
			actor.apply_look(character, {})
			actor.aiming = false
			for tick in fps:
				actor.update_motion(Vector2(200, 0), Vector2.RIGHT, 1.0 / fps)
			if fps == 30:
				reference = actor._gait
			_check(absf(reference - actor._gait) < 0.0001, str(character["id"]) + " same stride at every FPS")
			var phase := actor._gait
			for tick in fps:
				actor.update_motion(Vector2.ZERO, Vector2.RIGHT, 1.0 / fps)
			_check(is_equal_approx(actor._gait, phase) and actor._clip_cur == "idle", "stationary legs stop")
			actor.flash()
			var hit_frames := {}
			for tick in int(fps * RaccoonVisual.HIT_CLIP_TIME):
				actor.flash()
				actor.update_motion(Vector2.ZERO, Vector2.RIGHT, 1.0 / fps)
				if actor._clip_cur == "hit":
					hit_frames[actor._clip_idx] = true
			_check(hit_frames.size() >= 3, "continuous damage cannot pin first hurt frame")
			_check(actor.get_muzzle_global(Vector2.RIGHT).is_finite(), "hero muzzle remains valid")
			actor.free()


func _test_enemies() -> void:
	var actor := Enemy.new()
	add_child(actor)
	for id in ContentDB.get_enemy_ids():
		actor.activate(ContentDB.get_enemy(id), Vector2(5000, 5000))
		actor._emerge = 0.0
		actor._target_pos = actor.global_position + Vector2(300, 0)
		for tick in 30:
			actor._animate(1.0 / 60.0, Vector2(actor.data.move_speed, 0))
		_check(actor._sprite.transform.is_finite(), str(id) + " finite pose")
		if actor.is_framed():
			var sheet := actor._sprite.frame_sheet
			_check(actor._sprite.frame_index >= 0 and actor._sprite.frame_index < (sheet["rects"] as Array).size(), "valid current frame")
			var run_phase := actor._run_phase
			for tick in 30:
				actor._animate(1.0 / 60.0, Vector2.ZERO)
			_check(is_equal_approx(actor._run_phase, run_phase), "stationary enemy stops run clip")
			for clip: String in sheet["clips"]:
				var frames: PackedInt32Array = sheet["clips"][clip]["frames"]
				for frame in frames:
					_check(frame >= 0 and frame < (sheet["rects"] as Array).size(), str(id) + " valid clip index")
		actor.deactivate()
	for id: StringName in [&"junk_overlord", &"mud_magnate"]:
		actor.activate(ContentDB.get_enemy(id), Vector2(400, 400))
		var sheet := actor._sprite.frame_sheet
		_check((sheet["rects"] as Array).size() == 32, "boss has 32 drawings")
		for frame in 12:
			actor._sprite.set_frame(frame)
			var sockets: PackedVector2Array = sheet["muzzles"][frame]
			for facing in [false, true]:
				actor._facing_left = facing
				actor._sprite.rotation = 0.03
				actor._apply_sprite_scale(0.98, 1.02)
				_check(actor.part_muzzle(0).distance_to(actor._sprite.global_transform * sockets[0]) < 0.001, "painted muzzle follows flip and pose")
		actor._brain.state = BossBrain.State.BASS_WINDUP
		actor._brain.windup = 0.5
		actor._facing_left = false
		actor._target_pos = actor.global_position - Vector2(100, 0)
		actor._animate(1.0 / 60.0, Vector2.ZERO)
		_check(not actor._facing_left, "committed boss windup keeps facing")
		actor.deactivate()
	actor.activate(ContentDB.get_enemy(&"rat_punk"), Vector2.ZERO)
	_check(actor._frame_clip.is_empty() and not actor._running and is_zero_approx(actor._visual_lean), "pool resets animation state")
	actor.free()


func _wall() -> void:
	var wall := StaticBody2D.new()
	wall.position = Vector2(120, 0)
	wall.collision_layer = PhysicsLayers.WORLD
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 400)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(400, 0)
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.activate(ContentDB.get_enemy(&"rat_punk"), Vector2(60, 0))
	enemy._flank = 0.0
	enemy._attack_timer = 100.0
	await get_tree().physics_frame
	for tick in 75:
		enemy.stuck_time = 0.0
		enemy._detour_time = 0.0
		enemy.tick(1.0 / 60.0, player)
		await get_tree().physics_frame
	_check(enemy.position.x < 120 and not enemy._running, "wall stops real walking animation")
	enemy.queue_free()
	player.queue_free()
	wall.queue_free()
	await get_tree().process_frame


func _atlas_isolation() -> void:
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, 32, 32), Color.RED)
	image.fill_rect(Rect2i(32, 0, 32, 32), Color.GREEN)
	var texture := ImageTexture.create_from_image(image)
	var view := SubViewport.new()
	view.size = Vector2i(72, 72)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var sprite := RigSprite.new()
	view.add_child(sprite)
	# Проверяем точную границу UV, без интерполяции размещения между physics-кадрами.
	sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.setup_texture(texture, 6.0)
	sprite.set_param("paint_strength", 0.0)
	sprite.position = Vector2(16, 16)
	sprite.frame_sheet = {"id": "motion-isolation", "density": 1.0, "texture": texture, "rects": [Rect2(0, 0, 32, 32)], "pivots": PackedVector2Array([Vector2.ZERO])}
	sprite._frame_margin = 6.0
	sprite.set_frame(0)
	for tick in 3:
		await RenderingServer.frame_post_draw
	var shot := view.get_texture().get_image()
	var edge := shot.get_pixel(47, 30)
	_check(edge.r > 0.9 and edge.g < 0.05, "edge keeps its own frame color: " + str(edge))
	_check(shot.get_pixel(49, 30).a < 0.01, "neighbor frame cannot leak into mesh margin")
	view.queue_free()
	await get_tree().process_frame


func _hand_marker(at: Vector2, color: Color, radius: int) -> Texture2D:
	var pixels := Image.create(300, 200, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	pixels.fill_rect(Rect2i(Vector2i(at) - Vector2i.ONE * radius, Vector2i.ONE * radius * 2), color)
	return ImageTexture.create_from_image(pixels)


## Проверяем видимые пиксели, а не только совпадение суставов: кисти поверх оружия,
## ближнее предплечье поверх приклада, задняя часть оружия сохраняется целиком.
func _hand_depth() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(384, 384)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var actor := RaccoonVisual.new()
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(actor)
	for character: Dictionary in ConfigLoader.load_json("res://data/characters.json").get("characters", []):
		if str(character["id"]) == "raccoon":
			actor.apply_look(character, {})
	actor.position = Vector2(192, 256)
	actor.scale = Vector2.ONE * 2.0
	actor.hero.hide()
	actor._front_layer.hide()
	actor._gun_layer.material = null
	actor.weapon_tier = 1
	actor.weapon_icon = &"qa_hand_depth"
	var gun := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	gun.fill(Color.BLUE)
	WeaponIcons._sprite(&"rifle")
	WeaponIcons._sprites[actor.weapon_icon] = {"texture": ImageTexture.create_from_image(gun), "center": Vector2(64, 32), "unit": 1.0, "length": 84.0, "grip": Vector2(-14, 6), "support": Vector2(16, 6), "muzzle": Vector2(62, 0)}
	actor._clip_arms = actor._clip_arms.duplicate()
	for which: String in ["right", "left"]:
		var palm := actor._clip_source_joint(which, "palm")
		var elbow := actor._clip_source_joint(which, "elbow")
		actor._clip_arms[which + "_upper"] = _hand_marker(Vector2.ZERO, Color.TRANSPARENT, 0)
		actor._clip_arms[which + "_fore"] = _hand_marker(palm.lerp(elbow, 0.55), Color.GREEN, 4) if which == "right" else _hand_marker(Vector2.ZERO, Color.TRANSPARENT, 0)
		actor._clip_arms[which + "_fist"] = _hand_marker(palm, Color.RED if which == "right" else Color.YELLOW, 5)
	for facing in [1.0, -1.0]:
		actor._facing = facing
		actor._gun_angle = 0.0
		actor._sway = 0.0
		var dir := Vector2(facing, 0)
		var center := actor._gun_center(actor._paw_at(0.0), dir, 0.0)
		actor._gun_layer.queue_redraw()
		actor._rear_layer.queue_redraw()
		for tick in 3:
			await RenderingServer.frame_post_draw
		var shot := view.get_texture().get_image()
		for which: String in ["right", "left"]:
			var target := actor._clip_hand_target(which, center, dir)
			var pixel := Vector2i(actor.transform * target)
			var color := shot.get_pixelv(pixel)
			_check(color.r > 0.9 and color.b < 0.05 and (color.g < 0.05 if which == "right" else color.g > 0.9), which + " palm overlaps weapon in both directions: " + str(color))
		var target := actor._clip_hand_target("right", center, dir)
		var midpoint := actor._clip_source_joint("right", "palm").lerp(actor._clip_source_joint("right", "elbow"), 0.55)
		var pixel := Vector2i(actor.transform * (actor._clip_segment_transform("right", "fore", target) * midpoint))
		var color := shot.get_pixelv(pixel)
		_check(color.g > 0.9 and color.b < 0.05, "near sleeve overlaps rear weapon: " + str(color))
		pixel = Vector2i(actor.transform * (center - dir * 55.0 * actor._weapon_scale()))
		color = shot.get_pixelv(pixel)
		_check(color.b > 0.9 and color.r < 0.05, "complete stock remains visible behind hand: " + str(color))
	WeaponIcons._sprites.erase(actor.weapon_icon)
	view.queue_free()
	await get_tree().process_frame


func _gallery() -> void:
	var output := OS.get_environment("MOTION_OUT")
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(1600, 1000)
	get_window().content_scale_size = Vector2i(1600, 1000)
	for ident: String in ["overlord", "magnate"]:
		var nodes: Array[RigSprite] = []
		var sheet := FrameDB.get_sheet(ident)
		for frame in 32:
			var sprite := RigSprite.new()
			add_child(sprite)
			sprite.setup_frames(ident, 6.0)
			sprite.set_frame(frame)
			sprite.scale = Vector2.ONE * 0.72
			sprite.position = Vector2(100 + frame % 8 * 200, 230 + frame / 8 * 235)
			nodes.append(sprite)
		for tick in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(ident + "-frames.png"))
		for sprite in nodes:
			sprite.queue_free()
		await get_tree().process_frame
