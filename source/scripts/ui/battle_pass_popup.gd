class_name BattlePassPopup
extends GlassPopup
## Боевой пропуск: полоса очков, бесплатная и платная ветки по 30 уровней, «забрать всё».

signal changed

var _hero: VBoxContainer
var _actions: VBoxContainer
var _status: Label
var _list: VBoxContainer
var _scroll_box: VBoxContainer
var _scroll_target: Control

const ROAD_WIDTH := 110.0
const ROW_HEIGHT := 132.0
const ROW_GAP := 6.0
const FEATURE_ITEM := "weapon:railgun_v1"
const FEATURE_TEXT := "Пробивает всех на линии. Рывок заряжает следующий выстрел, серии убийств растят рельс-комбо. Главная вкусность сезона."


func _init() -> void:
	super("БОЕВОЙ ПРОПУСК")
	_scroll_box = MenuPopups.scroll_list(content)
	_hero = VBoxContainer.new()
	_hero.add_theme_constant_override("separation", 8)
	_scroll_box.add_child(_hero)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_scroll_box.add_child(_actions)
	_status = UiStyle.label("", 18, UiStyle.TEXT_DIM, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(10, 0)
	_scroll_box.add_child(_status)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(ROW_GAP))
	_scroll_box.add_child(_list)


## Шапка: сезон, огромный уровень, дни и толстая полоса с подсказкой «до следующего уровня».
func _build_hero(level: int) -> void:
	MenuPopups.clear(_hero)
	var panel := PanelContainer.new()
	var box := UiStyle.box(Color("#0e2230"), Color("#35c8ff"), 4, 22)
	box.shadow_color = Color(0.7, 0.3, 1.0, 0.35)
	box.shadow_size = 10
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var season := UiStyle.label("СЕЗОН %d" % BattlePass.season(), 22, Color("#b8eaff"), 5)
	season.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	season.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(season)
	var days := UiStyle.label("осталось дней: %d" % BattlePass.days_left(), 20, UiStyle.TEXT, 5)
	days.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(days)
	var big := "УРОВЕНЬ %d / %d" % [level, BattlePass.TIERS] if level < BattlePass.TIERS else "ВСЕ %d УРОВНЕЙ ПРОЙДЕНЫ" % BattlePass.TIERS
	column.add_child(UiStyle.label(big, 38, UiStyle.GOLD, 9))
	var bar := UiStyle.progress_bar(Color("#ffb020"), 30)
	bar.max_value = 1.0
	bar.value = BattlePass.tier_progress()
	column.add_child(bar)
	var to_next := UiStyle.label("", 18, UiStyle.TEXT_DIM, 4)
	if level < BattlePass.TIERS:
		to_next.text = "До уровня %d: %d очков" % [level + 1, BattlePass.POINTS_PER_TIER - BattlePass.points() % BattlePass.POINTS_PER_TIER]
	else:
		to_next.text = "До бонус-награды: %d очков" % (BattlePass.BONUS_POINTS - BattlePass.bonus_points_into() % BattlePass.BONUS_POINTS)
	column.add_child(to_next)
	var earn := UiStyle.label("Хороший забег: до +%d очков · подарок дня +%d" % [BattlePass.MAX_RUN_POINTS, BattlePass.DAILY_POINTS], 16, Color("#9be8b4"), 4)
	earn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	earn.custom_minimum_size = Vector2(10, 0)
	column.add_child(earn)
	_hero.add_child(panel)
	if not BattlePass.is_claimed("prem", 1):
		_hero.add_child(_feature_card())
	_hero.add_child(_quests_card())


## Задания сезона: три строки с полосой и кнопкой награды в очках пропуска.
func _quests_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#0f1a24"), Color("#00e5ff"), 3, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(UiStyle.label("ЗАДАНИЯ СЕЗОНА", 18, UiStyle.NEON, 5))
	for quest: Dictionary in BattlePass.QUESTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 2)
		row.add_child(texts)
		var progress := BattlePass.quest_progress(quest)
		var goal := int(quest["goal"])
		var title := UiStyle.label("%s · %d/%d" % [quest["title"], progress, goal], 16, UiStyle.TEXT if not BattlePass.quest_claimed(quest) else UiStyle.TEXT_DIM, 4)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.clip_text = true
		texts.add_child(title)
		var bar := UiStyle.progress_bar(Color("#00e5ff"), 10)
		bar.max_value = float(goal)
		bar.value = float(progress)
		texts.add_child(bar)
		var claimed := BattlePass.quest_claimed(quest)
		var ready := BattlePass.quest_ready(quest)
		var button := UiStyle.button("ГОТОВО" if claimed else "+%d" % int(quest["points"]), Color("#2fae5f") if ready else UiStyle.PANEL, 16, Vector2(86, 40))
		button.disabled = not ready
		button.pressed.connect(func() -> void:
			if BattlePass.claim_quest(quest):
				SoundManager.play(&"star_dust")
				changed.emit()
				_refresh())
		row.add_child(button)
	return panel


## Главный приз сезона: отдельная карточка с описанием и кнопкой.
func _feature_card() -> Control:
	var color := Economy.rarity_color(Economy.item_rarity(FEATURE_ITEM))
	var panel := PanelContainer.new()
	var box := UiStyle.box(Color(0.16, 0.1, 0.03, 0.96), color, 5, 22)
	box.shadow_color = Color(color, 0.5)
	box.shadow_size = 14
	panel.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var art_box := FeatureGlow.new()
	art_box.tint = color
	art_box.custom_minimum_size = Vector2(150, 96)
	art_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art_box.clip_contents = true
	var art := _item_art(FEATURE_ITEM, Vector2(150, 96))
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.pivot_offset = Vector2(75, 48)
	art.rotation_degrees = -6.0
	art_box.add_child(art)
	row.add_child(art_box)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	var tag := UiStyle.label("ЛЕГЕНДАРНЫЙ · УРОВЕНЬ 1 ПРЕМИУМА", 14, color, 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(tag)
	var title := UiStyle.label(Economy.item_title(FEATURE_ITEM), 24, UiStyle.TEXT, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text = true
	texts.add_child(title)
	var desc := UiStyle.label(FEATURE_TEXT, 15, UiStyle.TEXT_DIM, 3)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(10, 0)
	texts.add_child(desc)
	if not BattlePass.is_premium():
		var buy := UiStyle.button("ПОЛУЧИТЬ С ПРЕМИУМОМ · %s" % Premium.price_text(BattlePass.price()), Color("#35c8ff"), 17, Vector2(0, 46))
		buy.pressed.connect(_buy)
		texts.add_child(buy)
	else:
		var take := UiStyle.button("ЗАБРАТЬ", Color("#2fae5f"), 18, Vector2(0, 46))
		take.disabled = not BattlePass.can_claim("prem", 1)
		take.pressed.connect(func() -> void:
			if BattlePass.claim("prem", 1):
				SoundManager.play(&"star_dust")
				changed.emit()
				_refresh())
		texts.add_child(take)
	return panel


func _refresh() -> void:
	var level := BattlePass.tier()
	_build_hero(level)
	MenuPopups.clear(_actions)
	var claim := UiStyle.button("СОБРАТЬ ВСЕ НАГРАДЫ", Color("#2fae5f"), 24, Vector2(0, 64))
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
	if not BattlePass.is_premium() and BattlePass.is_claimed("prem", 1):
		var buy := UiStyle.button("ОТКРЫТЬ ПРЕМИУМ · %s" % Premium.price_text(BattlePass.price()), Color("#35c8ff"), 26, Vector2(0, 76))
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
	if not milestone.is_empty() and str(milestone["item"]) != FEATURE_ITEM:
		_actions.add_child(_milestone_card(milestone))
	if BattlePass.tier() < BattlePass.TIERS:
		var can_skip_n := mini(SaveService.get_gems() / BattlePass.SKIP_COST, BattlePass.TIERS - BattlePass.tier())
		var skip := UiStyle.button("ПРОПУСТИТЬ УРОВЕНЬ · %s (можно: %d)" % [Economy.format_gems(BattlePass.SKIP_COST), can_skip_n], Color("#35c8ff") if BattlePass.can_skip() else UiStyle.PANEL, 17, Vector2(0, 50))
		skip.disabled = not BattlePass.can_skip()
		skip.pressed.connect(func() -> void:
			if BattlePass.skip_tier():
				SoundManager.play(&"star_dust")
				_status.text = "Уровень пропущен"
				changed.emit()
				_refresh())
		_actions.add_child(skip)
	if _status.text.is_empty():
		_status.text = "Уровень = 100 очков. Очки дают забеги (чем дальше волна, тем больше) и ежедневный подарок."
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
	var scroll := _scroll_box.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = maxi(int(_list.position.y + _scroll_target.position.y) - 120, 0)


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
	if Cosmetics.is_cosmetic(item):
		var art := CosmeticArt.new()
		art.key = item
		art.custom_minimum_size = art_size
		return art
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
	var labels := [["БЕСПЛАТНО", UiStyle.NEON], ["", UiStyle.TEXT], ["ПРЕМИУМ", Color("#b8eaff")]]
	for pair in labels:
		var label := UiStyle.label(str(pair[0]), 20, pair[1], 5)
		if str(pair[0]).is_empty():
			label.custom_minimum_size = Vector2(ROAD_WIDTH, 0)
		else:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	return row


func _row(tier: int, level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_cell("free", tier))
	var road := Road.new()
	road.tier = tier
	road.level = level
	road.all_claimed = BattlePass.is_claimed("free", tier) and (BattlePass.is_claimed("prem", tier) or not BattlePass.is_premium())
	road.step = ROW_HEIGHT + ROW_GAP
	road.set_process(tier == level + 1)
	row.add_child(road)
	row.add_child(_cell("prem", tier))
	return row


func _cell(track: String, tier: int) -> Control:
	var prize := BattlePass.reward(track, tier)
	var claimed := BattlePass.is_claimed(track, tier)
	var claimable := BattlePass.can_claim(track, tier)
	var locked_premium := track == "prem" and not BattlePass.is_premium()
	var accent := Color("#35c8ff") if track == "prem" else Color("#00e5ff")
	var bg := Color("#233a33") if claimed else (Color(0.28, 0.21, 0.07, 0.98) if claimable else UiStyle.PANEL_LIGHT)
	var border := Color("#2fae5f") if claimed else (UiStyle.GOLD if claimable else accent.darkened(0.5))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
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
		column.add_child(_amount("res://assets/ui/hub/neonite.png", "+%d" % int(prize["gems"]), Color("#b8eaff")))
	var item := str(prize["item"])
	if not item.is_empty():
		var art := _item_art(item, Vector2(90, 34))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(art)
		var item_name := Economy.item_title(item)
		var label := UiStyle.label(item_name, 16 if item_name.length() <= 16 else 13, Economy.rarity_color(Economy.item_rarity(item)), 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		column.add_child(label)
		border = Economy.rarity_color(Economy.item_rarity(item)) if not claimed else border
		var glow := UiStyle.box(bg, border, 5, 16)
		if not claimed and Economy.item_rarity(item) in ["epic", "legendary"]:
			glow.shadow_color = Color(border, 0.55)
			glow.shadow_size = 12
		panel.add_theme_stylebox_override("panel", glow)
	if claimed:
		var done := UiStyle.label("ЗАБРАНО", 15, Color("#5be37d"), 4)
		done.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(done)
	elif locked_premium:
		var lock := UiStyle.label("ПРЕМИУМ", 15, Color("#b8eaff"), 4)
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


## Дорога сезона: извилистая лента от узла к узлу, узел-медаль с номером уровня.
class Road:
	extends Control

	var tier := 1
	var level := 0
	var all_claimed := false
	var step := 138.0
	var _time := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(ROAD_WIDTH, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _x(t: int) -> float:
		return size.x * (0.3 if t % 2 == 1 else 0.7)

	func _draw() -> void:
		var node := Vector2(_x(tier), size.y * 0.5)
		var lit := tier <= level
		if tier < BattlePass.TIERS:
			var finish := Vector2(_x(tier + 1), node.y + step)
			var points := PackedVector2Array()
			for i in 21:
				var t := float(i) / 20.0
				var q := 1.0 - t
				var c1 := node + Vector2(0.0, step * 0.5)
				var c2 := finish - Vector2(0.0, step * 0.5)
				points.append(q * q * q * node + 3.0 * q * q * t * c1 + 3.0 * q * t * t * c2 + t * t * t * finish)
			var passed := tier + 1 <= level
			draw_polyline(points, Color("#ffb020") if passed else Color("#1c4256"), 40.0, true)
			draw_polyline(points, Color("#253136"), 32.0, true)
			for i in range(0, 20, 2):
				draw_line(points[i], points[i + 1], Color("#ffd23f") if passed else Color("#5d7c8a"), 3.0, true)
		if tier % 5 == 0:
			var side := 1.0 if tier % 2 == 1 else -1.0
			var base := node + Vector2(side * 40.0, 22.0)
			draw_colored_polygon(PackedVector2Array([base + Vector2(0, -22), base + Vector2(-11, 0), base + Vector2(11, 0)]), Color("#ff7a3d"))
			draw_rect(Rect2(base + Vector2(-14, 0), Vector2(28, 5)), Color("#253136"))
		var current := tier == level + 1
		var radius := 25.0 + (2.0 * sin(_time * 5.0) if current else 0.0)
		var fill := Color("#5a3d0a") if lit else (Color("#1f3d4a") if not current else Color("#7a5200"))
		var ring := Color("#ffd23f") if (lit or current) else Color("#4a778a")
		if current:
			draw_circle(node, radius + 9.0, Color(ring, 0.25 + 0.15 * sin(_time * 5.0)))
		draw_circle(node, radius + 3.0, Color("#0e1e24"))
		draw_circle(node, radius, fill)
		draw_arc(node, radius - 1.0, 0.0, TAU, 32, ring, 3.0, true)
		if all_claimed:
			draw_polyline(PackedVector2Array([node + Vector2(-9, 0), node + Vector2(-3, 7), node + Vector2(10, -8)]), Color("#5be37d"), 5.0, true)
		else:
			var font := get_theme_default_font()
			var text := str(tier)
			var font_size := 24
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, node + Vector2(-width * 0.5, 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE if (lit or current) else Color("#96b4c0"))


## Картинка косметики: рамка, цвет ника, титул-табличка, бустер-молния.
class CosmeticArt:
	extends Control

	var key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var rarity := Economy.rarity_color(Cosmetics.rarity_of(key))
		match Cosmetics.kind_of(key):
			"frame":
				var tint := Cosmetics.color_of(key)
				draw_circle(c, r, Color("#1c4256"))
				draw_arc(c, r - 2.0, 0.0, TAU, 32, Color(tint, 0.35), 9.0, true)
				draw_arc(c, r - 2.0, 0.0, TAU, 32, tint, 5.0, true)
			"color":
				var tint := Cosmetics.color_of(key)
				var font := get_theme_default_font()
				var w := font.get_string_size("НИК", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
				draw_string(font, Vector2(c.x - w * 0.5, c.y + 8.0), "НИК", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, tint)
				draw_line(Vector2(c.x - w * 0.5, c.y + 14.0), Vector2(c.x + w * 0.5, c.y + 14.0), Color(tint, 0.6), 3.0)
			"title":
				var plate := Rect2(c - Vector2(36, 12), Vector2(72, 24))
				draw_rect(plate.grow(2.0), Color("#0e1e24"))
				draw_rect(plate, Color(rarity, 0.25))
				draw_rect(plate, rarity, false, 2.0)
				for i in 3:
					draw_circle(Vector2(c.x - 18.0 + i * 18.0, c.y), 3.0, rarity)
			_:
				var bolt := PackedVector2Array([c + Vector2(4, -r), c + Vector2(-10, 4), c + Vector2(-1, 4), c + Vector2(-5, r), c + Vector2(11, -6), c + Vector2(1, -6)])
				draw_colored_polygon(bolt, rarity)


## Сияющий диск за главным призом сезона, медленно пульсирует.
class FeatureGlow:
	extends Control

	var tint := Color.WHITE
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var pulse := 0.5 + 0.5 * sin(_time * 2.4)
		for i in 6:
			var t := float(i) / 5.0
			draw_circle(c, size.y * (0.56 - t * 0.36), Color(tint, 0.06 + 0.05 * t + 0.03 * pulse))
		for i in 8:
			var a := TAU * float(i) / 8.0 + _time * 0.3
			draw_line(c + Vector2.from_angle(a) * size.y * 0.3, c + Vector2.from_angle(a) * size.y * (0.52 + 0.04 * pulse), Color(tint, 0.35), 3.0)
