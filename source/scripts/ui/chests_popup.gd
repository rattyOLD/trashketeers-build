class_name ChestsPopup
extends GlassPopup
## Сундуки: три уровня, витрина дня, серия-гарантия, кнопки рекламы и раскрытие наград.

signal changed
signal odds_requested(chest_id: String)

var _list: VBoxContainer
var _balance: Label
var _pity: Label
var _pity_bar: ProgressBar
var _timer_label: Label
var _timer_bar: ProgressBar
var _tick := 0.0
var _busy := false


func _init() -> void:
	super("СУНДУКИ")
	set_frame("window_neon_gold_s")
	_balance = UiStyle.label("", 24, UiStyle.GOLD, 6)
	content.add_child(_balance)
	var pity_card := PanelContainer.new()
	pity_card.add_theme_stylebox_override("panel", UiStyle.card_box())
	var pity_box := VBoxContainer.new()
	pity_box.add_theme_constant_override("separation", 4)
	pity_card.add_child(pity_box)
	_pity = UiStyle.label("", 18, UiStyle.TEXT, 4)
	_pity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pity.custom_minimum_size = Vector2(10, 0)
	pity_box.add_child(_pity)
	_pity_bar = ProgressBar.new()
	_pity_bar.max_value = 1.0
	_pity_bar.show_percentage = false
	_pity_bar.custom_minimum_size = Vector2(0, 16)
	_pity_bar.add_theme_stylebox_override("background", UiStyle.box(Color("#15120f"), Color("#5a4630"), 2, 8))
	_pity_bar.add_theme_stylebox_override("fill", UiStyle.box(UiStyle.GOLD, UiStyle.GOLD, 0, 8))
	pity_box.add_child(_pity_bar)
	content.add_child(pity_card)
	_list = MenuPopups.scroll_list(content)


func _process(delta: float) -> void:
	super._process(delta)
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	if _timer_label != null and is_instance_valid(_timer_label):
		_update_timer()


func _update_timer() -> void:
	var wait := Economy.ad_chest_wait()
	var total := maxi(Premium.chest_cooldown(), 1)
	if wait <= 0:
		_timer_label.text = "Готов! Забирай"
		_timer_bar.value = 1.0
		return
	_timer_label.text = "Следующий через %d:%02d:%02d" % [wait / 3600, (wait % 3600) / 60, wait % 60]
	_timer_bar.value = 1.0 - float(wait) / float(total)


func _refresh() -> void:
	_balance.text = "%s · %s" % [SaveService.format_coins(SaveService.get_coins()), Economy.format_gems(SaveService.get_gems())]
	var left := maxi(Economy.PITY_GUARANTEE - Economy.pity(), 0)
	_pity.text = "ГАРАНТИЯ: %d/%d. Через %d открытий выпадет герой или эпик/легендарка" % [Economy.pity(), Economy.PITY_GUARANTEE, left]
	_pity_bar.value = float(Economy.pity()) / float(Economy.PITY_GUARANTEE)
	MenuPopups.clear(_list)
	_list.add_child(_make_ad_chest())
	_list.add_child(_make_ads())
	_list.add_child(UiStyle.label("СУНДУКИ ЗА МОНЕТЫ", 22, UiStyle.GOLD, 6))
	for chest_id in Economy.CHEST_ORDER:
		_list.add_child(_make_chest(chest_id))


func _make_chest(chest_id: String) -> Control:
	var chest: Dictionary = Economy.CHESTS[chest_id]
	var color: Color = chest["color"]
	var panel := PanelContainer.new()
	# Рамка — общая янтарная с оттенком редкости; цвет редкости — в названии.
	panel.add_theme_stylebox_override("panel", UiStyle.card_box(color.lerp(UiStyle.CARD_BORDER, 0.45)))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	# Сундуки из одного рисованного набора с бесплатным (assets/ui/chests/<редкость>.png).
	icon.texture = ArenaProp.texture_of("res://assets/ui/chests/%s.png" % chest_id)
	icon.custom_minimum_size = Vector2(96, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UiStyle.label(str(chest["title"]).to_upper(), 28, color, 7)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_box.add_child(title)
	if chest_id == Economy.daily_chest():
		var deal := UiStyle.label("СУНДУК ДНЯ · -%d%%" % roundi(Economy.DAILY_DISCOUNT * 100.0), 22, UiStyle.GOLD, 6)
		deal.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title_box.add_child(deal)
	head.add_child(title_box)
	var odds := UiStyle.button("ШАНСЫ", UiStyle.PANEL, 18, Vector2(110, 56))
	odds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	odds.pressed.connect(func() -> void: odds_requested.emit(chest_id))
	head.add_child(odds)
	column.add_child(head)
	var info := UiStyle.label("Наград: %d · предмет %d%%" % [int(chest["rolls"]), roundi(Economy.item_chance(chest_id) * 100.0)], 19, UiStyle.TEXT, 4)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(info)
	var names: Array[String] = []
	for key in Economy.featured(chest_id):
		names.append(Economy.item_title(key))
	var shelf := UiStyle.label("Витрина: " + ", ".join(names), 18, UiStyle.TEXT_DIM, 4)
	shelf.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shelf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shelf.custom_minimum_size = Vector2(10, 0)
	shelf.clip_text = false
	column.add_child(shelf)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var coins_ok := Economy.can_afford(chest_id, false)
	var coin_button := UiStyle.button("%s" % SaveService.format_coins(Economy.chest_price(chest_id, false)), Color("#e0a020") if coins_ok else UiStyle.PANEL, 21, Vector2(0, 58))
	coin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_button.disabled = not coins_ok
	coin_button.pressed.connect(func() -> void: _open(chest_id, false))
	row.add_child(coin_button)
	if int(chest["gems"]) > 0:
		var gems_ok := Economy.can_afford(chest_id, true)
		var gem_button := UiStyle.button(Economy.format_gems(Economy.chest_price(chest_id, true)), Color("#9b5cff") if gems_ok else UiStyle.PANEL, 21, Vector2(0, 58))
		gem_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gem_button.disabled = not gems_ok
		gem_button.pressed.connect(func() -> void: _open(chest_id, true))
		row.add_child(gem_button)
	var price := Economy.chest_price(chest_id, false)
	var multi_row := HBoxContainer.new()
	multi_row.add_theme_constant_override("separation", 8)
	column.add_child(multi_row)
	for count: int in [5, 10]:
		var affordable: bool = SaveService.get_coins() >= price * count
		var multi := UiStyle.button("×%d · %s" % [count, SaveService.format_coins(price * count)], Color("#c98a1a") if affordable else UiStyle.PANEL, 17, Vector2(0, 46))
		multi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		multi.disabled = not affordable
		multi.pressed.connect(func() -> void: _open_many(chest_id, count))
		multi_row.add_child(multi)
	return panel


func _make_ad_chest() -> Control:
	var wait := Economy.ad_chest_wait()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card_box(Color("#4fbf6a")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = ArenaProp.texture_of("res://assets/ui/hub/chest_free.png")
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 3)
	row.add_child(texts)
	var head := UiStyle.label("БЕСПЛАТНЫЙ СУНДУК", 20, UiStyle.GOLD, 5)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(head)
	_timer_label = UiStyle.label("", 16, Color("#9be8b4"), 4)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(_timer_label)
	_timer_bar = ProgressBar.new()
	_timer_bar.max_value = 1.0
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 10)
	_timer_bar.add_theme_stylebox_override("background", UiStyle.box(Color("#15120f"), Color("#5a4630"), 2, 5))
	_timer_bar.add_theme_stylebox_override("fill", UiStyle.box(Color("#4fbf6a"), Color("#4fbf6a"), 0, 5))
	texts.add_child(_timer_bar)
	_update_timer()
	var take := UiStyle.button("ЗАБРАТЬ", Color("#2fae5f") if wait <= 0 else UiStyle.PANEL, 17, Vector2(104, 54))
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	take.disabled = wait > 0
	take.pressed.connect(func() -> void:
		Platform.show_rewarded_ad(func(ok: bool) -> void:
			if not ok:
				return
			var rewards := Economy.open_ad_chest()
			if rewards.is_empty():
				return
			_show_reveal(rewards, Premium.chest_tier())))
	row.add_child(take)
	return panel


## Реклама за валюту: две спокойные плашки в ряд, без тикетов и бейджей.
func _make_ads() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for kind in ["coins", "gems"]:
		var left := Economy.ads_left(kind)
		var color := Color("#e0a020") if kind == "coins" else Color("#9b5cff")
		var title := "+%s" % SaveService.format_coins(Economy.AD_COINS) if kind == "coins" else "+1-5 НЕОНИТА"
		# Одна строка по центру: что даёт и сколько осталось; шрифт ужимается по ширине.
		var button := UiStyle.button("%s · %s" % [title, ("ещё %d" % left) if left > 0 else "завтра"], color if left > 0 else UiStyle.PANEL, 19, Vector2(0, 56))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = left <= 0
		button.icon = BattlePanels.icon("ad")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
		button.resized.connect(func() -> void: UiStyle.fit_button_font(button, 19, button.size.x - 90.0))
		button.pressed.connect(func() -> void:
			Platform.show_rewarded_ad(func(ok: bool) -> void:
				if not ok:
					return
				var amount := Economy.claim_ad(kind)
				if amount > 0:
					SoundManager.play(&"star_dust")
					changed.emit()
					_refresh()))
		row.add_child(button)
	return row


func _open(chest_id: String, with_gems: bool) -> void:
	if _busy:
		return
	var rewards := Economy.open_chest(chest_id, with_gems)
	if rewards.is_empty():
		return
	_show_reveal(rewards, chest_id)


func _open_many(chest_id: String, count: int) -> void:
	if _busy:
		return
	var all: Array[Dictionary] = []
	for i in count:
		var rewards := Economy.open_chest(chest_id, false)
		if rewards.is_empty():
			break
		all.append_array(rewards)
	if all.is_empty():
		return
	_show_reveal(all, chest_id)


func _show_reveal(rewards: Array[Dictionary], chest_id: String) -> void:
	_busy = true
	changed.emit()
	var reveal := ChestReveal.new(rewards, chest_id, Economy.CHESTS[chest_id]["color"], str(Economy.CHESTS[chest_id]["title"]))
	add_child(reveal)
	reveal.finished.connect(func() -> void:
		_busy = false
		changed.emit()
		_refresh())
