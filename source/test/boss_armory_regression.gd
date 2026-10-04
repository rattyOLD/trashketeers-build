extends Node
## Regression coverage: owned weapon actions and lives spent behind a closed boss gate.
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("REGRESSION FAIL: " + label)

func _button(root: Node, prefix: String) -> Button:
	for child in root.get_children():
		if child is Button and child.text.begins_with(prefix):
			return child
		var found := _button(child, prefix)
		if found != null:
			return found
	return null

func _run() -> void:
	var original_save := SaveService.data.duplicate(true)
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.add_coins_silent(10000000)
	SaveService.add_gems(100000, false)
	var armory := MenuPopups.Armory.new()
	add_child(armory)
	var tested := 0
	for weapon in WeaponDB.get_player_weapons():
		if not Economy.is_buyable(weapon):
			continue
		armory._buy(weapon, Economy.shop_price(weapon) <= 0)
		_check(SaveService.owns_weapon(weapon.id), "purchase " + String(weapon.id))
		SaveService.set_selected_weapon(StringName(SaveService.START_WEAPON))
		var card := armory._make_card(weapon)
		var prefix := "T1 ×" if weapon.has_tiers() else "ВЗЯТЬ В РУКИ"
		var equip := _button(card, prefix)
		_check(equip != null, "card equip " + String(weapon.id))
		if equip != null:
			equip.pressed.emit()
			_check(SaveService.get_loadout().id == weapon.id, "loadout " + String(weapon.id))
		card.free()
		if weapon.has_tiers():
			SaveService.add_weapon(weapon.id, 1)
			armory._open_detail(weapon.id, 1)
			var merge := _button(armory._list, "MERGE » T2")
			_check(merge != null, "detail merge " + String(weapon.id))
			if merge != null:
				merge.pressed.emit()
			var tier2 := _button(armory._list, "T2 ×")
			_check(tier2 != null, "detail tier2 " + String(weapon.id))
			if tier2 != null:
				tier2.pressed.emit()
				_check(SaveService.get_selected_tier() == 2, "selected tier2 " + String(weapon.id))
		else:
			SaveService.set_selected_weapon(StringName(SaveService.START_WEAPON))
			armory._open_detail(weapon.id, 1)
			var legendary := _button(armory._list, prefix)
			_check(legendary != null, "legendary detail equip " + String(weapon.id))
			if legendary != null:
				legendary.pressed.emit()
				_check(SaveService.get_selected_weapon() == weapon.id, "legendary selected")
		tested += 1
		await get_tree().process_frame
	print("ARMORY_REGRESSION weapons=", tested, " failures=", failures)
	armory.queue_free()
	await get_tree().process_frame
	for mission_id in ["m1", "m2"]:
		await _test_boss(mission_id)
	print("BOSS_ARMORY_REGRESSION failures=", failures)
	SaveService.data = original_save
	SaveService.save_data()
	get_tree().quit(0 if failures == 0 else 1)

func _test_boss(mission_id: String) -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	var game := Game.new()
	game.story_mission = mission_id
	add_child(game)
	game.start()
	var story := game.story
	story.set_physics_process(false)
	var enc: Dictionary = {}
	for entry in story._encounters:
		if entry.has("boss") and not bool(entry.get("mini", false)):
			enc = entry
	_check(not enc.is_empty(), "final boss exists " + mission_id)
	if enc.is_empty():
		game.queue_free()
		return
	var old_checkpoint := story.checkpoint
	game.player.global_position = Vector2(game.map.boss_point.x, story._y_of(story._trigger_at(enc)))
	var entry_position := game.player.global_position
	_check(game.map.boss_rect.has_point(entry_position), "entry inside arena")
	story._begin(enc)
	var boss := game.director.boss
	_check(boss != null, "boss spawned")
	_check(story.checkpoint == entry_position and story.checkpoint != old_checkpoint, "checkpoint moved inside")
	_check(not game.map.story_gates["boss"].is_open, "gate closed")
	game.enemies.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_physics_process(false)
	for remaining in [2, 1]:
		game.player.shield = 0
		game.player.vest = 0
		game.player._invuln = 0.0
		game.player.take_damage(1000000.0)
		_check(game.player.is_dead, "death before respawn")
		await get_tree().create_timer(1.5).timeout
		_check(not game.player.is_dead, "revived")
		_check(story.lives == remaining, "one life consumed")
		_check(game.player.global_position.is_equal_approx(entry_position), "revived inside arena")
		_check(game.map.boss_rect.has_point(game.player.global_position), "arena reachable")
		_check(game.director.boss == boss and boss.is_alive(), "same boss continues")
		_check(not game.map.story_gates["boss"].is_open, "gate remains closed")
	print("BOSS_RESPAWN_REGRESSION ", mission_id, " failures=", failures)
	# Allow the existing delayed death banners to finish before freeing the game.
	await get_tree().create_timer(5.0).timeout
	game.queue_free()
	await get_tree().process_frame
