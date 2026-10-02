class_name ResultPanel
extends Control
## Экран конца забега: победа над боссом или смерть енота.

signal restart_pressed
signal menu_pressed
signal upgrade_pressed

var _panel: PanelContainer
var _box: VBoxContainer
var _title: Label
var _subtitle: Label
var _stats_card: PanelContainer
var _stats_rows: VBoxContainer
var _tip_card: PanelContainer
var _tip_label: Label
var _upgrade_button: Button
var _mood_slot: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.074, 0.071, 0.066, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.OUTLINE, 6, 28))
	center.add_child(_panel)

	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(560 if Orient.portrait else 720, 0)
	_box.add_theme_constant_override("separation", 12)
	_panel.add_child(_box)

	_title = UiStyle.label("", 46, UiStyle.GOLD, 11)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинные заголовки переносятся, а не растягивают рамку за экран
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_title)
	_subtitle = UiStyle.label("", 22, UiStyle.TEXT, 6)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_subtitle)
	_mood_slot = VBoxContainer.new()
	_box.add_child(_mood_slot)

	_stats_card = PanelContainer.new()
	_stats_card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.OUTLINE, 3, 20))
	_stats_rows = VBoxContainer.new()
	_stats_rows.add_theme_constant_override("separation", 6)
	_stats_card.add_child(_stats_rows)
	_box.add_child(_stats_card)

	_tip_card = PanelContainer.new()
	_tip_card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.16, 0.1, 0.05, 0.95), Color("#ff9a3d"), 4, 18))
	_tip_label = UiStyle.label("", 19, Color("#ffe2b8"), 5)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_card.add_child(_tip_label)
	_box.add_child(_tip_card)

	var buttons := BoxContainer.new()
	buttons.vertical = Orient.portrait
	buttons.add_theme_constant_override("separation", 14)
	_box.add_child(buttons)
	_upgrade_button = UiStyle.button("ПРОКАЧАТЬСЯ", Color("#2fae5f"), 28, Vector2(0, 76))
	_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_button.pressed.connect(func() -> void: upgrade_pressed.emit())
	_upgrade_button.visible = false
	buttons.add_child(_upgrade_button)
	var again := UiStyle.button("ПОВТОРИТЬ", UiStyle.HOT, 32, Vector2(0, 96 if Orient.portrait else 76))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.size_flags_stretch_ratio = 1.0 if Orient.portrait else 1.5
	again.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(again)
	var menu := UiStyle.button("НА БАЗУ", UiStyle.PANEL_LIGHT, 26, Vector2(0, 76))
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(menu)


## Первая строка - заголовок-причина, «ключ: значение» - строки статистики, остальное - совет в отдельной плашке.
const WIN_TITLES := ["ПОБЕДА!", "ЖИВОЙ! ДАЖЕ УДИВИЛИСЬ", "ГРАЦИОЗНО, КАК МУСОРНЫЙ БАК", "ЕНОТ ДОВОЛЕН", "КРЫСЫ В СЛЁЗАХ"]
const LOSE_TITLES := ["ЕНОТ ПОВЕРЖЕН", "ЕНОТ ОТДЫХАЕТ", "ТЕБЯ ВЫНЕСЛИ", "КРЫСЫ ПЛЯШУТ", "СЛИВ ЗАСЧИТАН", "ЕНОТ ПОСКОЛЬЗНУЛСЯ", "НЭЛЛ ВЗДОХНУЛА"]


func open(victory: bool, lines: PackedStringArray, title: String = "", can_upgrade: bool = true) -> void:
	_fit_width()
	_title.text = title if not title.is_empty() else (WIN_TITLES.pick_random() if victory else LOSE_TITLES.pick_random())
	_title.add_theme_color_override("font_color", UiStyle.GOLD if victory else UiStyle.DANGER)
	_subtitle.text = lines[0] if not lines.is_empty() else ""
	_subtitle.visible = not _subtitle.text.is_empty()
	for old in _mood_slot.get_children():
		old.queue_free()
	_mood_slot.add_child(HeroMoodCard.new(SaveService.get_character(), victory))
	for child in _stats_rows.get_children():
		child.queue_free()
	var notes: Array[String] = []
	for i in range(1, lines.size()):
		var split := lines[i].find(": ")
		if split > 0 and split < 24 and lines[i].length() - split - 2 <= 22 and not lines[i].begins_with("Совет"):
			_stats_rows.add_child(_stat_row(lines[i].substr(0, split), lines[i].substr(split + 2)))
		else:
			notes.append(lines[i])
	_stats_card.visible = _stats_rows.get_child_count() > 0
	_tip_label.text = "\n".join(notes)
	_tip_card.visible = not notes.is_empty()
	_upgrade_button.visible = not victory and can_upgrade
	visible = true
	UiStyle.pop_in(_panel)


## Рамка не шире экрана: по бокам остаётся поле, внутри всё переносится по словам.
func _fit_width() -> void:
	var wide := 560.0 if Orient.portrait else 720.0
	var avail := get_viewport_rect().size.x - 56.0
	_box.custom_minimum_size = Vector2(clampf(minf(wide, avail), 240.0, wide), 0)


func _stat_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := UiStyle.label(key, 22, UiStyle.TEXT_DIM, 4)
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	row.add_child(left)
	var right := UiStyle.label(value, 26, UiStyle.GOLD, 5)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	row.add_child(right)
	return row
