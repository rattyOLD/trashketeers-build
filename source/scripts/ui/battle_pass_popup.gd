class_name BattlePassPopup
extends GlassPopup
## Боевой пропуск: полоса очков, бесплатная и платная ветки по 30 уровней, «забрать всё».

signal changed

var _info: Label
var _bar: ProgressBar
var _actions: VBoxContainer
var _status: Label
var _list: VBoxContainer
var _scroll_target: Control


func _init() -> void:
	super("БОЕВОЙ ПРОПУСК")
	_info = UiStyle.label("", 24, UiStyle.GOLD, 6)
	content.add_child(_info)
	_bar = UiStyle.progress_bar(UiStyle.NEON, 20)
	_bar.max_value = 1.0
	content.add_child(_bar)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	content.add_child(_actions)
	_status = UiStyle.label("", 19, UiStyle.TEXT_DIM, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	content.add_child(_status)
	_list = MenuPopups.scroll_list(content)


func _refresh() -> void:
	var level := BattlePass.tier()
	_info.text = "Сезон %d · уровень %d из %d · осталось дней: %d" % [BattlePass.season(), level, BattlePass.TIERS, BattlePass.days_left()]
	if level >= BattlePass.TIERS:
		_info.text = "Сезон %d · всё пройдено! Бонус за каждые %d очков · дней: %d" % [BattlePass.season(), BattlePass.BONUS_POINTS, BattlePass.days_left()]
	_bar.value = BattlePass.tier_progress()
	MenuPopups.clear(_actions)
	var claim := UiStyle.button("СОБРАТЬ ВСЕ НАГРАДЫ", Color("#2fae5f"), 28, Vector2(0, 80))
	claim.disabled = not BattlePass.has_unclaimed()
	claim.pressed.connect(func() -> void:
		var got := BattlePass.claim_all()
		SoundManager.play(&"star_dust")
		var parts: Array[String] = []
		if int(got["coins"]) > 0:
			parts.append(SaveService.format_coins(int(got["coins"])))
		if int(got["gems"]) > 0:
			parts.append(Economy.format_gems(int(got["gems"])))
		if int(got["xp"]) > 0:
			parts.append("%d опыта" % int(got["xp"]))
		_status.text = "Собрано наград: %d. %s" % [int(got["count"]), ", ".join(parts)]
		changed.emit()
		_refresh())
	_actions.add_child(claim)
	if not BattlePass.is_premium():
		var buy := UiStyle.button("ОТКРЫТЬ ПРЕМИУМ · %s" % Premium.price_text(BattlePass.price()), Color("#b34dff"), 26, Vector2(0, 76))
		buy.pressed.connect(_buy)
		_actions.add_child(buy)
	if level >= BattlePass.TIERS:
		var ready := BattlePass.bonus_ready()
		var bonus := UiStyle.button("БОНУС-НАГРАДА ×%d · ЗАБРАТЬ" % ready if ready > 0 else "ДО БОНУСА: %d очков" % (BattlePass.BONUS_POINTS - BattlePass.bonus_points_into() % BattlePass.BONUS_POINTS),
				Color("#ffb020") if ready > 0 else UiStyle.PANEL, 24, Vector2(0, 70))
		bonus.disabled = ready <= 0
		bonus.pressed.connect(_claim_bonus)
		_actions.add_child(bonus)
	var milestone := BattlePass.next_milestone()
	if not milestone.is_empty():
		_actions.add_child(_milestone_card(milestone))
	if BattlePass.tier() < BattlePass.TIERS:
		var skip := UiStyle.button("ПРОПУСТИТЬ УРОВЕНЬ · %s" % Economy.format_gems(BattlePass.SKIP_COST), Color("#b34dff") if BattlePass.can_skip() else UiStyle.PANEL, 20, Vector2(0, 54))
		skip.disabled = not BattlePass.can_skip()
		skip.pressed.connect(func() -> void:
			if BattlePass.skip_tier():
				SoundManager.play(&"star_dust")
				_status.text = "Уровень пропущен"
				changed.emit()
				_refresh())
		_actions.add_child(skip)
	if _status.text.is_empty():
		_status.text = "Очки: забеги (чем дальше волна, тем больше) и ежедневный подарок. Уровень = 100 очков."
	MenuPopups.clear(_list)
	_list.add_child(_header_row())
	_scroll_target = null
	for tier in range(1, BattlePass.TIERS + 1):
		var row := _row(tier, level)
		_list.add_child(row)
		if tier == clampi(level, 1, BattlePass.TIERS):
			_scroll_target = row
	get_tree().process_frame.connect(_scroll_to_target, CONNECT_ONE_SHOT)


func _scroll_to_target() -> void:
	if _scroll_target == null or not is_instance_valid(_scroll_target):
		return
	var scroll := _list.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = maxi(int(_scroll_target.position.y) - 70, 0)


func _milestone_card(milestone: Dictionary) -> Control:
	var item := str(milestone["item"])
	var color := Economy.rarity_color(Economy.item_rarity(item))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.07, 0.2, 0.9), color, 4, 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(_item_art(item, Vector2(110, 50)))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var title := UiStyle.label("СЛЕДУЮЩИЙ ПРИЗ: %s" % Economy.item_title(item), 22, color, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text = true
	texts.add_child(title)
	var where := "премиум" if str(milestone["track"]) == "prem" else "бесплатно"
	var sub := UiStyle.label("Уровень %d · %s" % [int(milestone["level"]), where], 18, UiStyle.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(sub)
	return panel


func _item_art(item: String, art_size: Vector2) -> Control:
	if Economy.item_kind(item) == "weapon":
		var weapon := WeaponDB.get_weapon(StringName(Economy.item_id(item)))
		if weapon != null:
			return WeaponIcons.IconRect.new(weapon.icon, weapon.effect_color, art_size)
	var tag := UiStyle.label(Economy.item_type_name(item).to_upper(), 18, Economy.rarity_color(Economy.item_rarity(item)), 5)
	tag.custom_minimum_size = Vector2(art_size.x, 0)
	return tag


func _claim_bonus() -> void:
	var prize := BattlePass.claim_bonus()
	if prize.is_empty():
		return
	SoundManager.play(&"star_dust")
	match str(prize["kind"]):
		"gems":
			_status.text = "Бонус: %s!" % Economy.format_gems(int(prize["amount"]))
		"xp":
			_status.text = "Бонус: +%d опыта аккаунта" % int(prize["amount"])
		_:
			_status.text = "Бонус: %s" % SaveService.format_coins(int(prize["amount"]))
	changed.emit()
	_refresh()


func _buy() -> void:
	BattlePass.buy_premium()
	SoundManager.play(&"star_dust")
	_status.text = "Премиум-ветка открыта!" + ("" if Premium.PAYMENTS_LIVE else " (оплата отключена, тестовая выдача)")
	changed.emit()
	_refresh()


func _header_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(52, 0)
	row.add_child(spacer)
	for title in ["БЕСПЛАТНО", "ПРЕМИУМ"]:
		var label := UiStyle.label(title, 20, UiStyle.NEON if title == "БЕСПЛАТНО" else Color("#d9a6ff"), 5)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	return row


func _row(tier: int, level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var number := UiStyle.label(str(tier), 26, UiStyle.GOLD if tier <= level else UiStyle.TEXT_DIM, 6)
	number.custom_minimum_size = Vector2(52, 0)
	row.add_child(number)
	row.add_child(_cell("free", tier))
	row.add_child(_cell("prem", tier))
	return row


func _cell(track: String, tier: int) -> Control:
	var prize := BattlePass.reward(track, tier)
	var claimed := BattlePass.is_claimed(track, tier)
	var claimable := BattlePass.can_claim(track, tier)
	var locked_premium := track == "prem" and not BattlePass.is_premium()
	var accent := Color("#b34dff") if track == "prem" else Color("#00e5ff")
	var bg := Color("#233a33") if claimed else (Color(0.28, 0.21, 0.07, 0.98) if claimable else UiStyle.PANEL_LIGHT)
	var border := Color("#2fae5f") if claimed else (UiStyle.GOLD if claimable else accent.darkened(0.5))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 84)
	panel.add_theme_stylebox_override("panel", UiStyle.box(bg, border, 4 if claimable else 3, 16))
	panel.modulate = Color(1, 1, 1, 0.55) if (locked_premium or (not claimable and not claimed)) else Color.WHITE
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	if int(prize["coins"]) > 0:
		column.add_child(_amount("res://assets/ui/hub/coin.png", "+%d" % int(prize["coins"]), UiStyle.TEXT))
	if int(prize["gems"]) > 0:
		column.add_child(_amount("res://assets/ui/hub/neonite.png", "+%d" % int(prize["gems"]), Color("#d9a6ff")))
	var item := str(prize["item"])
	if not item.is_empty():
		var art := _item_art(item, Vector2(90, 34))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(art)
		var label := UiStyle.label(Economy.item_title(item), 16, Economy.rarity_color(Economy.item_rarity(item)), 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		column.add_child(label)
		panel.custom_minimum_size = Vector2(0, 124)
		border = Economy.rarity_color(Economy.item_rarity(item)) if not claimed else border
		panel.add_theme_stylebox_override("panel", UiStyle.box(bg, border, 5, 16))
	if claimed:
		var done := UiStyle.label("ЗАБРАНО", 15, Color("#5be37d"), 4)
		done.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(done)
	elif locked_premium:
		var lock := UiStyle.label("ПРЕМИУМ", 15, Color("#d9a6ff"), 4)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(lock)
	if claimable:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
			if tapped and BattlePass.claim(track, tier):
				SoundManager.play(&"star_dust")
				changed.emit()
				_refresh())
	return panel


func _amount(icon_path: String, text: String, color: Color) -> Control:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = ArenaProp.texture_of(icon_path)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := UiStyle.label(text, 22, color, 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box
