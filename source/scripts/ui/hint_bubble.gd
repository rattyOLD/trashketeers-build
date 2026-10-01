class_name HintBubble
extends PanelContainer
## Маленькая подсказка рядом с элементом интерфейса: тап по иконке или плашке показывает, что это.
## Сама не ловит касания, исчезает через несколько секунд или при новой подсказке.

const SHOW_TIME := 4.0
const MAX_WIDTH := 290.0
const GAP := 8.0

var _label: Label
var _token := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = 50
	var style := UiStyle.box(Color(0.06, 0.04, 0.14, 0.96), Color(UiStyle.NEON, 0.8), 2, 12)
	style.set_content_margin_all(8)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	_label = UiStyle.label("", 17, UiStyle.TEXT, 4)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Подсказка под элементом (или над ним, если он в нижней половине экрана).
## Размер считается через кадр: у свежего автоврапнутого Label высота при первом показе ещё не посчитана.
func show_for(target: Control, text: String) -> void:
	_token += 1
	var token := _token
	var view := get_viewport().get_visible_rect().size
	var width := minf(MAX_WIDTH, view.x - 36.0)
	_label.text = text
	_label.custom_minimum_size = Vector2(width - 16.0, 0.0)
	_label.size = Vector2(width - 16.0, 0.0)
	size = Vector2.ZERO
	modulate.a = 0.0
	visible = true
	await get_tree().process_frame
	if token != _token or not is_instance_valid(target):
		return
	reset_size()
	var rect := target.get_global_rect()
	var pos := Vector2(rect.position.x, rect.end.y + GAP)
	if rect.get_center().y > view.y * 0.5:
		pos.y = rect.position.y - size.y - GAP
	pos.x = clampf(pos.x, 18.0, view.x - size.x - 18.0)
	pos.y = clampf(pos.y, 12.0, view.y - size.y - 12.0)
	global_position = pos
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)
	get_tree().create_timer(SHOW_TIME, true, false, true).timeout.connect(func() -> void:
		if token == _token:
			visible = false)


## Элемент ловит тап и показывает подсказку; вложенные узлы касания не перехватывают.
static func attach(target: Control, bubble: HintBubble, text: Variant) -> void:
	target.mouse_filter = Control.MOUSE_FILTER_STOP
	_release_children(target)
	target.gui_input.connect(func(event: InputEvent) -> void:
		var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if not pressed:
			return
		var message: String = (text as Callable).call() if text is Callable else str(text)
		bubble.show_for(target, message))


static func _release_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_release_children(child)
