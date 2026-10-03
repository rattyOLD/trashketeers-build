extends Node
## Струи пива и рвоты: очередь капель из фиксированной точки в сторону енота, затем снимок.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Orient.portrait = true
	get_window().content_scale_size = Orient.PORTRAIT_SIZE
	SaveService.data["quality"] = 2
	var state: Dictionary = SaveService.data["tester"]
	state["god"] = true
	var game := Game.new()
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(2.0).timeout
	game.enemies.release_all()
	var beer := WeaponDB.get_weapon(&"beer_jet_v1")
	var puke := WeaponDB.get_weapon(&"puke_v1")
	for i in 40:
		var p := game.player.global_position
		var a := p + Vector2(260, -330)
		var b := p + Vector2(-260, -330)
		var t := float(i) * 0.04
		BulletPool.spawn(beer, a, (p - a).rotated(sin(t * 3.0) * 0.12), Bullet.Team.ENEMY)
		BulletPool.spawn(puke, b, (p - b).rotated(sin(t * 2.0) * 0.1), Bullet.Team.ENEMY)
		await get_tree().physics_frame
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
