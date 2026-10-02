extends Node
## Снимок шапки боя (виртуальный экран): выживание и сюжет.
func _ready() -> void:
	Orient.portrait = true
	var story := OS.get_environment("HUD_STORY") == "1"
	if OS.get_environment("HUD_CHAR") != "":
		SaveService.data["character"] = OS.get_environment("HUD_CHAR")
		var own: Array = SaveService.data.get("characters", [])
		own.append(OS.get_environment("HUD_CHAR"))
	var game := Game.new()
	if story:
		game.story_mission = "m1"
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(3.5).timeout
	if not story:
		game.hud.set_wave(3, 12, 0, 25)
		game.hud.set_kills(50)
		game.hud.set_xp(280, 1000, 12)
		game.hud.set_health(float(OS.get_environment("HUD_HP")) if OS.get_environment("HUD_HP") != "" else 100.0, 100.0)
	if OS.get_environment("HUD_CHAT") == "1":
		var barks: HudBarks = game.hud._barks
		barks.push_line("nell", "Рико, ты там цел?")
		barks.push_line("rico", "Цел. Местами.")
		barks.push_line("nell", "Хватит собирать царапины.")
		await get_tree().process_frame
		print("BARKS ", barks.get_global_rect())
	if OS.get_environment("HUD_MAP") == "1" and game.hud._minimap != null:
		game.hud._minimap.enlarge_toggled.emit(true)
	if OS.get_environment("HUD_BOSS") == "1":
		game.hud.show_boss("Барон", 800.0, 1000.0, false)
	await get_tree().create_timer(0.5).timeout
	var ids: Array = Controls.HUD_ELEMENTS
	var rects: Dictionary = {}
	for id: String in ids:
		var n: Control = game.hud.hud_node(id)
		if n != null and n.is_visible_in_tree() and n.get_global_rect().size.x > 4.0:
			rects[id] = n.get_global_rect()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if rects.has(ids[i]) and rects.has(ids[j]):
				var inter: Rect2 = (rects[ids[i]] as Rect2).intersection(rects[ids[j]])
				if inter.size.x > 2.0 and inter.size.y > 2.0:
					print("OVERLAP ", ids[i], " x ", ids[j], " ", inter)
	for line in TextOverlap.find(game.hud):
		print("OVERLAP text: ", line)
	var panel := OS.get_environment("HUD_PANEL")
	if panel != "":
		var lines := PackedStringArray(["Волна: 12", "Убито: 345", "Время: 12:34", "Оружие: Мусорный Дробовик Т3", "Очень длинная строка для проверки переносов и наложения текста"])
		match panel:
			"pause":
				game.hud.show_pause(lines)
			"result":
				game.hud.show_result(true, lines, "ПОБЕДА", true)
			"lose":
				game.hud.show_result(false, lines, "", true)
			"levelup":
				var choices := game.stats.roll_choices(ContentDB.get_upgrades(), 3, 0.2, 0)
				game.hud.show_level_up(choices, 5, game.stats, false, "РЕРОЛЛ · 20 орехов", true)
			"revive":
				game.hud.show_revive(120, 5, true, {"wave": 12, "kills": 345})
		await get_tree().create_timer(1.0).timeout
		for line in TextOverlap.find(game.hud):
			print("OVERLAP panel ", panel, ": ", line)
		get_viewport().get_texture().get_image().save_png("/tmp/anim/hud_panel_%s.png" % panel)
	print("RECTS ", rects)
	get_viewport().get_texture().get_image().save_png("/tmp/anim/hud_%s.png" % ("story" if story else "surv" + OS.get_environment("HUD_HP") + OS.get_environment("HUD_CHAR")))
	get_tree().quit()
