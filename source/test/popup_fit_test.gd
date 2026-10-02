extends Node
## Ни одно окно не шире и не выше экрана (портрет 720×1280, как на телефоне): рамки не должны «слезать».

func _ready() -> void:
	Orient.portrait = true
	var makers: Dictionary = {
		"Settings": func() -> Control: return MenuPopups.Settings.new(),
		"Shop": func() -> Control: return MenuPopups.Shop.new(false),
		"Skins": func() -> Control: return MenuPopups.Shop.new(true),
		"Armory": func() -> Control: return MenuPopups.Armory.new(),
		"Upgrades": func() -> Control: return MenuPopups.Upgrades.new(),
		"Achievements": func() -> Control: return MenuPopups.Achievements.new(),
		"Profile": func() -> Control: return MenuPopups.Profile.new(),
		"KeyBinds": func() -> Control: return MenuPopups.KeyBinds.new(),
		"Account": func() -> Control: return AccountPopup.new(),
		"Avatar": func() -> Control: return AvatarPicker.new(),
		"BattlePass": func() -> Control: return BattlePassPopup.new(),
		"Camp": func() -> Control: return CampPopup.new(),
		"Changelog": func() -> Control: return ChangelogPopup.new(),
		"Chests": func() -> Control: return ChestsPopup.new(),
		"Chronicle": func() -> Control: return ChroniclePopup.new(),
		"Credits": func() -> Control: return CreditsPopup.new(),
		"Currency": func() -> Control: return CurrencyPopup.new(),
		"Daily": func() -> Control: return DailyPopup.new(),
		"Friends": func() -> Control: return FriendsPopup.new(),
		"Hero": func() -> Control: return HeroPopup.new(),
		"ModeIntro": func() -> Control: return ModeIntroPopup.new(),
		"Odds": func() -> Control: return OddsPopup.new(),
		"Tester": func() -> Control: return TesterPopup.new(),
		"Vip": func() -> Control: return VipPopup.new(),
		"Chat": func() -> Control: return ChatPopup.new("ABC123", "НочнойМститель59 с очень длинным ником для проверки"),
		"SocialProfile": func() -> Control: return SocialProfilePopup.new("ABC123"),
		"BadgeWelcome": func() -> Control: return BadgeWelcomePopup.new(1),
	}
	var bad := 0
	for key: String in makers:
		var sub := SubViewport.new()
		sub.size = Vector2i(720, 1280)
		add_child(sub)
		var maker := makers[key] as Callable
		var popup := maker.call() as Control
		sub.add_child(popup)
		if popup is GlassPopup:
			(popup as GlassPopup).open()
		elif popup.has_method("open"):
			popup.call("open")
		await get_tree().create_timer(0.9).timeout
		var panel: Control = popup.get("_panel") if popup.get("_panel") != null else null
		if panel == null:
			print("SKIP ", key, " (нет _panel)")
		else:
			var r := panel.get_global_rect()
			var ok := r.position.x >= -0.5 and r.end.x <= 720.5 and r.size.y <= 1280.5
			if not ok:
				bad += 1
				print("FAIL %s rect=%s" % [key, str(r)])
		sub.queue_free()
		await get_tree().process_frame
	print("POPUP_FIT_TEST ", "PASS" if bad == 0 else "FAIL %d" % bad)
	get_tree().quit(0 if bad == 0 else 1)
