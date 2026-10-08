extends Node
## Окно выбора улучшения: по центру и правильной ширины после каждого открытия и реролла.
var main: Node
var failures := 0


func _ready() -> void:
	WeaponController.force_auto = true
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
	for i in 40:
		await _wait(0.25)
		if main._screen is Game and (main._screen as Game).player != null:
			break
	await _wait(1.0)
	var game := main._screen as Game
	var view := get_viewport().get_visible_rect().size
	for round in 4:
		game._pending_levelups = 1
		game._level_up_open = true
		game._open_level_up()
		await _wait(1.0)
		var box: Control = game.hud._level_up._box
		var r := box.get_global_rect()
		_check(r, view)
		game.hud._level_up._armed_at = 0
		if round < 3:
			game.hud._level_up.reroll_requested.emit()
			await _wait(0.6)
			r = box.get_global_rect()
			_check(r, view)
		game.hud._level_up._pick(0)
		await _wait(0.5)
	print("LEVELUP_LAYOUT failures=%d" % failures)
	get_tree().quit()


func _check(r: Rect2, view: Vector2) -> void:
	if absf(r.get_center().x - view.x * 0.5) > 2.0 or r.size.x > view.x or r.position.x < 0.0:
		failures += 1
		push_error("LEVELUP_LAYOUT FAIL: box %s in view %s" % [str(r), str(view)])
