extends Node
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("GRAPHICS_UPGRADE FAIL: " + message)


func _settle() -> void:
	await get_tree().create_timer(0.15, true, false, true).timeout
	await RenderingServer.frame_post_draw


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 2
	EnvLights.clear()
	var district := ArenaDistrict.new()
	add_child(district)
	seed(5252)
	district.build("junkyard", "junkyard", Rect2(0, 0, 1600, 1100), Rect2(160, 160, 1280, 780), 550, 70)
	await _settle()
	var living := get_tree().get_nodes_in_group(&"scenery_ambience")
	_check(living.size() >= 4, "new district buildings receive local atmosphere")
	for detail: SceneryAmbience in living:
		var building := detail.get_parent() as Sprite2D
		_check(detail.scale.x == (-1.0 if building.flip_h else 1.0), "steam and cables follow the mirrored building")
	var animated := living[0] as SceneryAmbience
	var previous := animated.clock
	await _settle()
	_check(animated.clock > previous, "steam and equipment animate during play")
	get_tree().paused = true
	previous = animated.clock
	animated.queue_redraw()
	await _settle()
	_check(animated.clock == previous, "redraw does not advance the paused atmosphere")
	get_tree().paused = false
	_check(district._shadows != null and district._shadows._mesh != null, "buildings cast cached shadows")
	for name in ArenaDistrict.NEW_BUILDINGS:
		var tex := load("res://assets/district/junkyard_v2/" + name + ".png") as Texture2D
		_check(tex != null and tex.get_size() == Vector2(512, 512), "building texture " + name)
	var ids := district._lights.duplicate()
	district.free()
	for id in ids:
		_check(EnvLights._radius[id % EnvLights.ID_STRIDE] == 0, "district light removed on scene exit")
	_check(get_tree().get_nodes_in_group(&"scenery_ambience").is_empty(), "scene exit removes all ambience")
	await _floor_variation()
	await _material_hits()
	print("GRAPHICS_UPGRADE failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _floor_variation() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(768, 256)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/maps/night_dump/floor.png")
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 3072, 1024)
	sprite.scale = Vector2.ONE * 0.25
	var mat := ShaderMaterial.new()
	mat.shader = LevelSpawner._calm_shader()
	mat.set_shader_parameter("mirror_tiles", true)
	mat.set_shader_parameter("wear_atlas", load("res://assets/maps/night_dump/wear_atlas.png"))
	sprite.material = mat
	view.add_child(sprite)
	await _settle()
	var plain := view.get_texture().get_image()
	mat.set_shader_parameter("wear_enabled", true)
	await _settle()
	var worn := view.get_texture().get_image()
	var changes := 0
	for y in range(12, 244, 4):
		for x in range(12, 756, 4):
			if plain.get_pixel(x, y) != worn.get_pixel(x, y):
				changes += 1
	_check(changes > 5000, "large floor patches replace repeated mirrored motifs")
	# Measure the seam introduced by the blend independently of the base asphalt grain.
	var worst := 0.0
	for boundary in [1, 2, 3]:
		var x := int(round(boundary * 128.0 / 0.62))
		for y in range(8, 248, 4):
			var a := worn.get_pixel(x - 1, y) - plain.get_pixel(x - 1, y)
			var b := worn.get_pixel(x, y) - plain.get_pixel(x, y)
			worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	_check(worst < 0.025, "blended material transitions have no hard seams")
	view.free()


func _material_hits() -> void:
	var fx := FxManager.new()
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)
	fx.surface_hit(Vector2.ZERO, Vector2.RIGHT, true, false, false)
	_check(fx._sp_next == 3 and fx._pf_next == 0, "metal impact produces sparks only")
	for i in 3:
		_check(is_equal_approx(fx._sp_max[i], 0.12), "impact sparks extinguish quickly")
	fx.surface_hit(Vector2.ZERO, Vector2.RIGHT, false, false, false)
	_check(fx._sp_next == 3 and fx._pf_next == 2, "body impact produces dust without an additive flash")
	get_tree().paused = true
	var life := fx._sp_life[0]
	await _settle()
	_check(fx._sp_life[0] == life, "combat impact freezes on pause")
	get_tree().paused = false
	fx.free()
