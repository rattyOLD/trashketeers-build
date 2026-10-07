extends Node
## Скриншот боя через N секунд (качество PROBE_Q).
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	WeaponController.force_auto = true
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	SaveService.data["quality"] = int(OS.get_environment("PROBE_Q")) if OS.get_environment("PROBE_Q") != "" else 0
	var state: Dictionary = SaveService.data["tester"]
	state["god"] = true
	state["start_wave"] = int(OS.get_environment("PROBE_WAVE")) if OS.get_environment("PROBE_WAVE") != "" else 3
	state["start_chapter"] = int(OS.get_environment("PROBE_CH")) if OS.get_environment("PROBE_CH") != "" else 0
	seed(4242)
	var game := Game.new()
	add_child(game)
	game.start(&"")
	var t := 0.0
	var secs := float(OS.get_environment("SHOT_AT")) if OS.get_environment("SHOT_AT") != "" else 12.0
	while t < secs:
		await get_tree().create_timer(0.25, true).timeout
		t += 0.25
		if get_tree().paused:
			for panel in get_tree().root.find_children("*", "LevelUpPanel", true, false):
				panel.queue_free()
			get_tree().paused = false
	game._request_skill()
	await get_tree().create_timer(1.0).timeout
	print("SKILL fr=", game.stats.get_stat(&"fire_rate_mult"), " pierce=", game.stats.get_stat(&"piercing"), " frac=", game.hero_skills.fraction())
	await get_tree().create_timer(5.0).timeout
	print("AFTER fr=", game.stats.get_stat(&"fire_rate_mult"), " pierce=", game.stats.get_stat(&"piercing"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
