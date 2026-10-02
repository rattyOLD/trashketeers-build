class_name OrdersScreen
extends CanvasLayer
## Полноэкранный список заданий: мир на паузе, заказ Нэлл и цели миссии с пояснениями, кнопка «Назад».

signal closed

const HINTS := {
	"Пленники": "Крысы держат пленных в клетках. Подойди и постой рядом, клетка откроется. Освобождённый лечит тебя и бросает шутку.",
	"Детали": "Детали Тяжёлой Бочки лежат на уровне и в тайниках. Собери все, и в конце получишь ствол.",
	"Тайники": "Трещины в стенах и подозрительные плиты. Постреляй по ним, внутри припасы и записки.",
}

var _paused_before := false
var _opened_ms := 0
var _done := false


func _init() -> void:
	layer = 72
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(order: Dictionary, goals: Array) -> void:
	_paused_before = get_tree().paused
	get_tree().paused = true
	_opened_ms = Time.get_ticks_msec()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.06, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(UiStyle.label("ЗАДАНИЯ", 44, UiStyle.TEXT, 10))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	if not order.is_empty() and not str(order.get("title", "")).is_empty():
		var reward := "Награда: %d монет и %d неонита" % [int(order.get("nuts", 0)), int(order.get("dust", 0))]
		list.add_child(_card("ЗАКАЗ НЭЛЛ", str(order.get("title", "")), "Каждый день новый. " + reward, int(order.get("progress", 0)), int(order.get("goal", 1)), bool(order.get("done", false)), Color("#ffac56")))
	for goal: Dictionary in goals:
		var title := str(goal.get("title", ""))
		list.add_child(_card("ЦЕЛЬ МИССИИ", title, str(HINTS.get(title, "")), int(goal.get("progress", 0)), int(goal.get("goal", 1)), bool(goal.get("done", false)), Color("#ffd257")))
	var back := UiStyle.button("НАЗАД", UiStyle.PANEL_LIGHT, 32, Vector2(0, 88))
	back.pressed.connect(_close)
	column.add_child(back)
	SoundManager.play(&"ui_confirm", -6.0)


func _card(tag: String, title: String, text: String, progress: int, goal: int, done: bool, color: Color) -> Control:
	var accent := Color("#7cff6b") if done else color
	var panel := PanelContainer.new()
	var style := UiStyle.box(Color(0.184, 0.177, 0.166, 0.96), accent, 4, 20)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiStyle.label(tag, 18, UiStyle.TEXT_DIM, 4))
	var head := UiStyle.label("%s   %s" % [title, "ГОТОВО" if done else "%d / %d" % [progress, maxi(goal, 1)]], 30, accent, 7)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(head)
	var bar := UiStyle.progress_bar(accent, 22)
	bar.max_value = maxi(goal, 1)
	bar.value = goal if done else progress
	box.add_child(bar)
	if not text.is_empty():
		var body := UiStyle.label(text, 22, UiStyle.TEXT, 5)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.custom_minimum_size = Vector2(300, 0)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(body)
	return panel


func _close() -> void:
	if _done or Time.get_ticks_msec() - _opened_ms < 250:
		return
	_done = true
	get_tree().paused = _paused_before
	closed.emit()
	queue_free()
