extends Node
## Exercise both Baron phases and the actual textured liquid renderer.
var game: Game
var baron: Enemy
var elapsed := 0.0
var seen := {}
var counts := {1: {"beer_jet_v1": 0, "puke_v1": 0}, 2: {"beer_jet_v1": 0, "puke_v1": 0}}
var captured := false
func _ready() -> void:
	Controls.apply_keys()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 1
	SaveService.data["tips_off"] = true
	SaveService.data["tester"]["god"] = true
	game = Game.new()
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(2.0).timeout
	game.director.set_physics_process(false)
	game.enemies.release_all()
	baron = game.enemies.spawn(ContentDB.get_enemy(&"beer_baron"), game.player.global_position + Vector2(350, 0))
	game._on_boss_spawned(baron)
func _physics_process(delta: float) -> void:
	if baron == null:
		return
	elapsed += delta
	if game._level_up_open:
		game.hud._level_up._armed_at = 0
		game.hud._level_up._pick(0)
	game.player.hp = game.player.max_hp
	baron.hp = baron.max_hp * (1.0 if elapsed < 20.0 else 0.4)
	var live_beer := 0
	for bullet: Bullet in BulletPool._active:
		if bullet.weapon.id not in [&"beer_jet_v1", &"puke_v1"]:
			continue
		var key := str(bullet.get_instance_id()) + ":" + str(bullet.spawn_frame)
		if not seen.has(key):
			seen[key] = true
			counts[baron._brain.phase][str(bullet.weapon.id)] += 1
		if bullet.weapon.id == &"beer_jet_v1":
			live_beer += 1
	if live_beer >= 6 and not captured:
		captured = true
		_snapshot.call_deferred()
	if elapsed >= 45.0:
		print("BARON_STREAM counts=", counts, " captured=", captured)
		var passed := captured
		for phase: int in counts:
			for weapon: String in counts[phase]:
				passed = passed and counts[phase][weapon] > 0
		print("BARON_STREAM failures=0" if passed else "BARON_STREAM failures=1")
		get_tree().quit(0 if passed else 1)
func _snapshot() -> void:
	await RenderingServer.frame_post_draw
	if not OS.get_environment("OUT").is_empty():
		get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
