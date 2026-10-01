class_name ChatPopup
extends GlassPopup
## Личный чат с другом в духе игровых мессенджеров: пузыри с хвостиком, время и галочки «доставлено/прочитано»,
## «печатает...», стикеры, картинки и файлы (Supabase Storage, SQL v19). Пока окно открыто, всё обновляется само.

const POLL_SEC := 2.0
const PEER_SEC := 3.0
const TYPING_EVERY := 3.0
const MAX_FILE := 10 * 1024 * 1024
const IMAGE_SIDE := 1280
const STICKERS: Array[String] = ["hi", "go", "letsgo", "ok", "gg", "lol", "yay", "angry", "srsly", "what", "hmm", "panic", "beer", "mine", "loot", "deal", "giveup", "nohit", "peace", "cold"]
const SEND_ERRORS := {
	"not_friends": "Вы больше не друзья, писать нельзя",
	"blocked": "Переписка заблокирована",
	"rate": "Слишком быстро. Енот, помедленнее",
	"banned": "Чат для тебя отключён за жалобы",
	"offline": "Нет связи. Сообщение не ушло",
	"no_server": "Стикеры и файлы заработают после обновления сервера (SQL v19)",
	"bad": "Такое отправить нельзя",
}
## Подсказка в строке ввода: каждый раз новая подколка вместо скучного «Сообщение».
const TEASES: Array[String] = [
	"Ну давай, заплачь", "Печатай быстрее", "Диванный герой?", "Напиши уже что-то",
	"Енот ждёт", "Крысы пишут быстрее", "Без голосовых", "Клавиатура не кусается",
	"Ну и? Мусоровоз ждёт", "Скажи что-то умное", "Опять молчишь?", "Жми, не стесняйся",
]
const REACTIONS: Array[String] = ["like", "lol", "fire"]
const LONG_PRESS := 0.42
const MINE_BG := Color("#7a2f9e")
const THEIR_BG := Color("#2b2148")
const CHECK_BLUE := Color("#5ff2ff")

static var _texture_cache: Dictionary = {}

var friend_code := ""
var friend_name := ""

var _scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _edit: LineEdit
var _stickers: GridContainer
var _last_id := 0
var _busy := false
var _clock := 0.0
var _peer_clock := 0.0
var _typing_sent := -100.0
var _last_day := ""
var _checks: Dictionary = {}
var _read_upto := 0
var _picking := false
var _uploading := false
var _base_height := 640.0
var _first_load := true
var _reaction_rows: Dictionary = {}
var _message_nodes: Dictionary = {}
var _media: Array[Dictionary] = []
var _reaction_state: Dictionary = {}
var _quick: HBoxContainer


var friend_character := "raccoon"
var _peer_avatar: PeerAvatar


func _init(code: String, nick: String, character: String = "raccoon") -> void:
	super(nick.left(18))
	friend_code = code
	friend_name = nick
	friend_character = character


static func is_sticker(body: String) -> bool:
	return STICKERS.has(body)


## Превью последнего сообщения для списка друзей.
static func preview_of(body: String) -> String:
	return "[стикер]" if is_sticker(body) else body


func _refresh() -> void:
	var keep := content.get_child(0)
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	_last_id = 0
	_last_day = ""
	_checks.clear()
	_read_upto = 0
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_peer_avatar = PeerAvatar.new()
	_peer_avatar.character = friend_character
	_peer_avatar.custom_minimum_size = Vector2(56, 56)
	head.add_child(_peer_avatar)
	_status = UiStyle.label("Загружаю переписку...", 18, UiStyle.TEXT_DIM, 4)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_status)
	var media := UiStyle.button("МЕДИА", UiStyle.PANEL_LIGHT, 17, Vector2(110, 46))
	media.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	media.pressed.connect(_show_gallery)
	head.add_child(media)
	content.add_child(head)

	_scroll = DragScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 16
	var view := get_viewport_rect().size
	_base_height = clampf(view.y * (0.58 if Orient.portrait else 0.5), 320.0, 900.0)
	_scroll.custom_minimum_size = Vector2(panel_width() - 50.0, _base_height)
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	_stickers = GridContainer.new()
	_stickers.columns = 5
	_stickers.add_theme_constant_override("h_separation", 6)
	_stickers.add_theme_constant_override("v_separation", 6)
	_stickers.visible = false
	for id in STICKERS:
		var b := TextureButton.new()
		b.texture_normal = _sticker_texture(id)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(100, 100)
		b.pressed.connect(_send_sticker.bind(id))
		_stickers.add_child(b)
	content.add_child(_stickers)

	_quick = HBoxContainer.new()
	_quick.add_theme_constant_override("separation", 6)
	content.add_child(_quick)
	_fill_quick()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var sticker_btn := ChatIcon.new(ChatIcon.Kind.STICKER)
	sticker_btn.pressed.connect(func() -> void:
		_stickers.visible = not _stickers.visible
		_scroll.custom_minimum_size.y = _base_height - (440.0 if _stickers.visible else 0.0)
		_scroll_down.call_deferred())
	bar.add_child(sticker_btn)
	var attach := ChatIcon.new(ChatIcon.Kind.ATTACH)
	attach.pressed.connect(_pick_attachment)
	bar.add_child(attach)
	_edit = LineEdit.new()
	_edit.placeholder_text = TEASES.pick_random()
	_edit.max_length = 500
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 60)
	SearchBar.style(_edit, 22)
	SearchBar.style_dark(_edit)
	SearchBar.attach_touch_input(_edit, _edit.placeholder_text)
	for child in _edit.get_children():
		if child is NativeField:
			(child as NativeField).focus_changed.connect(_on_input_focus)
	_edit.text_changed.connect(_on_typing)
	_edit.text_submitted.connect(func(_t: String) -> void: _send_text())
	bar.add_child(_edit)
	var send := ChatIcon.new(ChatIcon.Kind.SEND)
	send.pressed.connect(_send_text)
	bar.add_child(send)
	content.add_child(bar)
	_reaction_rows.clear()
	_reaction_state.clear()
	_message_nodes.clear()
	_media.clear()
	_poll()
	_poll_peer()


func _on_input_focus(focused: bool) -> void:
	if focused:
		_stickers.visible = false
	_quick.visible = not focused
	_scroll.custom_minimum_size.y = _base_height * (0.45 if focused and Orient.portrait else 1.0)
	_scroll_down.call_deferred()


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_peer_clock += delta
	if _clock >= POLL_SEC:
		_clock = 0.0
		_poll()
	if _peer_clock >= PEER_SEC:
		_peer_clock = 0.0
		_poll_peer()
		_poll_reactions()
	if _picking:
		var picked: Variant = Platform.pick_file_result()
		if picked != null:
			_picking = false
			_on_picked(picked as Dictionary)


func _on_typing(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not text.strip_edges().is_empty() and now - _typing_sent > TYPING_EVERY:
		_typing_sent = now
		Cloud.set_typing(friend_code)


func _poll() -> void:
	if _busy:
		return
	_busy = true
	var result := await Cloud.get_chat(friend_code, _last_id)
	_busy = false
	if not is_instance_valid(self) or not is_instance_valid(_list):
		return
	if not bool(result["ok"]):
		_status.text = "Нет связи с сервером, повторю сам"
		return
	var items: Array = result["items"]
	if _last_id == 0 and items.is_empty() and _list.get_node_or_null("Empty") == null:
		_list.add_child(_empty_hint())
	for item in items:
		if item is Dictionary:
			_add_message(item as Dictionary)
	_first_load = false
	if not items.is_empty():
		Cloud.refresh_unread()
		_scroll_down.call_deferred()


func _poll_peer() -> void:
	var peer := await Cloud.chat_peer(friend_code)
	if not is_instance_valid(self) or not is_instance_valid(_status):
		return
	if peer.is_empty():
		return
	if bool(peer.get("typing", false)):
		_status.text = "печатает..."
		_status.add_theme_color_override("font_color", CHECK_BLUE)
		_peer_avatar.online = true
	else:
		var seen := SocialProfilePopup.seen_text(str(peer.get("last_seen", "")))
		_status.text = "в сети" if seen == "Сейчас в сети" else seen.to_lower()
		_status.add_theme_color_override("font_color", Color("#35c46a") if seen == "Сейчас в сети" else UiStyle.TEXT_DIM)
		_peer_avatar.online = seen == "Сейчас в сети"
	var upto := int(peer.get("read_upto", 0))
	if upto > _read_upto:
		_read_upto = upto
		for id: int in _checks:
			if id <= upto and is_instance_valid(_checks[id]):
				(_checks[id] as ReadMark).seen = true


func _scroll_down() -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _empty_hint() -> Control:
	var box := VBoxContainer.new()
	box.name = "Empty"
	var art := TextureRect.new()
	art.texture = _sticker_texture("hi")
	art.custom_minimum_size = Vector2(140, 140)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(art)
	var hint := UiStyle.label("Тут пока тихо. Кинь стикер, это проще, чем придумывать «привет».", 18, UiStyle.TEXT_DIM, 4)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(panel_width() - 120.0, 0)
	box.add_child(hint)
	return box


## ---- Сообщения ----

func _add_message(item: Dictionary) -> void:
	var id := int(item.get("id", 0))
	if id <= _last_id:
		return
	_last_id = id
	var empty := _list.get_node_or_null("Empty")
	if empty != null:
		empty.queue_free()
	var stamp := str(item.get("created_at", ""))
	var day := _day_label(stamp)
	if day != _last_day:
		_last_day = day
		_list.add_child(UiStyle.label(day, 16, UiStyle.TEXT_DIM, 4))
	var mine := bool(item.get("mine", false))
	var kind := str(item.get("kind", "text"))
	var body := str(item.get("body", ""))
	var attachment: Dictionary = item.get("attachment") if item.get("attachment") is Dictionary else {}
	if kind == "text" and is_sticker(body):
		kind = "sticker"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var content_node: Control
	match kind:
		"sticker":
			var art := TextureRect.new()
			art.texture = _sticker_texture(body)
			art.custom_minimum_size = Vector2(170, 170)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			content_node = art
		"image":
			content_node = _bubble(mine, _image_view(attachment))
			_media.append({"id": id, "kind": "image", "attachment": attachment})
		"file":
			content_node = _bubble(mine, _file_view(attachment))
			_media.append({"id": id, "kind": "file", "attachment": attachment})
		"deleted":
			content_node = _bubble(mine, _deleted_label())
		_:
			var label := UiStyle.label(body, 22, UiStyle.TEXT, 3)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var limit := minf(panel_width() - 190.0, 440.0)
			var natural := label.get_theme_font("font").get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 8.0
			label.custom_minimum_size = Vector2(minf(limit, natural), 0)
			content_node = _bubble(mine, label)
	column.add_child(content_node)
	var meta := HBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	meta.add_theme_constant_override("separation", 4)
	meta.add_child(UiStyle.label(_clock_label(stamp), 14, UiStyle.TEXT_DIM, 3))
	if mine:
		var mark := ReadMark.new()
		mark.seen = bool(item.get("seen", false)) or id <= _read_upto
		meta.add_child(mark)
		_checks[id] = mark
	var reactions_row := HBoxContainer.new()
	reactions_row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	reactions_row.add_theme_constant_override("separation", 4)
	reactions_row.visible = false
	column.add_child(reactions_row)
	_reaction_rows[id] = reactions_row
	column.add_child(meta)
	_message_nodes[id] = {"column": column, "content": content_node, "mine": mine}
	if kind != "deleted":
		_make_long_press(content_node, column, id, mine)
	_list.add_child(row)
	if not _first_load:
		column.pivot_offset = Vector2(column.size.x if mine else 0.0, 30.0)
		column.scale = Vector2(0.6, 0.6)
		column.modulate.a = 0.0
		var tween := column.create_tween().set_parallel(true)
		tween.tween_property(column, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(column, "modulate:a", 1.0, 0.15)
		if not mine:
			SoundManager.play(&"ui_click", -2.0, false)


func _bubble(mine: bool, inner: Control) -> PanelContainer:
	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MINE_BG if mine else THEIR_BG
	style.set_corner_radius_all(20)
	if mine:
		style.corner_radius_bottom_right = 4
	else:
		style.corner_radius_bottom_left = 4
		style.border_color = Color(UiStyle.NEON, 0.35)
		style.set_border_width_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.anti_aliasing = true
	bubble.add_theme_stylebox_override("panel", style)
	bubble.add_child(inner)
	return bubble


func _image_view(attachment: Dictionary) -> Control:
	var w := maxf(float(attachment.get("w", 0)), 1.0)
	var h := maxf(float(attachment.get("h", 0)), 1.0)
	var side := minf(panel_width() - 220.0, 380.0)
	var fit := Vector2(side, side * h / w) if w >= h else Vector2(side * w / h, side)
	var art := TextureRect.new()
	art.custom_minimum_size = fit.clamp(Vector2(120, 90), Vector2(side, side * 1.3))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	var path := str(attachment.get("path", ""))
	_load_image(art, path)
	art.gui_input.connect(func(event: InputEvent) -> void:
		if _tapped(event) and art.texture != null:
			_show_viewer(art.texture, path))
	return art


func _load_image(art: TextureRect, path: String) -> void:
	if path.is_empty():
		return
	if _texture_cache.has(path):
		art.texture = _texture_cache[path]
		return
	var bytes := await Cloud.download_chat_file(path)
	if not is_instance_valid(art) or bytes.is_empty():
		return
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK and image.load_png_from_buffer(bytes) != OK and image.load_webp_from_buffer(bytes) != OK:
		return
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	art.texture = texture


func _file_view(attachment: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(FileGlyph.new())
	var text := VBoxContainer.new()
	var title := UiStyle.label(str(attachment.get("name", "файл")).left(26), 20, UiStyle.TEXT, 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(title)
	var size_label := UiStyle.label(_size_label(int(attachment.get("size", 0))), 15, UiStyle.TEXT_DIM, 3)
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(size_label)
	row.add_child(text)
	var open := UiStyle.button("ОТКРЫТЬ", UiStyle.PANEL_LIGHT, 17, Vector2(120, 46))
	open.disabled = true
	var url := [""]
	row.add_child(open)
	_sign_into(open, url, str(attachment.get("path", "")))
	open.pressed.connect(func() -> void:
		if not str(url[0]).is_empty():
			Platform.open_url(str(url[0])))
	return row


## Ссылку подписываем заранее: браузер открывает вкладку только прямо из нажатия, без ожидания сервера.
func _sign_into(button: Button, url: Array, path: String) -> void:
	if path.is_empty():
		return
	var signed := await Cloud.sign_chat_file(path)
	if not is_instance_valid(button):
		return
	url[0] = signed
	button.disabled = signed.is_empty()


## Долгий тап по сообщению: реакции 👍 😂 🔥 (нарисованные значки), у чужого ещё «Пожаловаться».
func _make_long_press(target: Control, column: VBoxContainer, id: int, mine: bool) -> void:
	if target.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		target.mouse_filter = Control.MOUSE_FILTER_PASS
	var pressed_at := [-1.0]
	target.gui_input.connect(func(event: InputEvent) -> void:
		var down := false
		var up := false
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			down = (event as InputEventMouseButton).pressed
			up = not down
		elif event is InputEventScreenTouch:
			down = (event as InputEventScreenTouch).pressed
			up = not down
		elif event is InputEventScreenDrag or event is InputEventMouseMotion:
			if pressed_at[0] >= 0.0 and event.get("relative") is Vector2 and (event.get("relative") as Vector2).length() > 6.0:
				pressed_at[0] = -1.0
			return
		if down:
			var stamp := Time.get_ticks_msec() / 1000.0
			pressed_at[0] = stamp
			get_tree().create_timer(LONG_PRESS).timeout.connect(func() -> void:
				if is_instance_valid(column) and pressed_at[0] == stamp:
					pressed_at[0] = -1.0
					_open_message_menu(column, id, mine))
		elif up:
			pressed_at[0] = -1.0)


func _open_message_menu(column: VBoxContainer, id: int, mine: bool) -> void:
	for other in get_tree().get_nodes_in_group("chat_menu"):
		other.queue_free()
	Platform.haptic("medium")
	var menu := PanelContainer.new()
	menu.add_to_group("chat_menu")
	var style := UiStyle.box(Color("#1d1536"), UiStyle.NEON, 2, 26)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	menu.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	menu.add_child(row)
	var current := str((_reaction_state.get(id, {}) as Dictionary).get("mine", ""))
	for emoji in REACTIONS:
		var b := TextureButton.new()
		b.texture_normal = _reaction_texture(emoji)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(52, 52)
		if emoji == current:
			b.modulate = Color(1.3, 1.3, 1.3)
		b.pressed.connect(func() -> void:
			menu.queue_free()
			_apply_reaction(id, "" if emoji == current else emoji))
		row.add_child(b)
	if mine or SaveService.get_insider() in [0, 1, Insider.GOD]:
		var remove := UiStyle.button("Удалить", Color("#a3283e"), 17, Vector2(120, 52))
		var armed := [false]
		remove.pressed.connect(func() -> void:
			if not armed[0]:
				armed[0] = true
				remove.text = "Точно?"
				return
			menu.queue_free()
			_mark_deleted(id)
			if not await Cloud.delete_message(id) and is_instance_valid(_status):
				_status.text = "Удаление заработает после обновления сервера (SQL v22)")
		row.add_child(remove)
	if not mine:
		var report := UiStyle.button("!", Color("#a3283e"), 18, Vector2(52, 52))
		report.pressed.connect(func() -> void:
			var result := await Cloud.report_user(friend_code, "сообщение", id)
			if is_instance_valid(report):
				report.text = "OK" if result == "ok" else "X"
				report.disabled = true
				get_tree().create_timer(1.2).timeout.connect(func() -> void:
					if is_instance_valid(menu):
						menu.queue_free()))
		row.add_child(report)
	column.add_child(menu)
	column.move_child(menu, 0)
	menu.pivot_offset = Vector2(0, 30)
	menu.scale = Vector2(0.7, 0.7)
	menu.create_tween().tween_property(menu, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if is_instance_valid(menu):
			menu.queue_free())


func _deleted_label() -> Label:
	var label := UiStyle.label("Сообщение удалено", 19, UiStyle.TEXT_DIM, 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


## Сообщение удалено (мной или собеседником): вместо содержимого серая плашка, реакции и меню убираются.
func _mark_deleted(id: int) -> void:
	var node: Dictionary = _message_nodes.get(id, {})
	if node.is_empty() or bool(node.get("deleted", false)):
		return
	node["deleted"] = true
	var column: VBoxContainer = node["column"]
	var old: Control = node["content"]
	if not is_instance_valid(column) or not is_instance_valid(old):
		return
	var replacement := _bubble(bool(node["mine"]), _deleted_label())
	column.add_child(replacement)
	column.move_child(replacement, old.get_index())
	old.queue_free()
	node["content"] = replacement
	_media = _media.filter(func(m: Dictionary) -> bool: return int(m["id"]) != id)
	var row: HBoxContainer = _reaction_rows.get(id)
	if row != null and is_instance_valid(row):
		row.visible = false
	_reaction_state.erase(id)


func _apply_reaction(id: int, emoji: String) -> void:
	var state: Dictionary = _reaction_state.get(id, {})
	state["mine"] = emoji
	_reaction_state[id] = state
	_draw_reactions(id)
	SoundManager.play(&"ui_click")
	if not await Cloud.react_message(id, emoji) and is_instance_valid(_status):
		_status.text = "Реакции заработают после обновления сервера (SQL v21)"


func _poll_reactions() -> void:
	var rows := await Cloud.chat_reactions(friend_code)
	if not is_instance_valid(self):
		return
	var seen := {}
	for row in rows:
		if row is Dictionary:
			var id := int((row as Dictionary).get("id", 0))
			seen[id] = true
			if bool((row as Dictionary).get("deleted", false)):
				_mark_deleted(id)
				continue
			var state := {"mine": "" if row.get("mine") == null else str(row.get("mine")), "theirs": "" if row.get("theirs") == null else str(row.get("theirs"))}
			if state != _reaction_state.get(id, {}):
				_reaction_state[id] = state
				_draw_reactions(id)
	for id: int in _reaction_state.keys():
		if not seen.has(id) and not (_reaction_state[id] as Dictionary).values().all(func(v: Variant) -> bool: return str(v).is_empty()):
			_reaction_state[id] = {"mine": "", "theirs": ""}
			_draw_reactions(id)


func _draw_reactions(id: int) -> void:
	var row: HBoxContainer = _reaction_rows.get(id)
	if row == null or not is_instance_valid(row):
		return
	MenuPopups.clear(row)
	var state: Dictionary = _reaction_state.get(id, {})
	var counts := {}
	for key in ["theirs", "mine"]:
		var e := str(state.get(key, ""))
		if not e.is_empty():
			counts[e] = int(counts.get(e, 0)) + 1
	row.visible = not counts.is_empty()
	for emoji: String in counts:
		var chip := PanelContainer.new()
		var mine_too := str(state.get("mine", "")) == emoji
		var style := UiStyle.box(Color("#3a2d60") if not mine_too else Color("#5a2a80"), UiStyle.NEON if mine_too else Color(UiStyle.NEON, 0.3), 2, 14)
		style.content_margin_left = 6
		style.content_margin_right = 8
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", style)
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		var icon := TextureRect.new()
		icon.texture = _reaction_texture(emoji)
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		inner.add_child(icon)
		if int(counts[emoji]) > 1:
			inner.add_child(UiStyle.label(str(counts[emoji]), 15, UiStyle.TEXT, 2))
		chip.add_child(inner)
		row.add_child(chip)
		chip.pivot_offset = Vector2(18, 15)
		chip.scale = Vector2(0.4, 0.4)
		chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _reaction_texture(id: String) -> Texture2D:
	var path := "res://assets/ui/reactions/%s.png" % id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _show_viewer(texture: Texture2D, path: String = "") -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.94)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var art := TextureRect.new()
	art.texture = texture
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 12
	art.offset_right = -12
	art.offset_top = 90
	art.offset_bottom = -110
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(art)
	var close := UiStyle.button("X", UiStyle.PANEL_LIGHT, 28, Vector2(64, 64))
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -84
	close.offset_top = 20
	close.pressed.connect(shade.queue_free)
	shade.add_child(close)
	if not path.is_empty():
		var save := UiStyle.button("ОТКРЫТЬ ОРИГИНАЛ", UiStyle.HOT, 22, Vector2(320, 64))
		save.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		save.offset_left = -160
		save.offset_right = 160
		save.offset_top = -90
		save.offset_bottom = -26
		save.disabled = true
		var url := [""]
		_sign_into(save, url, path)
		save.pressed.connect(func() -> void:
			if not str(url[0]).is_empty():
				Platform.open_url(str(url[0])))
		shade.add_child(save)
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if _tapped(event):
			shade.queue_free())
	_track_overlay(shade)
	add_child(shade)


func _track_overlay(node: Node) -> void:
	overlays += 1
	node.tree_exited.connect(func() -> void: overlays = maxi(overlays - 1, 0))


## Все картинки и файлы переписки: сетка превью, тап открывает на весь экран.
func _show_gallery() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.08, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_track_overlay(shade)
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20
	box.offset_right = -20
	box.offset_top = 24
	box.offset_bottom = -24
	box.add_theme_constant_override("separation", 12)
	shade.add_child(box)
	var head := HBoxContainer.new()
	var title := UiStyle.label("МЕДИА · %d" % _media.size(), 30, UiStyle.TEXT, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UiStyle.button("X", UiStyle.PANEL_LIGHT, 28, Vector2(64, 64))
	close.pressed.connect(shade.queue_free)
	head.add_child(close)
	box.add_child(head)
	if _media.is_empty():
		box.add_child(UiStyle.label("Пока ни одной картинки и ни одного файла.", 20, UiStyle.TEXT_DIM, 4))
		return
	var scroll := DragScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var side := (get_viewport_rect().size.x - 40.0 - 16.0) / 3.0
	for i in range(_media.size() - 1, -1, -1):
		var entry: Dictionary = _media[i]
		var attachment: Dictionary = entry["attachment"]
		var path := str(attachment.get("path", ""))
		if str(entry["kind"]) == "image":
			var art := TextureRect.new()
			art.custom_minimum_size = Vector2(side, side)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.mouse_filter = Control.MOUSE_FILTER_STOP
			_load_image(art, path)
			art.gui_input.connect(func(event: InputEvent) -> void:
				if _tapped(event) and art.texture != null:
					_show_viewer(art.texture, path))
			grid.add_child(art)
		else:
			var tile := PanelContainer.new()
			tile.custom_minimum_size = Vector2(side, side)
			tile.add_theme_stylebox_override("panel", UiStyle.box(Color("#2b2148"), Color(UiStyle.NEON, 0.4), 2, 14))
			var inner := VBoxContainer.new()
			inner.alignment = BoxContainer.ALIGNMENT_CENTER
			inner.add_child(FileGlyph.new())
			(inner.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var name_label := UiStyle.label(str(attachment.get("name", "файл")).left(14), 15, UiStyle.TEXT, 2)
			inner.add_child(name_label)
			tile.add_child(inner)
			var url := [""]
			var dummy := Button.new()
			_sign_into(dummy, url, path)
			tile.add_child(dummy)
			dummy.flat = true
			dummy.pressed.connect(func() -> void:
				if not str(url[0]).is_empty():
					Platform.open_url(str(url[0])))
			grid.add_child(tile)


## ---- Отправка ----

func _send_text() -> void:
	var text := _edit.text.strip_edges()
	if text.is_empty():
		return
	_edit.text = ""
	_set_tease()
	_deliver("text", text, {})


## Новая подколка после каждого отправленного сообщения.
func _set_tease() -> void:
	var tease: String = TEASES.pick_random()
	_edit.placeholder_text = tease
	for child in _edit.get_children():
		if child is NativeField:
			(child as NativeField).placeholder = tease
			(child as NativeField).refresh()


## Быстрые стикеры над строкой ввода: пять последних, которыми пользовался (сначала самые ходовые).
func _fill_quick() -> void:
	MenuPopups.clear(_quick)
	var recent: Array = SaveService.data.get("recent_stickers", []) if SaveService.data.get("recent_stickers") is Array else []
	var ids: Array = recent.duplicate()
	for id in ["hi", "gg", "lol", "ok", "letsgo"]:
		if ids.size() >= 5:
			break
		if not ids.has(id):
			ids.append(id)
	for id in ids.slice(0, 5):
		var b := TextureButton.new()
		b.texture_normal = _sticker_texture(str(id))
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(64, 64)
		b.pressed.connect(_send_sticker.bind(str(id)))
		_quick.add_child(b)


func _send_sticker(id: String) -> void:
	var recent: Array = SaveService.data.get("recent_stickers", []) if SaveService.data.get("recent_stickers") is Array else []
	recent.erase(id)
	recent.push_front(id)
	SaveService.data["recent_stickers"] = recent.slice(0, 5)
	_fill_quick()
	_stickers.visible = false
	_scroll.custom_minimum_size.y = _base_height
	_deliver("sticker", id, {})


func _deliver(kind: String, body: String, attachment: Dictionary) -> void:
	var result := await Cloud.send_chat(friend_code, kind, body, attachment)
	if not is_instance_valid(self):
		return
	if result == "ok":
		SoundManager.play(&"ui_click")
		_clock = 0.0
		_poll()
	else:
		_status.text = str(SEND_ERRORS.get(result, "Не отправилось. Попробуй ещё раз"))
		if kind == "text" and _edit.text.is_empty():
			_edit.text = body


func _pick_attachment() -> void:
	if _uploading:
		return
	if not OS.has_feature("web"):
		_status.text = "Файлы отправляются из браузерной версии"
		return
	_picking = true
	Platform.pick_file("*/*", MAX_FILE)


func _on_picked(file: Dictionary) -> void:
	if file.is_empty():
		return
	if bool(file.get("too_big", false)):
		_status.text = "Файл больше 10 МБ, такой не пролезет в мусоропровод"
		return
	var bytes := Marshalls.base64_to_raw(str(file.get("data", "")))
	if bytes.is_empty():
		_status.text = "Файл не прочитался"
		return
	var file_name := str(file.get("name", "file"))
	var mime := str(file.get("type", ""))
	_uploading = true
	_status.text = "Отправляю «%s»..." % file_name.left(24)
	var image := Image.new()
	var as_image := mime.begins_with("image/") and _load_any(image, bytes, mime)
	var attachment := {}
	var kind := "file"
	if as_image:
		var longest := maxi(image.get_width(), image.get_height())
		if longest > IMAGE_SIDE:
			var k := float(IMAGE_SIDE) / float(longest)
			image.resize(maxi(int(image.get_width() * k), 1), maxi(int(image.get_height() * k), 1), Image.INTERPOLATE_LANCZOS)
		if image.get_format() != Image.FORMAT_RGB8:
			image.convert(Image.FORMAT_RGB8)
		bytes = image.save_jpg_to_buffer(0.82)
		mime = "image/jpeg"
		kind = "image"
		attachment = {"name": file_name.get_basename() + ".jpg", "w": image.get_width(), "h": image.get_height()}
	else:
		attachment = {"name": file_name}
	var ext := "jpg" if kind == "image" else file_name.get_extension()
	var path := await Cloud.upload_chat_file(friend_code, ext, bytes, mime)
	_uploading = false
	if not is_instance_valid(self):
		return
	if path.is_empty():
		_status.text = "Не загрузилось: %s" % (Cloud.last_error.left(90) if not Cloud.last_error.is_empty() else "нет связи")
		return
	attachment["path"] = path
	attachment["size"] = bytes.size()
	attachment["mime"] = mime
	if kind == "image":
		_texture_cache[path] = ImageTexture.create_from_image(image)
	_status.text = ""
	_deliver(kind, "", attachment)


static func _load_any(image: Image, bytes: PackedByteArray, mime: String) -> bool:
	if mime.contains("png"):
		return image.load_png_from_buffer(bytes) == OK
	if mime.contains("webp"):
		return image.load_webp_from_buffer(bytes) == OK
	if mime.contains("jpeg") or mime.contains("jpg"):
		return image.load_jpg_from_buffer(bytes) == OK
	return false


## ---- Мелочи ----

static func _tapped(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


static func _sticker_texture(id: String) -> Texture2D:
	var path := "res://assets/ui/stickers/%s.png" % id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Время сервера (UTC со смещением) -> местное, в секундах.
static func _local_unix(stamp: String) -> int:
	if stamp.length() < 19:
		return 0
	var utc := int(Time.get_unix_time_from_datetime_string(stamp.substr(0, 19)))
	var tail := stamp.substr(19)
	var plus := tail.rfind("+")
	var minus := tail.rfind("-")
	var at := maxi(plus, minus)
	var offset := 0
	if at >= 0 and tail.length() >= at + 3:
		var mins := int(tail.substr(at + 4, 2)) if tail.length() >= at + 6 else 0
		offset = (int(tail.substr(at + 1, 2)) * 3600 + mins * 60) * (1 if at == plus else -1)
	return utc - offset + int(Time.get_time_zone_from_system().get("bias", 0)) * 60


static func _clock_label(stamp: String) -> String:
	var t := _local_unix(stamp)
	if t == 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d:%02d" % [int(d["hour"]), int(d["minute"])]


static func _day_label(stamp: String) -> String:
	var t := _local_unix(stamp)
	if t == 0:
		return ""
	var now := int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var day := t / 86400
	var today := now / 86400
	if day == today:
		return "Сегодня"
	if day == today - 1:
		return "Вчера"
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d.%02d.%d" % [int(d["day"]), int(d["month"]), int(d["year"])]


static func _size_label(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f МБ" % (bytes / 1048576.0)
	return "%d КБ" % maxi(bytes / 1024, 1)


## Круглый портрет героя игрока; зелёная точка — в сети.
class PeerAvatar:
	extends Control
	static var _portraits: Dictionary = {}
	static var _textures: Dictionary = {}
	var character := "raccoon":
		set(value):
			character = value
			queue_redraw()
	var online := false:
		set(value):
			online = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(60, 60)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	static func portrait_of(id: String) -> Texture2D:
		if _portraits.is_empty():
			for entry in ConfigLoader.load_json("res://data/characters.json").get("characters", []):
				_portraits[str(entry.get("id", ""))] = str(entry.get("portrait", ""))
		var path := str(_portraits.get(id, _portraits.get("raccoon", "")))
		if _textures.has(path):
			return _textures[path]
		if path.is_empty() or not ResourceLoader.exists(path):
			return null
		# Как у аватара в меню: сжатая текстура в круглом полигоне рисуется белой, поэтому распаковываем.
		var image := (load(path) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		var texture := ImageTexture.create_from_image(image)
		_textures[path] = texture
		return texture

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, UiStyle.OUTLINE)
		draw_circle(c, r - 3.0, Color("#3a2d60"))
		var tex := PeerAvatar.portrait_of(character)
		if tex != null:
			MenuWidgets.Avatar.draw_round(self, tex, c, r - 4.0)
		if online:
			var dot := c + Vector2(r * 0.7, r * 0.7)
			draw_circle(dot, 9.0, Color("#1a1030"))
			draw_circle(dot, 6.5, Color("#35c46a"))


## Галочки: одна серая — доставлено, две голубые — прочитано.
class ReadMark:
	extends Control
	var seen := false:
		set(value):
			seen = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(26, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var color := ChatPopup.CHECK_BLUE if seen else Color("#9a92b8")
		_tick(Vector2(2, 8), color)
		if seen:
			_tick(Vector2(10, 8), color)

	func _tick(at: Vector2, color: Color) -> void:
		draw_polyline(PackedVector2Array([at, at + Vector2(4, 4), at + Vector2(12, -5)]), color, 2.4, true)


## Круглые кнопки панели ввода: стикеры, вложение, отправить. Нарисованы, чтобы не зависеть от шрифта.
class ChatIcon:
	extends Button
	enum Kind { STICKER, ATTACH, SEND }
	var kind: Kind

	func _init(which: Kind) -> void:
		kind = which
		custom_minimum_size = Vector2(60, 60)
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var bg := UiStyle.HOT if kind == Kind.SEND else Color("#3a2d60")
		if is_pressed():
			bg = bg.lightened(0.2)
		draw_circle(c, r, bg)
		var ink := Color.WHITE
		match kind:
			Kind.STICKER:
				draw_arc(c, r * 0.55, 0.0, TAU, 32, ink, 3.0, true)
				draw_circle(c + Vector2(-6, -5), 2.6, ink)
				draw_circle(c + Vector2(6, -5), 2.6, ink)
				draw_arc(c + Vector2(0, 1), 8.0, 0.35, PI - 0.35, 12, ink, 3.0, true)
			Kind.ATTACH:
				draw_line(c + Vector2(-11, 0), c + Vector2(11, 0), ink, 4.0, true)
				draw_line(c + Vector2(0, -11), c + Vector2(0, 11), ink, 4.0, true)
			Kind.SEND:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -11), c + Vector2(14, 0), c + Vector2(-12, 11), c + Vector2(-7, 0)]), ink)


class FileGlyph:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(40, 48)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(4, 2), Vector2(26, 2), Vector2(36, 12), Vector2(36, 46), Vector2(4, 46)]), Color("#5ff2ff"))
		draw_colored_polygon(PackedVector2Array([Vector2(26, 2), Vector2(36, 12), Vector2(26, 12)]), Color("#1d8fb0"))
		for i in 3:
			draw_line(Vector2(10, 22 + i * 7), Vector2(30, 22 + i * 7), Color("#1a1030"), 2.0)
