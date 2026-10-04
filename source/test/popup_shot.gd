extends Node
## Снимок одного окна: POPUP=BattlePass → /tmp/anim/popup_<имя>.png (720×1280).
func _ready() -> void:
	Orient.portrait = false
	var key := OS.get_environment("POPUP")
	var maker: Variant = {
		"BattlePass": func() -> Control: return BattlePassPopup.new(),
		"Camp": func() -> Control: return CampPopup.new(),
		"Shop": func() -> Control: return MenuPopups.Shop.new(false),
		"Settings": func() -> Control: return MenuPopups.Settings.new(),
		"Daily": func() -> Control: return DailyPopup.new(),
		"Chests": func() -> Control: return ChestsPopup.new(),
		"Hero": func() -> Control: return HeroPopup.new(),
		"Armory": func() -> Control: return MenuPopups.Armory.new(),
		"Skins": func() -> Control: return MenuPopups.Shop.new(true),
	}.get(key)
	var popup := (maker as Callable).call() as Control
	add_child(popup)
	if popup is GlassPopup:
		(popup as GlassPopup).open()
	if popup is HeroPopup and OS.get_environment("HERO_IDX") != "":
		(popup as HeroPopup)._index = int(OS.get_environment("HERO_IDX"))
		(popup as HeroPopup)._refresh()
	await get_tree().create_timer(1.2).timeout
	for line in TextOverlap.find(popup):
		print("OVERLAP ", line)
	get_viewport().get_texture().get_image().save_png("/tmp/anim/popup_%s.png" % key)
	get_tree().quit()
