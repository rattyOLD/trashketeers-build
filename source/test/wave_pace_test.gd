extends Node
var failures := 0
var measurements: Array[Dictionary] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("WAVE_PACE: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	SaveService.data["tips_off"] = true
	Orient.portrait = false
	var game := Game.new()
	add_child(game)
	game.start()
	for node: Node in [game, game.director, game.events, game.hazards, game.player, game.player.weapon_controller, game.enemies, game.tactics, game.status, game.pickups]:
		node.set_physics_process(false)
	game.enemies.release_all()
	_test_adaptation(game)
	_test_rewards(game)
	game.free()
	get_tree().paused = false
	BulletPool.release_all()
	for player in SoundManager._players: player.stop()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	var output := OS.get_environment("PACE_OUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(measurements, "\t"))
	print("WAVE_PACE failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _test_adaptation(game: Game) -> void:
	var director := WaveDirector.new()
	director.setup(game.enemies, game.player, game.map)
	for wave in [1, 4, 9, 11, 21, 61]:
		var previous_efficiency := 0.0
		var base_damage := 0.0
		for attack in [1.0, 2.0, 4.0, 8.0, 16.0]:
			var run := RunStats.new()
			run.add_flat(&"damage_mult", minf(attack, 4.0) - 1.0)
			if attack >= 8.0: run.add_flat(&"fire_rate_mult", 1.0)
			if attack >= 16.0: run.add_flat(&"extra_projectiles", 4.0)
			director.run_stats = run
			director._start_wave(wave)
			if base_damage == 0.0: base_damage = director.get_damage_mult()
			var hp := director.get_hp_mult()
			var count := director.remaining_to_spawn
			var pressure := director.get_damage_mult()
			var power := run.offensive_power()
			var efficiency := power / (hp * count)
			_check(efficiency > previous_efficiency, "attack growth improves damage relative to the actual HP/count budget")
			_check(is_equal_approx(pressure, base_damage), "enemy damage follows the wave, not offensive upgrades")
			previous_efficiency = efficiency
			run.add_flat(&"max_hp_add", 1000.0)
			run.add_flat(&"damage_resist", 0.5)
			director._start_wave(wave)
			_check(is_equal_approx(run.offensive_power(), power) and run.power() > power, "defence remains part of the report, separate from attack")
			_check(is_equal_approx(director.get_hp_mult(), hp) and is_equal_approx(director.get_damage_mult(), pressure) and director.remaining_to_spawn == count, "defensive choices do not raise enemy HP, damage or count")
			measurements.append({"wave": wave, "attack": power, "adapt": director.adapt, "enemy_hp_mult": hp, "enemy_damage_mult": pressure, "count": count, "damage_per_hp_budget": efficiency})
	for wave in [1, 20, 80]:
		var previous := 1.0
		for power in [0.0, 1.0, 2.0, 8.0, 32.0, 10000.0]:
			var factor := WaveDirector.adaptive_factor(power, wave)
			_check(factor >= previous and factor <= WaveDirector.ADAPT_MAX, "adaptation stays bounded and monotonic")
			previous = factor
	director.free()

func _test_rewards(game: Game) -> void:
	game.director._start_wave(1)
	game.pickups.clear()
	game.level = 1
	game.xp = 0
	game.nuts = 0
	game._pending_levelups = 0
	var far := game.player.global_position + Vector2(10000, 0)
	game.pickups.spawn_xp(far, 50)
	game.pickups.spawn_xp_gold(far, 7)
	game.pickups.spawn(far, 8)
	game.pickups._physics_process(0.1)
	_check(game.xp == 0 and game.level == 1, "during combat distant XP still needs collecting")
	game._on_wave_cleared(1)
	_check(game._loot_at_clear == 8, "clean sweep counts coins rather than XP crystals")
	for step in 130: game.pickups._physics_process(1.0 / 60.0)
	_check(game.level == 4 and game.xp == 12 and game._pending_levelups == 3, "normal and gold XP are credited exactly once, including queued levels")
	_check(game.pickups.get_count() == 8 and game.pickups.get_coin_count() == 8 and game.nuts == 5, "wave clear leaves distant coins and does not create a clean-sweep bonus")
	game._check_clean_sweep()
	_check(game.nuts == 5, "XP vacuum alone cannot earn the manual coin collection bonus")
	game._loot_at_clear = 8
	game.pickups.vacuum()
	for step in 130: game.pickups._physics_process(1.0 / 60.0)
	_check(game.pickups.get_count() == 0 and game.nuts == 13, "full chapter vacuum still collects all eight coins exactly once")
	game._check_clean_sweep()
	_check(game.nuts == 23 and game.xp == 19, "manual clean sweep retains its existing coin and XP reward")
	game._check_clean_sweep()
	_check(game.nuts == 23 and game.xp == 19, "clean sweep is paid once")
	game.pickups.spawn_xp(far, 8)
	game._loot_at_clear = 8
	game._check_clean_sweep()
	_check(game.nuts == 33, "uncollected XP cannot block an earned coin sweep")
	game.pickups.clear()
	var picked := [0]
	game.pickups.xp_collected.connect(func(amount: int) -> void: picked[0] += amount)
	game.pickups.spawn_xp(far, 960)
	for i in PickupManager.CAPACITY: game.pickups.spawn_xp_gold(far, 2)
	game.pickups.vacuum(true)
	for step in 130: game.pickups._physics_process(1.0 / 60.0)
	_check(game.pickups.get_count() == 0 and picked[0] == 1600, "a full pool and overflow credit every XP point once")
	measurements.append({"reward_test": "wave XP / coins / clean sweep / full pool", "pool_count": game.pickups.get_count()})
