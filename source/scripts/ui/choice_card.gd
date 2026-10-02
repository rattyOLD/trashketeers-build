class_name ChoiceCard
extends CanvasLayer
## Выбор в сюжете: мир на паузе, заголовок, описание и две кнопки с последствиями.

signal chosen(index: int)

const MIN_OPEN_MS := 500

var _paused_before := false
var _done := false
var _opened_ms := 0


func _init() -> void:
	layer = 72
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(card: Dictionary) -> void:
	_paused_before = get_tree().paused
	get_tree().paused = true
	_opened_ms = Time.get_ticks_msec()
	var color := Color(str(card.get("color", "#ffb020")))
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.06, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var style := UiStyle.box(Color(0.184, 0.177, 0.166, 0.98), color, 6, 28)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var width := clampf(get_viewport().get_visible_rect().size.x - 60.0, 320.0, 700.0)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := UiStyle.label(str(card.get("title", "")).to_upper(), 30, color, 8)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(width - 20.0, 0)
	box.add_child(title)
	var image_path := str(card.get("image", ""))
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		var stage := Glow.new()
		stage.tint = color
		stage.custom_minimum_size = Vector2(0, 250)
		box.add_child(stage)
		var picture := TextureRect.new()
		picture.texture = load(image_path) as Texture2D
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(picture)
	var text_plate := PanelContainer.new()
	var plate_style := UiStyle.box(Color(0.074, 0.071, 0.066, 0.9), Color(color, 0.7), 3, 18)
	plate_style.set_content_margin_all(12)
	text_plate.add_theme_stylebox_override("panel", plate_style)
	box.add_child(text_plate)
	var text := UiStyle.label(str(card.get("text", "")), 22, UiStyle.TEXT, 5)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(width - 60.0, 0)
	text_plate.add_child(text)
	var options: Array = card.get("options", [])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var cell := (width - 12.0 * maxi(options.size() - 1, 0)) / maxf(options.size(), 1)
	for i in options.size():
		row.add_child(_make_option(options[i], i, color, cell))
	SoundManager.play(&"ui_confirm", -6.0)


func _make_option(option: Dictionary, index: int, color: Color, cell: float) -> Button:
	var accent := Color("#3fe0a0") if index == 0 else Color("#ff6a3d")
	var button := Button.new()
	button.custom_minimum_size = Vector2(cell, 250)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var tone := accent.darkened(0.62).lerp(Color.WHITE, 0.0 if state == "normal" else 0.08)
		button.add_theme_stylebox_override(state, UiStyle.box(tone, accent, 5 if state != "pressed" else 7, 20))
	button.pressed.connect(_pick.bind(index))
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8
	column.offset_right = -8
	column.offset_top = 8
	column.offset_bottom = -8
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	var icon_path := str(option.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path) as Texture2D
		icon.custom_minimum_size = Vector2(0, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(icon)
	var label := UiStyle.label(str(option.get("label", "")), 24, UiStyle.TEXT, 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	var bullets: Array = option.get("bullets", [])
	if bullets.is_empty():
		var note := UiStyle.label(str(option.get("note", "")), 17, Color(UiStyle.TEXT, 0.92), 4)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(cell - 36.0, 0)
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(note)
	for line in bullets:
		var good := not str(line).begins_with("-")
		var row := UiStyle.label(("+ %s" % line) if good else ("- %s" % str(line).substr(1)), 18, Color("#b9ffd9") if good else Color("#ff9a8a"), 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)
	return button


class Glow:
	extends Control
	var tint := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.62
		for i in 7:
			var t := float(i) / 6.0
			draw_circle(center, radius * (1.0 - t * 0.8), Color(tint, 0.05 + 0.04 * t))
		draw_arc(center, radius * 0.98, 0.0, TAU, 48, Color(tint, 0.35), 3.0, true)


func _pick(index: int) -> void:
	if _done or Time.get_ticks_msec() - _opened_ms < MIN_OPEN_MS:
		return
	_done = true
	get_tree().paused = _paused_before
	chosen.emit(index)
	queue_free()
