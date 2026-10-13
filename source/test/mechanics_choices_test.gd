extends Node
var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("MECHANICS_CHOICES: " + label)

func _pick(id: String) -> UpgradeData:
	for upgrade in ContentDB.get_upgrades():
		if String(upgrade.id) == "tactic_" + id:
			return upgrade
	return null

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	Orient.portrait = false
	var panel := LevelUpPanel.new()
	add_child(panel)
	var output := OS.get_environment("MECHANICS_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	for dimensions in [Vector2i(960,540), Vector2i(1280,720)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		panel.set_deferred("size", Vector2(dimensions))
		for group in [["frost","arson","bankshot"],["sentry","switcher","vanguard"]]:
			var run := RunStats.new()
			run.multi_weapon_context = true
			run.apply(_pick(group[0]))
			run.apply(_pick(group[0]))
			var choices: Array[UpgradeData] = []
			for id: String in group:
				choices.append(_pick(id))
			panel.open(choices, 10, run, false, "ПЕРЕБРОСИТЬ", true)
			await get_tree().create_timer(0.7, true, false, true).timeout
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			for card: Button in panel._cards.get_children():
				_check(bounds.grow(1).encloses(card.get_global_rect()), "rank card fits " + str(dimensions))
			_check(bounds.grow(1).encloses(panel._reroll.get_global_rect()), "reroll remains visible")
			_check(panel._holder.scale.x >= 0.75, "rank descriptions remain readable")
			for index in choices.size():
				var description := CombatTactics.run_description(group[index], run)
				var labels := panel._cards.get_child(index).find_children("*", "Label", true, false)
				_check(labels.any(func(label: Label) -> bool: return label.text == description), "card shows runtime rank description")
			if not output.is_empty():
				get_viewport().get_texture().get_image().save_png(output.path_join("choices-%d-%s.png" % [dimensions.x,group[0]]))
	panel.queue_free()
	for frame in 4:
		await get_tree().process_frame
	print("MECHANICS_CHOICES failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)
