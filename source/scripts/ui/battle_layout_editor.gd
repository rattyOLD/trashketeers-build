class_name BattleLayoutEditor
extends Control
## Правка боевого интерфейса прямо в бою. Фон прозрачный: игрок видит живой интерфейс и сразу понимает,
## как всё будет выглядеть. Любой элемент (кнопки, здоровье, монеты, миникарта, задание и остальное)
## перетаскивается пальцем, масштабируется и меняет прозрачность. Игра при этом стоит на паузе.

signal closed

var hud: Hud

var _selected := ""
var _dragging := ""
var _grab := Vector2.ZERO
var _panel: PanelContainer
var _body: VBoxContainer
var _summary: VBoxContainer
var _fold: Button
var _collapsed := false
var _title: Label
var _size_slider: HSlider
var _alpha_slider: HSlider
var _joystick_slider: HSlider
var _fixed_toggle: Button
var _swipe_toggle: Button
var _preset_buttons: Array[Button] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100


func select(id: String) -> void:
	_selected = id


func open() -> void:
	_build()
	visible = true
	_sync()


func _build() -> void:
	var resume := UiStyle.button("", UiStyle.GOLD, 26, Vector2(120, 120))
	var icon := BattlePanels.icon_rect(BattlePanels.icon("pause"), 64)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.offset_left = -32
	icon.offset_right = 32
	icon.offset_top = -38
	icon.offset_bottom = 26
	resume.add_child(icon)
	UiStyle.anchor(resume, Vector2(0.5, 0.5), Rect2(-60, -60, 120, 120))
	resume.pressed.connect(_finish)
	add_child(resume)
	var caption := UiStyle.label("ПАУЗА. Тап, чтобы продолжить", 20, UiStyle.TEXT, 6)
	UiStyle.anchor(caption, Vector2(0.5, 0.5), Rect2(-250, 70, 250, 110))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.06, 0.03, 0.12, 0.62), UiStyle.NEON, 4, 22))
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 14.0
	_panel.offset_right = -14.0
	_panel.offset_top = -90.0
	_panel.offset_bottom = -90.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_panel.add_child(_body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiStyle.label("РЕДАКТОР УПРАВЛЕНИЯ", 24, UiStyle.GOLD, 7)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.custom_minimum_size = Vector2(0, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(title)
	_fold = UiStyle.button("СВЕРНУТЬ", UiStyle.PANEL_LIGHT, 17, Vector2(118, 48))
	_fold.pressed.connect(_toggle_fold)
	head.add_child(_fold)
	var done := UiStyle.button("ГОТОВО", Color("#5fd11f"), 19, Vector2(108, 48))
	done.pressed.connect(_finish)
	head.add_child(done)
	_body.add_child(head)

	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 6)
	_body.add_child(_summary)
	_title = UiStyle.label("", 21, UiStyle.NEON, 5)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(300, 0)
	_summary.add_child(_title)
	_size_slider = _slider("Размер", 0.5, 1.8, func(v: float) -> void:
		if not _selected.is_empty():
			Controls.set_scale_of(_selected, v)
			_refresh())
	_alpha_slider = _slider("Прозрачность", 0.2, 1.0, func(v: float) -> void:
		if not _selected.is_empty():
			Controls.set_opacity_of(_selected, v)
			_refresh())
	_joystick_slider = _slider("Джойстик", 0.7, 1.5, func(v: float) -> void:
		Controls.set_value("joystick_scale", v))

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 6)
	_fixed_toggle = _button("", 17, func() -> void:
		Controls.set_value("joystick_fixed", not bool(Controls.get_value("joystick_fixed")))
		_sync())
	toggles.add_child(_fixed_toggle)
	_swipe_toggle = _button("", 17, func() -> void:
		Controls.set_value("swipe_switch", not bool(Controls.get_value("swipe_switch")))
		_sync())
	toggles.add_child(_swipe_toggle)
	_summary.add_child(toggles)

	var hands := HBoxContainer.new()
	hands.add_theme_constant_override("separation", 6)
	hands.add_child(_button("ПРАВША", 18, func() -> void:
		Controls.apply_preset(false)
		_refresh()))
	hands.add_child(_button("ЛЕВША", 18, func() -> void:
		Controls.apply_preset(true)
		_refresh()))
	hands.add_child(_button("БОЛЬШИЕ ПАЛЬЦЫ", 18, func() -> void:
		Controls.apply_big(bool(Controls.get_value("left_handed")))
		_refresh()))
	_summary.add_child(hands)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	_preset_buttons.clear()
	for i in Controls.PRESET_SLOTS:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		column.add_child(_button("Сохр. %d" % (i + 1), 16, func() -> void:
			Controls.save_preset(i)
			_sync()))
		var load_button := _button("Загр. %d" % (i + 1), 16, func() -> void:
			if Controls.load_preset(i):
				_refresh())
		column.add_child(load_button)
		_preset_buttons.append(load_button)
		presets.add_child(column)
	_summary.add_child(presets)

	var resets := HBoxContainer.new()
	resets.add_theme_constant_override("separation", 6)
	var reset_one := _button("СБРОСИТЬ ЭЛЕМЕНТ", 17, func() -> void:
		if not _selected.is_empty():
			Controls.hud_reset(_selected)
			_refresh())
	resets.add_child(reset_one)
	var reset_all := _button("СБРОСИТЬ ВСЁ", 17, func() -> void:
		Controls.hud_reset_all()
		Controls.apply_preset(bool(Controls.get_value("left_handed")))
		_refresh())
	resets.add_child(reset_all)
	_summary.add_child(resets)
	var hint := UiStyle.label("Тащи любой элемент пальцем. Тап выбирает его для настройки.", 16, UiStyle.TEXT_DIM, 4)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0)
	_summary.add_child(hint)


func _button(text: String, font_size: int, action: Callable) -> Button:
	var button := UiStyle.button(text, UiStyle.PANEL_LIGHT, font_size, Vector2(0, 46))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _slider(caption: String, low: float, high: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := UiStyle.label(caption, 18, UiStyle.TEXT, 5)
	label.custom_minimum_size = Vector2(150, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 34)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	_summary.add_child(row)
	return slider


func _toggle_fold() -> void:
	_collapsed = not _collapsed
	_summary.visible = not _collapsed
	_fold.text = "РАЗВЕРНУТЬ" if _collapsed else "СВЕРНУТЬ"
	_panel.reset_size()


func _finish() -> void:
	Controls.save()
	visible = false
	closed.emit()


func _refresh() -> void:
	hud.apply_layout()
	_sync()


func _sync() -> void:
	var has := not _selected.is_empty()
	_title.text = "Выбрано: %s" % Controls.title_of(_selected) if has else "Тапни по элементу, чтобы выбрать его"
	_size_slider.editable = has
	_alpha_slider.editable = has
	if has:
		_size_slider.set_value_no_signal(Controls.scale_of(_selected))
		_alpha_slider.set_value_no_signal(Controls.opacity_of(_selected))
	_joystick_slider.set_value_no_signal(float(Controls.get_value("joystick_scale")))
	_fixed_toggle.text = "Джойстик: %s" % ("фикс." if bool(Controls.get_value("joystick_fixed")) else "плавающий")
	_swipe_toggle.text = "Свайп ствола: %s" % ("вкл" if bool(Controls.get_value("swipe_switch")) else "выкл")
	for i in _preset_buttons.size():
		_preset_buttons[i].disabled = not Controls.has_preset(i)
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if hud == null:
		return
	for id in hud.editable_ids():
		var rect := hud.element_rect(id)
		if rect.size.x < 1.0:
			continue
		if id == _selected:
			draw_rect(rect.grow(6.0), Color(UiStyle.GOLD, 0.95), false, 4.0)
		else:
			draw_rect(rect.grow(3.0), Color(UiStyle.NEON, 0.5), false, 2.0)


func _pick(point: Vector2) -> String:
	var best := ""
	var best_area := INF
	for id in hud.editable_ids():
		var rect := hud.element_rect(id).grow(10.0)
		if rect.has_point(point) and rect.get_area() < best_area:
			best_area = rect.get_area()
			best = id
	return best


func _gui_input(event: InputEvent) -> void:
	if hud == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if button.pressed:
			var id := _pick(button.position)
			_dragging = id
			if not id.is_empty():
				_selected = id
				_grab = button.position - hud.element_rect(id).get_center()
				_sync()
		else:
			if not _dragging.is_empty():
				Controls.save()
			_dragging = ""
	elif event is InputEventMouseMotion and not _dragging.is_empty():
		var center := (event as InputEventMouseMotion).position - _grab
		var fx := clampf(center.x / size.x, 0.04, 0.96)
		var fy := clampf(center.y / size.y, 0.03, 0.97)
		if Controls.is_hud_element(_dragging):
			Controls.hud_set(_dragging, {"x": fx, "y": fy})
		else:
			var e := Controls.element(_dragging)
			Controls.set_element(_dragging, fx, fy, float(e["s"]))
		hud.apply_layout()
