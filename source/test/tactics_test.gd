extends Node
var failures := 0
var game: Game
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("TACTICS: " + label)
func _pick(id: String) -> UpgradeData:
	for upgrade in ContentDB.get_upgrades():
		if String(upgrade.id) == "tactic_" + id:
			return upgrade
	return null
func _ready() -> void:
	Controls.apply_keys()
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tester"]["god"] = true
	SaveService.data["tips_off"] = true
	WeaponController.force_auto = false
	var model := RunStats.new()
	model.ranged_context = false
	_check(not model.is_available(_pick("bankshot")), "melee-only build cannot roll wall bounces")
	model.apply(_pick("bankshot"))
	_check(CombatTactics.rank(model, "bankshot") == 0, "unusable bounces cannot impose a damage penalty")
	model.ranged_context = true
	model.apply(_pick("bankshot"))
	model.apply(_pick("frost"))
	_check(not model.is_available(_pick("arson")), "two-tactic limit")
	model.apply(_pick("arson"))
	_check(CombatTactics.rank(model, "arson") == 0, "unavailable tactic cannot be applied")
	for i in 6:
		model.apply(_pick("bankshot"))
	_check(CombatTactics.rank(model, "bankshot") == 3, "three ranks")
	var base := WeaponDB.get_weapon(&"pistol_v1")
	var damage := base.damage
	var derived := base.with_run_stats(model)
	_check(derived.world_bounces == 4 and derived.damage < damage, "bankshot has real bounces and direct-shot tradeoff")
	_check(base.damage == damage and base.world_bounces == 0, "base weapon is immutable")
	game = Game.new()
	add_child(game)
	game.start()
	await get_tree().create_timer(2.0).timeout
	game.director.set_physics_process(false)
	game.enemies.release_all()
	game.stats.apply(_pick("bankshot"))
	game.player.apply_run_stats(game.stats)
	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.position = Vector2(10000, 10000)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 250)
	collision.shape = shape
	wall.add_child(collision)
	game.entities.add_child(wall)
	for frame in 3:
		await get_tree().physics_frame
	var bounced := BulletPool.spawn(game.player.weapon_controller.weapon, wall.global_position - Vector2(35, 0), Vector2.RIGHT)
	for i in 12:
		await get_tree().physics_frame
		if bounced.wall_bounces > 0:
			break
	_check(bounced.wall_bounces > 0 and bounced.velocity.x < 0 and bounced.damage_scale > 1.0, "real wall reflects and strengthens the projectile")
	BulletPool.release_all()
	wall.queue_free()
	game.stats.apply(_pick("frost"))
	game.player.apply_run_stats(game.stats)
	var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(110, 0), 100.0)
	_check(enemy != null, "enemy fixture")
	if enemy != null:
		enemy.set_physics_process(false)
		await get_tree().physics_frame
		for i in 3:
			var bullet := BulletPool.spawn(game.player.weapon_controller.weapon, game.player.global_position, Vector2.RIGHT)
			bullet._apply_damage(enemy)
			BulletPool.release(bullet)
		_check(enemy.freeze_left > 0.0, "three physical hits freeze an ordinary enemy")
		enemy.take_damage(999999.0)
		_check(game.tactics.shatters > 0 and BulletPool.get_active_count() >= 5, "a frozen kill creates real ice shards")
		_check(game.tactics._shard_weapon.bullet_texture != null, "ice shards retain visible original art")
	BulletPool.release_all()
	var chilled := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(300, 0), 100.0)
	if chilled != null:
		chilled.add_slow(0.95, 3.0)
		game.tactics._kill_left = 0.0
		var shards_before := game.tactics.shatters
		chilled.take_damage(999999.0)
		_check(game.tactics.shatters == shards_before, "slow without freezing does not create frozen-death shards")
	var melee_target := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(40, 0), 100.0)
	if melee_target != null:
		var blade := WeaponDB.get_weapon(&"katana_junk_v1")
		var fighter := game.player.weapon_controller.melee
		fighter._weapon = blade
		fighter.direction = Vector2.RIGHT
		await get_tree().physics_frame
		for hit in 2:
			fighter._resolve_hit(game.player.global_position, 1.0, false)
		_check(melee_target.freeze_left == 0.0, "two actual melee hits do not double-count frost")
		fighter._resolve_hit(game.player.global_position, 1.0, false)
		_check(melee_target.freeze_left > 0.0, "third actual melee contact freezes the target")
		_check(game.tactics._frost_hits[melee_target.get_instance_id()]["hits"] == 0, "one frost stack per actual hit")
	await get_tree().process_frame
	await _fresh()
	game.stats.apply(_pick("arson"))
	game.stats.apply(_pick("vanguard"))
	game.player.apply_run_stats(game.stats)
	game.player.move_input = Vector2.RIGHT
	game.player.try_dash()
	await get_tree().create_timer(0.8).timeout
	_check(game.tactics.echoes > 0, "dash path creates a delayed attack")
	_check(game.tactics._fields.size() >= 3, "fire and dash combine into a trail")
	for i in 40:
		game.tactics._add_field("fire", game.player.global_position, game.player.global_position, 80.0, 1.0, 5.0)
	_check(game.tactics._fields.size() == CombatTactics.MAX_FIELDS, "field memory budget")
	var before := game.tactics._clock
	get_tree().paused = true
	await get_tree().create_timer(0.2, true).timeout
	_check(game.tactics._clock == before, "tactic effects stop during pause")
	get_tree().paused = false
	await _fresh()
	game.stats.apply(_pick("sentry"))
	_check(not game.stats.is_available(_pick("switcher")), "switching tactic unavailable with one weapon")
	game.stats.apply(_pick("switcher"))
	_check(CombatTactics.rank(game.stats, "switcher") == 0, "unusable tactic cannot impose its damage penalty")
	game.player.weapon_controller.set_slot(1, WeaponDB.get_weapon(&"pistol_v1"))
	_check(not game.stats.is_available(_pick("switcher")), "duplicate weapon does not unlock switching tactic")
	game.player.weapon_controller.set_slot(1, WeaponDB.get_weapon(&"smg_v1"))
	_check(game.stats.is_available(_pick("switcher")), "two distinct weapons unlock switching tactic")
	game.stats.apply(_pick("switcher"))
	game.player.apply_run_stats(game.stats)
	var target := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(220, 0), 100.0)
	if target != null:
		target.set_physics_process(false)
	game.player.move_input = Vector2.ZERO
	await get_tree().create_timer(2.2).timeout
	_check(game.tactics.shots_from_turret > 0, "holding a position deploys a firing turret")
	game.player.weapon_controller.switch_slot(1)
	_check(game.stats.switch_boost_left > 0.0, "weapon swap opens a timed damage window")
	_check(game.player.weapon_controller.weapon.damage > game.player.weapon_controller.base_weapon.damage, "swap changes actual weapon damage")
	await get_tree().create_timer(2.6).timeout
	_check(game.stats.switch_boost_left <= 0.0, "swap boost expires")
	game.tactics.clear_fields()
	_check(game.tactics._fields.is_empty() and game.tactics._turret_left == 0.0, "chapter transition clears persistent fields")
	await _test_combinations()
	await _test_ranks()
	await _test_pooled_statuses()
	game.queue_free()
	for frame in 4:
		await get_tree().process_frame
	print("TACTICS_TEST failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)
func _fresh() -> void:
	game.queue_free()
	await get_tree().process_frame
	BattleMemory.release()
	game = Game.new()
	add_child(game)
	game.start()
	await get_tree().create_timer(1.2).timeout
	game.director.set_physics_process(false)
	game.enemies.release_all()


func _test_combinations() -> void:
	await _fresh()
	game.stats.apply(_pick("arson"))
	game.stats.apply(_pick("frost"))
	game.player.apply_run_stats(game.stats)
	var origin := game.player.global_position
	var warm := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), origin + Vector2(220, 0), 100.0)
	var neighbor := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), origin + Vector2(240, 0), 100.0)
	_check(warm != null and neighbor != null, "thermal strike fixtures")
	if warm != null and neighbor != null:
		warm.set_physics_process(false)
		neighbor.set_physics_process(false)
		for frame in 3:
			await get_tree().physics_frame
		_check(game.tactics._near(warm.global_position, 105.0).has(neighbor), "thermal neighbor is indexed by physics")
		var bullet := BulletPool.spawn(game.player.weapon_controller.weapon, origin, Vector2.RIGHT)
		bullet._apply_damage(warm)
		_check(warm.bleed_is_burn and warm.bleed_left > 0, "first physical hit applies fire")
		var before := neighbor.hp
		bullet._apply_damage(warm)
		_check(neighbor.hp < before, "fire and frost cause real area damage")
		before = neighbor.hp
		bullet._apply_damage(warm)
		_check(is_equal_approx(neighbor.hp, before), "thermal cooldown prevents repeated blasts in one frame")
		BulletPool.release_all()
	game.tactics._proc_left = 0.0
	game.tactics._kill_left = 0.0
	game.tactics._shatter_left = 0.0
	var ordinary := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), origin + Vector2(300, 0), 100.0)
	ordinary.add_slow(0.7, 3.0)
	ordinary.take_damage(999999.0)
	var shards := game.tactics.shatters
	var frozen := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), origin + Vector2(330, 0), 100.0)
	frozen.freeze(1.0)
	frozen.take_damage(999999.0)
	_check(game.tactics.shatters == shards + 1, "fire kill does not suppress a frozen kill in the same frame")
	_check(game.tactics._fields.size() > 0, "fire and shards coexist")
	await _fresh()
	game.stats.apply(_pick("bankshot"))
	game.stats.apply(_pick("frost"))
	game.player.apply_run_stats(game.stats)
	var target := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(220, 0), 100.0)
	var bounced := BulletPool.spawn(game.player.weapon_controller.weapon, game.player.global_position, Vector2.RIGHT)
	bounced.wall_bounces = 1
	bounced._apply_damage(target)
	_check(target.freeze_left > 0.0, "ice bank freezes on one bounced hit")
	BulletPool.release_all()
	var boss := game.enemies.spawn(ContentDB.get_enemy(&"beer_baron"), game.player.global_position + Vector2(320, 0), 100.0)
	bounced = BulletPool.spawn(game.player.weapon_controller.weapon, game.player.global_position, Vector2.RIGHT)
	bounced.wall_bounces = 1
	bounced._apply_damage(boss)
	_check(boss.freeze_left == 0.0 and boss.slow_left > 0.0, "ice bank slows a boss without freezing it")
	BulletPool.release_all()

func _test_ranks() -> void:
	await _fresh()
	game.tactics.set_physics_process(false)
	for tier in range(1, 4):
		var run := RunStats.new()
		for step in tier:
			run.apply(_pick("frost"))
			run.apply(_pick("sentry"))
		game.stats = run
		game.tactics.stats = run
		game.player.apply_run_stats(run)
		game.tactics.clear_fields()
		game.tactics._shatter_left = 0.0
		var target := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(220, 0), 100.0)
		target.set_physics_process(false)
		await get_tree().physics_frame
		for hit in 3:
			var bullet := BulletPool.spawn(game.player.weapon_controller.weapon, game.player.global_position, Vector2.RIGHT)
			bullet._apply_damage(target)
			BulletPool.release(bullet)
		_check(is_equal_approx(target.freeze_left, [0.8, 0.95, 1.1][tier - 1]), "frost duration increases at rank " + str(tier))
		target.take_damage(999999.0)
		_check(BulletPool.get_active_count() == 4 + tier, "actual shard count at rank " + str(tier))
		BulletPool.release_all()
		for id: String in CombatTactics.CATALOG:
			var model := RunStats.new()
			model.multi_weapon_context = true
			for step in tier - 1:
				model.apply(_pick(id))
			var description := CombatTactics.run_description(id, model)
			_check(not description.is_empty() and description != _pick(id).description, "rank-specific card: " + id + str(tier))
	game.stats = RunStats.new()
	game.tactics.stats = game.stats
	game.stats.apply(_pick("sentry"))
	game.player.apply_run_stats(game.stats)
	var target := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(220, 0), 100.0)
	target.set_physics_process(false)
	game.tactics._find_target = func(_at: Vector2, _range: float) -> Node2D: return target
	game.tactics._still = 1.3
	var shots: Array[int] = []
	for tier in range(1, 4):
		if tier > 1:
			game.stats.apply(_pick("sentry"))
		game.tactics._turret_shot = 0.0
		var before := game.tactics.shots_from_turret
		for tick in 600:
			game.tactics._tick_sentry(0.01)
		shots.append(game.tactics.shots_from_turret - before)
		BulletPool.release_all()
	_check(shots[2] > shots[1] and shots[1] > shots[0], "higher sentry ranks fire more shots over equal time")
	game.tactics._still = 0.0
	game.tactics._tick_sentry(3.1)
	_check(game.tactics._turret_left == 0.0, "turret expires after leaving its position")


func _test_pooled_statuses() -> void:
	await _fresh()
	game.stats.apply(_pick("frost"))
	game.player.apply_run_stats(game.stats)
	var at := game.player.global_position + Vector2(220, 0)
	var previous := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), at, 100.0)
	previous.set_physics_process(false)
	previous.add_bleed(500.0, 3.0, true)
	previous.add_poison(200.0, 3.0, 3)
	previous.add_slow(0.7, 3.0)
	for hit in 2:
		var bullet := BulletPool.spawn(game.player.weapon_controller.weapon, game.player.global_position, Vector2.RIGHT)
		bullet._apply_damage(previous)
		BulletPool.release(bullet)
	var activation := previous.activation_id
	game.enemies.release(previous)
	var reused := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), at, 100.0)
	reused.set_physics_process(false)
	_check(reused == previous and reused.activation_id != activation, "fixture reuses the same enemy object")
	_check(reused.bleed_dps == 0.0 and reused.poison_dps == 0.0 and reused.slow_amount == 0.0 and not reused.bleed_is_burn, "spawn resets status strength and burn identity")
	reused.add_bleed(6.0, 1.0, true)
	reused.add_poison(2.0, 1.0, 1)
	reused.add_slow(0.45, 1.0)
	var bullet := BulletPool.spawn(game.player.weapon_controller.weapon, game.player.global_position, Vector2.RIGHT)
	bullet._apply_damage(reused)
	BulletPool.release(bullet)
	_check(reused.freeze_left == 0.0, "a new enemy does not inherit the previous enemy's frost stacks")
	_check(reused.bleed_dps == 6.0 and reused.poison_dps == 2.0 and reused.slow_amount == 0.45, "weak effects stay weak after reuse")
	var before := reused.hp
	reused._tick_status(0.01)
	var expected := 8.0 * Enemy.STATUS_TICK * (1.0 - reused.data.armor * 0.5)
	_check(is_equal_approx(before - reused.hp, expected), "actual damage uses the new burn and poison strength")
