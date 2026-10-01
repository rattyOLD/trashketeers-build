class_name TesterPopup
extends GlassPopup
## Меню тестера: выдача валюты, оружия, героев, прокачки и флаги для проверки боя.

signal changed

const BOSS_NAMES := {
	"beer_baron": "Пивной Барон",
	"junk_overlord": "Король Хлама",
	"electric_shaman": "Шаман-Электрик",
	"pig_magnate": "Свинья-Магнат",
	"mud_magnate": "Грязный Магнат",
}

var _status: Label
var _reset_armed := false
var _list: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	super("Я ТЕСТЕР")


func _refresh() -> void:
	var keep := content.get_child(0)
	var scroll_pos := 0
	if _scroll != null and is_instance_valid(_scroll):
		scroll_pos = _scroll.scroll_vertical
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	_reset_armed = false
	_status = UiStyle.label("", 22, UiStyle.NEON, 5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	content.add_child(_status)
	_status.text = "Монет: %d · Неонита: %d · Уровень: %d" % [SaveService.get_coins(), SaveService.get_gems(), SaveService.get_account_level()]
	_list = MenuPopups.scroll_list(content)
	_scroll = _list.get_parent().get_parent() as ScrollContainer
	_restore_scroll.call_deferred(scroll_pos)

	_section("ВЫДАЧА")
	var grid := _grid()
	_action(grid, "+100 000 монет", func() -> String:
		Tester.give_coins(100000)
		return "Выдано 100 000 монет")
	_action(grid, "+2 000 неонита", func() -> String:
		Tester.give_gems(2000)
		return "Выдано 2 000 неонита")
	_action(grid, "Всё оружие (макс)", func() -> String:
		return "Оружия T5 выдано: %d" % Tester.give_all_weapons(true))
	_action(grid, "Все герои и скины", func() -> String:
		Tester.give_all_looks()
		return "Открыты все герои и скины")
	_action(grid, "Прокачка на макс", func() -> String:
		Tester.max_perks()
		return "Сила / Выносливость / Броня на максимуме")
	_list.add_child(grid)

	_section("СЮЖЕТ И РЕЖИМЫ")
	var story := _grid()
	var open := Tester.flag("survival_open")
	var open_button := UiStyle.button("Выживание: %s" % ("ОТКРЫТО" if open else "закрыто"), Color("#2fae5f") if open else UiStyle.PANEL_LIGHT, 21, Vector2(0, 62))
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(func() -> void:
		Tester.toggle("survival_open")
		changed.emit()
		_refresh())
	story.add_child(open_button)
	_action(story, "Засчитать миссию 1", func() -> String:
		SaveService.story_complete("m1", 1, 0)
		SaveService.add_stat("story_missions", 1, false)
		return "Миссия 1 засчитана, осколков: %d" % SaveService.story_shards())
	_action(story, "Показать мишень снова", func() -> String:
		SaveService.data["train_again"] = true
		SaveService.save_data()
		return "Мишень покажется при старте сюжета")
	_action(story, "Забыть диалоги сюжета", func() -> String:
		SaveService.data["story_log"] = {}
		SaveService.save_data()
		return "Журнал диалогов очищен")
	_list.add_child(story)

	_section("В БОЮ")
	for name in Tester.FLAGS:
		var on := Tester.flag(name)
		var button := UiStyle.button("%s: %s" % [Tester.FLAGS[name], "ВКЛ" if on else "выкл"], Color("#2fae5f") if on else UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
		button.pressed.connect(func() -> void:
			Tester.toggle(name)
			_refresh())
		_list.add_child(button)

	_section("СТАРТ БОЯ")
	var titles: Array = []
	for i in ContentDB.get_chapters().size():
		var def := ContentDB.get_chapter(i)
		titles.append("%s · %s" % [def.get("title", ""), str(def.get("subtitle", "")).get_slice("· ", 1)])
	var chapter_now := Tester.start_chapter()
	var wave_now := Tester.start_wave()
	var start := _grid()
	_action(start, "Биом: %s" % titles[chapter_now], func() -> String:
		Tester.set_start((chapter_now + 1) % titles.size(), wave_now)
		return "Старт с биома: %s" % titles[Tester.start_chapter()])
	_action(start, "Волна: %d из %d" % [wave_now, WaveDirector.WAVES_PER_CHAPTER], func() -> String:
		Tester.set_start(chapter_now, wave_now % WaveDirector.WAVES_PER_CHAPTER + 1)
		return "Старт с волны %d" % Tester.start_wave())
	_list.add_child(start)
	_list.add_child(UiStyle.label("Сразу к боссу:", 20, UiStyle.TEXT_DIM, 4))
	var bosses := _grid()
	for entry in _boss_fights():
		var chosen := chapter_now == int(entry["chapter"]) and wave_now == int(entry["wave"])
		var label := "%s%s" % ["> " if chosen else "", entry["title"]]
		_action(bosses, label, func() -> String:
			Tester.set_start(int(entry["chapter"]), int(entry["wave"]))
			return "Следующий бой: %s" % entry["title"])
	_action(bosses, "Обычный старт", func() -> String:
		Tester.set_start(0, 1)
		return "Старт с 1-й волны 1-й главы")
	_list.add_child(bosses)

	_section("СБРОС ЛИМИТОВ")
	var resets := _grid()
	_action(resets, "Реклама: сбросить лимиты", func() -> String:
		Tester.reset_ads()
		return "Лимиты рекламы обнулены")
	_action(resets, "Бесплатный сундук готов", func() -> String:
		Tester.reset_chest_timer()
		return "Бесплатный сундук снова доступен")
	_action(resets, "Подарок: забрать снова", func() -> String:
		Tester.reset_daily()
		return "Ежедневный подарок снова доступен")
	_list.add_child(resets)

	_section("ОПАСНО")
	var reset := UiStyle.button("Сбросить сохранение", Color("#a3283e"), 22, Vector2(0, 58))
	reset.pressed.connect(func() -> void:
		if not _reset_armed:
			_reset_armed = true
			reset.text = "Точно? Нажми ещё раз"
			return
		Tester.reset_save()
		changed.emit()
		_refresh()
		_status.text = "Сохранение сброшено")
	_list.add_child(reset)


func _boss_fights() -> Array:
	var list: Array = []
	var seen := {}
	for i in ContentDB.get_chapters().size():
		var waves: Array = ContentDB.get_chapter(i).get("waves", [])
		for w in waves.size():
			var wave: Dictionary = waves[w]
			var id := str(wave.get("boss", wave.get("miniboss", "")))
			if id.is_empty() or seen.has(id):
				continue
			seen[id] = true
			list.append({"title": str(BOSS_NAMES.get(id, id)), "chapter": i, "wave": w + 1})
	return list


func _section(text: String) -> void:
	_list.add_child(UiStyle.label(text, 22, UiStyle.TEXT_DIM, 5))


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _action(grid: GridContainer, text: String, action: Callable) -> void:
	var button := UiStyle.button(text, UiStyle.PANEL_LIGHT, 21, Vector2(0, 62))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		var message: String = action.call()
		SoundManager.play(&"ui_confirm")
		changed.emit()
		_refresh()
		_status.text = message)
	grid.add_child(button)


func _restore_scroll(pos: int) -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = pos
