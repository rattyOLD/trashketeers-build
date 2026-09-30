class_name ChroniclePopup
extends GlassPopup
## «Летопись»: короткие записи о мире, открываются по мере прогресса. Закрытые показывают «???» и подсказку.

var _list: VBoxContainer
var _counter: Label


func _init() -> void:
	super("ЛЕТОПИСЬ")
	_counter = UiStyle.label("", 24, UiStyle.GOLD, 6)
	content.add_child(_counter)
	_list = MenuPopups.scroll_list(content)


static func _stat(key: String) -> int:
	return int(SaveService.data.get(key, 0))


static func entries() -> Array:
	return [
		{"title": "Неон-Сити", "hint": "Сыграй свой первый забег",
			"text": "Город утонул в мусоре, а мусор начал светиться. Звери от него умнеют, звереют и жаднеют. Кто-то же должен это разгребать. Спойлер: вы.",
			"open": _stat("runs") >= 1},
		{"title": "Мусорщики", "hint": "Сыграй 5 забегов",
			"text": "Trashketeers — последние, кто ещё убирает город. Работа грязная, зарплата в орехах, зато трофеи можно оставлять себе.",
			"open": _stat("runs") >= 5},
		{"title": "Крысиные банды", "hint": "Дойди до 5-й волны",
			"text": "Скрэппи, Токсичные и техно-крысы делят свалку и не делят вообще ничего друг с другом. Объединяет их одно: ненависть к енотам.",
			"open": _stat("best_wave") >= 5},
		{"title": "Пивной Барон", "hint": "Дойди до 10-й волны",
			"text": "Хозяин единственного работающего бара на свалке. Пивной бак на спине качает жижу под давлением. Пьёт всегда за чужой счёт, а расплачивается рвотой.",
			"open": _stat("best_wave") >= 10},
		{"title": "Король Хлама", "hint": "Победи Короля Хлама",
			"text": "Крыса на троне из колонок и ржавых тазов. Коллекционировал всё, что плохо лежит, и считал город своей коллекцией. Теперь коллекция без короля.",
			"open": _stat("boss_kills") >= 1},
		{"title": "Золотой Банк", "hint": "Дойди до 20-й волны",
			"text": "Пока крысы дрались за свалку, свиньи тихо скупили всё остальное. Бекон-охрана, сейфоломы, крупье. Улыбаются только на камеру.",
			"open": _stat("best_wave") >= 20},
		{"title": "Налоги свиной деревни", "hint": "Дойди до 30-й волны",
			"text": "Когда-то Крестный Голубь сбил налоги с деревни свиней. Народ рад, банкиры в ярости, и с тех пор в биоме свиней его недолюбливают. Голубь считает, что это была акция лояльности.",
			"open": _stat("best_wave") >= 30 or SaveService.owns_character("pigeon_mafioso")},
		{"title": "Экзокостюм", "hint": "Открой Рыжую Панду",
			"text": "Бывший инженер-пиротехник собрал костюм из обломков реактора. Инструкции не было, поэтому он иногда искрит. Все считают это фишкой.",
			"open": SaveService.owns_character("red_panda")},
		{"title": "Мерзлота", "hint": "Открой Белого Енота",
			"text": "Под старым холодильным заводом вечная зима. Тот, кто вышел оттуда, не торопится никогда и никуда. Враги, кстати, тоже.",
			"open": SaveService.owns_character("snow")},
		{"title": "Тень на асфальте", "hint": "Открой Ночного Енота",
			"text": "Чёрный как мокрый асфальт. Крысы клянутся, что он был в двух местах сразу. Он клянётся, что просто быстро бегает.",
			"open": SaveService.owns_character("night")},
		{"title": "Ховер-рельса", "hint": "Открой Неонового Кролика",
			"text": "Три подпольные гонки, три победы, ноль тормозов. Кролик не умеет стоять на месте, и это не метафора, а диагноз его сапог.",
			"open": SaveService.owns_character("neon_hopper")},
		{"title": "Слишком яркие опыты", "hint": "Открой Кота-химика",
			"text": "Из лаборатории его выгнали за яркость экспериментов. Он не обиделся, а забрал баллон с зелёной жижей и открыл собственную лабораторию, на свалке.",
			"open": SaveService.owns_character("fluffy_chemist")},
		{"title": "Небесный босс", "hint": "Открой Крестного Голубя",
			"text": "Пригородные крыши давно принадлежат ему. Томми-ган, шляпа и лёгкое презрение к любой земной юрисдикции.",
			"open": SaveService.owns_character("pigeon_mafioso")},
		{"title": "Ледяной налёт", "hint": "Сыграй 10 забегов",
			"text": "Дракон Хладгор много лет спит подо льдом озера. Когда просыпается, озеро трещит, а у Мусорщиков холодеют лапки. Термос с чаем рекомендуется.",
			"open": _stat("runs") >= 10 or _stat("raid_wins") >= 1},
		{"title": "Хозяин озера", "hint": "Победи Хладгора",
			"text": "Он не злой, просто ему тесно в собственной вечной мерзлоте. Теперь озеро тихо, а лёд держит. Пока.",
			"open": _stat("raid_wins") >= 1},
		{"title": "Горизонт", "hint": "Сыграй 25 забегов",
			"text": "Мусорщики знают: город лучше всего смотрится в ширину. Поэтому телефон держат боком, а на вертикаль смотрят с уважением.",
			"open": _stat("runs") >= 25},
	]


func _refresh() -> void:
	MenuPopups.clear(_list)
	var all := entries()
	var opened := 0
	for entry in all:
		var e := entry as Dictionary
		var is_open: bool = e["open"]
		if is_open:
			opened += 1
		_list.add_child(_make_entry(e, is_open))
	_counter.text = "Записей: %d / %d" % [opened, all.size()]


func _make_entry(entry: Dictionary, is_open: bool) -> Control:
	var panel := PanelContainer.new()
	var border := UiStyle.OUTLINE if is_open else Color(UiStyle.TEXT_DIM, 0.4)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT if is_open else UiStyle.PANEL, border, 3, 20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := UiStyle.label(str(entry["title"]) if is_open else "???", 26, UiStyle.GOLD if is_open else UiStyle.TEXT_DIM, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)
	var body := UiStyle.label(str(entry["text"]) if is_open else "Откроется: " + str(entry["hint"]), 19, UiStyle.TEXT if is_open else UiStyle.TEXT_DIM, 4)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	column.add_child(body)
	return panel
