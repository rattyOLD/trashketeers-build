class_name LoadoutPopup
extends GlassPopup
signal applied
var _list: VBoxContainer
var _notice := ""

func _init() -> void:
	super("БОЕВЫЕ КОМПЛЕКТЫ")
	var hint := UiStyle.label("Герой, два оружия и нашивки. Комплекты работают в выживании и рейде; в сюжете оружие выдаёт лагерь.", 18, UiStyle.TEXT_DIM, 6)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	_list = MenuPopups.scroll_list(content)

func _refresh() -> void:
	MenuPopups.clear(_list)
	var secondary := SaveService.get_secondary_loadout()
	var current := UiStyle.label("Сейчас: %s\n%s · второй: %s" % [SaveService.get_character().get("title", ""), SaveService.get_loadout().display_name, secondary.display_name if secondary != null else "не выбран"], 20, UiStyle.GOLD, 8)
	current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(current)
	if not _notice.is_empty():
		var notice := UiStyle.label(_notice, 18, UiStyle.TEXT, 4)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(notice)
	for slot in LoadoutPresets.COUNT:
		var kit := LoadoutPresets.get_preset(slot)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 8)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CARD_BG, UiStyle.GOLD.darkened(0.4), 2, 16))
		panel.add_child(card)
		_list.add_child(panel)
		var title := "КОМПЛЕКТ %d · пусто" % (slot + 1)
		if not kit.is_empty():
			var hero := CharacterDB.get_character(str(kit.get("hero", "")))
			var weapon := WeaponDB.get_weapon(StringName(str(kit.get("primary", ""))))
			title = "КОМПЛЕКТ %d · %s\n%s T%d" % [slot + 1, hero.get("title", ""), weapon.display_name if weapon != null else "Оружие недоступно", int(kit.get("primary_tier", 1))]
		var label := UiStyle.label(title, 20, UiStyle.TEXT, 4)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var save := UiStyle.button("СОХРАНИТЬ ТЕКУЩИЙ", UiStyle.PANEL, 17, Vector2(0, 48))
		save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		save.pressed.connect(func() -> void:
			LoadoutPresets.capture(slot)
			_notice = "Комплект %d сохранён" % (slot + 1)
			_refresh())
		row.add_child(save)
		var use := UiStyle.button("ПРИМЕНИТЬ", UiStyle.GOLD.darkened(0.35), 17, Vector2(0, 48))
		use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		use.disabled = kit.is_empty()
		use.pressed.connect(func() -> void:
			if LoadoutPresets.apply(slot):
				_notice = "Комплект %d выбран" % (slot + 1)
				applied.emit()
			else:
				_notice = LoadoutPresets.error_for(LoadoutPresets.get_preset(slot))
			_refresh())
		row.add_child(use)
