class_name PatchesPopup
extends GlassPopup
## Окно «Нашивки»: сверху куртка с 4 слотами (2 открыты, 2 покупаются), ниже 12 нашивок — купить, улучшить
## до 3 уровня, надеть/снять. Надетые действуют в Выживании (Patches.apply в BattleBase).

signal purchased

var _balance: Label
var _slots: HBoxContainer
var _list: VBoxContainer


func _init() -> void:
	super("НАШИВКИ")
	_balance = UiStyle.label("", 24, UiStyle.GOLD, 6)
	content.add_child(_balance)
	var note := UiStyle.label("Постоянные бонусы для Выживания. В забеге — 4 места и 5 улучшений карточками. Новые виды открываются заказами Нэлл.", 17, UiStyle.TEXT_DIM, 4)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(10, 0)
	content.add_child(note)
	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 12)
	content.add_child(_slots)
	_list = MenuPopups.scroll_list(content)


func _refresh() -> void:
	_balance.text = "Баланс: " + SaveService.format_coins(SaveService.get_coins())
	MenuPopups.clear(_slots)
	var worn := Patches.worn()
	for i in Patches.SLOTS:
		_slots.add_child(_slot(i, worn[i] if i < worn.size() else ""))
	MenuPopups.clear(_list)
	var grid := GridContainer.new()
	grid.columns = 2 if Orient.portrait else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_list.add_child(grid)
	for id in Patches.ORDER:
		grid.add_child(_card(id))


## Слот куртки: надетая нашивка (нажать — снять), пустой «+» или закрытый с ценой.
func _slot(index: int, id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var badge := Badge.new()
	badge.custom_minimum_size = Vector2(76, 76)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	if index >= Patches.open_slots():
		badge.locked = true
		if index == Patches.open_slots():
			var buy := UiStyle.button(SaveService.format_coins(Patches.slot_price()), Color("#e0a020"), 15, Vector2(110, 40))
			buy.disabled = SaveService.get_coins() < Patches.slot_price()
			buy.pressed.connect(func() -> void:
				if Patches.buy_slot():
					SoundManager.play(&"merge", 0.0, false)
					purchased.emit()
					_refresh())
			box.add_child(buy)
		else:
			box.add_child(UiStyle.label("закрыт", 14, UiStyle.TEXT_DIM, 3))
	elif id.is_empty():
		badge.empty = true
		box.add_child(UiStyle.label("пусто", 14, UiStyle.TEXT_DIM, 3))
	else:
		badge.id = id
		var off := UiStyle.button("СНЯТЬ", UiStyle.PANEL, 15, Vector2(110, 40))
		off.pressed.connect(func() -> void:
			Patches.toggle(id)
			_refresh())
		box.add_child(off)
	return box


func _card(id: String) -> Control:
	var info: Dictionary = Patches.CATALOG[id]
	var color := Color(str(info["color"]))
	var lvl := Patches.level(id)
	var worn := Patches.is_worn(id)
	var unlocked := Patches.unlocked(id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.card_box(UiStyle.GOLD if worn else color.lerp(UiStyle.CARD_BORDER, 0.5), 4 if worn else 3))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var badge := Badge.new()
	badge.id = id
	badge.dim = lvl == 0
	badge.custom_minimum_size = Vector2(58, 58)
	head.add_child(badge)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(texts)
	var title := UiStyle.label(str(info["title"]), 20, color if lvl > 0 else UiStyle.TEXT_DIM, 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(title)
	var dots := ""
	for i in Patches.MAX_LEVEL:
		dots += "●" if i < lvl else "○"
	texts.add_child(UiStyle.label(("Уровень %d  " % lvl) + dots if lvl > 0 else ("Не куплена" if unlocked else "За заказы Нэлл"), 14, UiStyle.GOLD if lvl > 0 else UiStyle.TEXT_DIM, 3))
	(texts.get_child(1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var desc := UiStyle.label(Patches.describe(id, maxi(lvl, 1)) + ("" if lvl == 0 or lvl >= Patches.MAX_LEVEL else "  →  " + Patches.describe(id, lvl + 1)), 16, UiStyle.TEXT, 4)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(10, 0)
	col.add_child(desc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	if not unlocked:
		row.add_child(UiStyle.label("ЗАКРЫТО · ЗАКАЗЫ НЭЛЛ", 14, UiStyle.TEXT_DIM, 3))
	elif lvl < Patches.MAX_LEVEL:
		var cost := Patches.price(id)
		var buy := UiStyle.button(("КУПИТЬ · " if lvl == 0 else "УЛУЧШИТЬ · ") + SaveService.format_coins(cost), Color("#e0a020"), 16, Vector2(0, 46))
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy.disabled = SaveService.get_coins() < cost
		buy.pressed.connect(func() -> void:
			if Patches.buy(id):
				SoundManager.play(&"merge", 0.0, false)
				if lvl == 0 and Patches.worn().size() < Patches.open_slots():
					Patches.toggle(id)
				purchased.emit()
				_refresh())
		row.add_child(buy)
	if lvl > 0:
		var full := not worn and Patches.worn().size() >= Patches.open_slots()
		var wear := UiStyle.button("СНЯТЬ" if worn else ("НЕТ МЕСТА" if full else "НАДЕТЬ"), UiStyle.PANEL if worn or full else Color("#2fae5f"), 16, Vector2(0, 46))
		wear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wear.disabled = full
		wear.pressed.connect(func() -> void:
			Patches.toggle(id)
			SoundManager.play(&"ui_click")
			_refresh())
		row.add_child(wear)
	return panel


## Значок нашивки: арт Астры, а пока — вышитый круг с буквой (кант пунктиром, как стежок).
class Badge:
	extends Control
	var id := ""
	var empty := false
	var locked := false
	var dim := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var dark := Color("#120d1c")
		if locked or empty or id.is_empty():
			var slot_art := Patches.art("slot_locked" if locked else "slot_empty")
			if slot_art != null:
				draw_texture_rect(slot_art, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
				return
			draw_circle(c, r, Color("#1c1714"))
			for i in 24:
				var a := TAU * i / 24.0
				draw_arc(c, r - 3.0, a, a + TAU / 48.0, 3, UiStyle.CARD_BORDER if empty else Color("#4a4038"), 3.0)
			var font := get_theme_default_font()
			var text := "+" if empty else "🔒"
			if locked:
				# Замок рисуем кодом: дужка и корпус.
				draw_arc(c + Vector2(0, -r * 0.12), r * 0.28, PI, TAU, 12, Color("#8a7a6a"), 4.0)
				draw_rect(Rect2(c + Vector2(-r * 0.36, -r * 0.1), Vector2(r * 0.72, r * 0.55)), Color("#8a7a6a"))
				return
			var fs := int(r)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.CARD_BORDER)
			return
		var info: Dictionary = Patches.CATALOG[id]
		var art := Patches.art(id)
		var tint := Color.WHITE if not dim else Color(0.45, 0.45, 0.5)
		if art != null:
			draw_texture_rect(art, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, tint)
			return
		var color := Color(str(info["color"]))
		draw_circle(c, r, dark)
		draw_circle(c, r - 3.0, color.darkened(0.55) * tint)
		for i in 24:
			var a := TAU * i / 24.0
			draw_arc(c, r - 6.0, a, a + TAU / 48.0, 3, color.lightened(0.2) * tint, 2.0)
		var font := get_theme_default_font()
		var letter := str(info["title"]).left(1)
		var fs := int(r * 1.05)
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := c + Vector2(-w * 0.5, fs * 0.36)
		draw_string_outline(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, dark)
		draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color.lightened(0.35) * tint)
