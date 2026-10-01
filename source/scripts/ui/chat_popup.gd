class_name ChatPopup
extends GlassPopup
## Личная переписка с другом: сообщения подтягиваются раз в несколько секунд, пока окно открыто.

const POLL_SEC := 4.0
const SEND_ERRORS := {
	"not_friends": "Вы больше не друзья, писать нельзя",
	"blocked": "Переписка заблокирована",
	"rate": "Слишком быстро. Енот, помедленнее",
	"banned": "Чат для тебя отключён за жалобы",
	"offline": "Нет связи. Сообщение не ушло",
}

var friend_code := ""
var friend_name := ""

var _scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _edit: LineEdit
var _last_id := 0
var _busy := false
var _clock := 0.0


func _init(code: String, nick: String) -> void:
	super(nick.left(18))
	friend_code = code
	friend_name = nick


func _refresh() -> void:
	var keep := content.get_child(0)
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	_last_id = 0
	_status = UiStyle.label("Загружаю переписку...", 18, UiStyle.TEXT_DIM, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	content.add_child(_status)
	_list = MenuPopups.scroll_list(content)
	_scroll = _list.get_parent().get_parent() as ScrollContainer
	_list.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Сообщение"
	_edit.max_length = 500
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 58)
	SearchBar.style(_edit, 22)
	SearchBar.attach_touch_input(_edit, "Сообщение для %s" % friend_name)
	row.add_child(_edit)
	var send := UiStyle.button("ОТПРАВИТЬ", UiStyle.HOT, 20, Vector2(176, 58))
	send.pressed.connect(_send)
	_edit.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(send)
	content.add_child(row)
	_poll()


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	if _clock >= POLL_SEC:
		_clock = 0.0
		_poll()


func _poll() -> void:
	if _busy:
		return
	_busy = true
	var result := await Cloud.get_messages(friend_code, _last_id)
	_busy = false
	if not is_instance_valid(self) or not is_instance_valid(_list):
		return
	if not bool(result["ok"]):
		_status.text = "Нет связи с сервером. Повторю сам"
		return
	var items: Array = result["items"]
	if _last_id == 0:
		_status.text = "Пока пусто. Напиши первым, но без спама: жалобы работают." if items.is_empty() else "Жми «!» у чужого сообщения, чтобы пожаловаться."
	for item in items:
		if item is Dictionary:
			_add_bubble(item as Dictionary)
	if not items.is_empty():
		Cloud.refresh_unread()
		_scroll_down.call_deferred()


func _scroll_down() -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _add_bubble(item: Dictionary) -> void:
	var id := int(item.get("id", 0))
	if id <= _last_id:
		return
	_last_id = id
	var mine := bool(item.get("mine", false))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 6)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UiStyle.box(Color("#7a2f9e") if mine else Color("#2f2452"), UiStyle.OUTLINE, 3, 16))
	var label := UiStyle.label(str(item.get("body", "")), 22, UiStyle.TEXT, 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.custom_minimum_size = Vector2(minf(panel_width() - 220.0, 420.0), 0)
	bubble.add_child(label)
	row.add_child(bubble)
	if not mine:
		var report := UiStyle.button("!", Color("#a3283e"), 20, Vector2(46, 46))
		var armed := [false]
		report.pressed.connect(func() -> void:
			if not armed[0]:
				armed[0] = true
				report.text = "?"
				get_tree().create_timer(2.0).timeout.connect(func() -> void:
					if is_instance_valid(report):
						armed[0] = false
						report.text = "!")
				return
			var result := await Cloud.report_user(friend_code, "сообщение", id)
			if is_instance_valid(report):
				report.text = "OK" if result == "ok" else "X"
				report.disabled = true)
		row.add_child(report)
		row.move_child(report, 1)
	_list.add_child(row)


func _send() -> void:
	var text := _edit.text.strip_edges()
	if text.is_empty():
		return
	var result := await Cloud.send_message(friend_code, text)
	if not is_instance_valid(self) or not is_instance_valid(_edit):
		return
	if result == "ok":
		_edit.text = ""
		_clock = 0.0
		_poll()
	else:
		_status.text = str(SEND_ERRORS.get(result, "Не отправилось. Попробуй ещё раз"))
