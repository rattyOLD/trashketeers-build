extends Node
var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("REWARD_PACE: " + label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	game.director._start_wave(5)
	var boss := game.enemies.spawn(ContentDB.get_enemy(&"beer_baron"), game.player.global_position + Vector2(350, 0))
	game._on_miniboss_killed(boss, boss.global_position)
	_check((SaveService.data["boss_firsts"] as Array).is_empty(), "actual miniboss reward preserves chapter-first bonus")
	_check(game.run_gems == Economy.miniboss_gems(0, 0), "actual miniboss pays the advertised amount")
	game.enemies.release_all()
	for chapter in 6:
		for round_index in [0, 2, 5]:
			SaveService.data["boss_firsts"] = []
			var mini := Economy.miniboss_gems(chapter, round_index)
			var robbed := Economy.miniboss_gems(chapter, round_index, true)
			_check(mini > 0 and robbed > 0 and (SaveService.data["boss_firsts"] as Array).is_empty(), "both mini choices preview positive rewards without consuming firsts")
			var first := Economy.boss_reward(chapter, round_index)
			var second := Economy.boss_reward(chapter, round_index)
			_check(int(first["gems"]) - int(second["gems"]) == Economy.FIRST_BOSS_GEMS, "chapter-first bonus is paid exactly once")
			_check(int(second["gems"]) == Economy.base_boss_gems(chapter, round_index), "repeat boss retains base payout")
	var at := game.player.global_position
	game.player.hp = 50.0
	var friendly := BulletPool.spawn(WeaponDB.get_weapon(&"pistol_v1"), at + Vector2(10000, 0), Vector2.RIGHT)
	BulletPool.spawn(WeaponDB.get_weapon(&"pistol_v1"), at, Vector2.RIGHT, Bullet.Team.ENEMY)
	BulletPool.spawn(WeaponDB.get_weapon(&"pistol_v1"), at, Vector2.LEFT, Bullet.Team.ENEMY)
	BulletPool._blast_queue.append([at, 100.0, 50.0, Bullet.Team.ENEMY, Color.WHITE, 1.0, &"blast"])
	BulletPool._blast_queue.append([at + Vector2(10000, 0), 100.0, 50.0, Bullet.Team.PLAYER, Color.WHITE, 1.0, &"blast"])
	var lob_resources := _owned_lob(game.lobs, at)
	_check(lob_resources[0].get_ref() != null and lob_resources[1].get_ref() != null, "active lob owns both textures")
	game.hazards._kind[0] = HazardDirector.Kind.SHOCK
	game.hazards._pos[0] = at
	game.hazards._warn[0] = 0.0
	game.hazards._life[0] = 3.0
	game.hazards._time[0] = 1.0
	game.hazards._fired[0] = 0
	for pool in game.events.pools:
		pool.activate(at)
	var prop_pool := AcidPool.new()
	game.layers.decals.add_child(prop_pool)
	prop_pool.activate(at)
	var acid_handle := prop_pool._light_id
	game._on_wave_cleared(5)
	_check(lob_resources[0].get_ref() == null and lob_resources[1].get_ref() == null, "wave clear releases cancelled lob resources")
	var hp := game.player.hp
	_check(friendly.pool_index >= 0 and BulletPool.get_active_count() == 1, "clear removes enemy bullets, preserves player projectile")
	_check(BulletPool._blast_queue.size() == 1 and BulletPool._blast_queue[0][3] == Bullet.Team.PLAYER, "clear cancels queued enemy explosions only")
	game.director.phase = WaveDirector.Phase.INTERMISSION
	game.lobs._physics_process(2.0)
	game.hazards._physics_process(2.0)
	BulletPool._physics_process(2.0)
	_check(is_equal_approx(game.player.hp, hp), "completed wave cannot deal residual projectile, lob or hazard damage")
	for pool in game.events.pools:
		_check(not pool.visible and not pool.is_processing() and pool.collision_mask == 0, "leaks stop after wave clear")
	_check(not prop_pool.visible and not prop_pool.is_processing() and prop_pool.collision_mask == 0, "prop acid also stops after wave clear")
	_check(prop_pool._light_id == -1 and EnvLights._radius[acid_handle % EnvLights.ID_STRIDE] == 0.0, "expired acid no longer retains its world light")
	prop_pool.activate(at + Vector2(1000, 0))
	for frame in 3: await get_tree().physics_frame
	_check(prop_pool.visible and prop_pool.monitoring and not prop_pool._collision.disabled and prop_pool.collision_mask == (PhysicsLayers.PLAYER | PhysicsLayers.ENEMY), "acid pool can be reused on a later wave")
	prop_pool.deactivate()
	for step in 16: game.hazards._physics_process(0.25)
	_check(not game.hazards.camping and game.hazards._history.is_empty(), "resting does not pre-charge anti-camping")
	var director := WaveDirector.new()
	director.setup(game.enemies, game.player, game.map)
	director._start_wave(5)
	director.phase = WaveDirector.Phase.FIGHT
	director.remaining_to_spawn = 0
	director._boss_pending = false
	director._physics_process(0.01)
	_check(director.phase == WaveDirector.Phase.INTERMISSION and director._phase_time >= 6.0, "mini wave gives six seconds to regroup")
	director.shift_left = 0.01
	director._physics_process(1.0)
	_check(director.wave_number == 5 and is_equal_approx(director.shift_left, 0.01), "siren clock cannot cut the rest short")
	director.phase = WaveDirector.Phase.FIGHT
	director._physics_process(0.02)
	_check(director.wave_number == 10, "siren still calls chapter boss when combat resumes")
	var run := RunStats.new()
	run.add_flat(&"tactic_switcher", 3.0)
	director.run_stats = run
	var wc := game.player.weapon_controller
	var boss_data := ContentDB.get_enemy(&"beer_baron")
	var source := WeaponDB.get_weapon(&"pistol_v1").duplicate_data()
	source.damage = boss_data.max_hp / WaveDirector.BOSS_TARGET_TIME * 4.0 * source.fire_interval / source.projectiles_per_shot
	wc.setup(game.enemies.find_nearest, source, run)
	var ordinary_damage := wc.weapon.damage
	var normal_hp := director._adaptive_boss_mult(boss_data)
	_check(normal_hp > 1.0 and normal_hp < 3.0, "boss fixture is inside the adaptive range, away from both clamps")
	run.switch_boost_left = 2.4
	wc.apply_run_stats(run)
	_check(wc.weapon.damage > ordinary_damage * 1.9, "fixture activates the real third-rank weapon swap bonus")
	var boosted_hp := director._adaptive_boss_mult(boss_data)
	_check(is_equal_approx(normal_hp, boosted_hp), "temporary swap boost cannot increase boss spawn HP")
	print("REWARD_PACE boss_hp_normal=", normal_hp, " boss_hp_boosted=", boosted_hp, " actual_weapon_ratio=", wc.weapon.damage / ordinary_damage)
	director.free()
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
	print("REWARD_PACE failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _owned_lob(pool: LobPool, at: Vector2) -> Array:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var projectile := ImageTexture.create_from_image(image)
	var blast := ImageTexture.create_from_image(image)
	pool.throw(at + Vector2(200, 0), at, 0.3, 100.0, 100.0, 50.0, Color.WHITE, projectile, blast, 20.0)
	return [weakref(projectile), weakref(blast)]
