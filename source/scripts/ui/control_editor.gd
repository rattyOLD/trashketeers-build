class_name ControlEditor
extends Control
## Редактор раскладки: кнопки навыка, слотов оружия и «ВЗЯТЬ» перетаскиваются пальцем,
## размер и прозрачность — ползунками, есть режимы правши/левши, фиксированный джойстик
## и три ячейки пресетов. Всё живёт в Controls и применяется в бою при следующем запуске.

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _items: Dictionary = {}
var _selected := "dash"
var _dragging := ""
var _grab_offset := Vector2.ZERO
var _size_slider: HSlider
var _selected_label: Label
var _joystick_slider: HSlider
var _opacity_slider: HSlider
var _element_opacity_slider: HSlider
var _fixed_toggle: Button
var _swipe_toggle: Button
var _preset_buttons: Array[Button] = []
var _collapsed := false
var _summary: Control
var _options_scroll: ScrollContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100


func select(id: String) -> void:
	if Controls.ELEMENTS.has(id):
		_selected = id


func open() -> void:
	ScreenSafeArea.fit(self, get_viewport_rect().size)
	for child in get_children():
		child.queue_free()
	_items.clear()
	_build()
	visible = true
	_sync()


func _build() -> void:
	var slot_bar := BattleControls.SlotBar.new()
	slot_bar.editor_preview = true
	var demo := [WeaponDB.get_weapon(&"pistol_v1"), WeaponDB.get_weapon(&"smg_v1"), WeaponDB.get_weapon(&"trash_shotgun_v1")]
	slot_bar.set_slots(demo, 0, Controls.weapon_slot_count())
	var interact := BattleControls.InteractButton.new()
	interact.editor_preview = true
	interact.show_for(demo[1], "в пустой слот 2")
	interact.visible = true
	var dash := DashPreview.new()
	dash.caption = "НАВЫК"
	var dodge := DashPreview.new()
	dodge.caption = "РЫВОК"
	_items = {"dash": dash, "dodge": dodge, "slots": slot_bar, "interact": interact}
	for id in _items:
		_items[id].mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_items[id])

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.06, 0.03, 0.12, 0.94), UiStyle.NEON, 4, 22))
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.offset_left = 14.0
	_panel.offset_right = -14.0
	_panel.clip_contents = true
	_panel.offset_top = 14.0
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_panel.add_child(_body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiStyle.label("РЕДАКТОР УПРАВЛЕНИЯ", 26, UiStyle.GOLD, 7)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.custom_minimum_size = Vector2(0, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)
	var fold := UiStyle.button("СВЕРНУТЬ", UiStyle.PANEL_LIGHT, 18, Vector2(120, 52))
	fold.pressed.connect(_toggle_fold)
	head.add_child(fold)
	var done := UiStyle.button("ГОТОВО", Color("#5fd11f"), 20, Vector2(110, 52))
	done.pressed.connect(_finish)
	head.add_child(done)
	_body.add_child(head)

	_summary = VBoxContainer.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_theme_constant_override("separation", 8)
	_options_scroll = DragScroll.new()
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options_scroll.custom_minimum_size = Vector2(0, 300)
	_body.add_child(_options_scroll)
	_options_scroll.add_child(_summary)
	var hint := UiStyle.label("Тащи кнопки пальцем. Тап по кнопке выбирает её: ниже её размер и прозрачность.", 18, UiStyle.TEXT_DIM, 4)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(hint)

	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 8)
	for pair in [["ПРАВША", false], ["ЛЕВША", true]]:
		var b := UiStyle.button(pair[0], UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var left: bool = pair[1]
		b.pressed.connect(func() -> void:
			Controls.apply_preset(left)
			_sync())
		hand_row.add_child(b)
	_summary.add_child(hand_row)
	var big := UiStyle.button("БОЛЬШИЕ ПАЛЬЦЫ", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	big.pressed.connect(func() -> void:
		Controls.apply_big(bool(Controls.get_value("left_handed")))
		_sync())
	_summary.add_child(big)

	_selected_label = UiStyle.label("", 22, UiStyle.NEON, 5)
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summary.add_child(_selected_label)
	_size_slider = _slider(_summary, "Размер кнопки", 0.6, 1.6, func(v: float) -> void:
		var e := Controls.element(_selected)
		Controls.set_element(_selected, float(e["x"]), float(e["y"]), v)
		Controls.save()
		_place_all())
	_element_opacity_slider = _slider(_summary, "Прозрачность кнопки", 0.2, 1.0, func(v: float) -> void:
		Controls.set_element_opacity(_selected, v)
		Controls.save()
		_place_all())
	_joystick_slider = _slider(_summary, "Размер джойстика", 0.7, 1.5, func(v: float) -> void:
		Controls.set_value("joystick_scale", v)
		queue_redraw())
	_opacity_slider = _slider(_summary, "Прозрачность всех", 0.3, 1.0, func(v: float) -> void:
		Controls.set_value("opacity", v)
		_place_all())

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 8)
	_fixed_toggle = UiStyle.button("", UiStyle.PANEL_LIGHT, 19, Vector2(0, 58))
	_fixed_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fixed_toggle.pressed.connect(func() -> void:
		Controls.set_value("joystick_fixed", not bool(Controls.get_value("joystick_fixed")))
		_sync())
	toggles.add_child(_fixed_toggle)
	_swipe_toggle = UiStyle.button("", UiStyle.PANEL_LIGHT, 19, Vector2(0, 58))
	_swipe_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swipe_toggle.pressed.connect(func() -> void:
		Controls.set_value("swipe_switch", not bool(Controls.get_value("swipe_switch")))
		_sync())
	toggles.add_child(_swipe_toggle)
	_summary.add_child(toggles)

	var presets := UiStyle.label("ПРЕСЕТЫ", 22, UiStyle.NEON, 5)
	presets.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summary.add_child(presets)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	_preset_buttons.clear()
	for i in Controls.PRESET_SLOTS:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		var save_button := UiStyle.button("Сохр. %d" % (i + 1), UiStyle.PANEL_LIGHT, 18, Vector2(0, 50))
		save_button.pressed.connect(func() -> void:
			Controls.save_preset(i)
			_sync())
		column.add_child(save_button)
		var load_button := UiStyle.button("Загр. %d" % (i + 1), UiStyle.PANEL_LIGHT, 18, Vector2(0, 50))
		load_button.pressed.connect(func() -> void:
			if Controls.load_preset(i):
				_sync())
		column.add_child(load_button)
		_preset_buttons.append(load_button)
		preset_row.add_child(column)
	_summary.add_child(preset_row)
	var reset := UiStyle.button("СБРОСИТЬ РАСКЛАДКУ", Color("#b03a5a"), 20, Vector2(0, 54))
	reset.pressed.connect(func() -> void:
		Controls.apply_preset(bool(Controls.get_value("left_handed")))
		_sync())
	_summary.add_child(reset)


func _slider(parent: Control, caption: String, low: float, high: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := UiStyle.label(caption, 20, UiStyle.TEXT, 5)
	label.custom_minimum_size = Vector2(190, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 40)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _toggle_fold() -> void:
	_collapsed = not _collapsed
	_summary.visible = not _collapsed
	_options_scroll.visible = not _collapsed
	((_body.get_child(0) as HBoxContainer).get_child(1) as Button).text = "РАЗВЕРНУТЬ" if _collapsed else "СВЕРНУТЬ"
	_panel.reset_size()


func _finish() -> void:
	Controls.save()
	visible = false
	closed.emit()


func _sync() -> void:
	var e := Controls.element(_selected)
	_selected_label.text = "Выбрано: %s" % Controls.ELEMENT_TITLES[_selected]
	_size_slider.set_value_no_signal(float(e["s"]))
	_joystick_slider.set_value_no_signal(float(Controls.get_value("joystick_scale")))
	_opacity_slider.set_value_no_signal(float(Controls.get_value("opacity")))
	_element_opacity_slider.set_value_no_signal(Controls.element_opacity(_selected))
	_fixed_toggle.text = "Джойстик: %s" % ("фиксированный" if bool(Controls.get_value("joystick_fixed")) else "плавающий")
	_swipe_toggle.text = "Свайп смены ствола: %s" % ("вкл" if bool(Controls.get_value("swipe_switch")) else "выкл")
	for i in _preset_buttons.size():
		_preset_buttons[i].disabled = not Controls.has_preset(i)
	_place_all()


func _place_all() -> void:
	var count := Controls.weapon_slot_count()
	for id in _items:
		var base: Vector2 = BattleControls.slots_base_size(count) if id == "slots" else Vector2.ZERO
		Controls.place(_items[id], id, size, base)
		_items[id].modulate.a = float(Controls.get_value("opacity")) * Controls.element_opacity(id)
		_items[id].queue_redraw()
	queue_redraw()


func _joystick_center() -> Vector2:
	return Vector2(size.x * (0.84 if bool(Controls.get_value("left_handed")) else 0.16), size.y * 0.8)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.083, 0.079, 0.075, 0.97))
	var step := size.x / 12.0
	for i in 13:
		draw_line(Vector2(i * step, 0), Vector2(i * step, size.y), Color(1, 1, 1, 0.035), 2.0)
	for j in int(size.y / step) + 1:
		draw_line(Vector2(0, j * step), Vector2(size.x, j * step), Color(1, 1, 1, 0.035), 2.0)
	var radius := 110.0 * float(Controls.get_value("joystick_scale"))
	var center := _joystick_center()
	draw_circle(center, radius, Color(0.05, 0.02, 0.1, 0.5))
	draw_arc(center, radius, 0.0, TAU, 48, Color(UiStyle.NEON, 0.6), 5.0)
	draw_circle(center, 46.0 * float(Controls.get_value("joystick_scale")), Color(UiStyle.NEON, 0.6))
	draw_string(ThemeDB.fallback_font, center + Vector2(-90, radius + 34.0), "ДЖОЙСТИК", HORIZONTAL_ALIGNMENT_CENTER, 180, 22, Color(1, 1, 1, 0.5))
	if _items.has(_selected):
		var item: Control = _items[_selected]
		draw_rect(Rect2(item.position, item.size).grow(8.0), Color(UiStyle.GOLD, 0.95), false, 4.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = ""
			for id in ["interact", "slots", "dodge", "dash"]:
				var item: Control = _items[id]
				if Rect2(item.position, item.size).grow(12.0).has_point(event.position):
					_dragging = id
					_selected = id
					_grab_offset = event.position - (item.position + item.size * 0.5)
					_sync()
					break
		else:
			if _dragging != "":
				Controls.save()
			_dragging = ""
	elif event is InputEventMouseMotion and _dragging != "":
		var center: Vector2 = event.position - _grab_offset
		var e := Controls.element(_dragging)
		var y_min := 0.16 if _collapsed else 0.16
		Controls.set_element(_dragging, center.x / size.x, maxf(center.y / size.y, y_min), float(e["s"]))
		_place_all()


class DashPreview:
	extends Control
	var caption := "НАВЫК"

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.46
		draw_circle(c, r, Color(0.06, 0.03, 0.12, 0.6))
		draw_arc(c, r, 0.0, TAU, 48, Color(UiStyle.NEON, 0.9), 5.0, true)
		var tip := c + Vector2(30, 0) * (size.x / 160.0)
		var k := size.x / 160.0
		var arrow := PackedVector2Array([tip, c + Vector2(4, -22) * k, c + Vector2(4, -9) * k, c + Vector2(-20, -9) * k, c + Vector2(-20, 9) * k, c + Vector2(4, 9) * k, c + Vector2(4, 22) * k])
		draw_colored_polygon(arrow, Color(1, 1, 1, 0.95))
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.78), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, maxi(12, roundi(size.x * 0.14)), Color.WHITE)
