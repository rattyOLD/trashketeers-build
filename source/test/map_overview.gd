extends Node
## Вся карта выживания сверху (глава PROBE_CH, зерно SEED): камера вписывает границы арены.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Orient.portrait = true
	get_window().content_scale_size = Orient.PORTRAIT_SIZE
	SaveService.data["quality"] = 2
	var state: Dictionary = SaveService.data["tester"]
	state["god"] = true
	state["start_chapter"] = int(OS.get_environment("PROBE_CH")) if OS.get_environment("PROBE_CH") != "" else 0
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1)
	var game := Game.new()
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(1.0).timeout
	game.enemies.release_all()
	get_tree().paused = true
	for child in game.get_children():
		if child is CanvasLayer:
			child.visible = false
	game.hud.visible = false
	var b: Rect2 = game.map.bounds
	var view := get_viewport().get_visible_rect().size
	var z := minf(view.x / b.size.x, view.y / b.size.y)
	game.camera.limit_left = -100000; game.camera.limit_top = -100000
	game.camera.limit_right = 100000; game.camera.limit_bottom = 100000
	game.camera.offset = Vector2.ZERO
	game.camera.zoom = Vector2(z, z)
	game.camera.global_position = b.get_center()
	game.camera.reset_smoothing()
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
