class_name CampPopup
extends GlassPopup
## Лагерь перед сюжетной миссией: два торговца продают расходники на одну миссию.
## Покупки лежат в SaveService.data["camp_pack"] и сгорают при старте миссии.

signal departed

const TRADERS := {
	"nell": {"name": "НЭЛЛ", "role": "Снабжение", "color": "#ffac56", "portrait": "res://assets/story/portraits/nell.png",
		"quote": "Всё по описи. Чай не продаётся. Он остыл."},
	"monya": {"name": "КРОТ МОНЯ", "role": "Барыга с лопатой", "color": "#ffb347", "portrait": "",
		"quote": "Не спрашивай, откуда. Спрашивай, сколько."},
}
const ITEMS: Array[Dictionary] = [
	{"id": "vest", "trader": "nell", "title": "Бронежилет", "desc": "Гасит одно попадание целиком.", "cost": 300},
	{"id": "thermos", "trader": "nell", "title": "Термос", "desc": "+40% к здоровью на миссию.", "cost": 250},
	{"id": "shotgun", "trader": "monya", "title": "Бабах «Дед»", "desc": "Стартовый ствол миссии: дробовик вместо пистолета.", "cost": 500},
	{"id": "whetstone", "trader": "monya", "title": "Точило", "desc": "+20% урона на миссию.", "cost": 400},
]

var _balance: Label
var _list: VBoxContainer
var _resume: Button
var _cat_face: TextureRect
var _cat_line: Label
var _cat_sticker: TextureRect
var _pet_times: Array[float] = []
var _pet_token := 0

const MOSYA_FRAMES := "res://assets/ui/mosya/mosya_frames.png"
const MOSYA_LINES: Array[String] = ["мур", "мррр", "мур-мур", "мрр, ещё", "мяу", "мррр-мяу"]


func _init() -> void:
	super("ЛАГЕРЬ")
	_balance = UiStyle.label("", 26, UiStyle.GOLD, 6)
	content.add_child(_balance)
	var note := UiStyle.label("Покупки действуют одну миссию и сгорают на старте.", 19, UiStyle.TEXT_DIM, 4)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	content.add_child(note)
	content.add_child(_online_plate())
	_list = MenuPopups.scroll_list(content)
	_resume = UiStyle.button("ПРОДОЛЖИТЬ С ЧЕКПОИНТА", Color("#1d8fb0"), 26, Vector2(0, 70))
	_resume.pressed.connect(func() -> void:
		SaveService.resume_requested = true
		close()
		departed.emit())
	content.add_child(_resume)
	var go := UiStyle.button("В ПУТЬ", Color("#2fae5f"), 30, Vector2(0, 76))
	go.pressed.connect(func() -> void:
		SaveService.resume_requested = false
		close()
		departed.emit())
	content.add_child(go)


## Плашка-крючок: история продолжится в онлайне (Реестр не закрыт). Пока только анонс.
func _online_plate() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.14, 0.07, 0.24, 0.95), Color("#ffc487"), 4, 18))
	var label := UiStyle.label("Продолжи свою историю в онлайне: Сервер Аквилона ещё не вскрыт, остался Директор.", 19, Color("#e9d6ff"), 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 0)
	panel.add_child(label)
	return panel


func _refresh() -> void:
	_balance.text = "Баланс: " + SaveService.format_coins(SaveService.get_nuts())
	var resume := SaveService.story_resume(StoryRun.next_mission_id())
	_resume.visible = not resume.is_empty()
	if not resume.is_empty():
		_resume.text = ("ПРОДОЛЖИТЬ: У ДВЕРИ БОССА · ЖИЗНИ %d" % int(resume.get("lives", 3))) if bool(resume.get("boss_door", false)) else ("ПРОДОЛЖИТЬ: ЗОНА %d · ЖИЗНИ %d" % [int(resume.get("zone", 0)) + 1, int(resume.get("lives", 3))])
	MenuPopups.clear(_list)
	for trader_id in TRADERS:
		_list.add_child(_trader_card(trader_id))


func _trader_card(trader_id: String) -> Control:
	var info: Dictionary = TRADERS[trader_id]
	var color := Color(str(info["color"]))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, color, 4, 20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(84, 84)
	frame.add_theme_stylebox_override("panel", UiStyle.box(color.darkened(0.7), color, 3, 42))
	head.add_child(frame)
	var path := str(info["portrait"])
	if path.is_empty():
		var glyph := UiStyle.label("М", 44, color, 6)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(glyph)
	else:
		var face := TextureRect.new()
		face.texture = load(path) as Texture2D
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(face)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var title := UiStyle.label("%s · %s" % [info["name"], info["role"]], 24, color, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(title)
	var quote := UiStyle.label("«%s»" % info["quote"], 18, color.lightened(0.25), 4)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(quote)
	for item in ITEMS:
		if str(item["trader"]) == trader_id:
			column.add_child(_item_row(item, color))
	return panel


func _item_row(item: Dictionary, color: Color) -> Control:
	var id := str(item["id"])
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var desc := UiStyle.label("%s: %s" % [item["title"], item["desc"]], 19, UiStyle.TEXT, 4)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)
	var cost := int(item["cost"])
	var taken := SaveService.camp_has(id)
	var buy: Button
	if taken:
		buy = UiStyle.button("ВЗЯТО (вернуть: +%s)" % SaveService.format_coins(cost), UiStyle.PANEL, 21, Vector2(0, 58))
		buy.pressed.connect(func() -> void:
			SaveService.camp_refund(id, cost)
			_refresh())
	else:
		buy = UiStyle.button("Купить · %s" % SaveService.format_coins(cost), color.darkened(0.45), 22, Vector2(0, 58))
		buy.disabled = SaveService.get_nuts() < cost
		buy.pressed.connect(func() -> void:
			if SaveService.camp_buy(id, cost):
				SoundManager.play(&"merge", 0.0, false)
				_refresh())
	row.add_child(buy)
	return row


## Мася, кот Рико: гладится в лагере. Закрывает глаза, мурчит. Если тыкать слишком быстро, сердится.
func _cat_frame(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(MOSYA_FRAMES) as Texture2D
	atlas.region = Rect2(index * 192, 0, 192, 256)
	return atlas


func _mosya_card() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_cat_face = TextureRect.new()
	_cat_face.custom_minimum_size = Vector2(120, 160)
	_cat_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cat_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cat_face.texture = _cat_frame(0)
	row.add_child(_cat_face)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	column.add_child(UiStyle.label("МОСЯ · кот Рико", 24, Color("#ffd257"), 5))
	_cat_line = UiStyle.label("Не спрашивай, откуда в лагере кот.", 18, UiStyle.TEXT_DIM, 4)
	_cat_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cat_line.custom_minimum_size = Vector2(300, 0)
	column.add_child(_cat_line)
	var pet := UiStyle.button("ПОГЛАДИТЬ", Color("#c86600"), 24, Vector2(0, 60))
	pet.pressed.connect(_pet_mosya)
	column.add_child(pet)
	_cat_sticker = TextureRect.new()
	_cat_sticker.custom_minimum_size = Vector2(110, 110)
	_cat_sticker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cat_sticker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cat_sticker.modulate.a = 0.0
	row.add_child(_cat_sticker)
	return row


func _pet_mosya() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_pet_times.append(now)
	while not _pet_times.is_empty() and now - _pet_times[0] > 3.0:
		_pet_times.pop_front()
	SaveService.add_stat("mosya_pets", 1, false)
	_pet_token += 1
	var token := _pet_token
	SoundManager.play(&"ui_confirm")
	if _pet_times.size() >= 7:
		_cat_face.texture = load("res://assets/ui/stickers/mosya_angry.png") as Texture2D
		_cat_line.text = "Мася: ФШШ. Хватит. Дай подышать."
		_show_cat_sticker("mosya_angry")
		_pet_times.clear()
	else:
		_cat_face.texture = _cat_frame(3)
		var total := SaveService.get_stat("mosya_pets")
		_cat_line.text = "%s  (погладил %d)" % [MOSYA_LINES[total % MOSYA_LINES.size()], total]
		if total % 10 == 0:
			_show_cat_sticker("mosya_meow")
	await get_tree().create_timer(0.8).timeout
	if token == _pet_token and is_instance_valid(_cat_face):
		_cat_face.texture = _cat_frame(0)


func _show_cat_sticker(id: String) -> void:
	_cat_sticker.texture = load("res://assets/ui/stickers/%s.png" % id) as Texture2D
	_cat_sticker.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(_cat_sticker, "modulate:a", 0.0, 0.5)
