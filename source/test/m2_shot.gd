extends Node
func _ready() -> void:
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	SaveService.data["show_fps"] = true
	var game := Game.new()
	game.story_mission = "m2"
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(2.0).timeout
	var j := OS.get_environment("JUMP")
	if j != "":
		game.story.debug_jump(float(j))
		await get_tree().create_timer(3.0).timeout
	print("M2 map ", game.map.layout, " ", game.map.grid_size, " enc ", game.story._encounters.size())
	get_viewport().get_texture().get_image().save_png("/tmp/anim/m2.png")
	get_tree().quit()
