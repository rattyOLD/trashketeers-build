class_name HeroPopup
extends GlassPopup
## Экран героя как в аналоговых играх: витрина со стрелками, редкость, история, характеристики,
## покупка с эффектом и улучшение уровня за монеты.

signal skin_changed

const RARITY_TITLES := {"common": "ОБЫЧНЫЙ", "rare": "РЕДКИЙ", "epic": "ЭПИЧЕСКИЙ", "legendary": "ЛЕГЕНДАРНЫЙ"}
const STAT_ROWS := [["hp", "ЗДОРОВЬЕ"], ["speed", "СКОРОСТЬ"], ["dash", "РЫВОК"], ["crit", "КРИТ"], ["damage", "УРОН"]]

var _index := 0
var _list: VBoxContainer
var _balance: Label
var _action_box: VBoxContainer
var _stage: Control
var _preview: MenuWidgets.RaccoonPreview
var _flash: ColorRect
var _burst: HeroBurst
var _reveal: UnlockReveal


func _init() -> void:
	super("ГЕРОИ")
	_balance = UiStyle.label("", 24, UiStyle.GOLD, 6)
	content.add_child(_balance)
	var search := SearchBar.new("Найти героя по имени")
	search.changed.connect(_on_search)
	content.add_child(search)
	_list = MenuPopups.scroll_list(content)
	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 10)
	content.add_child(_action_box)
	_reveal = UnlockReveal.new()
	add_child(_reveal)


func _on_search(query: String) -> void:
	if query.is_empty():
		return
	var all := CharacterDB.all()
	for i in all.size():
		if SearchBar.matches(query, "%s %s" % [all[i]["title"], all[i]["id"]]):
			_index = i
			_refresh()
			return


func open() -> void:
	var current := SaveService.get_character_id()
	var all := CharacterDB.all()
	for i in all.size():
		if str(all[i]["id"]) == current:
			_index = i
	super()


func _refresh() -> void:
	var all := CharacterDB.all()
	_index = wrapi(_index, 0, all.size())
	var character: Dictionary = all[_index]
	var id := str(character["id"])
	var owned := SaveService.owns_character(id)
	var level := SaveService.get_hero_level(id)
	var rarity := str(Economy.HERO_RARITY.get(id, "common"))
	var accent: Color = WeaponData.RARITY_COLORS.get(rarity, Color.WHITE)
	_balance.text = "%s · %s" % [SaveService.format_coins(SaveService.get_coins()), Economy.format_gems(SaveService.get_gems())]
	MenuPopups.clear(_list)
	MenuPopups.clear(_action_box)
	_list.add_child(_build_stage(character, accent, owned))
	_list.add_child(_build_dots(all.size(), accent))
	_list.add_child(_build_header(character, rarity, accent))
	var lore := UiStyle.label(str(character.get("lore", character.get("description", ""))), 19, UiStyle.TEXT, 4)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.custom_minimum_size = Vector2(520, 0)
	_list.add_child(lore)
	_list.add_child(_build_passive(character, accent))
	_list.add_child(_build_stats(character, level, owned))
	if owned and not bool(character.get("coming_soon", false)):
		_list.add_child(_build_level_card(id, level))
	_build_actions(character, owned)


func _build_stage(character: Dictionary, accent: Color, owned: bool) -> Control:
	var panel := PanelContainer.new()
	var style := UiStyle.box(accent.darkened(0.72), accent, 4, 24)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, 300)
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(0, 290)
	panel.add_child(_stage)
	var skin: Dictionary = SaveService.get_skin()
	_preview = MenuWidgets.RaccoonPreview.new(skin, 1.55, character)
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.modulate = Color.WHITE if owned else Color(0.35, 0.35, 0.45, 1.0)
	_stage.add_child(_preview)
	_stage.gui_input.connect(func(event: InputEvent) -> void:
		var tapped: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if tapped:
			_preview.fire_burst())
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_flash)
	_burst = HeroBurst.new()
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	_burst.color = accent
	_stage.add_child(_burst)
	if not owned:
		var lock := UiStyle.label("НЕ ОТКРЫТ", 26, Color(1, 1, 1, 0.9), 8)
		lock.set_anchors_preset(Control.PRESET_CENTER_TOP)
		lock.offset_left = -100.0
		lock.offset_right = 100.0
		lock.offset_top = 10.0
		_stage.add_child(lock)
	for side in [-1, 1]:
		var arrow := UiStyle.button("<" if side < 0 else ">", Color(0, 0, 0, 0.35), 34, Vector2(64, 96))
		arrow.set_anchors_preset(Control.PRESET_CENTER_LEFT if side < 0 else Control.PRESET_CENTER_RIGHT)
		arrow.offset_left = 6.0 if side < 0 else -70.0
		arrow.offset_right = 70.0 if side < 0 else -6.0
		arrow.offset_top = -48.0
		arrow.offset_bottom = 48.0
		arrow.pressed.connect(func() -> void:
			SoundManager.play(&"ui_click")
			_index += side
			_refresh())
		_stage.add_child(arrow)
	return panel


func _build_dots(count: int, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for i in count:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(16, 16) if i == _index else Vector2(11, 11)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", UiStyle.box(accent if i == _index else Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0, 8))
		row.add_child(dot)
	return row


func _build_header(character: Dictionary, rarity: String, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 0)
	var title := UiStyle.label(str(character["title"]).to_upper(), 34, UiStyle.TEXT, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(340, 0)
	name_box.add_child(title)
	var role := UiStyle.label(str(character.get("role", "Налётчик")), 20, accent.lightened(0.2), 5)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_box.add_child(role)
	row.add_child(name_box)
	var tag := PanelContainer.new()
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_theme_stylebox_override("panel", UiStyle.box(accent.darkened(0.45), accent, 3, 12))
	tag.add_child(UiStyle.label(RARITY_TITLES.get(rarity, "ОБЫЧНЫЙ"), 18, UiStyle.TEXT, 4))
	row.add_child(tag)
	return row


func _build_passive(character: Dictionary, accent: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(accent, 0.18), accent, 5, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var passive: Dictionary = character.get("passive", {})
	var head := UiStyle.label("ПАССИВКА: %s" % str(passive.get("title", "-")).to_upper(), 24, UiStyle.GOLD, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(head)
	var text := UiStyle.label(str(passive.get("text", "Особых способностей нет")), 20, UiStyle.TEXT, 5)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(500, 0)
	column.add_child(text)
	var skill: Dictionary = character.get("skill", {})
	if not skill.is_empty():
		var skill_color := Color(str(skill.get("color", "#ffcf3d")))
		var skill_head := UiStyle.label("НАВЫК вместо рывка: %s · %d с" % [str(skill.get("title", "")).to_upper(), int(skill.get("cooldown", 0))], 21, skill_color, 5)
		skill_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(skill_head)
		var skill_text := UiStyle.label(str(skill.get("text", "")), 18, UiStyle.TEXT, 4)
		skill_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		skill_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill_text.custom_minimum_size = Vector2(500, 0)
		column.add_child(skill_text)
	else:
		var none := UiStyle.label("НАВЫК: рывок. Универсал без лишних фокусов", 19, UiStyle.TEXT_DIM, 4)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(none)
	return panel


func _stat_value(character: Dictionary, key: String, level: int) -> float:
	var stats: Dictionary = character.get("stats", {})
	match key:
		"hp":
			return float(stats.get("hp", 0.0)) + SaveService.HERO_HP_PER_LEVEL * (level - 1)
		"dash":
			return -float(stats.get("dash", 0.0))
		"damage":
			return SaveService.HERO_DAMAGE_PER_LEVEL * (level - 1)
	return float(stats.get(key, 0.0))


func _build_stats(character: Dictionary, level: int, owned: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.OUTLINE, 3, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var head := UiStyle.label("ХАРАКТЕРИСТИКИ", 21, UiStyle.NEON, 5)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(head)
	for row_info in STAT_ROWS:
		var value := _stat_value(character, row_info[0], level if owned else 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := UiStyle.label(row_info[1], 18, UiStyle.TEXT_DIM, 4)
		name_label.custom_minimum_size = Vector2(150, 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(name_label)
		var color := Color("#5be37d") if value > 0.001 else (Color("#ff6b6b") if value < -0.001 else Color("#9aa3c0"))
		var bar := UiStyle.progress_bar(color, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 1.0
		bar.value = clampf(0.5 + value * 2.0, 0.06, 1.0)
		row.add_child(bar)
		var number := UiStyle.label("%+d%%" % roundi(value * 100.0), 18, color, 4)
		number.custom_minimum_size = Vector2(70, 0)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(number)
		column.add_child(row)
	return panel


func _build_level_card(id: String, level: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color("#ffd257"), 3, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var head := UiStyle.label("УРОВЕНЬ %d / %d" % [level, SaveService.HERO_MAX_LEVEL], 24, UiStyle.GOLD, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(head)
	var bar := UiStyle.progress_bar(UiStyle.GOLD, 16)
	bar.max_value = float(SaveService.HERO_MAX_LEVEL - 1)
	bar.value = float(level - 1)
	column.add_child(bar)
	var maxed := level >= SaveService.HERO_MAX_LEVEL
	var hint := "Максимальный уровень" if maxed else "Следующий уровень: +%d%% здоровья, +%d%% урона" % [roundi(SaveService.HERO_HP_PER_LEVEL * 100.0), roundi(SaveService.HERO_DAMAGE_PER_LEVEL * 100.0)]
	var hint_label := UiStyle.label(hint, 18, UiStyle.TEXT_DIM, 4)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(500, 0)
	column.add_child(hint_label)
	if not maxed:
		var cost := SaveService.hero_upgrade_cost(id)
		var ok := SaveService.get_coins() >= cost
		var button := UiStyle.button("УЛУЧШИТЬ · %s" % SaveService.format_coins(cost), Color("#e0a020") if ok else UiStyle.PANEL, 24, Vector2(0, 70))
		button.disabled = not ok
		button.pressed.connect(func() -> void: _upgrade(id))
		column.add_child(button)
	return panel


func _build_actions(character: Dictionary, owned: bool) -> void:
	var id := str(character["id"])
	var button: Button
	if bool(character.get("coming_soon", false)):
		button = UiStyle.button("СКОРО", UiStyle.PANEL, 30, Vector2(0, 88))
		button.disabled = true
	elif not owned:
		var currency := str(character["currency"])
		var price := int(character["price"])
		var affordable := int(SaveService.data[currency]) >= price
		var price_text := SaveService.format_coins(price) if currency == "nuts" else Economy.format_gems(price)
		button = UiStyle.button("ОТКРЫТЬ · %s" % price_text, Color("#2fae5f") if affordable else UiStyle.PANEL, 30, Vector2(0, 88))
		button.disabled = not affordable
		button.pressed.connect(func() -> void: _buy(id))
	elif SaveService.get_character_id() == id:
		button = UiStyle.button("ВЫБРАН", UiStyle.PANEL, 30, Vector2(0, 88))
		button.disabled = true
	else:
		button = UiStyle.button("ВЫБРАТЬ", Color("#00a8c8"), 30, Vector2(0, 88))
		button.pressed.connect(func() -> void:
			SaveService.select_character(id)
			SoundManager.play(&"ui_confirm")
			skin_changed.emit()
			_refresh())
	_action_box.add_child(button)


func _buy(id: String) -> void:
	if not SaveService.buy_character(id):
		return
	skin_changed.emit()
	_refresh()
	var character := CharacterDB.get_character(id)
	var rarity := Economy.HERO_RARITY.get(id, "rare") as String
	var art := MenuWidgets.RaccoonPreview.new(SaveService.get_skin(), 2.3, character)
	_reveal.play("НОВЫЙ ГЕРОЙ!", str(character.get("title", "")), "%s · %s" % [RARITY_TITLES.get(rarity, ""), str(character.get("role", ""))],
			str(character.get("quote", "")), WeaponData.RARITY_COLORS.get(rarity, Color.WHITE), art, {"rare": 1, "epic": 2, "legendary": 3}.get(rarity, 1))


func _upgrade(id: String) -> void:
	if not SaveService.upgrade_hero(id):
		return
	skin_changed.emit()
	_refresh()
	SoundManager.play(&"level_up", 0.0, false)
	_celebrate(0.5)


func _celebrate(strength: float) -> void:
	if _preview == null:
		return
	_preview.celebrate()
	_preview.pivot_offset = _preview.size * 0.5
	_preview.scale = Vector2.ONE * (1.0 - 0.18 * strength)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_preview, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_flash.color = Color(1, 1, 1, 0.75 * strength)
	tween.tween_property(_flash, "color:a", 0.0, 0.5)
	_burst.fire(strength)


## Вспышка искр вокруг героя при покупке и улучшении.
class HeroBurst:
	extends Control
	var color := Color.WHITE
	var _t := 1.0
	var _strength := 1.0
	var _angles: Array[float] = []

	func fire(strength: float) -> void:
		_t = 0.0
		_strength = strength
		_angles.clear()
		for i in int(26.0 * strength):
			_angles.append(randf() * TAU)
		set_process(true)

	func _process(delta: float) -> void:
		if _t >= 1.0:
			set_process(false)
			return
		_t += delta * 1.4
		queue_redraw()

	func _draw() -> void:
		if _t >= 1.0:
			return
		var center := size * 0.5 + Vector2(0, 20)
		var fade := 1.0 - _t
		for i in _angles.size():
			var speed := 120.0 + fmod(float(i) * 37.0, 160.0)
			var pos := center + Vector2.from_angle(_angles[i]) * speed * _t * 1.6
			draw_circle(pos, (3.0 + fmod(float(i), 4.0)) * fade * _strength, Color(color.lightened(0.5), fade))
		draw_arc(center, 40.0 + 220.0 * _t, 0.0, TAU, 48, Color(color.lightened(0.4), fade * 0.8), 6.0 * fade + 1.0, true)
