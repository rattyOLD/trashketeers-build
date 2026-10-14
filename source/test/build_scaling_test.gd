extends Node
var failures := 0
var measurements: Array[Dictionary] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("BUILD_SCALING: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	var game := Game.new()
	add_child(game)
	game.start()
	for node: Node in [game, game.director, game.events, game.hazards, game.player, game.player.weapon_controller, game.enemies, game.tactics, game.status, game.pickups]:
		node.set_physics_process(false)
	game.enemies.release_all()
	var weapon_count := 0
	for base in WeaponDB.get_player_weapons():
		for tier in [1, 5]:
			var run := RunStats.new()
			var original := base.with_tier(tier)
			var source := original.with_run_stats(run)
			var baseline := CombatTactics.turret_damage(source, run)
			var dps := source.damage * source.projectiles_per_shot / source.fire_interval
			_check(is_equal_approx(baseline / CombatTactics.turret_interval(1), dps * 0.22), "turret has same first-rank share for every weapon")
			run.add_flat(&"damage_mult", 1.0)
			var upgraded := CombatTactics.turret_damage(original.with_run_stats(run), run)
			_check(is_equal_approx(upgraded, baseline * 2.0), "damage upgrade reaches turret without a flat damage cap")
			run.add_flat(&"fire_rate_mult", 0.5)
			var faster := CombatTactics.turret_damage(original.with_run_stats(run), run)
			_check(is_equal_approx(faster, upgraded * 1.5), "fire-rate upgrade reaches turret")
			run.add_flat(&"tactic_switcher", 3.0)
			var normal := original.with_run_stats(run)
			var ordinary := CombatTactics.turret_damage(normal, run)
			var boosted := normal.duplicate_data()
			boosted.damage *= CombatTactics.swap_damage_multiplier(3)
			run.switch_boost_left = 2.4
			_check(is_equal_approx(CombatTactics.turret_damage(boosted, run), ordinary), "runtime swap multiplier is removed from turret base")
			var previous := 0.0
			for rank_index in [1, 2, 3]:
				var output := baseline / CombatTactics.turret_interval(rank_index)
				_check(output > previous, "each turret rank increases actual sustained output")
				previous = output
			measurements.append({"weapon":String(base.id),"tier":tier,"turret_damage":baseline,"damage_upgrade":upgraded,"rate_upgrade":faster})
			weapon_count += 1
	game.player.global_position = Vector2(10000, 10000)
	var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(100, 0), 1000.0)
	enemy.set_physics_process(false)
	for frame in 3: await get_tree().physics_frame
	var burn_values: Array[float] = []
	var zone_values: Array[float] = []
	var shard_values: Array[float] = []
	for strength in [0.0, 1.0]:
		var run := RunStats.new()
		run.has_tactics = true
		run.add_flat(&"tactic_arson", 1.0)
		run.add_flat(&"tactic_frost", 1.0)
		run.add_flat(&"status_power", strength)
		game.tactics.stats = run
		game.player.weapon_controller.weapon = WeaponDB.get_weapon(&"pistol_v1").with_run_stats(run)
		enemy.bleed_dps = 0.0
		enemy.bleed_left = 0.0
		game.tactics._affect(enemy, 50.0, false)
		burn_values.append(enemy.bleed_dps)
		game.tactics._kill_left = 0.0
		game.tactics._fields.clear()
		game.tactics.enemy_died(enemy)
		zone_values.append(float(game.tactics._fields[0]["damage"]))
		BulletPool.release_all()
		game.tactics._shatter(enemy.global_position, 1)
		var bullet: Bullet = BulletPool._active.back()
		bullet.weapon.crit_chance = 0.0
		var hp := enemy.hp
		bullet._apply_damage(enemy)
		shard_values.append(hp - enemy.hp)
	_check(is_equal_approx(burn_values[1], burn_values[0] * 2.0), "effect power doubles tactical burn")
	_check(is_equal_approx(zone_values[1], zone_values[0] * 2.0), "effect power doubles death zone")
	_check(absf(shard_values[1] / shard_values[0] - 2.0) < 0.001, "effect power doubles actual shard impact")
	var active: Bullet = BulletPool._active.back()
	var emitted := active.weapon.damage * active.damage_scale
	game.player.weapon_controller.weapon = WeaponDB.get_weapon(&"sniper_v1").with_tier(5)
	game.tactics.stats.add_flat(&"status_power", 0.5)
	game.tactics._shatter(enemy.global_position, 3)
	_check(is_equal_approx(emitted, active.weapon.damage * active.damage_scale), "upgrades do not change a shard already in flight")
	measurements.append({"burn":burn_values,"zone":zone_values,"actual_shard_hits":shard_values,"weapons_and_tiers":weapon_count})
	BulletPool.release_all()
	game.free()
	get_tree().paused = false
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("BUILD_SCALING measurements=", JSON.stringify(measurements))
	print("BUILD_SCALING failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
