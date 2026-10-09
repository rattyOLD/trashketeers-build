extends Node
## Холодное оружие не должно выпускать пули: зажимаем «курок» с каждым мечом и считаем пули игрока.
var main: Node
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	get_tree().root.add_child.call_deferred(main)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	await _wait(0.6)
	main._start_game(SaveService.get_selected_weapon())
	await _wait(2.5)
	var game := main._screen as Game
	game.director.set_physics_process(false)
	var wc := game.player.weapon_controller
	var shots := [0]
	wc.fired.connect(func(_w: WeaponData, _o: Vector2, _d: Vector2) -> void: shots[0] += 1)
	var swings := [0]
	wc.melee.swing_started.connect(func(_a: WeaponData, _b: Vector2, _c: Vector2, _d: int, _e: bool, _f: float) -> void: swings[0] += 1)
	for weapon in WeaponDB.get_player_weapons():
		if not weapon.is_melee():
			continue
		wc.set_slot(0, weapon)
		shots[0] = 0
		swings[0] = 0
		var before := _player_bullets()
		game.hud.aim_stick._touch_index = 0
		game.hud.aim_stick.direction = Vector2.RIGHT
		var peak := 0
		for i in 60:
			await get_tree().physics_frame
			peak = maxi(peak, _player_bullets() - before)
		game.hud.aim_stick._reset()
		print("MELEE ", weapon.id, " swings=", swings[0], " fired=", shots[0], " bullets=", peak)
		# Моргенштерн не машет, а держит шар на цепи: стик вправо — шар вынесен вправо на длину цепи.
		var acting: bool = swings[0] > 0
		if weapon.melee_class == "flail":
			var reach := (wc.flail.ball - game.player.global_position).dot(Vector2.RIGHT) if wc.flail != null else 0.0
			acting = wc.flail != null and wc.flail.visible and reach > 60.0
			print("MELEE ", weapon.id, " flail_reach=", reach)
		if shots[0] > 0 or peak > 0 or not acting:
			failures += 1
	print("MELEE_PROBE failures=%d" % failures)
	get_tree().quit()


func _player_bullets() -> int:
	var n := 0
	for b in BulletPool._active:
		if (b as Bullet).team == Bullet.Team.PLAYER:
			n += 1
	return n
