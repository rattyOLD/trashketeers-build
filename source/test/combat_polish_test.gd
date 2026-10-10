extends Node
## Непрерывная очередь, отдача, плотные критические попадания и реальные HP в отчёте.
var failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("COMBAT_POLISH FAIL: " + message)


func _ready() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._apply_text('{"camera_shake":false}')
	_check(not bool(SaveService.data.get("camera_shake", true)), "camera setting survives save reload")
	SaveService._apply_text('{}')
	_check(bool(SaveService.data.get("camera_shake", false)), "old saves retain default feedback")
	_test_animation()
	_test_feedback()
	_test_report()
	print("COMBAT_POLISH failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_animation() -> void:
	for character: Dictionary in ConfigLoader.load_json("res://data/characters.json").get("characters", []):
		if not character.has("sprite") or str(character["sprite"].get("clips", "")).is_empty():
			continue
		for fps in [30, 60]:
			var actor := RaccoonVisual.new()
			add_child(actor)
			actor.apply_look(character, {})
			var dt: float = 1.0 / fps
			var frames := {}
			for tick in fps * 2:
				# Один выстрел за кадр — стрессовый случай для пулемёта и бонусов темпа.
				actor.kick(Vector2.RIGHT, 2.5)
				_check(actor._body_kick.length() <= 6.001, "body recoil cap")
				actor.update_motion(Vector2.ZERO, Vector2.RIGHT, dt)
				if actor._clip_cur == "shoot":
					frames[actor._clip_idx] = true
			_check(frames.size() == 4, str(character["id"]) + " sustained fire plays all four frames")
			for tick in fps:
				actor.update_motion(Vector2.ZERO, Vector2.RIGHT, dt)
			_check(actor._clip_cur == "idle" and actor._body_kick.length() < 0.01, "settles after firing")
			actor.free()


func _test_feedback() -> void:
	var battle := BattleBase.new()
	var effects := FxManager.new()
	var shot := Bullet.new()
	var target := Node2D.new()
	shot.weapon = WeaponDB.get_weapon(&"pistol_v1")
	_check(shot.weapon != null, "test weapon exists")
	battle.fx = effects
	battle.finished = true
	shot.last_hit_crit = true
	for i in 300:
		battle._on_bullet_hit(shot, target)
	_check(is_equal_approx(battle._hit_fx_budget, 0.0), "critical burst respects impact budget")
	_check(effects._ring_next == int(BattleBase.HIT_FX_BURST), "critical rings share impact budget")
	for i in 300:
		battle._on_player_fired(shot.weapon, Vector2.ZERO, Vector2.RIGHT)
	_check(battle._kick.length() <= 12.001, "camera recoil cap")
	for i in 100:
		battle.add_shake(0.2)
	_check(is_equal_approx(battle._shake, 0.2), "small events do not amplify camera shake")
	SaveService.data["camera_shake"] = false
	battle._kick = Vector2.ZERO
	battle._shake = 0.0
	battle._on_player_fired(shot.weapon, Vector2.ZERO, Vector2.RIGHT)
	battle.add_shake(1.0)
	_check(battle._kick == Vector2.ZERO and battle._shake == 0.0, "camera shake can be disabled")
	SaveService.data["camera_shake"] = true
	shot.free()
	target.free()
	effects.free()
	battle.free()


func _test_report() -> void:
	var report := CombatReport.new()
	report.record_enemy(10.0, 90.0, &"projectile")
	report.record_enemy(250.0, -160.0, &"blast")
	report.record_enemy(20.0, 30.0, &"fire")
	_check(is_equal_approx(report.enemy_damage, 120.0), "overkill is excluded")
	_check(is_equal_approx(float(report.damage_by_kind[&"blast"]), 90.0), "actual blast HP")
	report.record_received(18.0, &"projectile")
	_check(report.lines(true).contains("последний удар: пуля"), "human readable death source")
	_check(not report.lines(false).contains("последний удар"), "living run does not claim death")
	var player := Player.new()
	add_child(player)
	player.visual = RaccoonVisual.new()
	player.add_child(player.visual)
	player.hp = 10.0
	player.max_hp = 100.0
	player.armor = 0.5
	player.take_damage(12.0)
	_check(is_equal_approx(player.last_damage_taken, 6.0), "received HP respects armor")
	player._invuln = 0.0
	player.take_damage(1000.0)
	_check(is_equal_approx(player.last_damage_taken, 4.0), "fatal hit excludes overkill")
	player.free()
