extends Node
## Прогон героев в бою выживания: берём героя, 6 с боя, использует навык, ловим ошибки. HERO=id
func _ready() -> void:
	WeaponController.force_auto = true
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	var hero := OS.get_environment("HERO")
	if hero != "":
		if not SaveService.owns_character(hero):
			(SaveService.data["characters"] as Array).append(hero)
		SaveService.data["character"] = hero
	var game := Game.new()
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(3.0).timeout
	game.player.move_input = Vector2.ZERO
	if game.hero_skills.has_skill():
		for k in 3:
			game.hero_skills._left = 0.0
			print("skill used ", game.hero_skills.try_use(), " ", game.hero_skills.title())
			await get_tree().create_timer(2.0).timeout
	for k in 12:
		game.hero_skills.on_kill()
	await get_tree().create_timer(2.0).timeout
	print("OK ", hero, " hp=", game.player.hp, " kills=", game.kills)
	get_tree().quit()
