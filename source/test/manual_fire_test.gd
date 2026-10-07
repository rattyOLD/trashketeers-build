extends Node
## Ручная стрельба: без пальца/мыши герой не стреляет; палец справа с протяжкой — стреляет туда; мышь — на курсор.
var main: Node
var failures := 0
var shots := 0
var last_dir := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	get_tree().root.add_child.call_deferred(main)
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("MANUAL_FIRE FAIL: " + label)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	await _wait(0.6)
	main._start_game(SaveService.get_selected_weapon())
	await _wait(2.5)
	var game := main._screen as Game
	game.director.set_physics_process(false)
	var wc := game.player.weapon_controller
	_check(not wc.auto_mode, "player has no auto-fire")
	wc.fired.connect(func(_w: WeaponData, _o: Vector2, d: Vector2) -> void:
		shots += 1
		last_dir = d)
	await _wait(1.2)
	_check(shots == 0, "no shots without a finger (got %d)" % shots)
	AimStick.force_touch = true
	var view := get_viewport().get_visible_rect().size
	var start := Vector2(view.x * 0.8, view.y * 0.6)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = start
	press.pressed = true
	Input.parse_input_event(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = start + Vector2(0, -80)
	drag.relative = Vector2(0, -80)
	Input.parse_input_event(drag)
	await _wait(1.0)
	_check(game.hud.aim_stick.is_active(), "aim stick catches the right side")
	_check(shots > 0, "finger held fires (got %d)" % shots)
	_check(last_dir.y < -0.8, "fires where the finger pulls (dir %s)" % str(last_dir))
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	release.pressed = false
	Input.parse_input_event(release)
	await _wait(0.3)
	var after := shots
	await _wait(1.0)
	_check(shots == after, "release stops firing")
	AimStick.force_touch = false
	print("MANUAL_FIRE failures=%d" % failures)
	get_tree().quit()
