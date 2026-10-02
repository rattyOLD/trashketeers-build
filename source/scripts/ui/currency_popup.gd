class_name CurrencyPopup
extends GlassPopup
## Пополнение валюты по тапу на монеты/неонит в шапке: реклама + 6 пакетов.
## Неонит продаётся за деньги, монеты - за неонит.

signal changed

const GEM_PACKS := [
	{"gems": 80, "price": "$0.99", "tag": ""},
	{"gems": 170, "price": "$1.99", "tag": "+6%"},
	{"gems": 450, "price": "$4.99", "tag": "ПОПУЛЯРНО"},
	{"gems": 950, "price": "$9.99", "tag": "+18%"},
	{"gems": 2000, "price": "$19.99", "tag": "+25%"},
	{"gems": 5500, "price": "$49.99", "tag": "ЛУЧШАЯ ЦЕНА"},
]
const COIN_PACKS := [
	{"coins": 800, "cost": 10, "tag": ""},
	{"coins": 2200, "cost": 25, "tag": "+10%"},
	{"coins": 5500, "cost": 55, "tag": "ПОПУЛЯРНО"},
	{"coins": 12000, "cost": 110, "tag": "+9%"},
	{"coins": 32000, "cost": 280, "tag": "+14%"},
	{"coins": 70000, "cost": 560, "tag": "ЛУЧШАЯ ЦЕНА"},
]
const STARTER := {"id": "starter", "gems": 300, "coins": 6000, "price": "$1.99"}
const GEM_COLOR := Color("#35c8ff")
const COIN_COLOR := Color("#e0a020")

var _kind := "gems"
var _tabs: HBoxContainer
var _body: VBoxContainer
var _status: Label


func _init() -> void:
	super("ПОПОЛНЕНИЕ")
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 10)
	content.add_child(_tabs)
	_status = UiStyle.label("", 20, UiStyle.TEXT_DIM, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(540, 0)
	content.add_child(_status)
	_body = MenuPopups.scroll_list(content)


func open_kind(kind: String) -> void:
	_kind = kind
	open()


func _refresh() -> void:
	MenuPopups.clear(_tabs)
	for kind in ["gems", "coins"]:
		var active: bool = kind == _kind
		var base: Color = (GEM_COLOR if kind == "gems" else COIN_COLOR) if active else UiStyle.PANEL_LIGHT
		var tab := UiStyle.button("НЕОНИТ" if kind == "gems" else "МОНЕТЫ", base, 26, Vector2(0, 70))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func() -> void:
			_kind = kind
			_status.text = ""
			_refresh())
		_tabs.add_child(tab)
	MenuPopups.clear(_body)
	if _kind == "gems" and not _bought(str(STARTER["id"])):
		_body.add_child(_make_starter())
	_body.add_child(_make_ad_row())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	var packs: Array = GEM_PACKS if _kind == "gems" else COIN_PACKS
	for i in packs.size():
		grid.add_child(_make_pack(i, packs[i] as Dictionary))
	if _status.text.is_empty():
		_status.text = "Неонит: %d  ·  Монеты: %d" % [SaveService.get_gems(), SaveService.get_coins()]


func _bought(id: String) -> bool:
	return (SaveService.data["iap_bought"] as Array).has(id)


func _mark_bought(id: String) -> void:
	if not _bought(id):
		(SaveService.data["iap_bought"] as Array).append(id)


func _make_starter() -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 150)
	button.focus_mode = Control.FOCUS_NONE
	var base := Color("#c9722b")
	button.add_theme_stylebox_override("normal", UiStyle.button_box(base, false))
	button.add_theme_stylebox_override("hover", UiStyle.button_box(base.lightened(0.06), false))
	button.add_theme_stylebox_override("pressed", UiStyle.button_box(base.lightened(0.1), true))
	button.pressed.connect(_buy_starter)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 10)
	button.add_child(row)
	for path in ["res://assets/ui/hub/neonite_pile.png", "res://assets/ui/hub/coins_pile.png"]:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = ArenaProp.texture_of(path)
		icon.custom_minimum_size = Vector2(84, 0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var title := UiStyle.label("СТАРТОВЫЙ НАБОР", 26, UiStyle.GOLD, 7)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)
	var body := UiStyle.label("%d неонита + %d монет" % [int(STARTER["gems"]), int(STARTER["coins"])], 22, UiStyle.TEXT, 5)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(body)
	var once := UiStyle.label("ОДИН РАЗ · %s" % str(STARTER["price"]), 22, Color("#5be37d"), 5)
	once.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(once)
	return button


func _buy_starter() -> void:
	SaveService.add_gems(int(STARTER["gems"]), false)
	SaveService.add_coins(int(STARTER["coins"]))
	_mark_bought(str(STARTER["id"]))
	SaveService.save_data()
	SoundManager.play(&"star_dust")
	_status.text = "Стартовый набор получен!"
	changed.emit()
	_refresh()


func _make_ad_row() -> Control:
	var left := Economy.ads_left(_kind)
	var amount: String = "+%d" % Economy.AD_COINS if _kind == "coins" else "1-5"
	var button := UiStyle.button("СМОТРЕТЬ РЕКЛАМУ  %s   (осталось %d)" % [amount, left] if left > 0 else "Реклама на сегодня закончилась", Color("#2fae5f"), 24, Vector2(0, 84))
	button.disabled = left <= 0
	button.pressed.connect(func() -> void:
		Platform.show_rewarded_ad(func(ok: bool) -> void:
			if not ok:
				return
			var got := Economy.claim_ad(_kind)
			if got > 0:
				SoundManager.play(&"star_dust")
				_status.text = "Получено: +%d" % got
				changed.emit()
				_refresh()))
	return button


func _make_pack(index: int, pack: Dictionary) -> Control:
	var gems: bool = _kind == "gems"
	var color: Color = GEM_COLOR if gems else COIN_COLOR
	var amount := int(pack["gems"]) if gems else int(pack["coins"])
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 210)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	var affordable: bool = gems or SaveService.get_gems() >= int(pack["cost"])
	var base: Color = color.darkened(0.35) if affordable else UiStyle.PANEL
	button.add_theme_stylebox_override("normal", UiStyle.button_box(base, false))
	button.add_theme_stylebox_override("hover", UiStyle.button_box(base.lightened(0.06), false))
	button.add_theme_stylebox_override("pressed", UiStyle.button_box(base.lightened(0.1), true))
	button.add_theme_stylebox_override("disabled", UiStyle.button_box(base, false))
	button.disabled = not affordable
	button.pressed.connect(_buy.bind(index))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	column.add_theme_constant_override("separation", 2)
	button.add_child(column)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = ArenaProp.texture_of("res://assets/ui/hub/neonite_pile.png" if gems else "res://assets/ui/hub/coins_pile.png")
	icon.custom_minimum_size = Vector2(0, 72 + index * 6)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(icon)
	var amount_label := UiStyle.label(str(amount), 30, UiStyle.TEXT, 6)
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount_label)
	var price_text := str(pack["price"]) if gems else "%d неонит" % int(pack["cost"])
	var price := UiStyle.label(price_text, 24, UiStyle.GOLD if gems else Color("#ffd3a6"), 5)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(price)
	var tag_text := str(pack["tag"])
	if gems and not _bought("gem_%d" % index):
		tag_text = "ПЕРВЫЙ РАЗ x2"
	if not tag_text.is_empty():
		var tag := UiStyle.label(tag_text, 16, Color("#5be37d"), 4)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(tag)
	return button


func _buy(index: int) -> void:
	if _kind == "gems":
		var pack: Dictionary = GEM_PACKS[index]
		var amount := int(pack["gems"]) * (1 if _bought("gem_%d" % index) else 2)
		_mark_bought("gem_%d" % index)
		SaveService.add_gems(amount)
		_status.text = "+%d неонита (оплата пока отключена, тестовая выдача)" % amount if not Premium.PAYMENTS_LIVE else "+%d неонита" % amount
	else:
		var pack: Dictionary = COIN_PACKS[index]
		if not SaveService.spend_gems(int(pack["cost"])):
			_status.text = "Не хватает неонита"
			return
		SaveService.add_coins(int(pack["coins"]))
		_status.text = "+%d монет" % int(pack["coins"])
	SoundManager.play(&"star_dust")
	changed.emit()
	_refresh()
