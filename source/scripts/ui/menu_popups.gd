class_name MenuPopups
extends RefCounted
## Окна хаба на базе GlassPopup: Настройки, Гардероб (герои и наряды), Оружие + Merge, Прокачка, Ачивки.
## Длинные списки — в ScrollContainer (на телефоне листаются пальцем).

static func list_height() -> float:
	return 760.0 if Orient.portrait else 400.0


static func scroll_list(parent: Control) -> VBoxContainer:
	var scroll := DragScroll.new()
	scroll.custom_minimum_size = Vector2(0, list_height())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 16
	scroll.follow_focus = true
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(10, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.06)
	track.set_corner_radius_all(5)
	var grab := StyleBoxFlat.new()
	grab.bg_color = UiStyle.NEON.darkened(0.15)
	grab.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("scroll", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, grab)
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	margin.add_child(list)
	return list


static func small_hint(text: String) -> Label:
	var hint := UiStyle.label(text, 17, UiStyle.TEXT_DIM, 4)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return hint


static func section_card(list: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.OUTLINE, 3, 20))
	list.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var caption := UiStyle.label(title, 26, UiStyle.NEON, 6)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(caption)
	return column


static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Настройки: ползунки музыки и эффектов, качество графики (3 уровня), счётчик FPS.
class Settings:
	extends GlassPopup
	signal editor_requested
	const QUALITY_NAMES := ["ЭКОНОМ", "БАЛАНС", "КРАСИВО"]
	const QUALITY_HINTS := [
		"Для слабых телефонов: без теней и свечения, меньше частиц, разрешение 1×",
		"Тени, цветокоррекция, полные эффекты, 1.5×",
		"Всё включено, свечение, 2×. Для мощных устройств",
	]
	var _quality_buttons: Array[Button] = []
	var _quality_hint: Label
	var _min_hud: MenuWidgets.PawToggle
	var _nearest: MenuWidgets.PawToggle
	var _fps: MenuWidgets.PawToggle
	var _lite: MenuWidgets.PawToggle
	var _mini: MenuWidgets.PawToggle
	var _fullscreen: MenuWidgets.PawToggle
	var _auto_pick: MenuWidgets.PawToggle
	var _tips: MenuWidgets.PawToggle
	var _slot_buttons: Array[Button] = []
	var _slot_hint: Label
	var _slot_confirm := false
	var _keys: KeyBinds
	var _credits: CreditsPopup

	func _init() -> void:
		super("НАСТРОЙКИ")
		var list := MenuPopups.scroll_list(content)
		var credits_button := UiStyle.button("СОЗДАТЕЛИ · BEER PARTY STUDIO", UiStyle.PANEL_LIGHT, 22, Vector2(0, 68))
		credits_button.pressed.connect(func() -> void: _credits.open())
		list.add_child(credits_button)
		var sound := MenuPopups.section_card(list, "ЗВУК")
		sound.add_child(Hud.VolumeSlider.new("Музыка", "music"))
		sound.add_child(Hud.VolumeSlider.new("Эффекты", "sfx"))
		var graphics := MenuPopups.section_card(list, "ГРАФИКА")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		graphics.add_child(row)
		for i in QUALITY_NAMES.size():
			var b := UiStyle.button(QUALITY_NAMES[i], UiStyle.PANEL_LIGHT, 24, Vector2(0, 76))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func() -> void:
				SaveService.set_quality(i)
				_refresh())
			row.add_child(b)
			_quality_buttons.append(b)
		_quality_hint = UiStyle.label("", 19, UiStyle.TEXT_DIM, 4)
		_quality_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		graphics.add_child(_quality_hint)
		_lite = MenuWidgets.PawToggle.new("Упрощённые эффекты", SaveService.is_fx_lite())
		_lite.toggled.connect(func(on: bool) -> void: SaveService.set_flag("fx_lite", on))
		graphics.add_child(_lite)
		graphics.add_child(MenuPopups.small_hint("Меньше частиц и свечения. Помогает слабым телефонам."))
		var eco := MenuWidgets.PawToggle.new("Экономия заряда", bool(SaveService.data.get("eco_fps", false)))
		eco.toggled.connect(func(on: bool) -> void:
			SaveService.set_flag("eco_fps", on)
			SaveService.apply_quality())
		graphics.add_child(eco)
		graphics.add_child(MenuPopups.small_hint("Телефон меньше греется. Включи, если игра лагает."))
		var haptics := MenuWidgets.PawToggle.new("Вибрация", bool(SaveService.data.get("haptics", true)))
		haptics.toggled.connect(func(on: bool) -> void:
			SaveService.set_flag("haptics", on)
			Platform.haptic("medium"))
		graphics.add_child(haptics)
		_fps = MenuWidgets.PawToggle.new("Счётчик FPS", bool(SaveService.data["show_fps"]))
		_fps.toggled.connect(func(on: bool) -> void: SaveService.set_flag("show_fps", on))
		graphics.add_child(_fps)
		_mini = MenuWidgets.PawToggle.new("Мини-карта в бою", SaveService.is_minimap_enabled())
		_mini.toggled.connect(func(on: bool) -> void: SaveService.set_flag("minimap", on))
		graphics.add_child(_mini)
		_min_hud = MenuWidgets.PawToggle.new("Минимальный худ", bool(SaveService.data.get("min_hud", false)))
		_min_hud.toggled.connect(func(on: bool) -> void: SaveService.set_flag("min_hud", on))
		graphics.add_child(_min_hud)
		graphics.add_child(MenuPopups.small_hint("В бою только здоровье, пауза, таймер и монеты."))
		if Platform.fullscreen_supported():
			_fullscreen = MenuWidgets.PawToggle.new("На весь экран", Platform.is_fullscreen())
			_fullscreen.toggled.connect(func(on: bool) -> void: Platform.set_fullscreen(on))
			graphics.add_child(_fullscreen)
		else:
			graphics.add_child(MenuPopups.small_hint("iPhone: «Поделиться» → «На экран Домой», тогда игра пойдёт на весь экран."))
		var backup := MenuPopups.section_card(list, "СОХРАНЕНИЕ")
		var backup_hint := UiStyle.label("Код хранит весь прогресс. Safari и значок на экране Домой хранят его раздельно, код переносит между ними и на другие устройства.", 19, UiStyle.TEXT_DIM, 4)
		backup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		backup.add_child(backup_hint)
		var copy_button := UiStyle.button("СКОПИРОВАТЬ КОД СОХРАНЕНИЯ", UiStyle.PANEL_LIGHT, 22, Vector2(0, 66))
		copy_button.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(SaveService.backup_code())
			copy_button.text = "СКОПИРОВАНО")
		backup.add_child(copy_button)
		var paste := LineEdit.new()
		paste.placeholder_text = "Вставь код TRS1..."
		paste.custom_minimum_size = Vector2(0, 66)
		paste.add_theme_font_size_override("font_size", 22)
		backup.add_child(paste)
		var restore := UiStyle.button("ВОССТАНОВИТЬ ИЗ КОДА", Color("#b03a5a"), 22, Vector2(0, 66))
		var armed := [false]
		restore.pressed.connect(func() -> void:
			if not armed[0]:
				armed[0] = true
				restore.text = "ЗАМЕНИТ ТЕКУЩИЙ ПРОГРЕСС. ТАПНИ ЕЩЁ РАЗ"
				return
			armed[0] = false
			restore.text = "ПРОГРЕСС ВОССТАНОВЛЕН" if SaveService.restore_backup(paste.text) else "КОД НЕ ПОДОШЁЛ")
		backup.add_child(restore)
		if Platform.can_install() and not Platform.is_standalone():
			var install := UiStyle.button("УСТАНОВИТЬ ИГРУ НА ТЕЛЕФОН", UiStyle.PANEL_LIGHT, 22, Vector2(0, 72))
			install.pressed.connect(Platform.install_app)
			graphics.add_child(install)
			var install_hint := UiStyle.label("Иконка на экране, запуск без адресной строки.", 19, UiStyle.TEXT_DIM, 4)
			install_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			graphics.add_child(install_hint)
		var controls := MenuPopups.section_card(list, "УПРАВЛЕНИЕ")
		var controls_row := HBoxContainer.new()
		controls_row.add_theme_constant_override("separation", 10)
		var editor_button := UiStyle.button("РАСКЛАДКА", UiStyle.PANEL_LIGHT, 24, Vector2(0, 76))
		editor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		editor_button.pressed.connect(func() -> void: editor_requested.emit())
		controls_row.add_child(editor_button)
		var keys_button := UiStyle.button("КЛАВИШИ", UiStyle.PANEL_LIGHT, 24, Vector2(0, 76))
		keys_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys_button.pressed.connect(func() -> void: _keys.open())
		controls_row.add_child(keys_button)
		controls.add_child(controls_row)
		controls.add_child(MenuPopups.small_hint("Стрельба автоматическая. Держи палец справа, чтобы целиться самому."))
		_tips = MenuWidgets.PawToggle.new("Подсказки в сюжете", Tips.enabled())
		_tips.toggled.connect(func(on: bool) -> void: Tips.set_enabled(on))
		controls.add_child(_tips)
		_auto_pick = MenuWidgets.PawToggle.new("Автоподбор оружия", bool(Controls.get_value("auto_pick")))
		_auto_pick.toggled.connect(func(on: bool) -> void: Controls.set_value("auto_pick", on))
		controls.add_child(_auto_pick)
		_nearest = MenuWidgets.PawToggle.new("Цель: только ближайшая", bool(SaveService.data.get("target_nearest", false)))
		_nearest.toggled.connect(func(on: bool) -> void: SaveService.set_flag("target_nearest", on))
		controls.add_child(_nearest)
		controls.add_child(MenuPopups.small_hint("Выкл: сначала боссы и стрелки. Вкл: всегда ближайший враг."))
		var slots_row := HBoxContainer.new()
		slots_row.add_theme_constant_override("separation", 10)
		var slots_label := UiStyle.label("Слоты оружия", 26, UiStyle.TEXT, 6)
		slots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		slots_row.add_child(slots_label)
		for n in [2, 3]:
			var b := UiStyle.button(str(n), UiStyle.PANEL_LIGHT, 26, Vector2(150 if n == 3 else 96, 64))
			b.pressed.connect(func() -> void: _on_slot_pressed(n))
			slots_row.add_child(b)
			_slot_buttons.append(b)
		controls.add_child(slots_row)
		_slot_hint = UiStyle.label("", 19, UiStyle.TEXT_DIM, 4)
		_slot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		controls.add_child(_slot_hint)
		_keys = KeyBinds.new()
		add_child(_keys)
		_credits = CreditsPopup.new()
		add_child(_credits)

	func _on_slot_pressed(n: int) -> void:
		if n == 3 and not SaveService.has_slot3():
			if SaveService.get_gems() < SaveService.SLOT3_PRICE:
				_slot_hint.text = "Не хватает неонита: нужно %s, у тебя %s" % [Economy.format_gems(SaveService.SLOT3_PRICE), Economy.format_gems(SaveService.get_gems())]
				SoundManager.play(&"ui_confirm")
				return
			if not _slot_confirm:
				_slot_confirm = true
				_slot_hint.text = "Нажми на «3» ещё раз, чтобы купить слот за %s" % Economy.format_gems(SaveService.SLOT3_PRICE)
				return
			if SaveService.buy_slot3():
				SoundManager.play(&"star_dust")
				Controls.set_value("weapon_slots", 3)
			_slot_confirm = false
			_refresh()
			return
		Controls.set_value("weapon_slots", n)
		_refresh()

	func _refresh() -> void:
		var q := SaveService.get_quality()
		for i in _quality_buttons.size():
			var color := UiStyle.NEON.darkened(0.25) if i == q else UiStyle.PANEL_LIGHT
			for state in ["normal", "hover"]:
				_quality_buttons[i].add_theme_stylebox_override(state, UiStyle.button_box(color, false))
		_quality_hint.text = QUALITY_HINTS[q] + ("\nИгра закрылась во время боя, поэтому графика снижена автоматически." if bool(SaveService.data.get("crash_downgraded", false)) else "")
		_fps.set_pressed_no_signal(bool(SaveService.data["show_fps"]))
		_lite.set_pressed_no_signal(SaveService.is_fx_lite())
		_mini.set_pressed_no_signal(SaveService.is_minimap_enabled())
		_min_hud.set_pressed_no_signal(bool(SaveService.data.get("min_hud", false)))
		_nearest.set_pressed_no_signal(bool(SaveService.data.get("target_nearest", false)))
		if _fullscreen != null:
			_fullscreen.set_pressed_no_signal(Platform.is_fullscreen())
		_auto_pick.set_pressed_no_signal(bool(Controls.get_value("auto_pick")))
		_slot_buttons[1].text = "3" if SaveService.has_slot3() else "3 · " + Economy.format_gems(SaveService.SLOT3_PRICE)
		if SaveService.has_slot3():
			_slot_hint.text = "Третий слот открыт"
		elif not _slot_confirm:
			_slot_hint.text = "Третий слот: %s" % Economy.format_gems(SaveService.SLOT3_PRICE)
		for i in _slot_buttons.size():
			var color := UiStyle.NEON.darkened(0.25) if Controls.weapon_slot_count() == i + 2 else UiStyle.PANEL_LIGHT
			for state in ["normal", "hover"]:
				_slot_buttons[i].add_theme_stylebox_override(state, UiStyle.button_box(color, false))

	func close() -> void:
		SaveService.save_data()
		super.close()


## Гардероб: герои (окрас, пропорции, характеристики) и наряды. У каждой строки — живое превью
## на риге: герой в текущем наряде / текущий герой в этом наряде.
class Shop:
	extends GlassPopup
	signal skin_changed
	var _list: VBoxContainer

	var _skins_mode := false
	var _balance: Label
	var _query := ""

	func _init(skins_mode: bool = false) -> void:
		super("СКИНЫ" if skins_mode else "ГЕРОИ")
		_skins_mode = skins_mode
		_balance = UiStyle.label("", 24, UiStyle.GOLD, 6)
		content.add_child(_balance)
		var search := SearchBar.new("Найти скин по названию" if skins_mode else "Найти героя по имени")
		search.changed.connect(func(query: String) -> void:
			_query = query
			_refresh())
		content.add_child(search)
		_list = MenuPopups.scroll_list(content)

	func _refresh() -> void:
		_balance.text = "%s · %s" % [SaveService.format_coins(SaveService.get_coins()), Economy.format_gems(SaveService.get_gems())]
		MenuPopups.clear(_list)
		if not _skins_mode:
			for character in CharacterDB.all():
				if SearchBar.matches(_query, "%s %s" % [character["title"], character.get("description", "")]):
					_list.add_child(_make_character_row(character))
			return
		var hint := UiStyle.label("Скин меняет внешний вид выбранного героя. Купленные скины остаются навсегда.", 18, UiStyle.TEXT_DIM, 4)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(520, 0)
		_list.add_child(hint)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_list.add_child(grid)
		for skin_id in SaveService.SKINS:
			var skin: Dictionary = SaveService.SKINS[skin_id]
			if SearchBar.matches(_query, "%s %s" % [skin["title"], skin["description"]]):
				grid.add_child(_make_skin_card(skin_id))

	func _section(title: String) -> Control:
		var label := UiStyle.label(title, 26, UiStyle.NEON, 6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		return label

	func _row_panel(selected: bool) -> Array:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.NEON if selected else UiStyle.OUTLINE, 4, 20))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		panel.add_child(row)
		return [panel, row]

	func _info(row: HBoxContainer, title: String, text: String, extra: String = "") -> void:
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(info)
		var name_label := UiStyle.label(title, 28, UiStyle.TEXT, 8)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(name_label)
		var text_label := UiStyle.label(text, 18, UiStyle.TEXT_DIM, 4)
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(text_label)
		if not extra.is_empty():
			var extra_label := UiStyle.label(extra, 17, UiStyle.GOLD, 4)
			extra_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			extra_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(extra_label)

	func _price_text(price: int, currency: String) -> String:
		return SaveService.format_coins(price) if currency == "nuts" else Economy.format_gems(price)

	func _make_character_row(character: Dictionary) -> Control:
		var id: String = character["id"]
		var selected := SaveService.get_character_id() == id
		var parts := _row_panel(selected)
		var row: HBoxContainer = parts[1]
		if bool(character.get("coming_soon", false)) or ResourceLoader.exists(str(character.get("portrait", ""))):
			var portrait := TextureRect.new()
			var path := str(character.get("portrait", ""))
			if ResourceLoader.exists(path):
				portrait.texture = load(path)
			portrait.custom_minimum_size = Vector2(150, 130)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(portrait)
		else:
			var preview := MenuWidgets.RaccoonPreview.new(SaveService.get_skin(), 1.0, character)
			preview.custom_minimum_size = Vector2(150, 130)
			row.add_child(preview)
		var extra := str(character.get("traits", ""))
		var passive: Dictionary = character.get("passive", {})
		if not passive.is_empty():
			extra += "\nПАССИВКА «%s»: %s" % [passive.get("title", ""), passive.get("text", "")]
		_info(row, character["title"], str(character.get("description", "")), extra)
		var action: Button
		if bool(character.get("coming_soon", false)):
			action = UiStyle.button("Скоро", UiStyle.PANEL, 22, Vector2(150, 70))
			action.disabled = true
		elif selected:
			action = UiStyle.button("Выбран", UiStyle.PANEL, 22, Vector2(150, 70))
			action.disabled = true
		elif SaveService.owns_character(id):
			action = UiStyle.button("Выбрать", UiStyle.NEON.darkened(0.3), 22, Vector2(150, 70))
			action.pressed.connect(func() -> void:
				SaveService.select_character(id)
				SoundManager.play(&"ui_confirm")
				skin_changed.emit()
				_refresh())
		else:
			action = UiStyle.button(_price_text(int(character["price"]), character["currency"]), UiStyle.HOT, 20, Vector2(150, 70))
			action.disabled = int(SaveService.data[character["currency"]]) < int(character["price"])
			action.pressed.connect(func() -> void:
				if SaveService.buy_character(id):
					SoundManager.play(&"star_dust")
					skin_changed.emit()
					_refresh())
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action)
		return parts[0]

	func _make_skin_card(skin_id: String) -> Control:
		var skin: Dictionary = SaveService.SKINS[skin_id]
		var selected := SaveService.get_selected_skin() == skin_id
		var owned := SaveService.owns_skin(skin_id)
		var accent := UiStyle.NEON if selected else (Color("#ffd257") if owned else UiStyle.OUTLINE)
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, accent, 5 if selected else 3, 22))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		panel.add_child(column)
		var stage := PanelContainer.new()
		stage.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.03, 0.12, 0.9), Color(accent, 0.5), 2, 16))
		stage.custom_minimum_size = Vector2(0, 230)
		column.add_child(stage)
		var preview := MenuWidgets.RaccoonPreview.new(skin, 1.35)
		preview.custom_minimum_size = Vector2(0, 230)
		stage.add_child(preview)
		var title := UiStyle.label(str(skin["title"]).to_upper(), 24, UiStyle.TEXT, 6)
		column.add_child(title)
		var text := UiStyle.label(MenuPopups.describe_skin(skin), 16, UiStyle.TEXT_DIM, 3)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(200, 44)
		column.add_child(text)
		var action: Button
		if selected:
			action = UiStyle.button("НАДЕТ", UiStyle.PANEL, 22, Vector2(0, 64))
			action.disabled = true
		elif owned:
			action = UiStyle.button("НАДЕТЬ", UiStyle.NEON.darkened(0.3), 22, Vector2(0, 64))
			action.pressed.connect(func() -> void:
				SaveService.select_skin(skin_id)
				SoundManager.play(&"ui_confirm")
				skin_changed.emit()
				_refresh())
		else:
			var affordable := int(SaveService.data[skin["currency"]]) >= int(skin["price"])
			action = UiStyle.button(_price_text(int(skin["price"]), skin["currency"]), UiStyle.HOT if affordable else UiStyle.PANEL, 21, Vector2(0, 64))
			action.disabled = not affordable
			action.pressed.connect(func() -> void:
				if SaveService.buy_skin(skin_id):
					SoundManager.play(&"star_dust")
					skin_changed.emit()
					_refresh())
		column.add_child(action)
		return panel


static func describe_skin(skin: Dictionary) -> String:
	return str(skin.get("description", ""))


## Оружие + Merge: арсенал по тирам. Две копии одного тира сливаются в тир выше.
class Armory:
	extends GlassPopup
	signal weapon_changed(weapon_id: StringName)
	var _list: VBoxContainer
	var _balance: Label
	var _query := ""

	func _init() -> void:
		super("ОРУЖИЕ + MERGE")
		_balance = UiStyle.label("", 24, UiStyle.GOLD, 6)
		content.add_child(_balance)
		var hint := UiStyle.label("Купить ствол — за монеты, легендарные — только за неонит. Из ящиков забега ствол остаётся навсегда не всегда. 2 одинаковых = тир выше (у легендарных тиров нет: они сильнее всех).", 18, UiStyle.TEXT_DIM, 4)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(hint)
		var search := SearchBar.new("Найти оружие по названию")
		search.changed.connect(func(query: String) -> void:
			_query = query
			_refresh())
		content.add_child(search)
		_list = MenuPopups.scroll_list(content)

	func _refresh() -> void:
		_balance.text = "%s · %s" % [SaveService.format_coins(SaveService.get_coins()), Economy.format_gems(SaveService.get_gems())]
		MenuPopups.clear(_list)
		var owned: Array[WeaponData] = []
		var locked: Array[WeaponData] = []
		for weapon in WeaponDB.get_player_weapons():
			if not SearchBar.matches(_query, "%s %s %s" % [weapon.get_title(), weapon.short_name, WeaponData.RARITY_NAMES[weapon.rarity]]):
				continue
			if SaveService.owns_weapon(weapon.id):
				owned.append(weapon)
			else:
				locked.append(weapon)
		for weapon in owned:
			_list.add_child(_make_card(weapon))
		for weapon in locked:
			_list.add_child(_make_locked(weapon))

	func _make_card(base: WeaponData) -> Control:
		var selected := SaveService.get_selected_weapon() == base.id
		var tier := SaveService.get_selected_tier() if selected else SaveService.best_tier(base.id)
		var weapon := base.with_tier(tier)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, weapon.get_rarity_color() if selected else UiStyle.OUTLINE, 5 if selected else 3, 20))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		panel.add_child(column)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		column.add_child(top)
		var art := WeaponIcons.IconRect.new(base.icon, base.effect_color, Vector2(130, 56))
		art.tier = tier if base.rarity != "legendary" else 0
		top.add_child(art)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(info)
		var title := UiStyle.label(weapon.get_title(), 26, weapon.get_rarity_color(), 7)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(title)
		var stats := UiStyle.label("Урон %d · %.1f %s · DPS %d" % [roundi(weapon.damage), 1.0 / weapon.fire_interval, "ударов/с" if weapon.is_melee() else "выстр/с", roundi(weapon.get_dps())], 18, UiStyle.TEXT_DIM, 4)
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(stats)
		var behavior := UiStyle.label(base.behavior_text(), 17, UiStyle.NEON, 4)
		behavior.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		behavior.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(behavior)
		if WeaponData.TRAITS.has(String(base.trait_id)):
			var trait_label := UiStyle.label(WeaponData.TRAITS[String(base.trait_id)], 16, UiStyle.GOLD, 4)
			trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(trait_label)
		if selected:
			info.add_child(UiStyle.label("В РУКАХ", 18, UiStyle.NEON, 4))

		if not base.has_tiers():
			var note := UiStyle.label("ЛЕГЕНДАРНОЕ: без тиров и слияния, сильнее любого обычного, редкого и эпического ствола", 17, UiStyle.GOLD, 4)
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(note)
			if not selected:
				var equip := UiStyle.button("ВЗЯТЬ В РУКИ", base.get_rarity_color().darkened(0.35), 20, Vector2(0, 54))
				equip.pressed.connect(func() -> void:
					SaveService.set_selected_weapon(base.id, 1)
					weapon_changed.emit(base.id)
					_refresh())
				column.add_child(equip)
			return panel
		var tiers := HBoxContainer.new()
		tiers.add_theme_constant_override("separation", 8)
		column.add_child(tiers)
		for t in range(1, WeaponData.MAX_TIER + 1):
			var copies := SaveService.get_copies(base.id, t)
			if copies <= 0:
				continue
			var chip := UiStyle.button("T%d ×%d" % [t, copies], UiStyle.PANEL if not (selected and t == tier) else base.get_rarity_color().darkened(0.35), 20, Vector2(96, 54))
			chip.pressed.connect(func() -> void:
				SaveService.set_selected_weapon(base.id, t)
				weapon_changed.emit(base.id)
				_refresh())
			tiers.add_child(chip)
			if SaveService.can_merge(base.id, t):
				var merge := UiStyle.button("MERGE » T%d" % (t + 1), Color("#7ed321").darkened(0.2), 20, Vector2(170, 54))
				merge.pressed.connect(func() -> void:
					if SaveService.merge(base.id, t):
						SoundManager.play(&"merge", 0.0, false)
						weapon_changed.emit(base.id)
						_refresh())
				tiers.add_child(merge)
		var buy_row := _make_buy_row(base, "ЕЩЁ КОПИЮ")
		if buy_row != null:
			column.add_child(buy_row)
		return panel

	func _make_buy_row(weapon: WeaponData, verb: String) -> Control:
		if not Economy.is_buyable(weapon):
			return null
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var coins := Economy.shop_price(weapon)
		if coins > 0:
			var afford := SaveService.get_coins() >= coins
			var b := UiStyle.button("%s · %s" % [verb, SaveService.format_coins(coins)], Color("#e0a020") if afford else UiStyle.PANEL, 20, Vector2(0, 54))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = not afford
			b.pressed.connect(func() -> void: _buy(weapon, false))
			row.add_child(b)
		var gems := Economy.shop_gem_price(weapon)
		if gems > 0:
			var afford_gems := SaveService.get_gems() >= gems
			var g := UiStyle.button("%s · %s" % [verb if coins <= 0 else "ИЛИ", Economy.format_gems(gems)], Color("#b34dff") if afford_gems else UiStyle.PANEL, 20, Vector2(0, 54))
			g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.disabled = not afford_gems
			g.pressed.connect(func() -> void: _buy(weapon, true))
			row.add_child(g)
		return row

	func _buy(weapon: WeaponData, with_gems: bool) -> void:
		if Economy.buy_weapon(weapon, with_gems):
			SoundManager.play(&"ui_confirm")
			weapon_changed.emit(weapon.id)
			_refresh()

	func _make_locked(weapon: WeaponData) -> Control:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL.darkened(0.3), UiStyle.OUTLINE, 3, 20))
		panel.modulate = Color(1, 1, 1, 0.6)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var icon := WeaponIcons.IconRect.new(weapon.icon, Color("#4a4460"), Vector2(130, 56))
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var title := UiStyle.label(weapon.display_name, 24, weapon.get_rarity_color(), 6)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(title)
		var hint := "Чертёж — награда Ледяного налёта" if weapon.unlock_blueprint != &"" else "%s · в магазине или из ящиков" % WeaponData.RARITY_NAMES[weapon.rarity]
		var hint_label := UiStyle.label(hint, 18, UiStyle.TEXT_DIM, 4)
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(hint_label)
		if WeaponData.TRAITS.has(String(weapon.trait_id)):
			var trait_label := UiStyle.label(WeaponData.TRAITS[String(weapon.trait_id)], 16, UiStyle.GOLD, 4)
			trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(trait_label)
		var buy_row := _make_buy_row(weapon, "КУПИТЬ")
		if buy_row != null:
			info.add_child(buy_row)
			panel.modulate = Color(1, 1, 1, 0.9)
		return panel


## Прокачка: постоянные бонусы за монеты; список листается пальцем.
class Upgrades:
	extends GlassPopup
	signal purchased
	const COLORS := {
		"power": "#ff4d6d", "stamina": "#69f0ae", "armor": "#40c4ff", "eye": "#ffe14d",
		"boots": "#7cffcb", "magnet": "#ff6bd6", "loot": "#ffd257",
		"reroll": "#8ec5ff", "vest": "#ffb347", "drone": "#7cd4ff", "logistics": "#c792ff", "headstart": "#ff7a5c", "cash": "#a8ff5e", "radar": "#5cf3ff",
	}
	var _list: VBoxContainer
	var _balance: Label

	func _init() -> void:
		super("ПРОКАЧКА")
		_balance = UiStyle.label("", 26, UiStyle.GOLD, 6)
		content.add_child(_balance)
		var note := UiStyle.label("Действует только в режиме выживания. В сюжете все начинают с нуля, как в старых аркадах.", 18, UiStyle.TEXT_DIM, 4)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(520, 0)
		content.add_child(note)
		_list = MenuPopups.scroll_list(content)

	func _refresh() -> void:
		_balance.text = "Баланс: " + SaveService.format_coins(SaveService.get_nuts())
		MenuPopups.clear(_list)
		var spent := 0
		for perk_id in SaveService.PERKS:
			spent += SaveService.get_perk_level(perk_id)
		if spent == 0:
			var tip := UiStyle.label("Новичку: начни со «Здоровья» и «Силы», это самая заметная прибавка. Монеты берутся из забегов.", 20, Color("#ffe2b8"), 5)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip.custom_minimum_size = Vector2(520, 0)
			_list.add_child(tip)
		for perk_id in SaveService.PERKS:
			_list.add_child(_make_card(perk_id))

	func _make_card(perk_id: String) -> Control:
		var perk: Dictionary = SaveService.PERKS[perk_id]
		var level := SaveService.get_perk_level(perk_id)
		var color := Color(COLORS.get(perk_id, "#00e5ff"))
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, color, 4, 20))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		panel.add_child(column)
		var head := HBoxContainer.new()
		column.add_child(head)
		var title := UiStyle.label(String(perk["title"]).to_upper(), 30, color, 8)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(UiStyle.label("%d/%d" % [level, int(perk["max"])], 26, UiStyle.TEXT, 6))
		var flavor := UiStyle.label(String(perk.get("theme", "")), 17, color.lightened(0.2), 4)
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(flavor)
		var desc := UiStyle.label("%s\nСейчас: %s" % [perk["description"], _bonus_text(perk_id, level)], 19, UiStyle.TEXT_DIM, 4)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(desc)
		var bar := UiStyle.progress_bar(color, 18)
		bar.max_value = float(perk["max"])
		bar.value = level
		column.add_child(bar)
		var buy: Button
		if SaveService.is_perk_maxed(perk_id):
			buy = UiStyle.button("МАКСИМУМ", UiStyle.PANEL, 24, Vector2(0, 66))
			buy.disabled = true
		else:
			var cost := SaveService.get_perk_cost(perk_id)
			buy = UiStyle.button("След.: %s · %s" % [_bonus_text(perk_id, level + 1), SaveService.format_coins(cost)], Color("#7ed321").darkened(0.15), 22, Vector2(0, 66))
			buy.disabled = SaveService.get_nuts() < cost
			buy.pressed.connect(func() -> void:
				if SaveService.buy_perk(perk_id):
					SoundManager.play(&"merge", 0.0, false)
					purchased.emit()
					_refresh())
		column.add_child(buy)
		return panel

	func _bonus_text(perk_id: String, level: int) -> String:
		var bonus := float(SaveService.PERKS[perk_id]["step"]) * level
		match perk_id:
			"stamina":
				return "+%d HP" % roundi(bonus)
			"reroll":
				return "+%d" % roundi(bonus)
			"vest", "drone", "headstart", "radar":
				return "+%d" % roundi(bonus)
			"cash":
				return "+%d" % roundi(bonus)
			"armor":
				return "-%d%%" % roundi(bonus * 100.0)
			_:
				return "+%d%%" % roundi(bonus * 100.0)


## Ачивки: прогресс и награда каждой.
class Achievements:
	extends GlassPopup
	var _list: VBoxContainer

	func _init() -> void:
		super("АЧИВКИ")
		_list = MenuPopups.scroll_list(content)

	func _refresh() -> void:
		MenuPopups.clear(_list)
		var items: Array = SaveService.ACHIEVEMENTS.duplicate()
		items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			var dx := SaveService.is_achieved(x["id"])
			var dy := SaveService.is_achieved(y["id"])
			if dx != dy:
				return dy
			return SaveService.get_achievement_progress(x) > SaveService.get_achievement_progress(y))
		for achievement in items:
			_list.add_child(_make_row(achievement))

	func _make_row(achievement: Dictionary) -> Control:
		var done := SaveService.is_achieved(achievement["id"])
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT if done else UiStyle.PANEL, UiStyle.GOLD if done else UiStyle.OUTLINE, 4, 18))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		panel.add_child(column)
		var head := HBoxContainer.new()
		column.add_child(head)
		var title := UiStyle.label((String(achievement["title"]) if done or not achievement.get("hidden", false) else "???") + ("  · получено" if done else ""), 26, UiStyle.GOLD if done else UiStyle.TEXT, 7)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var reward := PackedStringArray()
		if int(achievement["nuts"]) > 0:
			reward.append("+" + SaveService.format_coins(int(achievement["nuts"])))
		if int(achievement["dust"]) > 0:
			reward.append("+" + Economy.format_gems(int(achievement["dust"])))
		head.add_child(UiStyle.label(" ".join(reward), 18, UiStyle.GOLD, 4))
		var desc := UiStyle.label(String(achievement["description"]) if done or not achievement.get("hidden", false) else "Скрытое достижение. Хладгор подскажет.", 19, UiStyle.TEXT_DIM, 4)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(desc)
		var bar := UiStyle.progress_bar(UiStyle.GOLD if done else UiStyle.NEON, 16)
		bar.max_value = 1.0
		bar.value = SaveService.get_achievement_progress(achievement)
		column.add_child(bar)
		if not done:
			var count := UiStyle.label("%d / %d" % [mini(SaveService.get_stat(achievement["stat"]), int(achievement["goal"])), int(achievement["goal"])], 17, UiStyle.TEXT_DIM, 4)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			column.add_child(count)
		return panel


class Profile:
	extends GlassPopup

	signal achievements_requested
	signal chronicle_requested
	signal friends_requested
	signal account_requested

	const ICON_DIR := "res://assets/ui/icons/"
	const RANKS := [
		[1, "Помойный новичок"], [4, "Мусорщик"], [8, "Свалочный волк"],
		[14, "Ржавый ветеран"], [22, "Неоновый воротила"], [32, "Король хлама"],
	]

	var _picker: AvatarPicker

	func _init() -> void:
		super("ПРОФИЛЬ")
		_picker = AvatarPicker.new()
		_picker.picked.connect(_refresh)
		add_child(_picker)

	static func rank_for(level: int) -> String:
		var title := str(RANKS[0][1])
		for row in RANKS:
			if level >= int(row[0]):
				title = str(row[1])
		return title

	func _refresh() -> void:
		var keep := content.get_child(0)
		for child in content.get_children():
			if child != keep:
				content.remove_child(child)
				child.queue_free()
		var list := MenuPopups.scroll_list(content)
		list.add_child(_build_header())
		if not Cloud.has_email():
			list.add_child(_account_bar())
		list.add_child(_friends_bar())
		if Cloud.has_email():
			list.add_child(_account_bar())
		list.add_child(_recovery_bar())
		list.add_child(_rank_button())
		list.add_child(_section("РЕКОРДЫ"))
		var records := GridContainer.new()
		records.columns = 3
		records.add_theme_constant_override("h_separation", 12)
		records.add_theme_constant_override("v_separation", 12)
		records.add_child(_tile("Лучшая волна", str(SaveService.get_stat("best_wave")), "upgrade", UiStyle.GOLD, true))
		records.add_child(_tile("Лучшее время", BattleBase.format_time(float(SaveService.data.get("best_time", 0.0))), "clock", UiStyle.NEON, true))
		records.add_child(_tile("Боссов убито", str(int(SaveService.data.get("boss_kills", 0))), "trophy", UiStyle.HOT, true))
		list.add_child(records)
		list.add_child(_section("СТАТИСТИКА"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.add_child(_tile("Убито крыс", _num(SaveService.get_stat("kills")), "skull", UiStyle.DANGER, false))
		grid.add_child(_tile("Критов", _num(SaveService.get_stat("crits")), "swords", Color("#ff9a3d"), false))
		grid.add_child(_tile("Забегов", _num(SaveService.get_stat("runs")), "play", UiStyle.NEON, false))
		grid.add_child(_tile("Монет собрано", _num(SaveService.get_stat("nuts_total")), "", UiStyle.GOLD, false))
		grid.add_child(_tile("Глав пройдено", str(SaveService.get_biomes_cleared()), "controls", Color("#b46bff"), false))
		grid.add_child(_tile("Налётов выиграно", str(int(SaveService.data.get("raid_wins", 0))), "trophy", Color("#5cf3ff"), false))
		list.add_child(grid)
		list.add_child(_achievements_bar())
		list.add_child(_chronicle_bar())
		list.add_child(_section("Версия игры"))
		var version := UiStyle.label(Platform.build_label() if not Platform.build_label().is_empty() else "локальная сборка", 30, UiStyle.GOLD, 7)
		version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(version)
		list.add_child(MenuPopups.small_hint("Если у друга другой номер, пусть откроет игру заново или нажмёт на розовую плашку обновления."))
		list.add_child(_section("Облачное сохранение"))
		list.add_child(_cloud_block())
		list.add_child(_section("Сохранение и реплики"))
		list.add_child(_insider_block())

	## Вход в аккаунт по логину и паролю: единственный способ ничего не терять при очистке браузера.
	func _account_bar() -> Control:
		var text := "АККАУНТ: %s" % Cloud.email if Cloud.has_email() else "АККАУНТ НЕ СОЗДАН!\nпрогресс может пропасть. Нажми и придумай логин и пароль"
		var b := UiStyle.button(text, Color("#2fae5f") if Cloud.has_email() else Color("#d63a3a"), 24, Vector2(0, 84))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func() -> void: account_requested.emit())
		if not Cloud.has_email() and Cloud.guest_key.is_empty():
			return b
		# Сколько устройств сейчас в этом аккаунте: видно, что браузер и приложение — один енот.
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(b)
		var devices := MenuPopups.small_hint("")
		box.add_child(devices)
		_fill_devices(devices)
		return box

	func _fill_devices(label: Label) -> void:
		var count := await Cloud.my_devices()
		if not is_instance_valid(label):
			return
		if count <= 0:
			label.visible = false
		elif count == 1:
			label.text = "Ты вошёл на 1 устройстве. Открой ссылку-вход или войди логином на втором, и это будет тот же енот."
		else:
			label.text = "Ты вошёл на %d устройствах, это один и тот же аккаунт: прогресс, друзья и тег общие." % count

	## Крупный код восстановления: нажал и скопировал. После любого сброса прогресс возвращается им.
	func _recovery_bar() -> Control:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var code := Cloud.recovery_code
		var b := UiStyle.button("", UiStyle.PANEL_LIGHT, 22, Vector2(0, 96))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = ("КОД ВОССТАНОВЛЕНИЯ\n%s\n(нажми, чтобы скопировать)" % code) if not code.is_empty() else "КОД ВОССТАНОВЛЕНИЯ\nготовлю... зайди сюда через минуту"
		b.pressed.connect(func() -> void:
			if Cloud.recovery_code.is_empty():
				Cloud.queue_upload()
				return
			DisplayServer.clipboard_set(Cloud.recovery_code)
			b.text = "Код скопирован: %s\nСохрани его в заметки" % Cloud.recovery_code)
		box.add_child(b)
		var link := UiStyle.button("Скопировать ссылку-вход", UiStyle.PANEL_LIGHT, 21, Vector2(0, 54))
		link.pressed.connect(func() -> void:
			var base := Platform.page_url()
			var param := Cloud.entry_link_param()
			if param.is_empty() or base.is_empty():
				link.text = "Ссылки пока нет, подожди минуту"
				return
			DisplayServer.clipboard_set("%s?%s" % [base, param])
			link.text = "Скопировано. Никому не показывай!")
		box.add_child(link)
		box.add_child(MenuPopups.small_hint("Ссылка-вход и код открывают твой аккаунт целиком. Никому их не показывай и не кидай в чаты, в отличие от визитки."))
		if code.is_empty():
			var fill := func() -> void:
				var fresh := await Cloud.upload_save()
				if not fresh.is_empty() and is_instance_valid(b):
					b.text = "КОД ВОССТАНОВЛЕНИЯ\n%s\n(нажми, чтобы скопировать)" % fresh
			fill.call()
		return box

	func _rank_button() -> Control:
		var have := SaveService.unlocked_ranks().size()
		var current := SaveService.get_rank()
		var text := "ТИТУЛ: %s" % (current if not current.is_empty() else "нет")
		var b := UiStyle.button(text if have > 0 else "ТИТУЛЫ: получи грязную ачивку", UiStyle.PANEL_LIGHT, 22, Vector2(0, 60))
		b.disabled = have == 0
		b.pressed.connect(func() -> void:
			SaveService.cycle_rank()
			_refresh())
		return b

	func _num(value: int) -> String:
		return SaveService.format_coins(value) if value >= 10000 else str(value)

	func _section(title: String) -> Control:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var line_left := ColorRect.new()
		line_left.color = Color(UiStyle.HOT, 0.7)
		line_left.custom_minimum_size = Vector2(28, 3)
		line_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line_left)
		row.add_child(UiStyle.label(title, 24, UiStyle.NEON, 6))
		var line_right := ColorRect.new()
		line_right.color = Color(UiStyle.NEON, 0.35)
		line_right.custom_minimum_size = Vector2(10, 3)
		line_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line_right)
		return row

	func _build_header() -> Control:
		var level := SaveService.get_account_level()
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#241a40"), Color("#c9722b"), 5, 24))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 18)
		panel.add_child(head)
		var avatar := MenuWidgets.Avatar.new()
		avatar.custom_minimum_size = Vector2(140, 140)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		avatar.mouse_filter = Control.MOUSE_FILTER_STOP
		avatar.gui_input.connect(func(event: InputEvent) -> void:
			var tapped: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
			if tapped:
				_picker.open())
		var avatar_box := VBoxContainer.new()
		avatar_box.add_theme_constant_override("separation", 2)
		avatar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		avatar_box.add_child(avatar)
		var change := UiStyle.label("СМЕНИТЬ", 16, UiStyle.NEON, 4)
		avatar_box.add_child(change)
		head.add_child(avatar_box)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 6)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(_build_nick_editor())
		var rank_label := UiStyle.label(rank_for(level).to_upper(), 20, Color("#ff9a3d"), 5)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(rank_label)
		if int(SaveService.data.get("dragon_kills", 0)) > 0:
			var lord := UiStyle.label("Владыка Тонкого Льда", 18, Color("#9fe8ff"), 5)
			lord.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			info.add_child(lord)
		var level_row := HBoxContainer.new()
		level_row.add_theme_constant_override("separation", 8)
		var star := TextureRect.new()
		star.texture = load(ICON_DIR + "xp_star.png")
		star.custom_minimum_size = Vector2(34, 34)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		level_row.add_child(star)
		var level_label := UiStyle.label("УРОВЕНЬ %d" % level, 26, UiStyle.TEXT, 7)
		level_row.add_child(level_label)
		info.add_child(level_row)
		var xp := UiStyle.progress_bar(UiStyle.NEON, 18)
		xp.max_value = 1.0
		xp.value = SaveService.get_level_progress()
		info.add_child(xp)
		var id_button := UiStyle.button("", UiStyle.PANEL_LIGHT, 20, Vector2(0, 46))
		var paint_id := func() -> void:
			id_button.text = "ID для друзей: %s" % Cloud.friend_code if Cloud.has_code() else "ID: ищу связь..."
		paint_id.call()
		if not Cloud.has_code():
			Cloud.sync_profile()
			Cloud.profile_synced.connect(func() -> void:
				if is_instance_valid(id_button):
					paint_id.call(), CONNECT_ONE_SHOT)
		id_button.pressed.connect(func() -> void:
			if Cloud.has_code():
				DisplayServer.clipboard_set(Cloud.friend_code)
				id_button.text = "ID скопирован")
		info.add_child(id_button)
		head.add_child(info)
		return panel

	func _styled_edit(placeholder: String) -> LineEdit:
		var edit := LineEdit.new()
		edit.placeholder_text = placeholder
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.custom_minimum_size = Vector2(0, 56)
		SearchBar.style(edit, 22)
		SearchBar.attach_touch_input(edit, placeholder)
		return edit

	func _cloud_block() -> Control:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var status := UiStyle.label("Код восстановления: %s" % (Cloud.recovery_code if not Cloud.recovery_code.is_empty() else "ещё не сохранялось"), 22, UiStyle.GOLD, 6)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(status)
		box.add_child(MenuPopups.small_hint("Прогресс сохраняется сам после забега. Код выше: способ вернуть его на другом устройстве."))
		var save := UiStyle.button("Сохранить в облако сейчас", UiStyle.PANEL_LIGHT, 22, Vector2(0, 56))
		save.pressed.connect(func() -> void:
			save.disabled = true
			save.text = "Сохраняю..."
			var code := await Cloud.upload_save()
			if not is_instance_valid(save):
				return
			save.disabled = false
			save.text = "Сохранено" if not code.is_empty() else "Нет связи с сервером"
			if not code.is_empty():
				status.text = "Код восстановления: %s" % code)
		box.add_child(save)
		var copy := UiStyle.button("Скопировать код восстановления", UiStyle.PANEL_LIGHT, 22, Vector2(0, 56))
		copy.pressed.connect(func() -> void:
			if not Cloud.recovery_code.is_empty():
				DisplayServer.clipboard_set(Cloud.recovery_code)
				copy.text = "Код скопирован")
		box.add_child(copy)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var edit := _styled_edit("Код восстановления")
		row.add_child(edit)
		var restore := UiStyle.button("ВЕРНУТЬ", UiStyle.HOT, 22, Vector2(170, 56))
		var armed := [false]
		restore.pressed.connect(func() -> void:
			if edit.text.strip_edges().is_empty():
				return
			if not armed[0]:
				armed[0] = true
				restore.text = "ТОЧНО?"
				get_tree().create_timer(3.0).timeout.connect(func() -> void:
					if is_instance_valid(restore):
						armed[0] = false
						restore.text = "ВЕРНУТЬ")
				return
			armed[0] = false
			restore.text = "..."
			var saved := await Cloud.restore_save(edit.text)
			if not is_instance_valid(restore):
				return
			if saved.begins_with("ACCOUNT:"):
				restore.text = "ВОЙДИ ЛОГИНОМ «%s»" % saved.trim_prefix("ACCOUNT:")
			elif not saved.is_empty() and SaveService.import_code(saved):
				restore.text = "ГОТОВО"
				Cloud.recovery_code = edit.text.strip_edges().to_upper()
				Platform.storage_set(Cloud.RECOVERY_KEY, Cloud.recovery_code)
			else:
				restore.text = "НЕ НАЙДЕНО")
		row.add_child(restore)
		box.add_child(row)
		box.add_child(MenuPopups.small_hint("«Вернуть» заменяет прогресс на этом устройстве сохранением из облака."))
		return box

	func _insider_block() -> Control:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var votes_box := VBoxContainer.new()
		votes_box.add_theme_constant_override("separation", 6)
		var votes := MenuWidgets.PawToggle.new("Оценка реплик", bool(SaveService.data.get("line_votes_on", true)))
		votes.toggled.connect(func(on: bool) -> void: SaveService.set_flag("line_votes_on", on))
		votes_box.add_child(votes)
		votes_box.add_child(MenuPopups.small_hint("Под репликой в бою кнопки «+» оставить и «×» убрать. Оценено: %d. Убранные реплики больше не появятся." % LineVotes.rated_count()))
		box.add_child(votes_box)
		var copy := UiStyle.button("Скопировать код сохранения", UiStyle.PANEL_LIGHT, 22, Vector2(0, 56))
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(SaveService.export_code())
			copy.text = "Код сохранения скопирован")
		box.add_child(copy)
		var load_row := HBoxContainer.new()
		load_row.add_theme_constant_override("separation", 8)
		var load_edit := _styled_edit("Вставь код сохранения")
		load_row.add_child(load_edit)
		var load := UiStyle.button("Загрузить", UiStyle.PANEL_LIGHT, 22, Vector2(170, 56))
		load.pressed.connect(func() -> void:
			if SaveService.import_code(load_edit.text):
				load.text = "Готово"
			else:
				load.text = "Не вышло")
		load_row.add_child(load)
		box.add_child(load_row)
		return box

	func _build_nick_editor() -> Control:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var edit := LineEdit.new()
		edit.text = SaveService.get_nickname()
		edit.placeholder_text = "Твой ник"
		edit.max_length = SaveService.NICKNAME_MAX
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.custom_minimum_size = Vector2(0, 56)
		SearchBar.style(edit, 24)
		SearchBar.attach_touch_input(edit, "Ник: до 16 символов, без пробелов")
		edit.text_changed.connect(func(text: String) -> void:
			var cleaned := SaveService.clean_nickname(text)
			if cleaned != text:
				var caret := mini(edit.caret_column, cleaned.length())
				edit.text = cleaned
				edit.caret_column = caret)
		var save := func() -> void:
			if edit.text != SaveService.get_nickname():
				SaveService.set_nickname(edit.text)
				edit.text = SaveService.get_nickname()
		edit.text_submitted.connect(func(_t: String) -> void:
			edit.release_focus())
		edit.focus_exited.connect(save)
		row.add_child(edit)
		var dice := MenuWidgets.DiceButton.new()
		dice.custom_minimum_size = Vector2(56, 56)
		dice.pressed.connect(func() -> void:
			edit.text = SaveService.random_nickname()
			save.call())
		row.add_child(dice)
		return row

	func _tile(title: String, value: String, icon: String, accent: Color, big: bool) -> Control:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := UiStyle.box(Color("#2f2452"), Color(accent, 0.75), 3, 16)
		panel.add_theme_stylebox_override("panel", box)
		var body: BoxContainer = VBoxContainer.new() if big else HBoxContainer.new()
		body.add_theme_constant_override("separation", 8 if not big else 2)
		body.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(body)
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(44, 44) if not big else Vector2(48, 48)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if icon.is_empty():
			icon_rect.texture = PickupManager.make_coin_texture(44)
		else:
			icon_rect.texture = load(ICON_DIR + icon + ".png")
		body.add_child(icon_rect)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 0)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(texts)
		texts.add_child(UiStyle.label(value, 38 if big else 34, accent.lightened(0.25), 9))
		var caption := UiStyle.label(title, 17 if big else 18, UiStyle.TEXT_DIM, 4)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(caption)
		return panel

	func _chronicle_bar() -> Control:
		var opened := 0
		for entry in ChroniclePopup.entries():
			if (entry as Dictionary)["open"]:
				opened += 1
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
			if tapped:
				SoundManager.play(&"ui_click")
				chronicle_requested.emit())
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#2f2452"), Color(UiStyle.NEON, 0.7), 3, 16))
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := UiStyle.label("Летопись - читать", 24, UiStyle.TEXT, 6)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(title)
		head.add_child(UiStyle.label("%d / %d" % [opened, ChroniclePopup.entries().size()], 28, UiStyle.NEON, 8))
		panel.add_child(head)
		return panel

	func _friends_bar() -> Control:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.custom_minimum_size = Vector2(0, 96)
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
			if tapped:
				SoundManager.play(&"ui_click")
				friends_requested.emit())
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#6b2a8f"), UiStyle.HOT, 4, 18))
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_theme_constant_override("separation", 12)
		var texts := VBoxContainer.new()
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := UiStyle.label("ДРУЗЬЯ", 34, UiStyle.TEXT, 8)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		texts.add_child(title)
		var sub := UiStyle.label("Новых сообщений и заявок: %d" % Cloud.unread if Cloud.unread > 0 else "Визитка, рейтинг, профили, чат", 18, UiStyle.GOLD if Cloud.unread > 0 else UiStyle.TEXT_DIM, 4)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		texts.add_child(sub)
		head.add_child(texts)
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.custom_minimum_size = Vector2(64, 64)
		badge.add_theme_stylebox_override("panel", UiStyle.box(Color("#ff2ea6"), UiStyle.OUTLINE, 3, 32))
		var count := UiStyle.label(str(SaveService.get_friends().size()), 32, Color.WHITE, 8)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.add_child(count)
		head.add_child(badge)
		panel.add_child(head)
		return panel

	func _achievements_bar() -> Control:
		var done := (SaveService.data["achievements"] as Array).size()
		var total := SaveService.ACHIEVEMENTS.size()
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
			if tapped:
				SoundManager.play(&"ui_click")
				achievements_requested.emit())
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#2f2452"), Color(UiStyle.GOLD, 0.7), 3, 16))
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 6)
		panel.add_child(column)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var trophy := TextureRect.new()
		trophy.texture = load(ICON_DIR + "trophy.png")
		trophy.custom_minimum_size = Vector2(36, 36)
		trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(trophy)
		var title := UiStyle.label("Достижения - открыть", 24, UiStyle.TEXT, 6)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(title)
		head.add_child(UiStyle.label("%d / %d" % [done, total], 28, UiStyle.GOLD, 8))
		column.add_child(head)
		var bar := UiStyle.progress_bar(UiStyle.GOLD, 16)
		bar.max_value = float(maxi(total, 1))
		bar.value = float(done)
		column.add_child(bar)
		return panel


class KeyBinds:
	extends GlassPopup
	var _list: VBoxContainer
	var _waiting: StringName = &""
	var _buttons: Dictionary = {}

	func _init() -> void:
		super("КЛАВИШИ")
		_list = MenuPopups.scroll_list(content)
		var reset := UiStyle.button("СБРОСИТЬ КЛАВИШИ", Color("#b03a5a"), 22, Vector2(0, 64))
		reset.pressed.connect(func() -> void:
			Controls.reset_keys()
			_refresh())
		content.add_child(reset)

	func _refresh() -> void:
		_waiting = &""
		_buttons.clear()
		MenuPopups.clear(_list)
		for entry in Controls.KEY_ACTIONS:
			var action: StringName = entry[0]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var label := UiStyle.label(str(entry[1]), 26, UiStyle.TEXT, 6)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_child(label)
			var button := UiStyle.button(_keys_text(action), UiStyle.PANEL_LIGHT, 22, Vector2(230, 62))
			button.pressed.connect(func() -> void:
				_waiting = action
				button.text = "нажми клавишу…")
			_buttons[action] = button
			row.add_child(button)
			_list.add_child(row)

	func _keys_text(action: StringName) -> String:
		var names := PackedStringArray()
		for keycode in Controls.keys_for(action):
			names.append(Controls.key_title(int(keycode)))
		return " / ".join(names)

	func _input(event: InputEvent) -> void:
		if _waiting == &"" or not visible or not event is InputEventKey or not event.pressed or event.echo:
			return
		var key := event as InputEventKey
		if key.keycode != KEY_ESCAPE:
			Controls.set_key(_waiting, int(key.physical_keycode))
		var action := _waiting
		_waiting = &""
		(_buttons[action] as Button).text = _keys_text(action)
		get_viewport().set_input_as_handled()
