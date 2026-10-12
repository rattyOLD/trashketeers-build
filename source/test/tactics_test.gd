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
	wall.position = game.player.global_position + Vector2(200, 0)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 250)
	collision.shape = shape
	wall.add_child(collision)
	game.entities.add_child(wall)
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
	game.stats.apply(_pick("switcher"))
	game.player.apply_run_stats(game.stats)
	game.player.weapon_controller.set_slot(1, WeaponDB.get_weapon(&"smg_v1"))
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
	print("TACTICS_TEST failures=", failures)
	get_tree().quit(1 if failures else 0)
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
