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
var _panel_grab := Vector2.ZERO
var _panel_drag := false
var _body: VBoxContainer
var _summary: VBoxContainer
var _summary_scroll: ScrollContainer
var _fold: Button
var _collapsed := false
var _title: Label
var _size_slider: HSlider
var _alpha_slider: HSlider
var _joystick_slider: HSlider
var _zones_toggle: Button
var _fixed_toggle: Button
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
	var resume := UiStyle.flat_button(Vector2(80, 80))
	resume.modulate.a = 0.8
	var icon := BattlePanels.icon_rect(BattlePanels.icon("pause"), 80)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	resume.add_child(icon)
	UiStyle.anchor(resume, Vector2(0.5, 0.5), Rect2(-40, -40, 80, 80))
	resume.pressed.connect(_finish)
	add_child(resume)
	var caption := UiStyle.label("ПАУЗА. Тап, чтобы продолжить", 20, UiStyle.TEXT, 6)
	UiStyle.anchor(caption, Vector2(0.5, 0.5), Rect2(-250, 48, 250, 88))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.06, 0.03, 0.12, 0.62), UiStyle.NEON, 4, 22))
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 14.0
	_panel.offset_right = -14.0
	_panel.offset_top = -10.0
	_panel.offset_bottom = -10.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
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

	# Настройки листаются внутри панели: в горизонтали их полная высота больше экрана и верх уезжал за край.
	_summary_scroll = DragScroll.new()
	_summary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_summary_scroll.scroll_deadzone = 12
	_body.add_child(_summary_scroll)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 6)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_scroll.add_child(_summary)
	_summary.minimum_size_changed.connect(_fit_summary.call_deferred)
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
	_zones_toggle = _button("", 17, func() -> void:
		Controls.set_value("stick_zones", "half" if str(Controls.get_value("stick_zones")) == "quarter" else "quarter")
		_sync())
	toggles.add_child(_zones_toggle)
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
	var hint := UiStyle.label("Тащи любой элемент пальцем. Эту панель тоже можно таскать за любое пустое место.", 16, UiStyle.TEXT_DIM, 4)
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


func _fit_summary() -> void:
	if _summary_scroll == null or not is_inside_tree():
		return
	var limit := get_viewport_rect().size.y * (0.62 if Orient.portrait else 0.4)
	_summary_scroll.custom_minimum_size.y = minf(_summary.get_combined_minimum_size().y, limit)
	_snap_panel()


## Высота панели — по содержимому, нижний край на месте (панель растёт вверх); ширину не трогаем.
func _snap_panel() -> void:
	_panel.offset_top = _panel.offset_bottom

func _toggle_fold() -> void:
	_collapsed = not _collapsed
	_summary_scroll.visible = not _collapsed
	_fold.text = "РАЗВЕРНУТЬ" if _collapsed else "СВЕРНУТЬ"
	_snap_panel()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		_panel_drag = button.pressed
		if button.pressed:
			var rect := _panel.get_global_rect()
			if _panel.anchor_right > 0.0:
				_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
				_panel.custom_minimum_size.x = rect.size.x
				_panel.size = rect.size
				_panel.position = rect.position
			_panel_grab = button.global_position - _panel.global_position
	elif event is InputEventMouseMotion and _panel_drag:
		var target := (event as InputEventMouseMotion).global_position - _panel_grab
		_panel.position = Vector2(
			clampf(target.x, 0.0, maxf(size.x - _panel.size.x, 0.0)),
			clampf(target.y, 0.0, maxf(size.y - 80.0, 0.0)))
		get_viewport().set_input_as_handled()


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
	_zones_toggle.text = "Зоны: %s" % ("четверти" if str(Controls.get_value("stick_zones")) == "quarter" else "половины")
	for i in _preset_buttons.size():
		_preset_buttons[i].disabled = not Controls.has_preset(i)
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if hud == null:
		return
	if str(Controls.get_value("stick_zones")) == "quarter":
		# Четверти стиков: подсвечиваем, где ловит ходьба и где стрельба (пустые четверти — свободны).
		var half := size * 0.5
		for id in ["move", "aim"]:
			var q := Controls.quarter_of(Controls.stick_home(id, size), size)
			var zone := Rect2(Vector2(half.x * (q % 2), half.y * (q >> 1)), half)
			var tint := UiStyle.NEON if id == "move" else Color("#ff6a3d")
			draw_rect(zone, Color(tint, 0.06))
			draw_rect(zone.grow(-4.0), Color(tint, 0.35), false, 3.0)
	for id in hud.editable_ids():
		var rect := _rect(id)
		if rect.size.x < 1.0:
			continue
		if id == "move" or id == "aim":
			# Стики рисуются только под пальцем — в редакторе показываем их кругом с подписью.
			var c := rect.get_center()
			var r := rect.size.x * 0.5
			var tint := UiStyle.NEON if id == "move" else Color("#ff6a3d")
			draw_circle(c, r, Color(tint, 0.12))
			draw_arc(c, r, 0.0, TAU, 48, Color(tint, 0.8), 4.0, true)
			draw_circle(c, r * 0.4, Color(tint, 0.35))
			draw_string(ThemeDB.fallback_font, c + Vector2(-r, r + 26.0), "ХОДЬБА" if id == "move" else "СТРЕЛЬБА", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, Color(1, 1, 1, 0.8))
		if id == _selected:
			draw_rect(rect.grow(6.0), Color(UiStyle.GOLD, 0.95), false, 4.0)
		else:
			draw_rect(rect.grow(3.0), Color(UiStyle.NEON, 0.5), false, 2.0)


## Рамка элемента в координатах редактора: сам редактор лежит в корне HUD, сдвинутом на безопасную зону
## (вырез камеры), а element_rect — экранные координаты. Без пересчёта рамки уезжали вбок на ширину выреза.
func _rect(id: String) -> Rect2:
	var rect := hud.element_rect(id)
	if rect.size.x < 1.0:
		return rect
	return get_global_transform().affine_inverse() * rect


func _pick(point: Vector2) -> String:
	var best := ""
	var best_area := INF
	for id in hud.editable_ids():
		var rect := _rect(id).grow(10.0)
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
				_grab = button.position - _rect(id).get_center()
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
