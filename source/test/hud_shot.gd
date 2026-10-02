extends Node
## Снимок шапки боя (виртуальный экран): выживание и сюжет.
func _ready() -> void:
	Orient.portrait = true
	var story := OS.get_environment("HUD_STORY") == "1"
	var game := Game.new()
	if story:
		game.story_mission = "m1"
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(3.5).timeout
	if not story:
		game.hud.set_wave(3, 12, 0, 25)
		game.hud.set_kills(50)
		game.hud.set_xp(280, 1000, 12)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/anim/hud_%s.png" % ("story" if story else "surv"))
	get_tree().quit()
