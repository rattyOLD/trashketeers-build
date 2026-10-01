class_name AmbientLine
extends CanvasLayer
## Фоновая реплика сюжета: компактная плашка с портретом, игру не ставит на паузу и не ловит касания.
## Реплики идут по очереди, каждая живёт по длине текста; тап по плашке сразу убирает реплику.

const MIN_TIME := 2.2
const MAX_TIME := 3.6
const PER_CHAR := 0.03
const FADE := 0.25

var _speakers: Dictionary = {}
var _queue: Array = []
var _current := false
var _left := 0.0
var _total := 0.0
var _panel: PanelContainer
var _name: Label
var _text: Label
var _portrait: TextureRect
var _frame: PanelContainer
var _tail: Tail


## Хвостик пузыря: треугольник под плашкой в цвет рамки.
class Tail:
	extends Control
	var fill := Color.WHITE
	var edge := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(30, 20)

	func _draw() -> void:
		var outer := PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(6, 20)])
		draw_colored_polygon(outer, edge)
		var inner := PackedVector2Array([Vector2(6, 0), Vector2(24, 0), Vector2(8, 13)])
		draw_colored_polygon(inner, fill)


func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(speakers: Dictionary) -> void:
	_speakers = speakers
	_build()


func push(lines: Array) -> void:
	for line in lines:
		_queue.append(line)
	set_process(true)


func is_busy() -> bool:
	return _current or not _queue.is_empty()


func clear() -> void:
	_queue.clear()
	_current = false
	_panel.visible = false
	_tail.visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 28.0
	_panel.offset_right = -28.0
	_panel.offset_top = 352.0
	_panel.offset_bottom = 353.0
	_panel.visible = false
	root.add_child(_panel)
	_tail = Tail.new()
	_tail.visible = false
	root.add_child(_tail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	_frame = PanelContainer.new()
	_frame.custom_minimum_size = Vector2(58, 58)
	_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_name = UiStyle.label("", 17, UiStyle.NEON, 4)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name)
	_text = UiStyle.label("", 19, UiStyle.TEXT, 4)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_text)
	set_process(false)


func _process(delta: float) -> void:
	var blocked := get_tree().paused
	if visible == blocked:
		visible = not blocked
	if blocked:
		return
	if not _current:
		if _queue.is_empty():
			set_process(false)
			return
		_show(_queue.pop_front())
		return
	_left -= delta
	var age := _total - _left
	_panel.modulate.a = clampf(minf(age, _left) / FADE, 0.0, 1.0)
	_tail.modulate.a = _panel.modulate.a
	if _left <= 0.0:
		_current = false
		_panel.visible = false
		_tail.visible = false


func _on_panel_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tapped and _current:
		_left = minf(_left, FADE)
		get_viewport().set_input_as_handled()


func _show(line: Dictionary) -> void:
	var who: Dictionary = _speakers.get(str(line.get("who", "")), {})
	var color := Color(str(who.get("color", "#ffffff")))
	var path := str(who.get("portrait", ""))
	if str(line.get("emo", "")) == "alt" and who.has("portrait_alt"):
		path = str(who["portrait_alt"])
	_portrait.texture = load(path) as Texture2D if not path.is_empty() else null
	_name.text = str(who.get("name", ""))
	_name.add_theme_color_override("font_color", color)
	_frame.add_theme_stylebox_override("panel", UiStyle.box(color.darkened(0.7), color, 3, 29))
	var bubble := Color(0.07, 0.05, 0.17, 0.9)
	var box := UiStyle.box(bubble, Color(color, 0.9), 4, 22)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", box)
	_tail.fill = bubble
	_tail.edge = Color(color, 0.9)
	_tail.queue_redraw()
	var text := str(line.get("text", ""))
	_text.text = text
	_total = clampf(MIN_TIME + float(text.length()) * PER_CHAR, MIN_TIME, MAX_TIME)
	_left = _total
	_current = true
	_panel.modulate.a = 0.0
	_panel.visible = true
	_tail.visible = true
	_tail.modulate.a = 0.0
	await get_tree().process_frame
	_tail.position = Vector2(_panel.position.x + 60.0, _panel.position.y + _panel.size.y - 3.0)
	SoundManager.play(&"ui_click", -14.0)
