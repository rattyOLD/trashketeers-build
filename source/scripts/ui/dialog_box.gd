class_name DialogBox
extends CanvasLayer
## Диалоговое окно сюжета: портрет-плашка, имя, печатающийся текст. Тап — допечатать/дальше,
## «ПРОПУСК» закрывает всю сцену. Пока открыто, игра на паузе (окно работает в паузе).

signal finished

const TYPE_SPEED := 70.0
const PANEL_HEIGHT := 190.0
const AUTO_BASE := 2.2
const AUTO_PER_CHAR := 0.06
const AUTO_MAX := 9.0

var _auto_left := -1.0

var _lines: Array = []
var _speakers: Dictionary = {}
var _index := 0
var _typed := 0.0
var _full_text := ""
var _panel: PanelContainer
var _portrait: Label
var _portrait_tex: TextureRect
var _portrait_box: PanelContainer
var _name: Label
var _text: Label
var _hint: Label
var _paused_before := false
var _done := false
var _last_press_ms := 0


func _init() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(lines: Array, speakers: Dictionary) -> void:
	_lines = lines
	_speakers = speakers
	_index = 0
	_paused_before = get_tree().paused
	get_tree().paused = true
	_build()
	_show_line()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_input)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.074, 0.071, 0.066, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.184, 0.177, 0.166, 0.96), UiStyle.NEON, 5, 22))
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 18.0
	_panel.offset_right = -18.0
	_panel.offset_top = -PANEL_HEIGHT - 14.0
	_panel.offset_bottom = -14.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_portrait_box = PanelContainer.new()
	_portrait_box.custom_minimum_size = Vector2(120, 120)
	_portrait_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait_box)
	_portrait = UiStyle.label("", 72, UiStyle.TEXT, 10)
	_portrait_box.add_child(_portrait)
	_portrait_tex = TextureRect.new()
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_box.add_child(_portrait_tex)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_name = UiStyle.label("", 30, UiStyle.GOLD, 8)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(_name)
	_text = UiStyle.label("", 26, UiStyle.TEXT, 6)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)
	_hint = UiStyle.label("тап — дальше", 20, UiStyle.TEXT_DIM, 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint)

	var skip := UiStyle.button("ПРОПУСК", UiStyle.PANEL, 22, Vector2(150, 56))
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -170.0
	skip.offset_right = -18.0
	skip.offset_top = 16.0
	skip.offset_bottom = 72.0
	skip.pressed.connect(_finish)
	root.add_child(skip)


func _show_line() -> void:
	var line: Dictionary = _lines[_index]
	var who: Dictionary = _speakers.get(str(line.get("who", "")), {})
	var color := Color(str(who.get("color", "#ffffff")))
	_name.text = str(who.get("name", ""))
	_name.add_theme_color_override("font_color", color)
	var tex_path := str(who.get("portrait", ""))
	var emo := str(line.get("emo", ""))
	if not emo.is_empty() and who.has("portrait_" + emo):
		tex_path = str(who["portrait_" + emo])
	_portrait_tex.texture = load(tex_path) as Texture2D if not tex_path.is_empty() else null
	_portrait_tex.visible = _portrait_tex.texture != null
	_portrait.text = "" if _portrait_tex.visible else str(who.get("glyph", "?"))
	_portrait.add_theme_color_override("font_color", color)
	_portrait_box.add_theme_stylebox_override("panel", UiStyle.box(color.darkened(0.7), color, 5, 60 if bool(who.get("radio", false)) else 16))
	_full_text = str(line.get("text", ""))
	_text.text = _full_text
	_fit_panel()
	_text.visible_characters = 0
	_typed = 0.0
	_auto_left = -1.0
	SoundManager.play(&"ui_click", -10.0)


## Высота панели под текст: оценка числа строк по ширине колонки текста.
func _fit_panel() -> void:
	var view := get_viewport().get_visible_rect().size
	var text_width := maxf(view.x - 36.0 - 120.0 - 18.0 - 32.0 - 20.0, 160.0)
	var chars_per_line := maxf(text_width / 14.5, 8.0)
	var lines := ceili(float(_full_text.length()) / chars_per_line) + 1
	var need := 40.0 + float(lines) * 34.0 + 34.0 + 28.0
	var height := clampf(need, 170.0, view.y * 0.6)
	_panel.offset_top = -height - 14.0
	_text.custom_minimum_size = Vector2(text_width, 0.0)


func _process(delta: float) -> void:
	if _done or _text == null:
		return
	if _text.visible_characters < _full_text.length():
		_typed += delta * TYPE_SPEED
		_text.visible_characters = mini(int(_typed), _full_text.length())
	var typed_out := _text.visible_characters >= _full_text.length()
	_hint.visible = typed_out
	if typed_out:
		if _auto_left < 0.0:
			_auto_left = clampf(AUTO_BASE + float(_full_text.length()) * AUTO_PER_CHAR, AUTO_BASE, AUTO_MAX)
		_auto_left -= delta
		if _auto_left <= 0.0:
			_advance()


func _on_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed or _done:
		return
	var now := Time.get_ticks_msec()
	if now - _last_press_ms < 140:
		return
	_last_press_ms = now
	if _text.visible_characters < _full_text.length():
		_text.visible_characters = _full_text.length()
		_typed = float(_full_text.length())
		return
	_advance()


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
	else:
		_show_line()


func _finish() -> void:
	if _done:
		return
	_done = true
	get_tree().paused = _paused_before
	finished.emit()
	queue_free()
