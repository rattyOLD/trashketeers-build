class_name FriendsPopup
extends GlassPopup
## Друзья: вкладки «Друзья» (чат, профиль), «Заявки», «Добавить» (ID, ссылка, визитка, бонус приглашения), «Топ».
## Открывается кнопкой «Друзья» в нижней панели меню, больше нигде.

const CARD_SIZE := Vector2(960, 540)
const MISSION_COUNT := 6
const BOARD_METRICS := [
	{"title": "Волна", "key": "w", "unit": "волна"},
	{"title": "Сюжет", "key": "sh", "unit": "печатей"},
	{"title": "Уровень", "key": "lv", "unit": "ур."},
]
const MEDALS := [Color("#ffd257"), Color("#c9d3e6"), Color("#d08a4a")]

var _status: Label
var _image_b64 := ""
var _render_token := 0


func _init() -> void:
	super("ДРУЗЬЯ")


enum Tab { FRIENDS, REQUESTS, ADD, TOP }

var _tab := Tab.FRIENDS
var _tabs_row: HBoxContainer
var _body: VBoxContainer
var _requests_count := 0
var _friends_box: VBoxContainer
var _board_box: VBoxContainer
var _online_box: VBoxContainer
var _top_box: VBoxContainer
var _online_note: Label
var _online_code: Label


## Друзья как в онлайн-играх: вкладки «Друзья», «Заявки», «Добавить», «Топ». Всё про друзей живёт только здесь.
func _refresh() -> void:
	var keep := content.get_child(0)
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	_image_b64 = ""
	_status = UiStyle.label("", 19, UiStyle.NEON, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	content.add_child(_status)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 6)
	content.add_child(_tabs_row)
	_body = MenuPopups.scroll_list(content)
	_show_tab(_tab)
	_count_requests()


func _count_requests() -> void:
	var requests := await Cloud.list_requests()
	if not is_instance_valid(_tabs_row):
		return
	_requests_count = requests.size()
	_build_tabs()


func _build_tabs() -> void:
	MenuPopups.clear(_tabs_row)
	var names := ["ДРУЗЬЯ", "ЗАЯВКИ" if _requests_count == 0 else "ЗАЯВКИ %d" % _requests_count, "ДОБАВИТЬ", "ТОП"]
	for i in names.size():
		var hot := i == _tab
		var color := UiStyle.HOT if hot else (Color("#a3283e") if i == Tab.REQUESTS and _requests_count > 0 else UiStyle.PANEL_LIGHT)
		var b := UiStyle.button(names[i], color, 18, Vector2(0, 50))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(i))
		_tabs_row.add_child(b)


func _show_tab(tab: int) -> void:
	_tab = tab as Tab
	_say("")
	_build_tabs()
	MenuPopups.clear(_body)
	match _tab:
		Tab.FRIENDS:
			_online_box = VBoxContainer.new()
			_online_box.add_theme_constant_override("separation", 8)
			_body.add_child(_online_box)
			_online_box.add_child(UiStyle.label("Загружаю...", 18, UiStyle.TEXT_DIM, 4))
			_load_online()
			_body.add_child(_blocked_section())
		Tab.REQUESTS:
			_online_box = VBoxContainer.new()
			_online_box.add_theme_constant_override("separation", 8)
			_body.add_child(_online_box)
			_load_requests()
		Tab.ADD:
			_build_add(_body)
		Tab.TOP:
			_build_top(_body)


func _build_add(list: VBoxContainer) -> void:
	list.add_child(_section("ТВОЙ ID"))
	_online_code = UiStyle.label(Cloud.friend_code if Cloud.has_code() else "...", 40, UiStyle.GOLD, 8)
	list.add_child(_online_code)
	if not Cloud.has_code():
		_fill_code()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var copy := UiStyle.button("Скопировать", UiStyle.PANEL_LIGHT, 20, Vector2(0, 56))
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func() -> void:
		if Cloud.has_code():
			DisplayServer.clipboard_set(Cloud.friend_code)
			_say("ID скопирован"))
	row.add_child(copy)
	var share := UiStyle.button("Позвать друга", UiStyle.HOT, 20, Vector2(0, 56))
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share.pressed.connect(func() -> void:
		var base := Platform.page_url()
		if not Cloud.has_code() or base.is_empty():
			_say("Ссылка появится, когда будет связь с сервером")
			return
		_say(Platform.share(_invite_line(), "%s?f=%s" % [base, Cloud.friend_code])))
	row.add_child(share)
	list.add_child(row)

	list.add_child(_section("ДОБАВИТЬ ПО ID"))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	var edit := _edit("ID друга, например E58CY3")
	edit.max_length = 64
	add_row.add_child(edit)
	var add := UiStyle.button("ДОБАВИТЬ", UiStyle.HOT, 20, Vector2(170, 56))
	add.pressed.connect(func() -> void: _add_by_id(edit, add))
	add_row.add_child(add)
	edit.text_submitted.connect(func(_t: String) -> void: add.pressed.emit())
	list.add_child(add_row)

	list.add_child(_section("ВИЗИТКА"))
	var card := CardView.new()
	card.info = SaveService.card_info()
	card.qr_text = SaveService.card_qr_text()
	card.custom_minimum_size = Vector2(panel_width() - 110.0, (panel_width() - 110.0) * CARD_SIZE.y / CARD_SIZE.x)
	list.add_child(card)
	var share_card := UiStyle.button("Поделиться визиткой", UiStyle.PANEL_LIGHT, 20, Vector2(0, 56))
	share_card.pressed.connect(func() -> void:
		var link := SaveService.card_qr_text()
		var caption := "%s\n%s" % [_invite_line(), link] if not link.is_empty() else "Моя визитка в Trash Squad"
		var note := Platform.share_image(_image_b64, "trashsquad_card.png", caption)
		_say(note if not note.is_empty() else "Картинка ещё готовится, нажми через секунду"))
	list.add_child(share_card)
	_render_card()

	list.add_child(_section("БОНУС ЗА ПРИГЛАШЕНИЕ"))
	var invite := UiStyle.label("Твой код %s: другу +%d монет и +%d неонита, тебе столько же." % [SaveService.invite_code(), SaveService.INVITE_COINS, SaveService.INVITE_GEMS], 18, UiStyle.TEXT_DIM, 4)
	invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	list.add_child(invite)
	var copy_invite := UiStyle.button("Скопировать код приглашения", UiStyle.PANEL_LIGHT, 20, Vector2(0, 54))
	copy_invite.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(SaveService.invite_code())
		SaveService.mark_invite_sent()
		_say("Код приглашения скопирован"))
	list.add_child(copy_invite)
	if str(SaveService.data["invite_used"]).is_empty():
		var code_row := HBoxContainer.new()
		code_row.add_theme_constant_override("separation", 8)
		var code_edit := _edit("Код друга: INV-...")
		code_edit.max_length = 32
		code_row.add_child(code_edit)
		var code_button := UiStyle.button("ПРИНЯТЬ", UiStyle.HOT, 20, Vector2(170, 56))
		code_button.pressed.connect(func() -> void:
			var result: String = SaveService.use_invite(code_edit.text)
			if result == "ok":
				_say("Бонус получен: +%d монет и +%d неонита" % [SaveService.INVITE_COINS, SaveService.INVITE_GEMS])
				_show_tab(Tab.ADD)
			else:
				_say({"self": "Свой код вводить нельзя", "used": "Приглашение уже принято"}.get(result, "Код не подошёл. Он начинается с INV-")))
		code_row.add_child(code_button)
		code_edit.text_submitted.connect(func(_t: String) -> void: code_button.pressed.emit())
		list.add_child(code_row)


func _fill_code() -> void:
	await Cloud.sync_profile()
	if is_instance_valid(_online_code):
		_online_code.text = Cloud.friend_code if Cloud.has_code() else "нет связи"


func _add_by_id(edit: LineEdit, add: Button) -> void:
	var code := edit.text.strip_edges()
	if code.is_empty():
		return
	if code.begins_with("TRF1."):
		var card_result: String = SaveService.add_friend(code)
		_say("Друг добавлен по визитке" if card_result == "ok" or card_result == "bonus" else "Визитка не подошла")
		edit.text = ""
		return
	code = Cloud.normalize_code(code)
	if code.length() != 6:
		_say("ID — 6 знаков, например E58CY3")
		return
	add.disabled = true
	var result := await Cloud.request_friend(code)
	if result == "no_server":
		result = await Cloud.add_friend(code)
	if not is_instance_valid(add):
		return
	add.disabled = false
	var answers := {"sent": "Заявка отправлена. Друг увидит её во вкладке «Заявки»", "ok": "Вы друзья!", "friends": "Вы уже друзья",
		"not_found": "Такого ID нет. Проверь буквы", "self": "Это твой собственный ID", "blocked": "Заявку отправить нельзя",
		"limit": "Лимит друзей или заявок исчерпан"}
	if answers.has(result):
		_say(str(answers[result]))
		if result in ["sent", "ok"]:
			edit.text = ""
	else:
		_say("Не вышло: %s" % (Cloud.last_error if not Cloud.last_error.is_empty() else "нет связи с сервером"))


func _blocked_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var button := UiStyle.button("Заблокированные", UiStyle.PANEL_LIGHT, 17, Vector2(0, 46))
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	button.pressed.connect(func() -> void:
		MenuPopups.clear(holder)
		var blocks := await Cloud.list_blocks()
		if not is_instance_valid(holder):
			return
		if blocks.is_empty():
			holder.add_child(UiStyle.label("Никого", 18, UiStyle.TEXT_DIM, 4))
		for entry in blocks:
			if entry is Dictionary:
				var code := str((entry as Dictionary).get("friend_code", ""))
				var line := HBoxContainer.new()
				var who := UiStyle.label(str((entry as Dictionary).get("nickname", "Енот")), 20, UiStyle.TEXT, 4)
				who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line.add_child(who)
				var undo := UiStyle.button("Разблокировать", UiStyle.PANEL_LIGHT, 17, Vector2(200, 46))
				undo.pressed.connect(func() -> void:
					await Cloud.unblock_user(code)
					if is_instance_valid(line):
						line.queue_free())
				line.add_child(undo)
				holder.add_child(line))
	box.add_child(button)
	box.add_child(holder)
	return box


func _build_top(list: VBoxContainer) -> void:
	list.add_child(_section("ЛУЧШИЕ ПО ВОЛНЕ"))
	_top_box = VBoxContainer.new()
	_top_box.add_theme_constant_override("separation", 6)
	list.add_child(_top_box)
	_load_top()


func _load_top() -> void:
	var result := await Cloud.top_waves(20)
	if not is_instance_valid(_top_box):
		return
	MenuPopups.clear(_top_box)
	var items: Array = result["items"]
	if not bool(result["ok"]) or items.is_empty():
		var text := "Топ не загрузился, нет связи" if not bool(result["ok"]) else "Пока пусто. Стань первым."
		_top_box.add_child(UiStyle.label(text, 18, UiStyle.TEXT_DIM, 4))
		return
	for i in items.size():
		var item: Dictionary = items[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var medal: Color = MEDALS[i] if i < MEDALS.size() else UiStyle.TEXT_DIM
		var place := UiStyle.label(str(i + 1), 24, medal, 6)
		place.custom_minimum_size = Vector2(40, 0)
		row.add_child(place)
		var badge := Insider.badge_of(int(item.get("insider", -1)))
		var nick := str(item.get("nickname", "Енот"))
		var name_label := UiStyle.label(nick if badge.is_empty() else "%s %s" % [badge, nick], 22, Insider.color_of(int(item.get("insider", -1)), UiStyle.TEXT), 5)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		row.add_child(UiStyle.label("волна %d" % int(item.get("best_wave", 0)), 20, UiStyle.GOLD, 5))
		_top_box.add_child(row)


func _load_online() -> void:
	var box := _online_box
	var result := await Cloud.inbox()
	if not is_instance_valid(box) or box != _online_box:
		return
	MenuPopups.clear(box)
	if not bool(result["ok"]):
		var note := _wrap_label("Нет связи с сервером (%s)\nПроверяю связь..." % Cloud.last_error)
		box.add_child(note)
		var report := await Cloud.ping()
		if is_instance_valid(note):
			note.text = "Нет связи с сервером (%s)\n%s" % [Cloud.last_error, report]
			DisplayServer.clipboard_set(report)
			note.text += "\n(отчёт скопирован, вставь в чат)"
		return
	var items: Array = result["items"]
	if items.is_empty():
		box.add_child(_empty_art("friends"))
		box.add_child(_wrap_label("Пока никого. Позови друга во вкладке «Добавить»."))
		var go := UiStyle.button("ДОБАВИТЬ ДРУГА", UiStyle.HOT, 22, Vector2(0, 60))
		go.pressed.connect(_show_tab.bind(Tab.ADD))
		box.add_child(go)
		return
	items.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ua := int((a as Dictionary).get("unread", 0))
		var ub := int((b as Dictionary).get("unread", 0))
		if ua != ub:
			return ua > ub
		return str((a as Dictionary).get("last_seen", "")) > str((b as Dictionary).get("last_seen", "")))
	var online := 0
	for item in items:
		if item is Dictionary and SocialProfilePopup.seen_text(str((item as Dictionary).get("last_seen", ""))) == "Сейчас в сети":
			online += 1
	var head := UiStyle.label("В сети %d из %d" % [online, items.size()], 18, Color("#35c46a") if online > 0 else UiStyle.TEXT_DIM, 4)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(head)
	for item in items:
		if item is Dictionary:
			box.add_child(_social_row(item as Dictionary))
	Cloud.refresh_unread()


func _load_requests() -> void:
	var box := _online_box
	var requests := await Cloud.list_requests()
	if not is_instance_valid(box) or box != _online_box:
		return
	MenuPopups.clear(box)
	_requests_count = requests.size()
	_build_tabs()
	if requests.is_empty():
		box.add_child(_empty_art("requests"))
		box.add_child(_wrap_label("Новых заявок нет."))
		return
	for request in requests:
		if request is Dictionary:
			box.add_child(_request_row(request as Dictionary))


## Картинка пустого списка (Астра): енот у костра, енот с проводами, голубь-почтальон.
func _empty_art(id: String) -> Control:
	var rect := TextureRect.new()
	var path := "res://assets/ui/empty/%s.png" % id
	rect.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	rect.custom_minimum_size = Vector2(0, 190)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _wrap_label(text: String) -> Label:
	var label := UiStyle.label(text, 19, UiStyle.TEXT_DIM, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(panel_width() - 120.0, 0)
	return label


func _open_profile(code: String) -> void:
	var popup := SocialProfilePopup.new(code)
	add_child(popup)
	popup.changed.connect(func() -> void: _show_tab(_tab))
	popup.closed.connect(func() -> void:
		popup.queue_free()
		_show_tab(_tab))
	popup.open()


const INVITES: Array[String] = [
	"%s зовёт тебя на свалку. Жми и будем друзьями:",
	"%s уже стреляет по крысам и скучает без тебя. Заходи:",
	"%s оставил тебе место на помойке. Подружимся:",
	"%s просит добавить его, пока не уехал мусоровоз:",
	"%s выдаёт пушки на свалке. Твоя ждёт тебя:",
]


func _invite_line() -> String:
	return INVITES[randi() % INVITES.size()] % SaveService.get_nickname()


func _open_chat(code: String, nick: String, character: String = "raccoon") -> void:
	var popup := ChatPopup.new(code, nick, character)
	add_child(popup)
	popup.closed.connect(func() -> void:
		popup.queue_free()
		_show_tab(_tab))
	popup.open()


func _tappable(panel: Control, action: Callable) -> void:
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var tapped := UiStyle.is_tap(event)
		if tapped:
			SoundManager.play(&"ui_click")
			action.call())


func _social_row(friend: Dictionary) -> Control:
	var code := str(friend.get("friend_code", ""))
	var nick := str(friend.get("nickname", "Енот"))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color(UiStyle.NEON, 0.6), 3, 14))
	_tappable(panel, _open_profile.bind(code))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var online := SocialProfilePopup.seen_text(str(friend.get("last_seen", ""))) == "Сейчас в сети"
	var stats: Dictionary = friend.get("stats") if friend.get("stats") is Dictionary else {}
	var character := str(stats.get("c", "raccoon"))
	var avatar := ChatPopup.PeerAvatar.new()
	avatar.character = character
	avatar.online = online
	row.add_child(avatar)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tag := int(friend.get("insider", -1))
	var badge := Insider.badge_of(tag)
	var name_label := UiStyle.label(nick if badge.is_empty() else "%s %s" % [badge, nick], 24, Insider.color_of(tag, UiStyle.TEXT), 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color(UiStyle.NEON, 0.6) if tag < 0 else Insider.color_of(tag, UiStyle.TEXT), 3, 16))
	var preview := "" if friend.get("last_body") == null else ChatPopup.preview_of(str(friend.get("last_body")))
	var when := "" if friend.get("last_at") == null else ChatPopup._clock_label(str(friend.get("last_at")))
	var sub_text := (preview.left(30) + ("  · " + when if not when.is_empty() else "")) if not preview.is_empty() else ("в сети" if online else "волна %d" % int(friend.get("best_wave", 0)))
	var sub := UiStyle.label(sub_text, 17, Color("#35c46a") if preview.is_empty() and online else UiStyle.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(sub)
	row.add_child(text)
	if not CoopScreen.host().is_empty():
		var play := UiStyle.button("КООП", Color("#00a5b8"), 20, Vector2(96, 52))
		play.name = "CoopInviteButton"
		play.pressed.connect(func() -> void:
			var menu := get_parent()
			if menu != null and menu.has_method("open_coop"):
				close()
				menu.call("open_coop", "", code))
		row.add_child(play)
	var unread := int(friend.get("unread", 0))
	var chat := UiStyle.button("ЧАТ" if unread == 0 else "ЧАТ %d" % unread, UiStyle.HOT if unread > 0 else UiStyle.PANEL_LIGHT, 20, Vector2(128, 52))
	chat.pressed.connect(func() -> void: _open_chat(code, nick, character))
	row.add_child(chat)
	return panel


func _request_row(request: Dictionary) -> Control:
	var code := str(request.get("friend_code", ""))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color(UiStyle.HOT, 0.8), 3, 14))
	_tappable(panel, _open_profile.bind(code))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var name_label := UiStyle.label(str(request.get("nickname", "Енот")), 24, UiStyle.TEXT, 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	var accept := UiStyle.button("ДА", Color("#2fae5f"), 20, Vector2(84, 52))
	accept.pressed.connect(func() -> void:
		await Cloud.answer_request(code, true)
		if is_instance_valid(self):
			_say("Теперь вы друзья")
			_show_tab(Tab.REQUESTS))
	row.add_child(accept)
	var decline := UiStyle.button("X", Color("#a3283e"), 20, Vector2(60, 52))
	decline.pressed.connect(func() -> void:
		await Cloud.answer_request(code, false)
		if is_instance_valid(self):
			_show_tab(Tab.REQUESTS))
	row.add_child(decline)
	return panel


func _online_row(friend: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color(UiStyle.NEON, 0.6), 3, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var badge := Insider.badge_of(int(friend.get("insider", -1)))
	var nick := str(friend.get("nickname", "Енот"))
	var name_label := UiStyle.label(nick if badge.is_empty() else "%s %s" % [badge, nick], 24, UiStyle.TEXT, 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(UiStyle.label("волна %d" % int(friend.get("best_wave", 0)), 22, UiStyle.GOLD, 6))
	var remove := UiStyle.button("X", Color("#a3283e"), 22, Vector2(52, 52))
	var armed := [false]
	remove.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			remove.text = "?"
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				if is_instance_valid(remove):
					armed[0] = false
					remove.text = "X")
			return
		await Cloud.remove_friend(str(friend.get("friend_code", "")))
		if is_instance_valid(self):
			_load_online())
	row.add_child(remove)
	return panel
var _board_metric := 0


func _refresh_list_only() -> void:
	MenuPopups.clear(_friends_box)
	_fill_friends()
	MenuPopups.clear(_board_box)
	_fill_board()


func _fill_board() -> void:
	var metric: Dictionary = BOARD_METRICS[_board_metric]
	var key := str(metric["key"])
	var entries: Array = SaveService.get_friends().duplicate()
	var mine := SaveService.card_info()
	mine["me"] = true
	entries.append(mine)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get(key, 0)) > int(b.get(key, 0)))
	for i in mini(entries.size(), 8):
		_board_box.add_child(_board_row(entries[i], i, key, str(metric["unit"])))


func _board_row(entry: Dictionary, place: int, key: String, unit: String) -> Control:
	var me := bool(entry.get("me", false))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT if not me else UiStyle.PANEL_LIGHT, UiStyle.NEON if me else Color(UiStyle.OUTLINE, 1.0), 3, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var medal: Color = MEDALS[place] if place < MEDALS.size() else UiStyle.TEXT_DIM
	var number := UiStyle.label(str(place + 1), 30, medal, 7)
	number.custom_minimum_size = Vector2(40, 0)
	row.add_child(number)
	var avatar := AvatarView.new()
	avatar.character_id = str(entry.get("c", ""))
	avatar.skin_id = str(entry.get("s", "classic"))
	avatar.custom_minimum_size = Vector2(56, 56)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	var name_label := UiStyle.label("%s%s" % [str(entry.get("n", "Енот")), "  (ты)" if me else ""], 24, UiStyle.TEXT, 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(UiStyle.label("%d %s" % [int(entry.get(key, 0)), unit], 22, UiStyle.GOLD, 6))
	return panel


func _fill_friends() -> void:
	var friends := SaveService.get_friends()
	if friends.is_empty():
		_friends_box.add_child(_empty_art("friends"))
		var empty := UiStyle.label("Пока пусто. Вставь код визитки друга выше.", 20, UiStyle.TEXT_DIM, 4)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
		_friends_box.add_child(empty)
		return
	for friend in friends:
		_friends_box.add_child(_friend_row(friend))


func _friend_row(friend: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, Color(UiStyle.NEON, 0.6), 3, 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var avatar := AvatarView.new()
	avatar.character_id = str(friend.get("c", ""))
	avatar.skin_id = str(friend.get("s", "classic"))
	avatar.custom_minimum_size = Vector2(84, 84)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var badge := Insider.badge_of(int(friend.get("ins", -1)))
	var nick := str(friend.get("n", "Енот"))
	var name_label := UiStyle.label(nick if badge.is_empty() else "%s %s" % [badge, nick], 26, UiStyle.TEXT, 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(name_label)
	var stats := UiStyle.label("Уровень %d · волна %d · боссов %d" % [int(friend.get("lv", 1)), int(friend.get("w", 0)), int(friend.get("bk", 0))], 18, UiStyle.TEXT_DIM, 4)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(stats)
	column.add_child(_mission_badges(friend.get("m", []) as Array, int(friend.get("sh", 0))))
	var remove := UiStyle.button("X", Color("#a3283e"), 22, Vector2(56, 56))
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var armed := [false]
	remove.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			remove.text = "?"
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				if is_instance_valid(remove):
					armed[0] = false
					remove.text = "X")
			return
		SaveService.remove_friend(str(friend.get("id", "")))
		_refresh_list_only())
	row.add_child(remove)
	return panel


func _mission_badges(done: Array, shards: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiStyle.label("Сюжет %d/6" % shards, 18, UiStyle.GOLD, 4))
	for i in MISSION_COUNT:
		var passed := done.has("m%d" % (i + 1))
		var chip := PanelContainer.new()
		var chip_box := UiStyle.box(Color("#35c46a") if passed else UiStyle.PANEL_LIGHT, UiStyle.OUTLINE, 2, 8)
		chip_box.content_margin_left = 5
		chip_box.content_margin_right = 5
		chip_box.content_margin_top = 1
		chip_box.content_margin_bottom = 1
		chip.add_theme_stylebox_override("panel", chip_box)
		chip.add_child(UiStyle.label("М%d" % (i + 1), 16, UiStyle.TEXT if passed else UiStyle.TEXT_DIM, 3))
		row.add_child(chip)
	return row


func _section(title: String) -> Control:
	var caption := UiStyle.label(title, 24, UiStyle.NEON, 6)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return caption


func _edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 56)
	edit.max_length = 4096
	SearchBar.style(edit, 22)
	SearchBar.attach_touch_input(edit, placeholder)
	return edit


func _say(text: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text


## Картинка визитки рендерится заранее, чтобы кнопка «Поделиться» сработала в рамках жеста нажатия.
func _render_card() -> void:
	_render_token += 1
	var token := _render_token
	if not Cloud.has_code():
		await Cloud.sync_profile()
		if not is_instance_valid(self) or token != _render_token:
			return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CARD_SIZE)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card := CardView.new()
	card.info = SaveService.card_info()
	card.qr_text = SaveService.card_qr_text()
	card.size = CARD_SIZE
	viewport.add_child(card)
	add_child(viewport)
	await get_tree().process_frame
	await get_tree().process_frame
	if token == _render_token and is_instance_valid(viewport):
		var image := viewport.get_texture().get_image()
		if image != null:
			_image_b64 = Marshalls.raw_to_base64(image.save_png_to_buffer())
	if is_instance_valid(viewport):
		viewport.queue_free()


## Круглый портрет героя по id и скину (для списка друзей).
class AvatarView:
	extends Control

	var character_id := ""
	var skin_id := "classic"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, UiStyle.OUTLINE)
		draw_circle(c, r - 3.0, UiStyle.PANEL_LIGHT)
		var tex := MenuWidgets.Avatar.get_texture_for(CharacterDB.get_character(character_id), skin_id)
		if tex != null:
			draw_texture_rect(tex, Rect2(c - Vector2.ONE * (r - 4.0), Vector2.ONE * (r - 4.0) * 2.0), false)
		draw_arc(c, r - 1.5, 0.0, TAU, 36, UiStyle.NEON, 3.0, true)


## Сама визитка: рисуется в виртуальных 960x540 и масштабируется под размер контрола.
class CardView:
	extends Control

	const BG_TOP := UiStyle.PANEL_LIGHT
	const BG_BOTTOM := UiStyle.PANEL

	var info: Dictionary = {}
	var qr_text := ""
	var _qr: QrCode
	var _qr_for := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := minf(size.x / FriendsPopup.CARD_SIZE.x, size.y / FriendsPopup.CARD_SIZE.y)
		draw_set_transform(Vector2((size.x - FriendsPopup.CARD_SIZE.x * k) * 0.5, 0.0), 0.0, Vector2(k, k))
		var font := get_theme_default_font()
		var w := FriendsPopup.CARD_SIZE.x
		var h := FriendsPopup.CARD_SIZE.y
		_draw_background(w, h)
		var level := int(info.get("lv", 1))
		var ins := int(info.get("ins", -1))
		var tag_color := Insider.color_of(ins, UiStyle.NEON) if ins != 1 else UiStyle.HOT
		var tag := Insider.badge_of(ins).trim_prefix("[").trim_suffix("]").to_upper()
		if not tag.is_empty():
			var tag_size := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22)
			var badge := Insider.badge_texture(ins)
			var icon_w := 46.0 if badge != null else 0.0
			var pill := Rect2(48, 38, tag_size.x + 36 + icon_w, 38)
			draw_style_box(UiStyle.box(Color(tag_color, 0.2), tag_color, 3, 19), pill)
			if badge != null:
				draw_texture_rect(badge, Rect2(pill.position.x - 6, pill.position.y - 12, 62, 62), false)
			_fit(font, tag, Vector2(pill.position.x + 18 + icon_w, pill.position.y + 28), 22, tag_color, tag_size.x + 2.0)
		_fit(font, str(info.get("n", "Енот")), Vector2(48, 134), 66, UiStyle.TEXT, 560.0)
		_wordmark(font, Vector2(w - 48, 74))
		var frame := Rect2(48, 176, 248, 248)
		draw_style_box(UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.NEON, 6, 40), frame)
		var tex := MenuWidgets.Avatar.get_texture_for(CharacterDB.get_character(str(info.get("c", ""))), str(info.get("s", "classic")))
		if tex != null:
			draw_texture_rect(tex, frame.grow(-12.0), false)
		var level_pill := Rect2(frame.position.x + 52, frame.end.y - 22, 144, 46)
		draw_style_box(UiStyle.box(UiStyle.HOT, UiStyle.OUTLINE, 3, 23), level_pill)
		_fit(font, "УР. %d" % level, Vector2(level_pill.position.x, level_pill.position.y + 34), 30, Color.WHITE, level_pill.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_fit(font, MenuPopups.Profile.rank_for(level).to_upper(), Vector2(332, 204), 30, Color("#ff9a3d"), 340.0)
		var stats := [["ВОЛНА", str(int(info.get("w", 0))), UiStyle.NEON], ["БОССЫ", str(int(info.get("bk", 0))), UiStyle.HOT], ["ОСКОЛКИ", "%d/6" % int(info.get("sh", 0)), UiStyle.GOLD]]
		for i in stats.size():
			var rect := Rect2(332 + i * 116, 226, 108, 104)
			var accent: Color = stats[i][2]
			draw_style_box(UiStyle.box(Color(1, 1, 1, 0.07), Color(accent, 0.55), 3, 20), rect)
			draw_rect(Rect2(rect.position.x + 22, rect.position.y + 10, rect.size.x - 44, 5), accent)
			_fit(font, str(stats[i][1]), rect.position + Vector2(0, 66), 44, UiStyle.TEXT, rect.size.x - 10.0, HORIZONTAL_ALIGNMENT_CENTER)
			_fit(font, str(stats[i][0]), rect.position + Vector2(0, 92), 17, UiStyle.TEXT_DIM, rect.size.x - 10.0, HORIZONTAL_ALIGNMENT_CENTER)
		_fit(font, "СЮЖЕТ", Vector2(332, 372), 18, UiStyle.TEXT_DIM, 120.0)
		var done: Array = info.get("m", []) as Array
		for i in FriendsPopup.MISSION_COUNT:
			var passed := done.has("m%d" % (i + 1))
			var centre := Vector2(354 + i * 56, 410)
			draw_circle(centre, 24.0, Color("#35c46a") if passed else UiStyle.PANEL_LIGHT)
			draw_arc(centre, 24.0, 0.0, TAU, 40, Color("#8dffb0") if passed else Color(UiStyle.TEXT_DIM, 0.6), 3.0, true)
			_fit(font, "%d" % (i + 1), centre + Vector2(-24, 10), 28, UiStyle.TEXT if passed else UiStyle.TEXT_DIM, 48.0, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_qr(font)
		draw_rect(Rect2(0, h - 70, w, 70), Color(0, 0, 0, 0.35))
		_fit(font, "Енот-налётчик против крыс и свиней", Vector2(48, h - 26), 24, UiStyle.TEXT_DIM, 520.0)
		var friend_code := str(info.get("fc", ""))
		if not friend_code.is_empty():
			var id_text := "ID %s" % friend_code
			var id_width := font.get_string_size(id_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30).x
			var id_rect := Rect2(w - 48 - id_width - 36, h - 62, id_width + 36, 46)
			draw_style_box(UiStyle.box(Color(UiStyle.NEON, 0.15), UiStyle.NEON, 3, 23), id_rect)
			_fit(font, id_text, Vector2(id_rect.position.x + 18, id_rect.position.y + 34), 30, UiStyle.NEON, id_width + 2.0)

	func _draw_background(w: float, h: float) -> void:
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
		for i in 7:
			draw_circle(Vector2(w - 60, 40), 340.0 - i * 44.0, Color(UiStyle.NEON, 0.012 + i * 0.006))
			draw_circle(Vector2(40, h - 20), 300.0 - i * 40.0, Color(UiStyle.HOT, 0.012 + i * 0.005))
		for i in range(-6, 22):
			draw_line(Vector2(i * 64.0, 0), Vector2(i * 64.0 + 320.0, h), Color(1, 1, 1, 0.025), 2.0)
		var ins := int(info.get("ins", -1))
		var outer := Insider.color_of(ins, UiStyle.NEON) if ins != 1 else UiStyle.HOT
		var inner := Color(UiStyle.GOLD, 0.8) if ins == 0 else (Color(UiStyle.NEON, 0.8) if ins > 0 else Color(UiStyle.HOT, 0.8))
		draw_style_box(UiStyle.box(Color(0, 0, 0, 0), outer, 6 if ins < 0 else 8, 30), Rect2(5, 5, w - 10, h - 10))
		draw_style_box(UiStyle.box(Color(0, 0, 0, 0), inner, 2, 26), Rect2(15, 15, w - 30, h - 30))

	func _wordmark(font: Font, right_top: Vector2) -> void:
		var first := "TRASH "
		var second := "SQUAD"
		var w1 := font.get_string_size(first, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36).x
		var w2 := font.get_string_size(second, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36).x
		var x := right_top.x - w1 - w2
		_fit(font, first, Vector2(x, right_top.y), 36, UiStyle.GOLD, w1 + 2.0)
		_fit(font, second, Vector2(x + w1, right_top.y), 36, UiStyle.NEON, w2 + 2.0)

	func _draw_qr(font: Font) -> void:
		var plate := Rect2(704, 176, 208, 208)
		if qr_text.is_empty():
			draw_style_box(UiStyle.box(Color(1, 1, 1, 0.07), Color(UiStyle.NEON, 0.55), 3, 24), plate)
			_fit(font, "УБИТО КРЫС", Vector2(plate.position.x, 224), 20, UiStyle.TEXT_DIM, plate.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_fit(font, str(int(info.get("k", 0))), Vector2(plate.position.x, 280), 52, UiStyle.DANGER, plate.size.x - 10.0, HORIZONTAL_ALIGNMENT_CENTER)
			_fit(font, "ЗАБЕГОВ", Vector2(plate.position.x, 332), 20, UiStyle.TEXT_DIM, plate.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_fit(font, str(int(info.get("r", 0))), Vector2(plate.position.x, 372), 40, UiStyle.GOLD, plate.size.x - 10.0, HORIZONTAL_ALIGNMENT_CENTER)
			return
		draw_style_box(UiStyle.box(Color(UiStyle.NEON, 0.25), Color(UiStyle.NEON, 0.0), 0, 34), plate.grow(14.0))
		draw_style_box(UiStyle.box(Color.WHITE, UiStyle.NEON, 5, 24), plate)
		if _qr_for != qr_text:
			_qr = QrCode.encode(qr_text)
			_qr_for = qr_text
		if _qr != null:
			var cell := floorf((plate.size.x - 16.0) / float(_qr.size + 2))
			var origin := plate.position + (plate.size - Vector2.ONE * cell * _qr.size) * 0.5
			for y in _qr.size:
				for x in _qr.size:
					if _qr.is_dark(x, y):
						draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell), Color("#23221f"))
		_fit(font, "СКАНИРУЙ QR", Vector2(plate.position.x - 12, 430), 24, UiStyle.TEXT, plate.size.x + 24.0, HORIZONTAL_ALIGNMENT_CENTER)
		_fit(font, "И ДОБАВЬ В ДРУЗЬЯ", Vector2(plate.position.x - 12, 460), 24, UiStyle.HOT, plate.size.x + 24.0, HORIZONTAL_ALIGNMENT_CENTER)

	## Строка с обводкой; кегль уменьшается, пока текст не влезет в ширину (иначе движок обрезает хвост).
	@warning_ignore("integer_division")
	func _fit(font: Font, text: String, at: Vector2, font_size: int, color: Color, width: float, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var used := font_size
		while used > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, used).x > width:
			used -= 1
		draw_string_outline(font, at, text, align, width, used, maxi(4, used / 8), UiStyle.OUTLINE)
		draw_string(font, at, text, align, width, used, color)

	func _text(font: Font, text: String, at: Vector2, font_size: int, color: Color, width: float, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		draw_string_outline(font, at, text, align, width, font_size, 7, UiStyle.OUTLINE)
		draw_string(font, at, text, align, width, font_size, color)
