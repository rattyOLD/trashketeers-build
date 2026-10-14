extends Node
var failures := 0
var measurements: Array[Dictionary] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("BOSS_BALANCE: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	SaveService.data["tips_off"] = true
	var game := Game.new()
	add_child(game)
	game.start()
	for node: Node in [game, game.director, game.events, game.hazards, game.player, game.player.weapon_controller, game.enemies, game.tactics, game.status, game.pickups]:
		node.set_physics_process(false)
	game.enemies.release_all()
	var director := WaveDirector.new()
	director.setup(game.enemies, game.player, game.map)
	var original := game.player.weapon_controller.weapon
	for chapter in 6:
		var definition := ContentDB.get_chapter(chapter)
		var data := ContentDB.get_enemy(StringName(definition["waves"][4]["miniboss"]))
		var previous := 0.0
		for scale in [1.0, 2.0, 4.0, 8.0, 16.0]:
			var weapon := original.duplicate_data()
			weapon.damage *= scale
			game.player.weapon_controller.weapon = weapon
			var factor := director._adaptive_boss_mult(data)
			var efficiency: float = scale / factor
			_check(efficiency > previous, "stronger weapon beats boss faster in chapter %d" % chapter)
			previous = efficiency
			weapon.ricochet_count += 4
			weapon.piercing = true
			_check(is_equal_approx(factor, director._adaptive_boss_mult(data)), "crowd effects do not raise single-target HP")
			weapon.ricochet_count = original.ricochet_count
			weapon.piercing = original.piercing
			var run := RunStats.new()
			run.add_flat(&"max_hp_add", 500.0)
			run.add_flat(&"damage_resist", 0.5)
			director.run_stats = run
			_check(is_equal_approx(factor, director._adaptive_boss_mult(data)), "defensive choices do not raise boss HP")
			measurements.append({"chapter":chapter,"damage_scale":scale,"boss_hp_factor":factor,"damage_per_hp":efficiency})
	game.player.weapon_controller.weapon = original
	director.run_stats = null
	for mini in [true, false]:
		game.enemies.release_all()
		director._start_wave(5 if mini else 10)
		director._physics_process(WaveDirector.INTRO_TIME + 0.01)
		director._tick_boss(1.0)
		_check(director.boss != null, "boss actually spawns")
		var spawned := 0
		for pack in 8:
			director._escort_timer = 0.0
			director._tick_boss(1.0)
			for enemy in game.enemies.get_active().duplicate():
				if enemy != director.boss:
					spawned += 1
					game.enemies.release(enemy)
		var pack_count := int(director._chapter["escort"]["count"])
		_check(spawned == pack_count * (2 if mini else 8), "mini escort is finite; chapter escort keeps pressure")
		measurements.append({"mini":mini,"escort_spawned":spawned})
	game.enemies.release_all()
	var baron := game.enemies.spawn(ContentDB.get_enemy(&"beer_baron"), game.player.global_position + Vector2(350, 0))
	for phase_number in [1, 2]:
		BulletPool.release_all()
		var brain := baron._brain as BossBrain
		brain.phase = phase_number
		brain._enter(BossBrain.State.BEAM_WINDUP)
		brain.tick(game.player, Vector2.LEFT, Vector2.LEFT, 350.0, 0.2)
		var locked := brain._aim_dir
		game.player.global_position += Vector2(0, 100)
		brain.tick(game.player, Vector2.LEFT, Vector2.LEFT, 350.0, 0.1)
		_check(brain._aim_dir.is_equal_approx(locked), "beam direction locked after warning in both phases")
		_check(brain.state == BossBrain.State.BEAM_WINDUP and BulletPool.get_active_count() == 0, "warning does not fire early")
		brain.tick(game.player, Vector2.LEFT, Vector2.LEFT, 350.0, 0.31)
		_check(brain._aim_dir.is_equal_approx(locked) and brain.state == BossBrain.State.BEAM_WINDUP, "moving player cannot be followed through locked warning")
		brain.tick(game.player, Vector2.LEFT, Vector2.LEFT, 350.0, 0.02)
		_check(brain.state == BossBrain.State.BEAM, "beam starts after full warning")
	_check(BossBrain.BEAM_WINDUP_TIME - BossBrain.BEAM_LOCK_TIME >= 0.35, "locked direction leaves at least 350 ms reaction")
	director.free()
	game.free()
	get_tree().paused = false
	BulletPool.release_all()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("BOSS_BALANCE measurements=", JSON.stringify(measurements))
	print("BOSS_BALANCE failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
