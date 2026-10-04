extends Node
## Шапка телефона: состояния HUD и ленты событий, снимки с линией BAND_SHARE.
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	SaveService.data["show_fps"] = true
	var game := Game.new()
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(1.0).timeout
	var hud: Hud = game.hud
	hud.set_wave(3, 16, 0, 25)
	hud.set_kills(36)
	hud.set_loot_left(101)
	hud.set_survival_order({"title": "Сделай 60 рывков", "progress": 0, "goal": 60})
	hud.radio().push_line("rico", "Чувствую, умнею.")
	hud.radio().push_line("nell", "Хватит собирать царапины.")
	await _shot(game, "a_normal", 0.6)
	for c in hud._left_column.get_children():
		print("COL ", c.get_class(), " ", (c as Control).get_combined_minimum_size(), " vis=", (c as Control).visible)
	print("DBG event_top=", hud._event_top, " topbar_min=", hud._top_bar.get_combined_minimum_size(), " topbar_size=", hud._top_bar.size, " band=", hud._band.size, " scale=", hud._band.scale, " barks_rect=", hud._barks.get_global_rect(), " barks_size=", hud._barks.size, " title_rect=", hud._wave_title.get_global_rect(), " root=", hud._root.size)
	hud.show_wave_intro(4, "Главная улица", false, 1)
	await _shot(game, "b_wave", 0.5)
	await get_tree().create_timer(2.5).timeout
	hud.show_countdown(3)
	hud.set_rail_combo(8)
	await _shot(game, "c_countdown", 0.3)
	await get_tree().create_timer(1.5).timeout
	hud.toast("ПОЛУЧЕНО: ПИВНАЯ ПРОБКА-КЛЮЧ", "Она откроет Ящик с оружием в Зоне 3")
	await _shot(game, "d_toast", 0.6)
	await get_tree().create_timer(3.0).timeout
	hud.show_boss("Барон", 800.0, 1000.0, false)
	hud.show_chapter("Глава 1", "Неоновая свалка")
	await _shot(game, "e_boss_chapter", 0.8)
	await get_tree().create_timer(4.0).timeout
	hud.set_boss_posture(1.0, true)
	hud.toast("ЯЩИК СБРОШЕН", "Открой его пробкой-ключом: стреляй по ящику")
	await get_tree().create_timer(0.5).timeout
	hud.show_banner("МАГНИТ! УБЕГАЙ ИЛИ РЫВОК", Color("#b46bff"), 1.4)
	await _shot(game, "f_banner", 0.3)
	await _shot(game, "g_toast_back", 2.6)
	get_tree().quit()


func _shot(game: Game, name: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var y := int(img.get_height() * Hud.BAND_SHARE)
	for x in img.get_width():
		img.set_pixel(x, y, Color.WHITE)
	img.save_png(OS.get_environment("OUT") + "_" + name + ".png")
