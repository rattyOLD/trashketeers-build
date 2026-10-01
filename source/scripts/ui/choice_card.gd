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
	var style := UiStyle.box(Color(0.1, 0.07, 0.2, 0.98), color, 6, 28)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var width := clampf(get_viewport().get_visible_rect().size.x - 60.0, 320.0, 700.0)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiStyle.label("ВЫБОР", 22, UiStyle.TEXT_DIM, 4))
	var title := UiStyle.label(str(card.get("title", "")).to_upper(), 36, color, 9)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var text := UiStyle.label(str(card.get("text", "")), 24, UiStyle.TEXT, 6)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(width - 50.0, 0)
	box.add_child(text)
	var options: Array = card.get("options", [])
	for i in options.size():
		var option: Dictionary = options[i]
		var button := UiStyle.button(str(option.get("label", "")), color.darkened(0.3) if i == 0 else UiStyle.PANEL_LIGHT, 26, Vector2(0, 76))
		button.pressed.connect(_pick.bind(i))
		box.add_child(button)
		var note := UiStyle.label(str(option.get("note", "")), 18, UiStyle.TEXT_DIM, 4)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(width - 50.0, 0)
		box.add_child(note)
	SoundManager.play(&"ui_confirm", -6.0)


func _pick(index: int) -> void:
	if _done or Time.get_ticks_msec() - _opened_ms < MIN_OPEN_MS:
		return
	_done = true
	get_tree().paused = _paused_before
	chosen.emit(index)
	queue_free()
