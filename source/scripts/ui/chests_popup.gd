class_name ChestsPopup
extends GlassPopup
## Сундуки: три уровня, витрина дня, серия-гарантия, кнопки рекламы и раскрытие наград.

signal changed
signal odds_requested(chest_id: String)

var _list: VBoxContainer
var _balance: Label
var _pity: Label
var _pity_bar: ProgressBar
var _busy := false


func _init() -> void:
	super("СУНДУКИ")
	_balance = UiStyle.label("", 24, UiStyle.GOLD, 6)
	content.add_child(_balance)
	_pity = UiStyle.label("", 19, UiStyle.TEXT_DIM, 4)
	_pity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pity.custom_minimum_size = Vector2(560, 0)
	content.add_child(_pity)
	_pity_bar = ProgressBar.new()
	_pity_bar.max_value = 1.0
	_pity_bar.show_percentage = false
	_pity_bar.custom_minimum_size = Vector2(0, 18)
	_pity_bar.add_theme_stylebox_override("background", UiStyle.box(Color("#1f1738"), Color("#3a2d60"), 2, 9))
	_pity_bar.add_theme_stylebox_override("fill", UiStyle.box(Color("#b34dff"), Color("#b34dff"), 0, 9))
	content.add_child(_pity_bar)
	_list = MenuPopups.scroll_list(content)


func _refresh() -> void:
	_balance.text = "%s · %s" % [SaveService.format_coins(SaveService.get_coins()), Economy.format_gems(SaveService.get_gems())]
	_pity.text = "До гарантии: %d/%d · герой или эпик/легендарка" % [Economy.pity(), Economy.PITY_GUARANTEE]
	_pity_bar.value = float(Economy.pity()) / float(Economy.PITY_GUARANTEE)
	MenuPopups.clear(_list)
	_list.add_child(UiStyle.label("БЕСПЛАТНО ЗА РЕКЛАМУ", 24, UiStyle.NEON, 6))
	_list.add_child(_make_ad_chest())
	_list.add_child(_make_ads())
	_list.add_child(UiStyle.label("СУНДУКИ ЗА МОНЕТЫ", 24, UiStyle.NEON, 6))
	for chest_id in Economy.CHEST_ORDER:
		_list.add_child(_make_chest(chest_id))


func _make_chest(chest_id: String) -> Control:
	var chest: Dictionary = Economy.CHESTS[chest_id]
	var color: Color = chest["color"]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, color, 5, 22))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = ArenaProp.texture_of("res://assets/ui/chests/chest_%s.png" % chest_id)
	icon.custom_minimum_size = Vector2(120, 88)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UiStyle.label(str(chest["title"]).to_upper(), 32, color, 8)
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
	var info := UiStyle.label("Наград: %d · шанс предмета %d%%" % [int(chest["rolls"]), roundi(Economy.item_chance(chest_id) * 100.0)], 20, UiStyle.TEXT, 5)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(info)
	var names: Array[String] = []
	for key in Economy.featured(chest_id):
		names.append(Economy.item_title(key))
	var shelf := UiStyle.label("Витрина: " + ", ".join(names), 18, UiStyle.TEXT_DIM, 4)
	shelf.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shelf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shelf.custom_minimum_size = Vector2(520, 0)
	column.add_child(shelf)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var coins_ok := Economy.can_afford(chest_id, false)
	var coin_button := UiStyle.button("ОТКРЫТЬ · %s" % SaveService.format_coins(Economy.chest_price(chest_id, false)), Color("#e0a020") if coins_ok else UiStyle.PANEL, 21, Vector2(0, 62))
	coin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_button.disabled = not coins_ok
	coin_button.pressed.connect(func() -> void: _open(chest_id, false))
	row.add_child(coin_button)
	var price := Economy.chest_price(chest_id, false)
	if SaveService.get_coins() >= price * 5:
		var multi := UiStyle.button("×5", Color("#c98a1a"), 21, Vector2(84, 62))
		multi.pressed.connect(func() -> void: _open_many(chest_id, 5))
		row.add_child(multi)
	if int(chest["gems"]) > 0:
		var gems_ok := Economy.can_afford(chest_id, true)
		var gem_button := UiStyle.button("ИЛИ · %s" % Economy.format_gems(Economy.chest_price(chest_id, true)), Color("#b34dff") if gems_ok else UiStyle.PANEL, 21, Vector2(0, 62))
		gem_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gem_button.disabled = not gems_ok
		gem_button.pressed.connect(func() -> void: _open(chest_id, true))
		row.add_child(gem_button)
	return panel


func _make_ad_chest() -> Control:
	var wait := Economy.ad_chest_wait()
	var subtitle := "Смотри рекламу - сундук сразу твой" if wait <= 0 else "Следующий через %s" % Economy.ad_chest_wait_text()
	return _ad_card("БЕСПЛАТНЫЙ СУНДУК", subtitle, "res://assets/ui/hub/chest_free.png", "", Color("#2fae5f"), wait <= 0, func() -> void:
		Platform.show_rewarded_ad(func(ok: bool) -> void:
			if not ok:
				return
			var rewards := Economy.open_ad_chest()
			if rewards.is_empty():
				return
			_show_reveal(rewards, Premium.chest_tier())))


func _make_ads() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	for kind in ["coins", "gems"]:
		var left := Economy.ads_left(kind)
		var title := "+%s" % SaveService.format_coins(Economy.AD_COINS) if kind == "coins" else "НЕОНИТ 1-5"
		var icon := "res://assets/ui/hub/coins_pile.png" if kind == "coins" else "res://assets/ui/hub/neonite_pile.png"
		var color := Color("#e0a020") if kind == "coins" else Color("#b34dff")
		var subtitle := "Смотри рекламу - получи сразу" if left > 0 else "На сегодня всё, возвращайся завтра"
		var chip := "осталось %d" % left if left > 0 else ""
		box.add_child(_ad_card(title, subtitle, icon, chip, color, left > 0, func() -> void:
			Platform.show_rewarded_ad(func(ok: bool) -> void:
				if not ok:
					return
				var amount := Economy.claim_ad(kind)
				if amount > 0:
					SoundManager.play(&"star_dust")
					changed.emit()
					_refresh())))
	return box


func _ad_card(title: String, subtitle: String, icon_path: String, chip: String, color: Color, enabled: bool, action: Callable) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 96)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not enabled
	var base := color.darkened(0.42) if enabled else UiStyle.PANEL
	button.add_theme_stylebox_override("normal", UiStyle.button_box(base, false))
	button.add_theme_stylebox_override("hover", UiStyle.button_box(base.lightened(0.06), false))
	button.add_theme_stylebox_override("pressed", UiStyle.button_box(base.lightened(0.1), true))
	button.add_theme_stylebox_override("disabled", UiStyle.button_box(base, false))
	button.pressed.connect(action)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	row.add_theme_constant_override("separation", 14)
	button.add_child(row)
	var ticket := TextureRect.new()
	ticket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticket.texture = ArenaProp.texture_of("res://assets/ui/hub/ad_ticket.png")
	ticket.custom_minimum_size = Vector2(64, 64)
	ticket.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ticket.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ticket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ticket.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.4)
	row.add_child(ticket)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	var head := UiStyle.label(title, 26, UiStyle.TEXT if enabled else UiStyle.TEXT_DIM, 7)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(head)
	var sub := UiStyle.label(subtitle, 17, Color(UiStyle.TEXT, 0.85) if enabled else UiStyle.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(230, 0)
	texts.add_child(sub)
	if chip != "":
		var chip_label := UiStyle.label(chip, 18, UiStyle.GOLD, 4)
		chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		texts.add_child(chip_label)
	row.add_child(texts)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = ArenaProp.texture_of(icon_path)
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.45)
	row.add_child(icon)
	if enabled:
		var badge := TextureRect.new()
		badge.texture = ArenaProp.texture_of("res://assets/ui/hub/free_badge.png")
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -128.0
		badge.offset_right = -6.0
		badge.offset_top = -50.0
		badge.offset_bottom = 6.0
		button.add_child(badge)
	return button


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
