class_name ObjectsIntroPopup
extends GlassPopup
## Короткое обучение перед Выживанием: что делает каждый объект на карте (вышка, сейф, касса, пылесос…).
## Листается по одной «фотокарточке» с рисунком Астры и двумя строками. Показывается перед забегом только
## два раза на аккаунт (счётчик objects_intro_count), потом — никогда; кнопкой «ПРОПУСТИТЬ» можно сразу в бой.

signal finished

const SHOWS := 2
## [скрин из игры (assets/ui/intro/<id>.jpg), рисунок-запаска, кадров в листе, заголовок, что делает, как пользоваться]
const PAGES := [
	["tower", "res://assets/world/charge_tower.png", 0, "ВЫШКА-РЕТРАНСЛЯТОР", "Даёт прошивку на выбор: урон, темп, крит, броня и другие.", "Стой в синем круге 5 секунд — вышка зарядится. Вышел — заряд тает."],
	["safe", "res://assets/world/junk_safe.png", 0, "СЕЙФ ХЛАМА", "Внутри предмет на выбор, редкость тянет Удача.", "Подойди и постой — откроется за гайки. Каждый следующий дороже."],
	["vacuum", "res://assets/world/vacuum.png", 0, "ПЫЛЕСОС", "Собирает весь опыт и монеты с карты к тебе.", "Постой рядом секунду. Сработает один раз — береги на потом."],
	["greed", "res://assets/world/greed_register.png", 0, "КАССА ЖАДНОСТИ", "+30% гаек до конца главы, но враги крепче.", "Постой рядом 2 секунды. Бери, если уверен в своей сборке."],
	["ring", "res://assets/world/ring.png", 0, "РИНГ", "Вызывает волну элиты. Победил — награда редкой карточкой.", "Встань в ринг и держись. Опасно, но выгодно."],
	["altar", "res://assets/world/altar.png", 0, "МУСОРНЫЙ АЛТАРЬ", "Призывает босса раньше времени — награда выше.", "Постой 3 секунды. Только если готов к бою с боссом."],
	["dealer", "res://assets/world/fence_dealer/idle.png", 4, "БАРЫГА ШНЫРЬ", "Продаёт три карточки за гайки.", "Подойди — выбери одну или уйди ни с чем."],
	["", "res://assets/world/siren.png", 0, "СИРЕНА СМЕНЫ", "Таймер «СМЕНА» вверху: когда выйдет, босс придёт сам.", "Успей обойти вышки и сейфы до сирены."],
]

var _page := 0
var _picture: TextureRect
var _heading: Label
var _what: Label
var _how: Label
var _dots: Label
var _next: Button


## Нужно ли показать перед этим забегом (и сразу отмечает показ).
static func should_show() -> bool:
	return int(SaveService.data.get("objects_intro_count", 0)) < SHOWS


func _init() -> void:
	super("ЧТО ЕСТЬ НА КАРТЕ")
	var photo := PanelContainer.new()
	photo.add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.GOLD.darkened(0.2), 4))
	photo.custom_minimum_size = Vector2(0, 250)
	content.add_child(photo)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.custom_minimum_size = Vector2(0, 236)
	photo.add_child(_picture)
	_heading = UiStyle.label("", 28, UiStyle.GOLD, 7)
	content.add_child(_heading)
	_what = _line(UiStyle.TEXT, 20)
	content.add_child(_what)
	_how = _line(Color("#9be8b4"), 18)
	content.add_child(_how)
	_dots = UiStyle.label("", 18, UiStyle.TEXT_DIM, 3)
	content.add_child(_dots)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var skip := UiStyle.button("ПРОПУСТИТЬ", UiStyle.PANEL, 22, Vector2(0, 64))
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip.pressed.connect(_done)
	row.add_child(skip)
	_next = UiStyle.button("ДАЛЕЕ", Color("#2fae5f"), 24, Vector2(0, 64))
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.pressed.connect(func() -> void:
		if _page >= PAGES.size() - 1:
			_done()
		else:
			_page += 1
			_show_page())
	row.add_child(_next)


func open() -> void:
	SaveService.data["objects_intro_count"] = int(SaveService.data.get("objects_intro_count", 0)) + 1
	SaveService.save_data()
	_page = 0
	super.open()
	_show_page()


func _show_page() -> void:
	var page: Array = PAGES[_page]
	# Скриншот объекта прямо из игры (герой рядом, видно круг и подпись); нет скрина — рисунок Астры.
	var shot := "res://assets/ui/intro/%s.jpg" % page[0]
	var tex: Texture2D = load(shot) if not str(page[0]).is_empty() and ResourceLoader.exists(shot) else null
	if tex == null:
		tex = load(str(page[1])) as Texture2D
		if tex != null and int(page[2]) > 0:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			var cell := tex.get_width() / int(page[2])
			atlas.region = Rect2(0, 0, cell, cell)
			tex = atlas
	_picture.texture = tex
	_heading.text = str(page[3])
	_what.text = str(page[4])
	_how.text = str(page[5])
	var dots := ""
	for i in PAGES.size():
		dots += "●" if i == _page else "○"
	_dots.text = dots
	_next.text = "В БОЙ!" if _page >= PAGES.size() - 1 else "ДАЛЕЕ"


func _done() -> void:
	close()
	finished.emit()


func _line(color: Color, font_size: int) -> Label:
	var label := UiStyle.label("", font_size, color, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(panel_width() - 70.0, 0)
	return label
