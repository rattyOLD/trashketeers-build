class_name GlassPopup
extends Control
## Всплывающее окно по паспорту интерфейса: тёмное матовое стекло (шейдер размытия),
## скруглённые углы, неоновый бирюзовый контур. Появление — вылет из центра с пружиной
## (TRANS_ELASTIC): окно на долю секунды становится больше и «встаёт» на место.
## Наследники наполняют content и переопределяют _refresh().

signal closed

const PANEL_WIDTH := 900.0
const CORNER := 28.0
const BORDER := Color("#00e5ff")

static var _glass_shader: Shader

var content: VBoxContainer

var _panel: Control
var _glass: ColorRect
var _frame: Panel
var _title: Label


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

	# Внешний контейнер без отступов: стекло и рамка растягиваются на всю панель,
	# а содержимое лежит во внутреннем контейнере с полями.
	_panel = MarginContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
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
	_frame.add_theme_stylebox_override("panel", frame_style)
	_panel.add_child(_frame)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 22)
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


func open() -> void:
	_refresh()
	visible = true
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.4, 0.4)
	_panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.15)


func close() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "scale", Vector2(0.6, 0.6), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(func() -> void:
		visible = false
		closed.emit())


## Хук наследника: перерисовать содержимое перед показом.
func _refresh() -> void:
	pass


func _sync_glass() -> void:
	_panel.pivot_offset = _panel.size * 0.5
	(_glass.material as ShaderMaterial).set_shader_parameter(&"rect_size", _panel.size)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
