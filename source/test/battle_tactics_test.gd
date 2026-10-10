extends Node2D
var failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("BATTLE_TACTICS FAIL: " + message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._apply_text('{"reduced_flashes":true,"contrast_warnings":true}')
	_check(bool(SaveService.data["reduced_flashes"]) and bool(SaveService.data["contrast_warnings"]), "comfort settings survive reload")
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	_test_aim()
	_test_support()
	_test_boss()
	await _test_tasks()
	_test_motion()
	_test_effects()
	_test_audio()
	await _test_closed_menu()
	print("BATTLE_TACTICS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_aim() -> void:
	var player := Player.new()
	add_child(player)
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.activate(ContentDB.get_enemy(&"pig_sniper"), Vector2(200, 0))
	player.position = Vector2(450, 100)
	enemy._target_pos = player.position
	enemy._enter(Enemy.Act.AIM, Enemy.AIM_TIME)
	enemy._act_time = 0.3
	enemy._run_act(player, Vector2.RIGHT, Vector2.RIGHT, 250.0)
	var locked := enemy._aim_target
	player.position = Vector2(450, 250)
	enemy._act_time = 0.15
	_check(enemy._run_act(player, Vector2.DOWN, Vector2.DOWN, 250.0) == Vector2.ZERO, "shooter stops after aiming lock")
	_check(enemy._aim_target == locked, "last aim window allows a sidestep")
	enemy._act_time = 0.0
	enemy._run_act(player, Vector2.DOWN, Vector2.DOWN, 250.0)
	var shot: Bullet = BulletPool._active.back()
	_check(shot.velocity.normalized().dot(shot.global_position.direction_to(locked)) > 0.999, "bullet follows the shown aim")
	BulletPool.release_all()
	enemy._enter(Enemy.Act.THROW, Enemy.THROW_WINDUP)
	enemy._act_time = 0.3
	player.velocity = Vector2(200, 0)
	enemy._run_act(player, Vector2.RIGHT, Vector2.RIGHT, 250.0)
	locked = enemy._aim_target
	player.position += Vector2(0, 200)
	enemy._act_time = 0.1
	enemy._run_act(player, Vector2.DOWN, Vector2.DOWN, 250.0)
	_check(enemy._aim_target == locked, "throw landing stops following the player")
	enemy.free()
	player.free()


func _test_support() -> void:
	var player := Player.new()
	add_child(player)
	var manager := EnemyManager.new()
	add_child(manager)
	manager.setup(player, self, 3)
	var guard := manager.spawn(ContentDB.get_enemy(&"rat_punk"), Vector2(220, 0))
	var healer := manager.spawn(ContentDB.get_enemy(&"pig_mechanic"), Vector2(180, 80))
	manager._update_support_positions()
	_check(healer.support_anchor.x > guard.position.x, "repairer stays behind the front line")
	_check(healer.support_anchor.distance_to(guard.position) < healer.data.heal_radius, "front line remains in repair range")
	guard.hp = 0.0
	manager._update_support_positions()
	_check(not healer.support_anchor.is_finite(), "repairer resumes its own role without allies")
	for e in manager._active + manager._free:
		e.free()
	manager.free()
	player.free()


func _test_boss() -> void:
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.activate(ContentDB.get_enemy(&"junk_overlord"), Vector2.ZERO)
	# Берём мозг из активации; сериализация данных босса проверяется остальными тестами.
	if enemy._brain == null:
		_check(false, "boss brain exists")
	else:
		var brain := enemy._brain
		brain.phase = 2
		brain.enraged = true
		brain.desperate = true
		for i in 20:
			brain._combo_attacks = 2
			brain._rest()
			_check(brain.opening >= BossBrain.OPENING_TIME and brain._cooldown >= brain.opening, "third attack guarantees a complete response window")
	enemy.free()


func _test_tasks() -> void:
	var task := WaveTask.new()
	for kind in [&"collect", &"break", &"tower"]:
		task.start({"kind": kind, "title": "Цель", "count": 2, "reward": 25})
		_check(not task.kill(&"rat_punk", false), "kills cannot complete an interaction goal")
		_check(not task.event(&"wrong", 100) and not task.event(kind, -1), "wrong events and negative amounts ignored")
		_check(not task.event(kind) and task.event(kind, 100), "interaction reaches goal")
		_check(task.progress == 2 and not task.event(kind), "interaction reward issued once")
	var game := Game.new()
	var hud := Hud.new()
	add_child(hud)
	hud.build(load("res://assets/ui/hub/coin.png"), SaveService.get_loadout())
	game.hud = hud
	game._wave_task.start({"kind": "collect", "title": "Собери монеты", "count": 20, "reward": 25})
	game._advance_wave_task(&"collect", 19)
	_check(game.nuts == 0, "incomplete task pays nothing")
	game._advance_wave_task(&"collect", 1)
	game._advance_wave_task(&"collect", 50)
	_check(game.nuts == 25 and game._wave_task.progress == 20, "game pays task once without counting its own reward")
	game.finished = true
	game._wave_task.start({"kind": "break", "count": 1, "reward": 25})
	game._advance_wave_task(&"break")
	_check(game.nuts == 25 and game._wave_task.progress == 0, "finished run cannot gain task progress")
	await get_tree().process_frame
	hud.queue_free()
	game.free()


func _test_motion() -> void:
	var smg := WeaponDB.get_weapon(&"smg_v1")
	var shotgun := WeaponDB.get_weapon(&"double_v1")
	var amounts := []
	for weapon in [smg, shotgun]:
		for fps in [30, 60]:
			var actor := RaccoonVisual.new()
			add_child(actor)
			actor.recoil_recovery = WeaponFeel.recovery(weapon)
			actor.kick(Vector2.RIGHT, 1.0)
			for i in fps / 5:
				actor.update_motion(Vector2.ZERO, Vector2.RIGHT, 1.0 / fps)
			amounts.append(actor._kick)
			actor.dashing = true
			actor.update_motion(Vector2(900, 0), Vector2.RIGHT, 1.0 / fps)
			var steps := actor.footsteps
			actor.update_motion(Vector2(900, 0), Vector2.RIGHT, 1.0 / fps)
			_check(actor.footsteps == steps, "dash does not produce walking steps")
			actor.dashing = false
			actor.update_motion(Vector2.ZERO, Vector2.RIGHT, 1.0 / fps)
			_check(actor._landing > 0.0, "dash settles without blocking input")
			for i in fps:
				actor.update_motion(Vector2.ZERO, Vector2.RIGHT, 1.0 / fps)
			_check(actor._landing == 0.0 and actor._brake_shift.length() < 0.01, "stop motion settles")
			actor.free()
	_check(absf(amounts[0] - amounts[1]) < 0.001 and absf(amounts[2] - amounts[3]) < 0.001, "recoil recovery equal at 30 and 60 FPS")
	_check(amounts[0] < amounts[2], "automatic returns faster than shotgun")
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	player._dash_left = Player.DASH_DURATION
	player._physics_process(1.0 / 60.0)
	_check(player.visual.dashing and player.visual._clip_cur == "dash", "real player drives dash animation")
	player.visual.aiming = true
	player.visual.kick(Vector2.RIGHT, 1.0)
	player.visual.update_motion(Vector2(900, 0), Vector2.RIGHT, 1.0 / 60.0)
	_check(player.visual._clip_has_arm_rig(), "firing during dash retains both hands and visible weapon")
	player.free()


func _test_effects() -> void:
	var fx := FxManager.new()
	add_child(fx)
	SaveService.data["reduced_flashes"] = true
	var before := fx._light_next
	fx.light_flash(Vector2.ZERO, Color.WHITE, 3.0, 200.0, 0.4)
	_check(fx._light_next == before, "reduced flashes avoid both light systems")
	fx.sprite_flash(load("res://assets/ui/hub/coin.png"), Vector2.ZERO, 60, 0.15)
	_check(fx._sf_nodes[0].modulate.a < 0.5, "impact brightness reduced from its first frame")
	SaveService.data["reduced_flashes"] = false
	fx.light_flash(Vector2.ZERO, Color.WHITE, 3.0, 200.0, 0.4)
	_check(fx._light_next != before, "normal light feedback remains available")
	fx.free()


func _test_audio() -> void:
	SoundManager.unlocked = true
	SoundManager._budget = 0.0
	SoundManager._budget_ms = Time.get_ticks_msec()
	SoundManager._last_warning_ms = -100000
	SoundManager.play_warning(&"beam_charge")
	var warning: AudioStreamPlayer = SoundManager._players.back()
	_check(warning.stream == SoundManager._streams[&"beam_charge"], "danger cue bypasses exhausted gunfire budget")
	for p in SoundManager._players:
		p.stream = SoundManager._streams[&"beam_charge"]
		p.play()
	_check(SoundManager._pick_player() < SoundManager.SFX_POOL_SIZE - 1, "gunfire cannot evict warning")
	for i in 12:
		SoundManager._budget = 5.0
		var before := int(SoundManager._step_variants.get(&"stone", -1))
		SoundManager.play_step(&"stone")
		_check(int(SoundManager._step_variants[&"stone"]) != before, "consecutive surface footsteps differ")
	for p in SoundManager._players:
		p.stop()


func _test_closed_menu() -> void:
	# Меню может исчезнуть раньше отложенного предложения войти в аккаунт.
	var controller := Node.new()
	add_child(controller)
	controller.set_script(load("res://scripts/main.gd"))
	controller.set_process(false)
	var waiting := Cloud.waiting_choice
	Cloud.waiting_choice = true
	var menu := MainMenuUI.new()
	controller._maybe_ask_returning(menu)
	menu.free()
	await get_tree().create_timer(1.2).timeout
	_check(controller._screen == null, "closed menu cannot open a delayed account screen")
	Cloud.waiting_choice = waiting
	controller.free()
