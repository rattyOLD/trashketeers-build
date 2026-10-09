extends Node
## Plate containment, both layouts, HUD readability and non-destructive skin previews.
var failures := 0
var output := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("UI_V32 FAIL: " + message)


func _settle() -> void:
	await get_tree().create_timer(0.6, true).timeout
	for i in 4:
		await get_tree().process_frame


func _label_fits(label_node: Label, message: String) -> void:
	var style := label_node.get_theme_stylebox("normal")
	var available := label_node.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT)
	var width := label_node.get_theme_font("font").get_string_size(label_node.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_node.get_theme_font_size("font_size")).x
	_check(width + label_node.get_theme_constant("outline_size") * 2.0 <= available + 1.0, message)


func _shot(name: String) -> void:
	if output.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))


func _run() -> void:
	output = OS.get_environment("UI_V32_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	for portrait in [false, true]:
		Orient.portrait = portrait
		get_window().content_scale_size = Orient.PORTRAIT_SIZE if portrait else Orient.LANDSCAPE_SIZE
		get_window().size = get_window().content_scale_size
		var suffix := "portrait" if portrait else "landscape"
		await _settle()
		var windows: Array[GlassPopup] = [MenuPopups.Settings.new(), MenuPopups.Shop.new(), MenuPopups.Shop.new(true), DailyPopup.new(), BattlePassPopup.new(), MenuPopups.Achievements.new(), FriendsPopup.new()]
		for index in windows.size():
			var popup := windows[index]
			add_child(popup)
			popup.open()
			await _settle()
			_label_fits(popup._title, suffix + " title " + popup._title.text)
			_check(popup._title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "title centered")
			var style := popup._title.get_theme_stylebox("normal")
			_check(is_equal_approx(style.get_content_margin(SIDE_LEFT), style.get_content_margin(SIDE_RIGHT)), "symmetric title margins")
			await _shot(suffix + "_window_" + str(index))
			GlassPopup._open_stack.erase(popup)
			popup.free()
		var hud := Hud.new()
		add_child(hud)
		hud.build(load("res://assets/ui/hub/coin.png"), SaveService.get_loadout())
		hud.set_xp(17, 40, 12)
		hud.show_boss("КАЗНАЧЕЙ ЗОЛОТОГО БАНКА", 500, 1000)
		await _settle()
		_check(hud._xp_title.text == "УР 12" and hud._xp_title.is_visible_in_tree(), suffix + " visible level")
		_check(not hud._level_badge.visible, "portrait medal hidden")
		_check(hud._xp_title.get_global_rect().end.x <= hud._xp_bar.get_global_rect().position.x, "level before XP bar")
		var portrait_right := (hud._portrait.get_global_transform() * Vector2(HudWidgets.DamagePortrait.SIDE, 0)).x
		_check(hud._xp_title.get_global_rect().position.x - 6.0 > portrait_right, suffix + " level clear of portrait")
		_check(hud._xp_row.get_global_rect().grow(1.0).encloses(hud._xp_bar.get_global_rect()), "XP inside row")
		await _shot(suffix + "_hud")
		hud.free()
		var panel := LevelUpPanel.new()
		add_child(panel)
		var offers: Array[UpgradeData] = []
		for upgrade in ContentDB.get_upgrades():
			if upgrade.icon != null and offers.size() < 3:
				offers.append(upgrade)
		panel.open(offers, 12, RunStats.new())
		await _settle()
		for card: Button in panel._cards.get_children():
			var column := card.get_child(0) as VBoxContainer
			var icon := card.get_child(1) as TextureRect
			_check(card.get_global_rect().grow(-18.0).encloses(column.get_global_rect()), "card text inside frame")
			_check(card.get_global_rect().grow(-18.0).encloses(icon.get_global_rect()), "card icon inside frame")
			_check(not column.get_global_rect().intersects(icon.get_global_rect()), "card text clear of icon")
			var frame := card.get_theme_stylebox("normal") as StyleBoxTexture
			_check(frame != null and is_equal_approx(frame.get_texture_margin(SIDE_LEFT), 17.0), "uniform card border")
		await _shot(suffix + "_cards")
		panel.free()
		var shop := MenuPopups.Shop.new(true)
		add_child(shop)
		var previous := SaveService.data.duplicate(true)
		for key in ["dash:ember", "shot:plasma"]:
			shop._show_cosmetic_preview(key, Cosmetics.kind_of(key))
			await _settle()
			var popup := get_children().back() as GlassPopup
			_check(popup != null, "tap opens preview")
			var preview := popup.content.get_child(1) as CosmeticPreview
			_check(preview != null and preview.key == key, "selected skin is previewed")
			_check(SaveService.data == previous, "preview does not change equipment or ownership")
			var locked_button := popup.content.get_child(2) as Button
			_check(locked_button.disabled, "locked skin cannot be equipped")
			await _shot(suffix + "_" + key.replace(":", "_"))
			GlassPopup._open_stack.erase(popup)
			popup.free()
		SaveService.data["cosmetics"].append("dash:ember")
		shop._show_cosmetic_preview("dash:ember", "dash")
		await _settle()
		var owned_popup := get_children().back() as GlassPopup
		var equip_button := owned_popup.content.get_child(2) as Button
		_check(not equip_button.disabled, "owned skin can be equipped")
		equip_button.pressed.emit()
		_check(Cosmetics.worn("dash") == "dash:ember", "equip applies chosen skin")
		await _settle()
		SaveService.data = previous
		shop.free()
	Orient.portrait = false
	print("UI_V32 failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
