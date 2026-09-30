class_name VipPopup
extends GlassPopup
## VIP: пять уровней на 30 дней, доплата поднимает уровень; отдельно - навсегда убрать рекламу после боссов.

signal changed

var _status: Label
var _list: VBoxContainer


func _init() -> void:
	super("VIP")
	_status = UiStyle.label("", 22, UiStyle.GOLD, 6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	content.add_child(_status)
	var gift := GiftBox.new("vip")
	gift.claimed.connect(func() -> void: changed.emit())
	content.add_child(gift)
	_list = MenuPopups.scroll_list(content)


func _refresh() -> void:
	var current := Premium.level()
	if current > 0:
		_status.text = "VIP %d · осталось дней: %d" % [current, Premium.days_left()]
	else:
		_status.text = "VIP не активен. Бонусы ускоряют прогресс, силу в бою не дают."
	MenuPopups.clear(_list)
	if not Premium.ads_removed():
		_list.add_child(_no_ads_card())
	for entry in Premium.VIP_LEVELS:
		_list.add_child(_level_card(entry as Dictionary, current))


func _no_ads_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color("#5be37d"), 4, 20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(UiStyle.label("БЕЗ РЕКЛАМЫ", 28, Color("#5be37d"), 7))
	column.add_child(_line("Навсегда убирает рекламу после боссов. Реклама за награду остаётся - она только в плюс."))
	var buy := UiStyle.button("КУПИТЬ · %s" % Premium.price_text(Premium.NO_ADS_PRICE), Color("#2fae5f"), 24, Vector2(0, 68))
	buy.pressed.connect(func() -> void:
		Premium.buy_no_ads()
		_done("Реклама после боссов отключена"))
	column.add_child(buy)
	return panel


func _level_card(entry: Dictionary, current: int) -> Control:
	var level := int(entry["level"])
	var color := entry["color"] as Color
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, color if level >= current else color.darkened(0.5), 5 if level == current else 3, 20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(UiStyle.label("VIP %d" % level, 30, color, 7))
	for perk in entry["perks"]:
		column.add_child(_line("+ " + str(perk)))
	var button: Button
	if current > 0 and level < current:
		button = UiStyle.button("ВХОДИТ В ТВОЙ VIP %d" % current, UiStyle.PANEL, 20, Vector2(0, 60))
		button.disabled = true
	else:
		var verb := "ПРОДЛИТЬ" if level == current else ("ДОПЛАТИТЬ" if current > 0 else "КУПИТЬ")
		button = UiStyle.button("%s · %s" % [verb, Premium.price_text(Premium.cost_for(level))], color.darkened(0.3), 24, Vector2(0, 68))
		button.pressed.connect(func() -> void:
			Premium.buy_vip(level)
			_done("VIP %d активен на %d дней" % [level, Premium.VIP_DAYS]))
	column.add_child(button)
	return panel


func _line(text: String) -> Label:
	var label := UiStyle.label(text, 19, UiStyle.TEXT, 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 0)
	return label


func _done(message: String) -> void:
	SoundManager.play(&"star_dust")
	changed.emit()
	_refresh()
	_status.text = message + ("" if Premium.PAYMENTS_LIVE else " (оплата отключена, тестовая выдача)")
