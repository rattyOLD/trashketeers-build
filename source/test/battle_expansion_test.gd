extends Node2D
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("BATTLE_EXPANSION FAIL: " + message)


func _frames(count: int = 3) -> void:
	for i in count:
		await RenderingServer.frame_post_draw


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 2
	SaveService.data["tips_off"] = true
	WeaponController.force_auto = false
	Controls.apply_keys()
	await _boss_damage()
	_tactics()
	await _chain()
	await _equipment()
	await _extraction()
	print("BATTLE_EXPANSION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _boss_damage() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(320, 320)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var boss := Enemy.new()
	view.add_child(boss)
	boss.activate(ContentDB.get_enemy(&"junk_overlord"), Vector2(160, 240))
	boss._flash = -1.0
	await _frames()
	var before := view.get_texture().get_image()
	var radius := boss.get_radius()
	boss.take_damage(boss.max_hp * 0.4)
	boss._flash = -1.0
	boss._sprite.set_param("flash", 0.0)
	await _frames()
	var worn := view.get_texture().get_image()
	var changed := 0
	var alpha_changed := 0
	for y in 320:
		for x in 320:
			var a := before.get_pixel(x, y)
			var b := worn.get_pixel(x, y)
			if a.a > 0.9 and a != b:
				changed += 1
			if absf(a.a - b.a) > 0.01:
				alpha_changed += 1
	_check(changed > 50, "damage leaves visible persistent cracks on boss")
	_check(alpha_changed == 0 and boss.get_radius() == radius, "wear preserves silhouette and collision")
	var corpse := RigSprite.new()
	corpse.copy_look(boss.get_sprite())
	_check(corpse.shader_material.get_shader_parameter("boss_damage") == 0.5, "corpse preserves damage")
	corpse.free()
	boss.hp = boss.max_hp * 0.30
	boss._update_boss_damage()
	_check(boss.get_sprite().shader_material.get_shader_parameter("boss_damage") == 1.0, "critical damage is distinct")
	boss.deactivate()
	boss.activate(ContentDB.get_enemy(&"rat_punk"), Vector2(160, 240))
	_check(boss.get_sprite().shader_material.get_shader_parameter("boss_damage") == 0.0, "pooled normal enemy starts unscarred")
	view.queue_free()
	await _frames()
	var dragon := WhiteDragon.new()
	add_child(dragon)
	dragon.scale_health(100.0)
	dragon.state = WhiteDragon.State.LANDED_ATTACK
	# Первый порог не требует обращения к арене ярости.
	dragon.phase_index = 2
	dragon.take_damage(dragon.max_hp * 0.45)
	_check(dragon._wear_stage == 1, "dragon body reflects phase damage")
	dragon.scale_health(100.0)
	_check(dragon._wear_stage == 0, "new dragon health resets wear")
	dragon.free()


func _tactics() -> void:
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(1100, 1100)
	player.velocity = Vector2(100, 0)
	var manager := EnemyManager.new()
	add_child(manager)
	manager.setup(player, self, 10)
	manager.set_physics_process(false)
	var guard := manager.spawn(ContentDB.get_enemy(&"pig_guard"), player.position + Vector2(250, 0))
	var sniper := manager.spawn(ContentDB.get_enemy(&"pig_sniper"), player.position + Vector2(440, 0))
	var rat := manager.spawn(ContentDB.get_enemy(&"rat_punk"), player.position + Vector2(0, 300))
	var fed := manager.spawn(ContentDB.get_enemy(&"fed_marksman"), player.position + Vector2(-340, 0))
	manager._update_faction_positions()
	_check(guard.tactic_role == &"screen", "guard screens same-faction shooter")
	_check(guard.tactic_anchor.distance_to(player.position) < sniper.position.distance_to(player.position), "screen stands between player and shooter")
	_check(rat.tactic_role == &"flank" and absf(rat.tactic_anchor.x - player.position.x) > 50, "melee rat approaches from side")
	_check(fed.tactic_role == &"line", "marksman maintains spaced firing line")
	rat._enter(Enemy.Act.WINDUP, 0.5)
	_check(rat._tactical_direction(Vector2.DOWN, 300) == Vector2.DOWN, "tactics cannot bend committed telegraph")
	manager.release(sniper)
	manager._update_faction_positions()
	_check(not guard.tactic_anchor.is_finite(), "guard advances when shooter disappears")
	manager.release_all()
	for e in manager._free:
		e.queue_free()
	manager.queue_free()
	player.queue_free()
	Enemy.status_sink = Callable()


func _chain() -> void:
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(700, 700)
	player.hp = 100
	var manager := EnemyManager.new()
	add_child(manager)
	manager.setup(player, self, 3)
	manager.set_physics_process(false)
	var enemy := manager.spawn(ContentDB.get_enemy(&"rat_punk"), Vector2(300, 300), 10)
	var chain := ChainHazards.new()
	add_child(chain)
	chain.set_physics_process(false)
	chain.player = player
	chain.enemies = manager
	chain.spill(Vector2(300, 300))
	chain.spill(Vector2(420, 300))
	var hp := enemy.hp
	chain.ignite(Vector2(300, 300), 0)
	chain._physics_process(0.6)
	_check(enemy.hp == hp, "full warning before any hazard damage")
	get_tree().paused = true
	var age: float = chain._zones[0]["age"]
	chain._physics_process(10)
	await _frames()
	_check(chain._zones[0]["age"] == age and enemy.hp == hp, "paused reaction does not age or hurt")
	get_tree().paused = false
	chain._physics_process(0.7)
	_check(enemy.hp < hp and enemy.last_damage_kind == &"fire", "fire hurts enemy with correct source")
	_check(chain._zones[1]["armed"] and chain._zones[1]["age"] == 0.0, "neighbor ignition has its own warning")
	for i in 30:
		chain.spill(Vector2(1000 + i * 100, 1000))
	_check(chain._zones.size() == ChainHazards.CAPACITY, "hazard budget never teleports active danger")
	chain.clear()
	var barrel := DestructibleObject.new()
	barrel.setup_art("d_barrel", self)
	barrel.position = Vector2(300, 300)
	add_child(barrel)
	var safe := DestructibleObject.new()
	safe.setup_art("d_safe", self)
	safe.position = Vector2(1500, 1500)
	add_child(safe)
	chain.attach([barrel, safe])
	barrel.take_damage(barrel.max_hp * 0.5)
	_check(chain._zones.size() == 1 and not chain._zones[0]["armed"], "damaged fuel barrel leaks before destruction")
	safe.take_damage(safe.max_hp * 0.5)
	_check(chain._zones.size() == 1, "vault cannot leak fuel")
	chain.clear()
	_check(not barrel.leaked.is_connected(chain._on_leaked), "chapter cleanup removes old listeners")
	chain.spill(Vector2(300, 300), true)
	chain._physics_process(1.3)
	_check(enemy.last_damage_kind == &"shock", "broken electrical equipment shocks")
	chain.queue_free()
	barrel.queue_free()
	safe.queue_free()
	manager.release_all()
	for e in manager._free:
		e.queue_free()
	manager.queue_free()
	player.queue_free()
	await _frames()


func _equipment() -> void:
	var visual := RaccoonVisual.new()
	add_child(visual)
	var ids: Array[String] = ["fist", "bullet", "boot", "heart"]
	for hero_id in ["raccoon", "red_panda", "snow", "night", "neon_hopper", "fluffy_chemist", "pigeon_mafioso", "sniper_f", "medic_f"]:
		visual.apply_look(CharacterDB.get_character(hero_id), {})
		visual.update_motion(Vector2(120, 0), Vector2.RIGHT, 0.1)
		var muzzle := visual.get_muzzle_global(Vector2.RIGHT)
		visual.apply_equipment(ids)
		visual.weapon_tier = 5
		visual.update_motion(Vector2(120, 0), Vector2.RIGHT, 0)
		_check(visual.get_muzzle_global(Vector2.RIGHT).is_equal_approx(muzzle), hero_id + " equipment preserves muzzle and arm pose")
		_check(visual.equipped_patches.size() == 4 and visual.equipment_anchor().is_finite(), hero_id + " carries four patches")
	visual.apply_equipment([])
	_check(visual.equipped_patches.is_empty(), "removing equipment clears all badges")
	visual.queue_free()
	await _frames()


func _extraction() -> void:
	var game := Game.new()
	game.story_mission = "m1"
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.start()
	await _frames(6)
	get_tree().paused = false
	game.story.set_process(false)
	game.story.set_physics_process(false)
	game.story.finished_mission = true
	game.enemies.release_all()
	game.story_finished()
	var extraction := game.extraction
	extraction.set_physics_process(false)
	_check(game.story_target == extraction and game.map.is_area_clear(extraction.position, 80), "extraction is reachable and tracked")
	var coins := SaveService.get_coins()
	game.story_finished()
	_check(game.extraction == extraction, "duplicate victory cannot start second transport")
	get_tree().paused = true
	extraction._physics_process(10)
	_check(extraction.elapsed == 0, "boarding and transport pause together")
	get_tree().paused = false
	extraction._physics_process(2.1)
	_check(extraction._guards.size() > 0 and game.enemies.get_active_count() <= 3, "evacuation creates a small final fight")
	# Убитый охранник не должен удалить следующего жильца того же слота пула.
	var entry: Dictionary = extraction._guards[0]
	var guard := (entry["ref"] as WeakRef).get_ref() as Enemy
	game.enemies.release(guard)
	var reused := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), Vector2(1000, 1000))
	game.player.position = extraction.position
	extraction._physics_process(2.0)
	extraction._physics_process(2.0)
	_check(game.finished and SaveService.get_coins() == coins + Extraction.BONUS, "boarding completes mission and grants bonus once")
	_check(reused.is_alive(), "cleanup respects pooled enemy lifetime")
	extraction.finish(true)
	_check(SaveService.get_coins() == coins + Extraction.BONUS, "repeated boarding cannot duplicate reward")
	get_tree().paused = false
	game.finished = false
	var recovery := Extraction.new()
	game.layers.world.add_child(recovery)
	recovery.start(game)
	recovery.set_physics_process(false)
	var outcome := {"count": 0, "boarded": true}
	recovery.completed.connect(func(boarded: bool) -> void:
		outcome["count"] += 1
		outcome["boarded"] = boarded)
	game.player.is_dead = true
	recovery._physics_process(0.1)
	_check(outcome["count"] == 1 and not outcome["boarded"], "injured squad is recovered without hanging or bonus")
	_check(SaveService.get_coins() == coins + Extraction.BONUS, "recovery preserves prior rewards")
	game.player.is_dead = false
	var backup := Extraction.new()
	game.layers.world.add_child(backup)
	backup.start(game)
	backup.set_physics_process(false)
	backup.completed.connect(func(boarded: bool) -> void:
		outcome["count"] += 1
		outcome["boarded"] = boarded)
	backup.elapsed = Extraction.LIMIT - 0.1
	game.player.position += Vector2(100, 0)
	backup._physics_process(0.2)
	_check(outcome["count"] == 2 and not outcome["boarded"], "backup transport guarantees a finite finale")
	game.queue_free()
	await _frames(4)
