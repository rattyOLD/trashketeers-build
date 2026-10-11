extends Node
var failures := 0

class KeyboardSettings:
	extends MenuPopups.Settings
	var keyboard_height := 0.0
	func _keyboard_inset() -> float:
		return keyboard_height


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("VISUAL_DIRECTION FAIL: " + message)


func _settle() -> void:
	await get_tree().create_timer(0.12, true, false, true).timeout
	await RenderingServer.frame_post_draw


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 2
	SaveService._apply_text('{"camera_focus":false}')
	_check(not SaveService.data["camera_focus"], "camera preference survives loading")
	SaveService._apply_text('{}')
	_check(SaveService.data["camera_focus"], "old saves receive the camera default")
	EnvLights.clear()
	await _occlusion()
	_camera()
	await _landmarks()
	_materials()
	await _mobile_windows()
	print("VISUAL_DIRECTION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _occlusion() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(300, 300)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var world := Node2D.new()
	world.y_sort_enabled = true
	view.add_child(world)
	var player := Node2D.new()
	player.position = Vector2(150, 185)
	world.add_child(player)
	var image := Image.create(20, 90, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var hero := Sprite2D.new()
	hero.texture = ImageTexture.create_from_image(image)
	hero.position = Vector2(0, -45)
	player.add_child(hero)
	var cover := ArenaProp.make_sprite("res://assets/world/scenery_v2/gold_vault.png", 250)
	cover.position = Vector2(150, 235)
	cover.self_modulate = Color(0.8, 0.9, 1.0, 0.75)
	world.add_child(cover)
	ForegroundFade.register(cover)
	var fade := ForegroundFade.new()
	fade.player = player
	fade.set_process(false)
	add_child(fade)
	await _settle()
	var before := view.get_texture().get_image()
	for i in 90:
		fade._process(1.0 / 60.0)
	await _settle()
	var after := view.get_texture().get_image()
	_check(cover.self_modulate.a < 0.22, "landmark reveals the hero standing behind it")
	var changed := 0
	for y in range(10, 250, 5):
		for x in range(20, 280, 5):
			if before.get_pixel(x, y) != after.get_pixel(x, y):
				changed += 1
	_check(changed > 100, "foreground visibility changes rendered pixels")
	_check(is_equal_approx(cover.self_modulate.r, 0.8) and cover.modulate == Color.WHITE, "fade preserves tint and the parent light strength")
	get_tree().paused = true
	var paused := cover.self_modulate.a
	player.position.y = 280
	fade.set_process(true)
	await _settle()
	_check(cover.self_modulate.a == paused, "foreground transition freezes on pause")
	get_tree().paused = false
	fade.set_process(false)
	for i in 90:
		fade._process(1.0 / 60.0)
	_check(cover.self_modulate == Color(0.8, 0.9, 1.0, 0.75), "foreground returns to its original alpha and tint")
	_check(not ForegroundFade.covers(cover, player.global_position), "objects behind the hero stay opaque")
	player.position = Vector2(150, 185)
	fade._timer = 0
	fade._process(0.1)
	cover.free()
	fade._process(0.1)
	_check(fade._active.is_empty(), "removed objects do not leave stale references")
	fade.free()
	view.free()


func _camera() -> void:
	var positions: Array[Vector2] = []
	for fps in [30, 60, 120]:
		var battle := BattleBase.new()
		battle.set_physics_process(false)
		battle.set_process(false)
		add_child(battle)
		battle.player = Player.new()
		battle.player.set_physics_process(false)
		battle.add_child(battle.player)
		battle.player.move_input = Vector2.RIGHT
		battle.player.weapon_controller.set_physics_process(false)
		battle.camera = Camera2D.new()
		battle.add_child(battle.camera)
		for tick in fps:
			battle._update_shake(1.0 / fps)
		positions.append(battle.camera.offset)
		battle.focus_camera(Vector2(5000, 0), 1.4)
		for tick in fps:
			battle._update_shake(1.0 / fps)
			_check(absf(battle.camera.offset.x) <= 90.01, "boss focus keeps the hero inside the view")
		get_tree().paused = true
		var previous := battle.camera.offset
		var age := battle._focus_left
		battle._update_shake(1.0)
		_check(battle.camera.offset == previous and battle._focus_left == age, "camera focus freezes on pause")
		get_tree().paused = false
		SaveService.data["camera_focus"] = false
		battle._update_shake(0.1)
		_check(battle._focus_weight == 0 and battle._focus_left == 0, "camera accents can be disabled separately")
		SaveService.data["camera_focus"] = true
		battle.free()
	_check(positions[0].distance_to(positions[1]) < 0.001 and positions[1].distance_to(positions[2]) < 0.001, "camera follow is consistent at 30/60/120 FPS")


func _landmarks() -> void:
	for id in ["night_dump", "gold_vault", "acid_rain", "pigeon_roofs"]:
		var node := ArenaProp.new()
		node.setup("scenery_" + id)
		add_child(node)
		await _settle()
		_check(node.sprite.texture.get_size() == Vector2(512, 512), "complete landmark art: " + id)
		_check(node.get_child_count() == 2, "one complete sprite and original collision, without architecture overlays")
		_check(node.sprite.is_in_group(&"foreground_cover"), "landmark participates in foreground reveal")
		var collision := node.get_child(1) as CollisionShape2D
		_check(collision.shape.size == ArenaProp.footprint("scenery_" + id), "landmark retains its original physical footprint")
		var handle := node._light_id
		_check(handle >= 0, "painted lamps register an environment light")
		node.free()
		_check(EnvLights._radius[handle % EnvLights.ID_STRIDE] == 0, "landmark light removed on exit")


func _materials() -> void:
	var enemy := Enemy.new()
	add_child(enemy)
	for id in [&"rat_punk", &"pig_sniper", &"fed_agent", &"toxic_rat", &"pigeon_bomber"]:
		var data := ContentDB.get_enemy(id)
		enemy.activate(data, Vector2.ZERO)
		var palette: Array = ArtDirection.FACTIONS[ArtDirection.faction(str(id))]
		_check(enemy._sprite.shader_material.get_shader_parameter("paint_shadow") == palette[0], "pooled enemy gets its own faction palette: " + str(id))
		var corpse := RigSprite.new()
		corpse.copy_look(enemy._sprite)
		_check(corpse.shader_material.get_shader_parameter("paint_shadow") == palette[0], "corpse retains the living faction appearance")
		corpse.free()
		_check(enemy.hp == data.max_hp and enemy._shape.radius > 0, "visual treatment preserves combat attributes")
	enemy.free()


func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


func _mobile_windows() -> void:
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var popup := KeyboardSettings.new()
	add_child(popup)
	popup.open()
	popup.set_process(false)
	await get_tree().create_timer(0.3, true).timeout
	await _settle()
	var original := _screen_rect(popup._panel)
	popup._lift(true)
	await _settle()
	_check(not popup._lifted and _screen_rect(popup._panel).is_equal_approx(original), "focus without a keyboard keeps settings full size")
	popup.keyboard_height = 320.0
	popup._process(0.1)
	await _settle()
	_check(popup._lifted and popup._center.offset_bottom <= -320.0, "settings fit above an actual keyboard")
	popup.keyboard_height = 0.0
	popup._process(0.1)
	await _settle()
	_check(popup._input_focused and not popup._lifted, "dismissing keyboard restores settings even while field retains focus")
	_check(_screen_rect(popup._panel).is_equal_approx(original), "keyboard dismissal restores exact settings bounds")
	popup.close()
	await get_tree().create_timer(0.3, true).timeout
	popup.open()
	await get_tree().create_timer(0.3, true).timeout
	await _settle()
	_check(not popup._input_focused and _screen_rect(popup._panel).is_equal_approx(original), "reopening settings clears keyboard layout")
	GlassPopup._open_stack.erase(popup)
	popup.free()
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(844, 390)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		await _settle()
		var result := ResultPanel.new()
		add_child(result)
		result.open(false, PackedStringArray(["ОПЕРАЦИЯ 1 · СВАЛКА", "Очки: 27580", "Убито: 121", "Спасено: 2", "Тайники: 0 из 8", "Детали ствола: 0 из 6", "Совет: " + "Проверяй маршрут и предупреждения. ".repeat(16)]), "МИССИЯ ПРОВАЛЕНА", true)
		await get_tree().create_timer(0.3, true).timeout
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		var panel := _screen_rect(result._panel)
		_check(bounds.grow(-20).encloses(panel), "mission results and buttons fit with margins " + str(dimensions))
		_check(panel.size.y <= dimensions.y - 79, "mission results leave free space around the panel")
		_check(panel.encloses(_screen_rect(result._upgrade_button)), "upgrade action remains inside mission result")
		result._tip_scroll.scroll_vertical = ceili(result._tip_label.size.y)
		await _settle()
		_check(_screen_rect(result._tip_label).end.y <= _screen_rect(result._tip_scroll).end.y + 2, "last mission note is reachable by scrolling")
		result.free()
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().size = Vector2i(1280, 720)
