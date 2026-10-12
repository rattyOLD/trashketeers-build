extends Node
var failures := 0
var callbacks := 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("POLISH_STABILITY: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.apply_keys()
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tester"]["god"] = true
	SaveService.data["tips_off"] = true
	WeaponController.force_auto = false
	var owner_node := Node.new()
	add_child(owner_node)
	SceneDelay.after(owner_node, 0.05, func() -> void: callbacks += 1)
	owner_node.queue_free()
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(callbacks == 0, "closed screen cancels delayed callback")
	owner_node = Node.new()
	add_child(owner_node)
	SceneDelay.after(owner_node, 0.05, func() -> void: callbacks += 1)
	get_tree().paused = true
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(callbacks == 0, "gameplay timer respects upgrade pause")
	get_tree().paused = false
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(callbacks == 1 and owner_node.get_child_count() == 0, "callback fires once and timer releases itself")
	owner_node.free()
	var game := Game.new()
	add_child(game)
	game.start()
	game.director.set_physics_process(false)
	game.enemies.release_all()
	var boss := game.enemies.spawn(ContentDB.get_enemy(&"sea_pirate"), game.player.global_position + Vector2(300, 0))
	var title := boss.data.display_name
	game._offer_mini_choice(boss, boss.global_position, 0)
	game.enemies.release(boss)
	var reused := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(300, 0))
	_check(reused == boss, "fixture reuses the defeated boss node")
	game._level_up_open = true
	get_tree().paused = true
	await get_tree().create_timer(10.0, true, false, true).timeout
	var card: ChoiceCard
	for child in game.get_children():
		if child is ChoiceCard:
			card = child
	_check(card == null, "long upgrade choice cannot open a competing boss reward")
	game._level_up_open = false
	get_tree().paused = false
	await get_tree().create_timer(1.0, true, false, true).timeout
	for child in game.get_children():
		if child is ChoiceCard:
			card = child
	_check(card != null, "boss reward survives a long upgrade pause")
	if card != null:
		var correct := false
		for label: Label in card.find_children("*", "Label", true, false):
			correct = correct or label.text.contains(title.to_upper())
		_check(correct, "reward keeps defeated boss identity after pool reuse")
		card._opened_ms = 0
		card._pick(0)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(5.5, true, false, true).timeout
	print("POLISH_STABILITY failures=", failures)
	get_tree().quit(1 if failures else 0)
