class_name TipCard
extends CanvasLayer
## Карточка-подсказка: мир на паузе, название, шуточный текст, характеристики. «Понятно» продолжает игру,
## «Убрать подсказки» выключает такие карточки насовсем (их можно вернуть в настройках).

signal finished

const MIN_OPEN_MS := 450

var _paused_before := false
var _done := false
var _opened_ms := 0


func _init() -> void:
	layer = 71
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(card: Dictionary) -> void:
	_paused_before = get_tree().paused
	get_tree().paused = true
	_opened_ms = Time.get_ticks_msec()
	var color: Color = card.get("color", UiStyle.NEON)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.06, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	var style := UiStyle.box(Color(0.1, 0.07, 0.2, 0.98), color, 6, 28)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var width := clampf(get_viewport().get_visible_rect().size.x - 60.0, 320.0, 700.0)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	box.add_child(UiStyle.label("НОВОЕ!", 22, UiStyle.TEXT_DIM, 4))
	var title := UiStyle.label(str(card.get("title", "")).to_upper(), 40, color, 10)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	if card.has("weapon_icon"):
		var art := WeaponIcons.IconRect.new(card["weapon_icon"], card.get("weapon_color", color), Vector2(220, 92))
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(art)
	var joke := UiStyle.label(str(card.get("joke", "")), 26, UiStyle.TEXT, 6)
	joke.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	joke.custom_minimum_size = Vector2(width - 50.0, 0)
	box.add_child(joke)

	var stats := PanelContainer.new()
	var stats_style := UiStyle.box(Color("#1f1738"), Color(color, 0.45), 3, 16)
	stats_style.set_content_margin_all(12)
	stats.add_theme_stylebox_override("panel", stats_style)
	box.add_child(stats)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	stats.add_child(rows)
	for entry: Variant in card.get("stats", []):
		var pair: Array = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var key := UiStyle.label(str(pair[0]), 20, UiStyle.TEXT_DIM, 4)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(key)
		var value := UiStyle.label(str(pair[1]), 22, UiStyle.TEXT, 5)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(width * 0.5, 0)
		row.add_child(value)
		rows.add_child(row)

	var ok := UiStyle.button("ПОНЯТНО", color.darkened(0.25), 32, Vector2(0, 84))
	ok.pressed.connect(_finish)
	box.add_child(ok)
	var off := UiStyle.button("УБРАТЬ ПОДСКАЗКИ", UiStyle.PANEL_LIGHT, 20, Vector2(0, 56))
	off.pressed.connect(func() -> void:
		Tips.set_enabled(false)
		_finish())
	box.add_child(off)
	box.add_child(UiStyle.label("Вернуть можно в настройках", 16, UiStyle.TEXT_DIM, 3))
	SoundManager.play(&"ui_confirm", -6.0)


func _finish() -> void:
	if _done or Time.get_ticks_msec() - _opened_ms < MIN_OPEN_MS:
		return
	_done = true
	get_tree().paused = _paused_before
	finished.emit()
	queue_free()
