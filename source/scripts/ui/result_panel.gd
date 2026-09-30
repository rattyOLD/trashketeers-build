class_name ResultPanel
extends Control
## Экран конца забега: победа над боссом или смерть енота.

signal restart_pressed
signal menu_pressed

var _panel: PanelContainer
var _box: VBoxContainer
var _title: Label
var _subtitle: Label
var _stats_card: PanelContainer
var _stats_rows: VBoxContainer
var _tip_card: PanelContainer
var _tip_label: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.OUTLINE, 6, 28))
	center.add_child(_panel)

	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(560, 0)
	_box.add_theme_constant_override("separation", 20)
	_panel.add_child(_box)

	_title = UiStyle.label("", 56, UiStyle.GOLD, 12)
	_box.add_child(_title)
	_subtitle = UiStyle.label("", 26, UiStyle.TEXT, 6)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_subtitle)

	_stats_card = PanelContainer.new()
	_stats_card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.OUTLINE, 3, 20))
	_stats_rows = VBoxContainer.new()
	_stats_rows.add_theme_constant_override("separation", 10)
	_stats_card.add_child(_stats_rows)
	_box.add_child(_stats_card)

	_tip_card = PanelContainer.new()
	_tip_card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.16, 0.1, 0.05, 0.95), Color("#ff9a3d"), 4, 18))
	_tip_label = UiStyle.label("", 22, Color("#ffe2b8"), 5)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_card.add_child(_tip_label)
	_box.add_child(_tip_card)

	var again := UiStyle.button("ЕЩЁ РАЗ", UiStyle.HOT, 36, Vector2(0, 96))
	again.pressed.connect(func() -> void: restart_pressed.emit())
	_box.add_child(again)
	var menu := UiStyle.button("НА БАЗУ", UiStyle.PANEL_LIGHT, 28, Vector2(0, 76))
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	_box.add_child(menu)


## Первая строка - заголовок-причина, «ключ: значение» - строки статистики, остальное - совет в отдельной плашке.
func open(victory: bool, lines: PackedStringArray, title: String = "") -> void:
	_title.text = title if not title.is_empty() else ("ПОБЕДА!" if victory else "ЕНОТ ПОВЕРЖЕН")
	_title.add_theme_color_override("font_color", UiStyle.GOLD if victory else UiStyle.DANGER)
	_subtitle.text = lines[0] if not lines.is_empty() else ""
	_subtitle.visible = not _subtitle.text.is_empty()
	for child in _stats_rows.get_children():
		child.queue_free()
	var notes: Array[String] = []
	for i in range(1, lines.size()):
		var split := lines[i].find(": ")
		if split > 0 and split < 24 and not lines[i].begins_with("Совет"):
			_stats_rows.add_child(_stat_row(lines[i].substr(0, split), lines[i].substr(split + 2)))
		else:
			notes.append(lines[i])
	_stats_card.visible = _stats_rows.get_child_count() > 0
	_tip_label.text = "\n".join(notes)
	_tip_card.visible = not notes.is_empty()
	visible = true
	UiStyle.pop_in(_panel)


func _stat_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var left := UiStyle.label(key, 22, UiStyle.TEXT_DIM, 4)
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := UiStyle.label(value, 26, UiStyle.GOLD, 5)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	return row
