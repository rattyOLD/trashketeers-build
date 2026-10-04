extends Node
func _ready() -> void:
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	var game := Game.new()
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(0.8).timeout
	game._switch_chapter(int(OS.get_environment("CH") if OS.get_environment("CH") != "" else "3"))
	await get_tree().create_timer(1.5).timeout
	var cnt := {}
	for n in game.map._owned:
		if is_instance_valid(n): cnt[n.get_class() + ":" + n.name.rstrip("0123456789@")] = cnt.get(n.get_class() + ":" + n.name.rstrip("0123456789@"), 0) + 1
	print("OWNED ", game.map._owned.size(), " destr ", game.map.destructibles.size())
	get_viewport().get_texture().get_image().save_png("/tmp/anim/bank.png")
	get_tree().quit()
