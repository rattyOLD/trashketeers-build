class_name OddsPopup
extends GlassPopup
## Шансы сундука: витрина дня с шансом каждого предмета и таблица остальных наград.

var _list: VBoxContainer


func _init() -> void:
	super("ШАНСЫ")
	_list = MenuPopups.scroll_list(content)


func open_for(chest_id: String) -> void:
	_chest_id = chest_id
	open()


var _chest_id := "common"


func _refresh() -> void:
	var chest: Dictionary = Economy.CHESTS[_chest_id]
	MenuPopups.clear(_list)
	_list.add_child(UiStyle.label(str(chest["title"]).to_upper(), 30, chest["color"] as Color, 8))
	_list.add_child(_note("Шанс предмета из витрины: %d%%. Растёт на 4%% за каждые 10 открытий без ценного, на 50-м открытии - гарантия (%s)." % [roundi(Economy.item_chance(_chest_id) * 100.0), "герой или эпик/легендарка"]))
	_list.add_child(UiStyle.label("ВИТРИНА ДНЯ", 22, UiStyle.NEON, 6))
	for entry in Economy.shelf_odds(_chest_id):
		_list.add_child(_item_row(str(entry["key"]), float(entry["chance"])))
	_list.add_child(UiStyle.label("ОСТАЛЬНЫЕ НАГРАДЫ", 22, UiStyle.NEON, 6))
	_list.add_child(_note("Если предмет не выпал, вместо него чертёж витрины. Остальные награды выпадают так:"))
	for entry in Economy.filler_odds(_chest_id):
		_list.add_child(_text_row(str(entry["title"]), float(entry["chance"])))


func _note(text: String) -> Label:
	var label := UiStyle.label(text, 19, UiStyle.TEXT_DIM, 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	return label


func _item_row(key: String, chance: float) -> Control:
	var rarity := Economy.item_rarity(key)
	var color := Economy.rarity_color(rarity)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, color, 3, 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	if Economy.item_kind(key) == "weapon":
		var weapon := WeaponDB.get_weapon(StringName(Economy.item_id(key)))
		if weapon != null:
			row.add_child(WeaponIcons.IconRect.new(weapon.icon, weapon.effect_color, Vector2(96, 44)))
	else:
		var tag := UiStyle.label(Economy.item_type_name(key).to_upper(), 16, color, 4)
		tag.custom_minimum_size = Vector2(96, 0)
		row.add_child(tag)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	var title := UiStyle.label(Economy.item_title(key), 22, UiStyle.TEXT, 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text = true
	texts.add_child(title)
	var rarity_label := UiStyle.label(Economy.rarity_name(rarity), 16, color, 4)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(rarity_label)
	row.add_child(texts)
	row.add_child(UiStyle.label(_percent(chance), 26, UiStyle.GOLD, 6))
	return panel


func _text_row(title: String, chance: float) -> Control:
	var row := HBoxContainer.new()
	var label := UiStyle.label(title, 21, UiStyle.TEXT, 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(UiStyle.label(_percent(chance), 22, UiStyle.GOLD, 5))
	return row


static func _percent(chance: float) -> String:
	var pct := chance * 100.0
	return "%.1f%%" % pct if pct < 10.0 else "%d%%" % roundi(pct)
