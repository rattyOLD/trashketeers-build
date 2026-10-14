extends Node2D
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("DAMAGE_INTEGRATION: " + label)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var game := Game.new()
	add_child(game)
	game.start()
	for node: Node in [game, game.director, game.events, game.hazards, game.player, game.player.weapon_controller, game.enemies, game.tactics, game.status, game.pickups, BulletPool]:
		node.set_physics_process(false)
	game.enemies.release_all()
	var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), Vector2(500, 0), 20.0)
	enemy.set_physics_process(false)
	var original_hp := enemy.hp
	var bullet := Bullet.new()
	bullet.weapon = WeaponDB.get_weapon(&"pistol_v1").duplicate_data()
	bullet.weapon.damage = 20.0
	bullet.weapon.crit_chance = 0.0
	bullet.velocity = Vector2.RIGHT
	bullet._apply_damage(enemy)
	_check(is_equal_approx(game._combat_report.enemy_damage, original_hp - enemy.hp), "actual Game wiring counts one bullet once")
	_check(game._combat_report.damage_by_source.has(&"pistol_v1"), "Game receives weapon identity")
	enemy.add_poison(10.0, 3.0, 3, &"pistol_v1")
	enemy.add_bleed(12.0, 3.0, true, &"skill:hero")
	enemy.add_dash_poison(5.0)
	game.enemies.release(enemy)
	var reused := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), Vector2(500, 0), 20.0)
	reused.set_physics_process(false)
	_check(reused == enemy and reused.poison_source == &"" and reused.bleed_source == &"" and reused.dash_poison_source == &"", "pooled enemy clears every DOT origin")
	_check(reused.poison_stacks == 0 and reused.bleed_left == 0.0 and reused.dash_poison_left == 0.0, "pool clears DOT state")
	for frame in 3: await get_tree().physics_frame
	var before := game._combat_report.enemy_damage
	BulletPool._blasts_this_frame = BulletPool.MAX_BLASTS_PER_FRAME
	BulletPool.explode(reused.global_position, 80.0, 40.0, Bullet.Team.PLAYER, Color.ORANGE, 0.0, &"blast", &"trash_shotgun_v1")
	_check(BulletPool._blast_queue.size() == 1 and game._combat_report.enemy_damage == before, "over-budget blast queues without early attribution")
	BulletPool._physics_process(0.0)
	_check(is_equal_approx(game._combat_report.enemy_damage - before, 40.0) and is_equal_approx(float(game._combat_report.damage_by_source.get(&"trash_shotgun_v1", 0.0)), 40.0), "deferred physics blast preserves source")
	before = game._combat_report.enemy_damage
	reused._take_dot(8.0, "burn", &"skill:hero")
	_check(is_equal_approx(game._combat_report.enemy_damage - before, 8.0) and is_equal_approx(float(game._combat_report.damage_by_source.get(&"skill:hero", 0.0)), 8.0), "Game DOT sink does not duplicate accounting")
	var shield_data := EnemyData.new()
	for property: Dictionary in reused.data.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			shield_data.set(property["name"], reused.data.get(property["name"]))
	shield_data.armor = 0.25
	shield_data.shield = true
	shield_data.shield_block = 0.8
	shield_data.shield_arc = PI
	reused.data = shield_data
	reused._shield_dir = Vector2.LEFT
	before = game._combat_report.enemy_damage
	var hp_before := reused.hp
	bullet._apply_damage(reused)
	_check(is_equal_approx(game._combat_report.enemy_damage - before, hp_before - reused.hp) and game._combat_report.enemy_damage - before < 20.0, "shield and armor count only removed HP")
	var total := 0.0
	for row: Dictionary in game._combat_report.contribution_rows(): total += float(row["amount"])
	_check(is_equal_approx(total, game._combat_report.enemy_damage), "all sources sum to actual combat total")
	game._combat_report.record_actual(7.0, &"blast", &"effect:chain")
	_check(game._combat_report.contribution_lines().contains("Цепные реакции"), "chain name survives effect grouping")
	game._finish()
	var panel := game.hud._run_result
	_check(panel._tip_label.text.contains("ВКЛАД В УРОН") and panel._tip_label.text.contains("Умение героя"), "actual result shows contribution text")
	get_tree().paused = false
	for resolution in [Vector2i(1280, 720), Vector2i(923, 420)]:
		get_window().size = resolution
		for frame in 8: await get_tree().process_frame
		await get_tree().create_timer(0.7, true, false, true).timeout
		panel._fit_result()
		var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		_check(view.grow(1.0).encloses(panel._panel.get_global_rect()), "result fits " + str(resolution))
		var bar := panel._report_scroll.get_v_scroll_bar()
		panel._report_scroll.scroll_vertical = int(bar.max_value)
		for frame in 3: await get_tree().process_frame
		_check(panel._report_scroll.scroll_vertical > 0, "contribution bottom reachable " + str(resolution))
		var output := OS.get_environment("DAMAGE_OUT")
		if not output.is_empty():
			DirAccess.make_dir_recursive_absolute(output)
			get_viewport().get_texture().get_image().save_png(output.path_join("result_%dx%d.png" % [resolution.x,resolution.y]))
	bullet.free()
	game.free()
	BulletPool.release_all()
	var dragon := WhiteDragon.new()
	add_child(dragon)
	dragon.set_physics_process(false)
	dragon.state = WhiteDragon.State.LANDED_ATTACK
	dragon.hp = 100.0
	dragon.max_hp = 100.0
	dragon.exhausted = true
	var raid_report := CombatReport.new()
	dragon.damage_reported.connect(raid_report.record_actual)
	dragon.set_damage_source(&"pistol_v1", &"projectile")
	dragon.take_damage(15.0)
	_check(is_equal_approx(raid_report.enemy_damage, 30.0) and raid_report.damage_by_source.has(&"pistol_v1"), "raid reports actual exhausted damage")
	dragon.state = WhiteDragon.State.AERIAL_PATROL
	dragon.set_damage_source(&"trash_shotgun_v1")
	dragon.take_damage(10.0)
	_check(raid_report.enemy_damage == 30.0 and dragon._damage_origin == &"", "invulnerable dragon consumes rejected source")
	dragon.free()
	var raid := Raid.new()
	add_child(raid)
	raid.start()
	raid.set_physics_process(false)
	raid._combat_report.record_actual(30.0, &"projectile", &"pistol_v1")
	raid._show_result(true, PackedStringArray(["Хладгор повержен!", "Урон по дракону: 30"]))
	_check(raid.hud._result._tip_label.text.contains("ВКЛАД В УРОН"), "raid result override includes real source report")
	get_tree().paused = false
	for frame in 6: await get_tree().process_frame
	raid.free()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("DAMAGE_INTEGRATION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
