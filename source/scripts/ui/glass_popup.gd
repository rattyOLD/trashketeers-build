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


static func panel_width() -> float:
	return 620.0 if Orient.portrait else 900.0


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
	content.add_theme_constant_override("separation", 12)
	inner.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	_title = UiStyle.label(title_text, 34, UiStyle.TEXT, 9)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := UiStyle.button("X", UiStyle.PANEL_LIGHT, 28, Vector2(56, 56))
	close_button.pressed.connect(close)
	header.add_child(close_button)

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
	_open_stack = _open_stack.filter(func(p: GlassPopup) -> bool: return is_instance_valid(p) and p.visible)
	return not _open_stack.is_empty()


## Поле в верхнем открытом окне, и окно уже доиграло анимацию появления.
static func is_on_top(node: Node) -> bool:
	var popup := owner_of(node)
	_open_stack = _open_stack.filter(func(p: GlassPopup) -> bool: return is_instance_valid(p) and p.visible)
	if popup == null:
		return _open_stack.is_empty()
	return not _open_stack.is_empty() and _open_stack.back() == popup and popup._panel.scale.is_equal_approx(Vector2.ONE) and not popup._closing and popup.overlays == 0


func open() -> void:
	_closing = false
	_open_stack.erase(self)
	_open_stack.append(self)
	Platform.trail("окно " + _title.text)
	_refresh()
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
	if not Orient.portrait:
		return
	_lifted = up
	set_process(up)
	if up:
		_apply_lift()
	else:
		_center.anchor_top = 0.0
		_center.anchor_bottom = 1.0
		_center.offset_top = 0.0
		_center.offset_bottom = 0.0


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
		_apply_lift()


func _sync_glass() -> void:
	_panel.pivot_offset = _panel.size * 0.5
	(_glass.material as ShaderMaterial).set_shader_parameter(&"rect_size", _panel.size)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
