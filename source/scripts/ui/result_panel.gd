class_name ResultPanel
extends Control
## Экран конца забега: победа над боссом или смерть енота.

signal restart_pressed
signal menu_pressed
signal upgrade_pressed

var _center: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _title: Label
var _subtitle: Label
var _stats_card: PanelContainer
var _stats_rows: VBoxContainer
var _tip_card: PanelContainer
var _tip_label: Label
var _tip_scroll: DragScroll
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

	_center = Control.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	resized.connect(_fit_layout.call_deferred)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.CARD_BORDER, 2, 12))
	_center.add_child(_panel)
	_panel.minimum_size_changed.connect(_fit_layout.call_deferred)

	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(880, 0)
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)

	_title = UiStyle.label("", 36, UiStyle.GOLD, 4)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинные заголовки переносятся, а не растягивают рамку за экран
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_title)
	_subtitle = UiStyle.label("", 20, UiStyle.TEXT, 3)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_subtitle)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	_box.add_child(body)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio = 1.0
	body.add_child(details)
	var character := VBoxContainer.new()
	character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character.size_flags_stretch_ratio = 1.0
	character.add_theme_constant_override("separation", 10)
	body.add_child(character)
	_mood_slot = VBoxContainer.new()
	character.add_child(_mood_slot)

	_stats_card = PanelContainer.new()
	_stats_card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.OUTLINE, 3, 20))
	_stats_rows = VBoxContainer.new()
	_stats_rows.add_theme_constant_override("separation", 4)
	_stats_card.add_child(_stats_rows)
	details.add_child(_stats_card)

	_tip_card = PanelContainer.new()
	_tip_card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.16, 0.1, 0.05, 0.95), Color("#ff9a3d"), 4, 18))
	_tip_label = UiStyle.label("", 19, Color("#ffe2b8"), 5)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_scroll = DragScroll.new()
	_tip_scroll.custom_minimum_size = Vector2(0, 120)
	_tip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_scroll.add_child(_tip_label)
	_tip_card.add_child(_tip_scroll)
	character.add_child(_tip_card)

	var buttons := BoxContainer.new()
	buttons.vertical = false
	buttons.add_theme_constant_override("separation", 14)
	_box.add_child(buttons)
	_upgrade_button = UiStyle.button("ПРОКАЧАТЬСЯ", Color("#2fae5f"), 24, Vector2(0, 64))
	_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_button.pressed.connect(func() -> void: upgrade_pressed.emit())
	_upgrade_button.visible = false
	buttons.add_child(_upgrade_button)
	var again := UiStyle.button("ПОВТОРИТЬ", UiStyle.HOT, 26, Vector2(0, 64))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.size_flags_stretch_ratio = 1.2
	again.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(again)
	var menu := UiStyle.button("НА БАЗУ", UiStyle.PANEL_LIGHT, 24, Vector2(0, 64))
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
	_mood_slot.add_child(HeroMoodCard.new(SaveService.get_character(), victory, "", 112.0))
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
	_tip_scroll.scroll_vertical = 0
	visible = true
	_appear.call_deferred()


## Родитель HUD уже учитывает вырезы; окно оставляет поля, а длинный совет прокручивается отдельно.
func _fit_width() -> void:
	_box.custom_minimum_size.x = minf(880.0, maxf(600.0, size.x - 80.0))


func _fit_layout() -> void:
	if not is_inside_tree():
		return
	_fit_width()
	var minimum := _panel.get_combined_minimum_size()
	if minimum.x <= 0.0 or minimum.y <= 0.0:
		return
	var available := (size - Vector2(80, 80)).max(Vector2(1, 1))
	var factor := minf(1.0, minf(available.x / minimum.x, available.y / minimum.y))
	_panel.size = minimum
	_panel.position = (size - minimum) * 0.5
	_panel.pivot_offset = minimum * 0.5
	_panel.set_meta("ui_scale", factor)
	_panel.scale = Vector2.ONE * factor


func _appear() -> void:
	_fit_layout()
	UiStyle.pop_in(_panel)


func _stat_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := UiStyle.label(key, 20, UiStyle.TEXT_DIM, 4)
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	row.add_child(left)
	var right := UiStyle.label(value, 22, UiStyle.GOLD, 5)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	row.add_child(right)
	return row
