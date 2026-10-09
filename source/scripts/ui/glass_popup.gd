class_name GlassPopup
extends Control
## Всплывающее окно по паспорту интерфейса: тёмное матовое стекло (шейдер размытия),
## скруглённые углы, неоновый бирюзовый контур. Появление — вылет из центра с пружиной
## (TRANS_ELASTIC): окно на долю секунды становится больше и «встаёт» на место.
## Наследники наполняют content и переопределяют _refresh().

signal closed

const CORNER := 28.0
const BORDER := Color("#ff8200")

static var _glass_shader: Shader
## Открытые окна по порядку: поле ввода браузера показывается только у верхнего (иначе оно висело бы поверх других окон).
static var _open_stack: Array[GlassPopup] = []

var content: VBoxContainer

var _panel: Control
var _glass: ColorRect
var _frame: Panel
var _title: Label
var _center: CenterContainer
var _lifted := false
var _closing := false
## Поверх окна открыт полноэкранный слой (просмотр фото, галерея): браузерное поле ввода прячется.
var overlays := 0
var _content_scroll_view: ScrollContainer
var _floating_close: Button


static func panel_width() -> float:
	return 620.0 if Orient.portrait else 1120.0


func _init(title_text: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_center = center

	# Внешний контейнер без отступов: стекло и рамка растягиваются на всю панель,
	# а содержимое лежит во внутреннем контейнере с полями.
	_panel = MarginContainer.new()
	_panel.custom_minimum_size = Vector2(panel_width(), 0)
	center.add_child(_panel)

	if _glass_shader == null:
		_glass_shader = load("res://shaders/glass_blur.gdshader")
	_glass = ColorRect.new()
	_glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass_material := ShaderMaterial.new()
	glass_material.shader = _glass_shader
	glass_material.set_shader_parameter(&"corner_radius", CORNER)
	_glass.material = glass_material
	_panel.add_child(_glass)

	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = BORDER
	frame_style.set_border_width_all(4)
	frame_style.set_corner_radius_all(int(CORNER))
	frame_style.anti_aliasing = true
	if UiStyle.KIT_ON and ResourceLoader.exists(UiStyle.KIT_DIR + "window_neon_turquoise_s.png"):
		var tex_frame := StyleBoxTexture.new()
		tex_frame.texture = load(UiStyle.KIT_DIR + "window_neon_turquoise_s.png") as Texture2D
		tex_frame.draw_center = false
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			tex_frame.set_texture_margin(side, 22.0)
		_frame.add_theme_stylebox_override("panel", tex_frame)
	else:
		_frame.add_theme_stylebox_override("panel", frame_style)
	_panel.add_child(_frame)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 28)
	_panel.add_child(inner)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_content_scroll_view = DragScroll.new()
	_content_scroll_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll_view.follow_focus = true
	_content_scroll_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_content_scroll_view)
	_content_scroll_view.add_child(content)
	content.minimum_size_changed.connect(_fit_popup_height.call_deferred)
	resized.connect(_fit_popup_height.call_deferred)

	var header := HBoxContainer.new()
	content.add_child(header)
	_title = UiStyle.label(title_text, 34, UiStyle.TEXT, 9)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Табличка заголовка из набора интерфейса Астры (assets/ui/kit/header_plate.png).
	if UiStyle.KIT_ON and ResourceLoader.exists(UiStyle.KIT_DIR + "header_plate.png"):
		var plate := StyleBoxTexture.new()
		plate.texture = load(UiStyle.KIT_DIR + "header_plate.png") as Texture2D
		plate.set_texture_margin(SIDE_LEFT, 34.0)
		plate.set_texture_margin(SIDE_RIGHT, 34.0)
		plate.set_texture_margin(SIDE_TOP, 14.0)
		plate.set_texture_margin(SIDE_BOTTOM, 14.0)
		# Текст по центру таблички, с отступом от болтов с обеих сторон.
		plate.set_content_margin(SIDE_LEFT, 56.0)
		plate.set_content_margin(SIDE_RIGHT, 56.0)
		plate.set_content_margin(SIDE_TOP, 6.0)
		plate.set_content_margin(SIDE_BOTTOM, 8.0)
		_title.add_theme_stylebox_override("normal", plate)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_title)
	# Место под крестик в заголовке; сам крестик — один, закреплён в углу окна и не уезжает при прокрутке.
	var close_slot := Control.new()
	close_slot.custom_minimum_size = Vector2(56, 56)
	close_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(close_slot)
	_floating_close = UiStyle.button("X", UiStyle.PANEL_LIGHT, 28, Vector2(56, 56))
	_floating_close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_floating_close.offset_left = -84
	_floating_close.offset_right = -28
	_floating_close.offset_top = 28
	_floating_close.offset_bottom = 84
	_floating_close.pressed.connect(close)
	# Панель — контейнер и растянула бы кнопку на всё окно, поэтому крестик живёт в отдельном слое поверх содержимого.
	var close_layer := Control.new()
	close_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(close_layer)
	close_layer.add_child(_floating_close)

	_panel.resized.connect(_sync_glass)
	# Телефонная клавиатура закрывает низ экрана: пока вводят текст, окно поднимается в верхнюю половину.
	content.child_entered_tree.connect(_watch_inputs)


static func owner_of(node: Node) -> GlassPopup:
	var cur := node.get_parent()
	while cur != null:
		if cur is GlassPopup:
			return cur as GlassPopup
		cur = cur.get_parent()
	return null


## Открыто хоть одно окно: экран под ним в этот момент не перестраиваем (иначе окно пропадёт).
static func any_open() -> bool:
	_open_stack = _open_stack.filter(func(p: Variant) -> bool: return is_instance_valid(p) and (p as GlassPopup).visible)
	return not _open_stack.is_empty()


## Поле в верхнем открытом окне, и окно уже доиграло анимацию появления.
static func is_on_top(node: Node) -> bool:
	var popup := owner_of(node)
	_open_stack = _open_stack.filter(func(p: Variant) -> bool: return is_instance_valid(p) and (p as GlassPopup).visible)
	if popup == null:
		return _open_stack.is_empty()
	return not _open_stack.is_empty() and _open_stack.back() == popup and popup._panel.scale.is_equal_approx(Vector2.ONE) and not popup._closing and popup.overlays == 0


## Рамка окна из набора Астры (assets/ui/kit/<имя>.png, 96×96, поля 22): золотая — для окон наград.
func set_frame(file: String) -> void:
	var tex := UiStyle.kit_texture(file + ".png")
	if tex == null or _frame == null:
		return
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.draw_center = false
	sb.set_texture_margin_all(22.0)
	_frame.add_theme_stylebox_override("panel", sb)


func open() -> void:
	_closing = false
	_open_stack.erase(self)
	_open_stack.append(self)
	Platform.trail("окно " + _title.text)
	_refresh()
	_fit_popup_height.call_deferred()
	visible = true
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.4, 0.4)
	_panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.15)


func close() -> void:
	_closing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "scale", Vector2(0.6, 0.6), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(func() -> void:
		visible = false
		_open_stack.erase(self)
		closed.emit())


## Хук наследника: перерисовать содержимое перед показом.
func _refresh() -> void:
	pass


func _fit_popup_height() -> void:
	if _content_scroll_view == null or not is_inside_tree():
		return
	var safe := ScreenSafeArea.rect(get_viewport_rect().size)
	var available := maxf(180.0, safe.size.y - 112.0)
	if _lifted:
		# Окно поднято над клавиатурой: место по высоте — только видимая над ней часть, рамку окна не трогаем.
		available = maxf(120.0, _lift_height() - 112.0)
	else:
		ScreenSafeArea.fit(_center, get_viewport_rect().size, 12.0)
	_panel.custom_minimum_size.x = minf(panel_width(), safe.size.x - 48.0)
	_fit_inner_list(available)
	_content_scroll_view.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, available)


## Список внутри окна (MenuPopups.scroll_list) получает ровно оставшуюся высоту: тогда листается только он,
## а у окна второй полосы прокрутки нет (раньше в горизонтали крутились обе).
func _fit_inner_list(available: float) -> void:
	var lists := content.find_children("*", "ScrollContainer", true, false).filter(func(n: Node) -> bool: return n.has_meta("fit_list") and (n as Control).is_visible_in_tree())
	if lists.size() != 1:
		return
	var list := lists[0] as ScrollContainer
	var natural := 0.0
	if list.get_child_count() > 0:
		var inner_box := list.get_child(0) as Control
		natural = inner_box.get_combined_minimum_size().y
		if not inner_box.minimum_size_changed.is_connected(_fit_popup_height):
			inner_box.minimum_size_changed.connect(_fit_popup_height, CONNECT_DEFERRED)
	var others := content.get_combined_minimum_size().y - list.custom_minimum_size.y
	var want := clampf(available - others, 140.0, maxf(natural, 140.0))
	if absf(list.custom_minimum_size.y - want) > 1.0:
		list.custom_minimum_size.y = want


func _watch_inputs(node: Node) -> void:
	if node is LineEdit:
		var edit := node as LineEdit
		if not edit.focus_entered.is_connected(_lift):
			edit.focus_entered.connect(_lift.bind(true))
			edit.focus_exited.connect(_lift.bind(false))
	for child in node.get_children():
		_watch_inputs(child)
	if not node.child_entered_tree.is_connected(_watch_inputs):
		node.child_entered_tree.connect(_watch_inputs)


func _lift(up: bool) -> void:
	if not Platform.is_touch():
		return
	_lifted = up
	# Обработку не выключаем: чат и выбор фото опрашивают сервер/браузер в своём _process.
	if up:
		set_process(true)
	if up:
		_apply_lift()
	else:
		_center.anchor_top = 0.0
		_center.anchor_bottom = 1.0
		_center.offset_top = 0.0
		_center.offset_bottom = 0.0
	_fit_popup_height.call_deferred()


## Высота области над клавиатурой, в которую должно уместиться поднятое окно.
func _lift_height() -> float:
	var view_h := get_viewport_rect().size.y
	var inset := Platform.keyboard_inset()
	return view_h - inset - 24.0 if inset > 60.0 else view_h * 0.5 - 40.0


## Пока открыта клавиатура, окно целиком умещается над ней (высота берётся из видимой области браузера).
## Если страница размер не меняла (Android) и клавиатуры «не видно», окно просто уходит в верхнюю половину.
func _apply_lift() -> void:
	var inset := Platform.keyboard_inset()
	_center.anchor_top = 0.0
	if inset > 60.0:
		_center.anchor_bottom = 1.0
		_center.offset_top = 24.0
		_center.offset_bottom = -inset
	else:
		_center.anchor_bottom = 0.5
		_center.offset_top = 40.0
		_center.offset_bottom = 0.0


func _process(_delta: float) -> void:
	if _lifted:
		var before := _center.offset_bottom
		_apply_lift()
		if not is_equal_approx(before, _center.offset_bottom):
			_fit_popup_height()


func _sync_glass() -> void:
	_panel.pivot_offset = _panel.size * 0.5
	(_glass.material as ShaderMaterial).set_shader_parameter(&"rect_size", _panel.size)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
