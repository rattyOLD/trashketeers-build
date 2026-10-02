class_name CoopScreen
extends Control
## Лобби коопа «Выживание на двоих» в духе мобильных игр: два слота героев, кнопка «ПОЗВАТЬ ДРУГА», одна большая кнопка старта.
## Без сервера в слоте напарника стоит бот (тренировка на устройстве). С сервером комната создаётся сама при входе,
## друзья зовутся из списка, приглашённый попадает сразу в чужое лобби. Бой считает сервер (CoopNet), награды выдаёт он же.

signal closed

enum Mode { MENU, CONNECTING, ROOM, RUN, RESULTS }

const HOST_KEY := "trk_coop_host"
const CONNECT_TIMEOUT := 8.0
const ME_COLOR := Color("#ff8200")
const FRIEND_COLOR := Color("#ff8a3d")

var mode: Mode = Mode.MENU
var _body: VBoxContainer
var _status: Label
var _view: CoopView
var _net: CoopNet
var _arena: CoopArena
var _local := false
var _acc := 0.0
var _ticks := 0
var _my_id := 0
var _room: Dictionary = {}
var _results: Dictionary = {}
## Задаются снаружи до add_child: войти в комнату друга по приглашению / сразу позвать друга после создания комнаты.
var join_code := ""
var invite_code := ""
## Автоматически создавать комнату при открытии (если есть сервер и аккаунт). Тесты могут отключить.
var auto_create := true
var _friends: Array = []
var _friends_loaded := false
var _invited: Dictionary = {}
var _count_end_ms := -1
var _count_label: Label
var _toast_label: Label
var _invite_sent_for := ""
var _friends_box: VBoxContainer
var _tab := "friends"          # friends | recent | requests
var _requests: Array = []
var _failed_note := ""
var _pending_checked := false
var _top_scope := "friends"
var _top: Array = []


## Адрес игрового сервера: настройка тестера, иначе data/platform.json. Пусто: комнат на сервере пока нет.
static func host() -> String:
	var custom := Platform.storage_get(HOST_KEY).strip_edges()
	if not custom.is_empty():
		return custom
	var file := FileAccess.open("res://data/platform.json", FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return str((parsed as Dictionary).get("coop_host", "")) if parsed is Dictionary else ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("#272523")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(minf(GlassPopup.panel_width(), 560.0), 0)
	_body.add_theme_constant_override("separation", 14)
	center.add_child(_body)


func _ready() -> void:
	_show_lobby()
	var refresh := Timer.new()
	refresh.wait_time = 30.0
	refresh.timeout.connect(func() -> void:
		if mode != Mode.RUN:
			_load_friends(true))
	add_child(refresh)
	refresh.start()
	if not join_code.is_empty():
		_connect_then("join", join_code)
	elif (not invite_code.is_empty() or auto_create) and _can_use_server():
		_connect_then("create")


func _process(_delta: float) -> void:
	if _count_label != null and is_instance_valid(_count_label) and _count_end_ms >= 0:
		var left := maxf(0.0, (_count_end_ms - Time.get_ticks_msec()) / 1000.0)
		_count_label.text = "Старт через %d..." % int(ceil(left))


func _exit_tree() -> void:
	_cleanup_net()


## Комнаты на сервере доступны, когда сервер задан и у игрока есть аккаунт (или идёт автотест).
func _can_use_server() -> bool:
	return not host().is_empty() and (Cloud.has_code() or Net.insecure_test)


# =========================== лобби ===========================

## Выход из боя или итогов: возвращаемся в лобби и, если можно, открываем новую комнату.
func _show_menu() -> void:
	_show_lobby()
	if _can_use_server() and _net == null and mode == Mode.MENU and _failed_note.is_empty() and not _local:
		_connect_then("create")


func _show_room() -> void:
	_show_lobby()


func _show_lobby() -> void:
	if mode == Mode.RUN or mode == Mode.RESULTS:
		_clear_run()
	if mode != Mode.ROOM and mode != Mode.CONNECTING:
		mode = Mode.MENU
	_reset_body()
	_count_label = null
	_status = null
	_friends_box = null
	_body.custom_minimum_size = Vector2(minf(GlassPopup.panel_width(), 620.0), 0)
	# --- верхняя строка: назад, название, приглашения ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var back := UiStyle.button("<", UiStyle.PANEL_LIGHT, 28, Vector2(72, 60))
	back.name = "BackButton"
	back.pressed.connect(_close)
	top.add_child(back)
	var title := UiStyle.label("КООП: ВЫЖИВАНИЕ", 28, UiStyle.GOLD, 7)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	top.add_child(title)
	var bell := UiStyle.button(CoopMute.short_text(), UiStyle.PANEL_LIGHT, 16, Vector2(150, 60))
	bell.name = "MuteButton"
	bell.pressed.connect(func() -> void:
		CoopMute.cycle()
		_show_lobby())
	top.add_child(bell)
	_body.add_child(top)
	# --- слоты героев ---
	var members: Array = _room.get("members", []) as Array
	var me: Dictionary = {}
	var other: Dictionary = {}
	for member: Variant in members:
		var m := member as Dictionary
		if int(m["id"]) == _my_id:
			me = m
		else:
			other = m
	var online := not members.is_empty()
	if me.is_empty():
		me = {"name": SaveService.get_nickname(), "c": SaveService.get_character_id(), "s": SaveService.get_selected_skin(), "lv": SaveService.get_account_level(), "ready": false, "host": true, "rating": int(SaveService.data.get("coop_rating", 0)), "tier": str(SaveService.data.get("coop_tier", "Ржавый"))}
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_child(_slot_card(me, ME_COLOR, true))
	if not other.is_empty():
		slots.add_child(_slot_card(other, FRIEND_COLOR, false))
	elif online or _can_use_server() or mode == Mode.CONNECTING:
		slots.add_child(_empty_slot())
	else:
		slots.add_child(_slot_card({"name": "Бот Рико", "c": "", "s": "classic", "lv": 1, "ready": true, "host": false, "bot": true}, FRIEND_COLOR, false))
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	controls.add_child(slots)
	_status = _wrap(_lobby_hint())
	controls.add_child(_status)
	if _count_end_ms >= 0:
		_count_label = UiStyle.label("", 32, UiStyle.GOLD, 6)
		controls.add_child(_count_label)
	controls.add_child(_main_button(me, other))
	if online and other.is_empty():
		var solo := UiStyle.button("ИГРАТЬ С БОТОМ", UiStyle.PANEL_LIGHT, 20, Vector2(0, 52))
		solo.name = "BotButton"
		solo.pressed.connect(func() -> void:
			_cleanup_net()
			_start_trainer())
		controls.add_child(solo)
	if not _failed_note.is_empty():
		var retry := UiStyle.button("ПОДКЛЮЧИТЬСЯ СНОВА", UiStyle.PANEL_LIGHT, 20, Vector2(0, 52))
		retry.name = "RetryButton"
		retry.pressed.connect(func() -> void: _connect_then("create"))
		controls.add_child(retry)
	_body.add_child(controls)
	_body.add_child(_friends_panel())
	if SaveService.get_insider() >= 0:
		_body.add_child(_host_field())   # только для тестеров, внизу
	_load_friends()
	_claim_pending()


## Показ лобби с выдуманной комнатой (для скриншотов и проверки вёрстки, адрес #coopdemo).
func show_demo() -> void:
	_my_id = 1
	_room = {"code": "DEMO", "min": 2, "max": 2, "running": false, "countdown": -1.0, "members": [
		{"id": 1, "name": SaveService.get_nickname(), "ready": true, "host": true, "c": SaveService.get_character_id(), "s": SaveService.get_selected_skin(), "lv": 7},
		{"id": 2, "name": "НочнойМститель59", "ready": false, "host": false, "c": "", "s": "classic", "lv": 12}]}
	var now := Time.get_datetime_string_from_system(true) + "+00:00"
	_friends = [
		{"nickname": "НочнойМститель59", "friend_code": "ABC123", "insider": 1, "last_seen": now, "stats": {"c": "", "s": "classic", "lv": 12}},
		{"nickname": "Кент", "friend_code": "KENT01", "insider": -1, "last_seen": "2026-10-01T10:00:00+00:00", "stats": {"c": "", "s": "classic", "lv": 4}},
		{"nickname": "Рико", "friend_code": "RICO02", "insider": -1, "last_seen": now, "stats": {"c": "", "s": "classic", "lv": 21}}]
	_requests = [{"nickname": "Новичок", "friend_code": "NEW001"}]
	_friends_loaded = true
	mode = Mode.ROOM
	_show_lobby()


func _lobby_hint() -> String:
	if not _failed_note.is_empty():
		return _failed_note
	if mode == Mode.CONNECTING:
		return "Подключаюсь к серверу..."
	var members: Array = _room.get("members", []) as Array
	if not members.is_empty():
		if members.size() < int(_room.get("min", 2)):
			return "Позови друга: нажми на пустой слот. Или сыграй с ботом."
		return "Оба в комнате. Жмите ГОТОВ: старт через 3 секунды."
	if host().is_empty():
		return "Тренировка с ботом. Игра с другом включится, когда подключим игровой сервер."
	if not Cloud.has_code() and not Net.insecure_test:
		return "Чтобы играть с другом, создай аккаунт в настройках. Пока можно потренироваться с ботом."
	return "Сервер считает бой сам, поэтому читерить и крутить награды нельзя."


func _slot_card(info: Dictionary, color: Color, is_me: bool) -> Control:
	var width := (minf(GlassPopup.panel_width(), 560.0) - 14.0) / 2.0
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ready := bool(info.get("ready", false))
	card.add_theme_stylebox_override("panel", UiStyle.box(Color("#3d3a37"), Color("#35c46a") if ready and not bool(info.get("bot", false)) else color, 5, 26))
	card.name = "SlotMe" if is_me else "SlotFriend"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var tag := "ТЫ" if is_me else ("БОТ" if bool(info.get("bot", false)) else "ДРУГ")
	if bool(info.get("host", false)) and not bool(info.get("bot", false)):
		tag += "  · хозяин"
	column.add_child(UiStyle.label(tag, 17, color, 4))
	var avatar := FriendsPopup.AvatarView.new()
	avatar.character_id = str(info.get("c", ""))
	avatar.skin_id = str(info.get("s", "classic"))
	avatar.custom_minimum_size = Vector2(width * 0.62, width * 0.62)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(avatar)
	var name_label := UiStyle.label(str(info.get("name", "Енот")), 24, UiStyle.TEXT, 5)
	name_label.clip_text = true
	column.add_child(name_label)
	column.add_child(UiStyle.label("УР. %d  ·  %s" % [int(info.get("lv", 1)), MenuPopups.Profile.rank_for(int(info.get("lv", 1)))] if not bool(info.get("bot", false)) else "учебный", 17, UiStyle.GOLD, 4))
	if not bool(info.get("bot", false)) and not str(info.get("tier", "")).is_empty():
		column.add_child(UiStyle.label("%s  ·  %d" % [str(info.get("tier", "")), int(info.get("rating", 0))], 16, Color("#ff9a3d"), 4))
	var state := "ГОТОВ" if ready else "ждёт"
	if bool(info.get("bot", false)):
		state = "всегда готов"
	column.add_child(UiStyle.label(state, 20, Color("#35c46a") if ready else UiStyle.TEXT_DIM, 4))
	return card


func _empty_slot() -> Control:
	var width := (minf(GlassPopup.panel_width(), 560.0) - 14.0) / 2.0
	var button := Button.new()
	button.name = "EmptySlot"
	button.custom_minimum_size = Vector2(width, 0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	var style := UiStyle.box(Color("#32302d"), Color(FRIEND_COLOR, 0.8), 4, 26)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.text = "+\nПОЗВАТЬ\nДРУГА"
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", FRIEND_COLOR)
	button.disabled = not _can_use_server()
	button.pressed.connect(func() -> void:
		_load_friends(true)
		_toast("Выбери друга в списке и жми ПОЗВАТЬ"))
	return button


func _main_button(me: Dictionary, other: Dictionary) -> Control:
	var members: Array = _room.get("members", []) as Array
	var button: Button
	if members.is_empty():
		button = UiStyle.button("ПОДКЛЮЧАЮСЬ..." if mode == Mode.CONNECTING else "НАЧАТЬ ТРЕНИРОВКУ", Color("#7ed321"), 30, Vector2(0, 80))
		button.disabled = mode == Mode.CONNECTING
		button.pressed.connect(_start_trainer)
	elif other.is_empty():
		button = UiStyle.button("ЖДЁМ ДРУГА...", UiStyle.PANEL_LIGHT, 26, Vector2(0, 80))
		button.disabled = true
	else:
		var me_ready := bool(me.get("ready", false))
		button = UiStyle.button("ОТМЕНА" if me_ready else "ГОТОВ", UiStyle.PANEL_LIGHT if me_ready else Color("#7ed321"), 32, Vector2(0, 80))
		button.pressed.connect(func() -> void:
			if _net != null:
				_net.set_ready(not me_ready))
	button.name = "StartButton"
	return button


func _host_field() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var toggle := UiStyle.button("СЕРВЕР (ТЕСТЕРАМ)", Color("#56534e"), 15, Vector2(0, 40))
	toggle.name = "ServerToggle"
	box.add_child(toggle)
	var host_edit := LineEdit.new()
	host_edit.visible = false
	host_edit.placeholder_text = "Адрес сервера (play.example.com)"
	host_edit.text = Platform.storage_get(HOST_KEY)
	host_edit.custom_minimum_size = Vector2(0, 48)
	SearchBar.style(host_edit, 17)
	SearchBar.attach_touch_input(host_edit, "Адрес сервера коопа")
	host_edit.text_submitted.connect(func(value: String) -> void:
		Platform.storage_set(HOST_KEY, value.strip_edges())
		_failed_note = ""
		_cleanup_net()
		_show_lobby()
		if _can_use_server():
			_connect_then("create"))
	box.add_child(host_edit)
	toggle.pressed.connect(func() -> void: host_edit.visible = not host_edit.visible)
	return box


# =========================== друзья справа (как в лобби мобильных игр) ===========================

func _friends_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "FriendsPanel"
	panel.custom_minimum_size = Vector2(0, 520)
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#32302d"), Color(UiStyle.NEON, 0.6), 4, 22))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	var tab_defs := [["friends", "ДРУЗЬЯ"], ["recent", "НЕДАВНИЕ"], ["requests", "ЗАЯВКИ" if _requests.is_empty() else "ЗАЯВКИ %d" % _requests.size()], ["top", "ТОП"]]
	for def: Array in tab_defs:
		var active := _tab == str(def[0])
		var tab := UiStyle.button(str(def[1]), UiStyle.HOT if active else UiStyle.PANEL_LIGHT, 16, Vector2(0, 46))
		tab.name = "Tab_" + str(def[0])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func() -> void:
			_tab = str(def[0])
			_show_lobby())
		tabs.add_child(tab)
	column.add_child(tabs)
	var head := UiStyle.label("", 17, UiStyle.TEXT_DIM, 4)
	head.name = "FriendsHead"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_friends_box = VBoxContainer.new()
	_friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_friends_box)
	_render_friends()
	return panel


## Список друзей подгружается один раз за вход и обновляется раз в полминуты. В начале те, кто сейчас в сети.
func _load_friends(force: bool = false) -> void:
	if (_friends_loaded and not force) or not Cloud.has_code():
		return
	_friends_loaded = true
	var result := await Cloud.inbox()
	if not bool(result["ok"]):
		_friends_loaded = false
		return
	_requests = await Cloud.list_requests()
	_friends = result["items"] as Array
	_friends.sort_custom(func(a: Variant, b: Variant) -> bool:
		var oa := _is_online(a as Dictionary)
		var ob := _is_online(b as Dictionary)
		if oa != ob:
			return oa
		return str((a as Dictionary).get("last_seen", "")) > str((b as Dictionary).get("last_seen", "")))
	_render_friends()


static func _is_online(friend: Dictionary) -> bool:
	return SocialProfilePopup.seen_text(str(friend.get("last_seen", ""))) == "Сейчас в сети"


func _render_friends() -> void:
	if _friends_box == null or not is_instance_valid(_friends_box):
		return
	for child in _friends_box.get_children():
		child.queue_free()
	var head := find_child("FriendsHead", true, false) as Label
	var online_count := 0
	for friend: Variant in _friends:
		if friend is Dictionary and _is_online(friend as Dictionary):
			online_count += 1
	if head != null:
		head.text = "В сети %d из %d" % [online_count, _friends.size()] if _tab == "friends" and not _friends.is_empty() else ""
	if not Cloud.has_code() and not Net.insecure_test and _friends.is_empty():
		_friends_box.add_child(_wrap("Создай аккаунт в настройках, и друзья появятся здесь."))
		return
	if _tab == "top":
		_render_top()
	elif _tab == "recent":
		_render_recent()
	elif _tab == "requests":
		_render_requests()
	elif _friends.is_empty():
		_friends_box.add_child(_wrap("Друзей пока нет. Добавь их в окне «Друзья»: кооп играется вдвоём."))
	else:
		for friend: Variant in _friends:
			if friend is Dictionary:
				_friends_box.add_child(_friend_row(friend as Dictionary))


## Топ сезона: среди друзей или общий. Очки считает сервер.
func _render_top() -> void:
	var switch := HBoxContainer.new()
	switch.add_theme_constant_override("separation", 8)
	for def: Array in [["friends", "СРЕДИ ДРУЗЕЙ"], ["global", "ВСЕ ИГРОКИ"]]:
		var b := UiStyle.button(str(def[1]), UiStyle.HOT if _top_scope == str(def[0]) else UiStyle.PANEL_LIGHT, 15, Vector2(0, 42))
		b.name = "TopScope_" + str(def[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_top_scope = str(def[0])
			_load_top())
		switch.add_child(b)
	_friends_box.add_child(switch)
	if _top.is_empty():
		_friends_box.add_child(_wrap("В этом сезоне пока никого. Сыграй забег вдвоём, и ты в таблице."))
		_load_top.call_deferred()
		return
	for row_data: Variant in _top:
		if not row_data is Dictionary:
			continue
		var d := row_data as Dictionary
		var mine := bool(d.get("mine", false))
		var panel := PanelContainer.new()
		panel.name = "Top_%d" % int(d.get("place", 0))
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#3a2f12") if mine else Color("#3a3834"), UiStyle.GOLD if mine else UiStyle.OUTLINE, 3, 14))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var place := UiStyle.label(str(int(d.get("place", 0))), 22, UiStyle.GOLD, 5)
		place.custom_minimum_size = Vector2(44, 0)
		row.add_child(place)
		var name_label := UiStyle.label(str(d.get("nickname", "Енот")), 20, UiStyle.TEXT, 5)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		row.add_child(UiStyle.label("%s  ·  %d" % [str(d.get("tier", "")), int(d.get("rating", 0))], 16, Color("#ff9a3d"), 4))
		_friends_box.add_child(panel)


func _load_top() -> void:
	_top = await Cloud.coop_top(_top_scope)
	if _tab == "top":
		_render_friends()


func _friend_codes() -> Array:
	var codes: Array = []
	for friend: Variant in _friends:
		if friend is Dictionary:
			codes.append(str((friend as Dictionary).get("friend_code", "")))
	return codes


## Те, с кем уже играл: хранится на устройстве (до 10 последних напарников).
func _render_recent() -> void:
	var recent: Variant = SaveService.data.get("coop_recent", [])
	var list: Array = recent as Array if recent is Array else []
	if list.is_empty():
		_friends_box.add_child(_wrap("Здесь появятся те, с кем ты сыграл в кооп. Можно сразу позвать в друзья."))
		return
	var friend_codes := _friend_codes()
	for entry: Variant in list:
		if not entry is Dictionary:
			continue
		var e := entry as Dictionary
		var code := str(e.get("code", ""))
		var panel := PanelContainer.new()
		panel.name = "Recent_" + code
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#3a3834"), UiStyle.OUTLINE, 3, 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var avatar := FriendsPopup.AvatarView.new()
		avatar.character_id = str(e.get("c", ""))
		avatar.skin_id = str(e.get("s", "classic"))
		avatar.custom_minimum_size = Vector2(64, 64)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(avatar)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := UiStyle.label(str(e.get("name", "Енот")), 20, UiStyle.TEXT, 5)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.clip_text = true
		text.add_child(name_label)
		var sub := UiStyle.label("УР. %d  ·  %s" % [int(e.get("lv", 1)), MenuPopups.Profile.rank_for(int(e.get("lv", 1)))], 15, UiStyle.TEXT_DIM, 4)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(sub)
		row.add_child(text)
		if friend_codes.has(code):
			row.add_child(UiStyle.label("ДРУГ", 16, Color("#35c46a"), 4))
		else:
			var add := UiStyle.button("В ДРУЗЬЯ", UiStyle.HOT, 16, Vector2(130, 48))
			add.name = "AddFriend_" + code
			add.pressed.connect(func() -> void:
				add.disabled = true
				var answer := await Cloud.request_friend(code)
				var texts := {"sent": "Заявка отправлена", "ok": "Вы теперь друзья", "friends": "Вы уже друзья", "blocked": "Нельзя отправить заявку", "limit": "Слишком много заявок", "self": "Это ты", "offline": "Нет связи"}
				_toast(str(texts.get(answer, answer)))
				if answer == "ok" or answer == "friends":
					_load_friends(true))
			row.add_child(add)
		_friends_box.add_child(panel)


func _render_requests() -> void:
	if _requests.is_empty():
		_friends_box.add_child(_wrap("Новых заявок нет."))
		return
	for request: Variant in _requests:
		if not request is Dictionary:
			continue
		var r := request as Dictionary
		var code := str(r.get("friend_code", ""))
		var panel := PanelContainer.new()
		panel.name = "Request_" + code
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#4a4742"), Color(UiStyle.HOT, 0.8), 3, 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := UiStyle.label(str(r.get("nickname", "Енот")), 20, UiStyle.TEXT, 5)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.clip_text = true
		text.add_child(name_label)
		var sub := UiStyle.label("хочет дружить", 15, UiStyle.TEXT_DIM, 4)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.add_child(sub)
		row.add_child(text)
		var accept := UiStyle.button("ПРИНЯТЬ", Color("#7ed321"), 16, Vector2(120, 48))
		accept.name = "Accept_" + code
		accept.pressed.connect(_answer_request.bind(code, true))
		row.add_child(accept)
		var decline := UiStyle.button("X", UiStyle.PANEL_LIGHT, 16, Vector2(52, 48))
		decline.pressed.connect(_answer_request.bind(code, false))
		row.add_child(decline)
		_friends_box.add_child(panel)


func _answer_request(code: String, accept: bool) -> void:
	await Cloud.answer_request(code, accept)
	_load_friends(true)


## Запоминаем напарника в «Недавних» (на этом устройстве).
func _remember_partner(info: Dictionary) -> void:
	var code := str(info.get("code", ""))
	if code.is_empty():
		return
	var raw: Variant = SaveService.data.get("coop_recent", [])
	var list: Array = (raw as Array).duplicate() if raw is Array else []
	for i in range(list.size() - 1, -1, -1):
		if list[i] is Dictionary and str((list[i] as Dictionary).get("code", "")) == code:
			list.remove_at(i)
	list.push_front({"code": code, "name": str(info.get("name", "Енот")).left(24), "c": str(info.get("c", "")), "s": str(info.get("s", "classic")), "lv": int(info.get("lv", 1))})
	while list.size() > 10:
		list.pop_back()
	SaveService.data["coop_recent"] = list
	SaveService.save_data()


func _friend_row(f: Dictionary) -> Control:
	var code := str(f.get("friend_code", ""))
	var nick := str(f.get("nickname", "Енот"))
	var online := _is_online(f)
	var stats: Dictionary = f.get("stats") if f.get("stats") is Dictionary else {}
	var panel := PanelContainer.new()
	panel.name = "Friend_" + code
	var tag := int(f.get("insider", -1))
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#3a3834"), Color("#35c46a") if online else Color(UiStyle.OUTLINE, 1.0), 3, 16))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_profile(code))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var avatar := FriendsPopup.AvatarView.new()
	avatar.character_id = str(stats.get("c", ""))
	avatar.skin_id = str(stats.get("s", "classic"))
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var badge := Insider.badge_of(tag)
	var name_label := UiStyle.label(nick if badge.is_empty() else "%s %s" % [badge, nick], 20, Insider.color_of(tag, UiStyle.TEXT), 5)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	var status := "В сети" if online else SocialProfilePopup.seen_text(str(f.get("last_seen", "")))
	var level := int(stats.get("lv", 1))
	var rank_label := UiStyle.label("УР. %d  ·  %s" % [level, MenuPopups.Profile.rank_for(level)], 15, UiStyle.GOLD, 4)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rank_label.clip_text = true
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(rank_label)
	var sub := UiStyle.label(status, 15, Color("#35c46a") if online else UiStyle.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(sub)
	row.add_child(text)
	var room_code := str(_room.get("code", ""))
	var members_n := (_room.get("members", []) as Array).size()
	var can_invite := not room_code.is_empty() and members_n < int(_room.get("max", 2))
	var invited := bool(_invited.get(code, false))
	var invite := UiStyle.button("ПОЗВАН" if invited else "ПОЗВАТЬ", UiStyle.HOT if online else UiStyle.PANEL_LIGHT, 16, Vector2(104, 48))
	invite.name = "Invite_" + code
	invite.disabled = invited or not can_invite
	invite.pressed.connect(_invite.bind(code, room_code, invite))
	row.add_child(invite)
	var chat := UiStyle.button("ЧАТ", UiStyle.PANEL_LIGHT, 16, Vector2(72, 48))
	chat.name = "Chat_" + code
	chat.pressed.connect(func() -> void: _open_chat(code, nick, str(stats.get("c", "raccoon"))))
	row.add_child(chat)
	return panel


func _open_profile(code: String) -> void:
	var popup := SocialProfilePopup.new(code)
	popup.z_index = 40
	add_child(popup)
	popup.closed.connect(func() -> void:
		popup.queue_free()
		_load_friends(true))
	popup.open()


func _open_chat(code: String, nick: String, character: String) -> void:
	var popup := ChatPopup.new(code, nick, character)
	popup.z_index = 40
	add_child(popup)
	popup.closed.connect(popup.queue_free)
	popup.open()


func _close() -> void:
	_cleanup_net()
	closed.emit()
	queue_free()


# =========================== тренировка (локально) ===========================

func _start_trainer() -> void:
	_local = true
	_arena = CoopArena.new()
	if not _arena.setup(0):
		_say("Не удалось загрузить данные арены")
		return
	_my_id = 1
	_arena.add_player(1)
	_arena.add_player(2)
	_arena.set_bot(2)
	_arena.finished.connect(func(_won: bool) -> void: _finish_local())
	_begin_run({1: "Ты", 2: "Бот Рико"}, _arena.type_names())


func _finish_local() -> void:
	var results := _arena.results()
	results["names"] = {1: "Ты", 2: "Бот Рико"}
	results["practice"] = true
	_show_results(results)


# =========================== сервер ===========================

func _connect_then(action: String, code: String = "") -> void:
	if not _can_use_server():
		_say("Для игры с другом нужен аккаунт и подключённый сервер.")
		return
	if mode == Mode.CONNECTING:
		return
	mode = Mode.CONNECTING
	_failed_note = ""
	_friends_loaded = false
	_invite_sent_for = ""
	_cleanup_net()
	_show_lobby()
	var address := host()
	_net = CoopNet.new()
	_net.name = "CoopNet"
	get_tree().root.add_child.call_deferred(_net)   # из _ready корень ещё занят, поэтому отложенно
	_net.room_state.connect(_on_room_state)
	_net.room_error.connect(_on_room_error)
	_net.snapshot_received.connect(_on_snapshot)
	_net.run_finished.connect(func(results: Dictionary) -> void: _show_results(results))
	_net.notice.connect(_on_notice)
	var api := multiplayer as SceneMultiplayer
	var done := [false]
	var on_connected := func() -> void:
		if done[0]:
			return
		done[0] = true
		_my_id = multiplayer.get_unique_id()
		if action == "create":
			_net.create_room()
		else:
			_net.join_room(code)
	api.connected_to_server.connect(on_connected, CONNECT_ONE_SHOT)
	Net.failed.connect(func(reason: String) -> void:
		if mode == Mode.CONNECTING or mode == Mode.ROOM or mode == Mode.RUN:
			_fail_connection(reason), CONNECT_ONE_SHOT)
	if not Net.connect_to(address):
		_fail_connection("start")
		return
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func() -> void:
		if not done[0] and mode == Mode.CONNECTING:
			_fail_connection("timeout"))


func _fail_connection(reason: String) -> void:
	var was_running := mode == Mode.RUN or mode == Mode.ROOM
	_cleanup_net()
	mode = Mode.MENU
	_failed_note = ("Связь с сервером пропала (%s). Забег прерван, награды за него нет." if was_running else "Не удалось подключиться к серверу коопа (%s). Проверь связь.") % reason
	_show_lobby()


func _on_room_state(state: Dictionary) -> void:
	_room = state
	for member: Variant in state.get("members", []):
		if int((member as Dictionary).get("id", 0)) != _my_id:
			_remember_partner(member as Dictionary)
	var left := float(state.get("countdown", -1.0))
	_count_end_ms = int(Time.get_ticks_msec() + left * 1000.0) if left >= 0.0 else -1
	if bool(state.get("running", false)):
		if mode != Mode.RUN:
			var names: Dictionary = {}
			for member: Variant in state["members"]:
				names[int((member as Dictionary)["id"])] = str((member as Dictionary)["name"])
			_begin_run(names, [])
		return
	if mode == Mode.RESULTS:
		return
	if mode != Mode.RUN:
		mode = Mode.ROOM
		_show_lobby()
	_send_pending_invite()


## Создали комнату ради приглашения друга: зовём, как только комната готова.
func _send_pending_invite() -> void:
	var code := str(_room.get("code", ""))
	if invite_code.is_empty() or code.is_empty() or _invite_sent_for == code:
		return
	_invite_sent_for = code
	var target := invite_code
	invite_code = ""
	_invite(target, code, null)


func _invite(friend_code: String, room_code: String, button: Button) -> void:
	if button != null:
		button.disabled = true
		button.text = "..."
	var answer := await Cloud.send_coop_invite(friend_code, room_code)
	_invited[friend_code] = answer == "ok"
	var texts := {"ok": "Приглашение отправлено", "not_friends": "Вы не друзья", "blocked": "Нельзя пригласить этого игрока", "banned": "Чат-бан: приглашения недоступны",
		"rate": "Слишком часто, подожди немного", "bad": "Не вышло: комната закрыта", "auth": "Нужен аккаунт", "offline": "Нет связи с базой", "no_server": "Сервер друзей не обновлён"}
	_toast(str(texts.get(answer, answer)))
	if button != null and is_instance_valid(button):
		button.text = "ПОЗВАН" if answer == "ok" else "ПОЗВАТЬ"
		button.disabled = answer == "ok"


func _on_notice(kind: String, who: String) -> void:
	_toast("%s зашёл в комнату" % who if kind == "joined" else "%s вышел" % who)


## Короткое всплывающее сообщение сверху (комната и бой).
func _toast(text: String) -> void:
	if _toast_label == null or not is_instance_valid(_toast_label):
		_toast_label = UiStyle.label("", 22, UiStyle.TEXT, 5)
		_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast_label.offset_top = 36
		_toast_label.offset_left = -300
		_toast_label.offset_right = 300
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_label.z_index = 50
		add_child(_toast_label)
	_toast_label.text = text
	_toast_label.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_interval(2.4)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.6)


func _on_room_error(code: String) -> void:
	var texts := {"no_room": "Такой комнаты нет. Проверь код.", "room_full": "В комнате уже двое.", "run_in_progress": "Бой уже идёт.",
		"already_in_room": "Ты уже в комнате.", "room_exists": "Твоя комната уже открыта.", "arena_failed": "Сервер не смог запустить арену.",
		"not_friends": "В комнату можно только к другу. Сначала добавьтесь в друзья.", "old_version": "Версия игры устарела. Обнови страницу (Ctrl+F5) и зайди снова.",
		"slow_down": "Слишком часто. Подожди пару секунд.", "bad_code": "Код комнаты неверный (3-12 латинских букв и цифр).", "check_failed": "Сервер не смог проверить дружбу. Попробуй ещё раз."}
	_cleanup_net()
	mode = Mode.MENU
	_failed_note = str(texts.get(code, "Ошибка: %s" % code))
	_show_lobby()


func _on_snapshot(data: Dictionary) -> void:
	if _view != null:
		_view.apply_snapshot(data)


# =========================== бой ===========================

func _begin_run(names: Dictionary, types: Array[String]) -> void:
	mode = Mode.RUN
	_reset_body()
	_body.get_parent().visible = false
	_view = CoopView.new()
	_view.my_id = _my_id
	_view.names = names
	_view.set_types(types)
	add_child(_view)
	var quit := UiStyle.button("ВЫЙТИ", Color("#a3283e"), 20, Vector2(120, 48))
	quit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quit.offset_left = -144
	quit.offset_right = -24
	quit.offset_top = 20
	quit.offset_bottom = 68
	quit.name = "QuitButton"
	quit.pressed.connect(func() -> void:
		_cleanup_net()
		_show_menu())
	add_child(quit)
	_acc = 0.0
	_ticks = 0
	if _local and _arena != null:
		_view.apply_snapshot(_arena.snapshot())
	var net_timer := Timer.new()
	net_timer.name = "MoveTimer"
	net_timer.wait_time = 0.05
	net_timer.timeout.connect(func() -> void:
		if not _local and _net != null and _view != null:
			_net.send_move(_view.move))
	add_child(net_timer)
	net_timer.start()


func _physics_process(delta: float) -> void:
	if mode != Mode.RUN or not _local or _arena == null or _view == null:
		return
	_acc += delta
	while _acc >= CoopArena.TICK:
		_acc -= CoopArena.TICK
		_arena.set_input(1, _view.move)
		_arena.tick(CoopArena.TICK)
		_ticks += 1
		if _ticks % CoopNet.SNAPSHOT_EVERY == 0 and _view != null:
			_view.apply_snapshot(_arena.snapshot())


func _clear_run() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	for node_name in ["QuitButton", "MoveTimer"]:
		var node := get_node_or_null(node_name)
		if node != null:
			node.queue_free()
	if _body != null and _body.get_parent() != null:
		(_body.get_parent() as Control).visible = true
	_arena = null
	_local = false


# =========================== итоги ===========================

func _show_results(results: Dictionary) -> void:
	_results = results
	_clear_run()
	mode = Mode.RESULTS
	_reset_body()
	var won := bool(results.get("won", false))
	_body.add_child(UiStyle.label("ПОБЕДА!" if won else "ЗАБЕГ ОКОНЧЕН", 38, UiStyle.GOLD if won else Color("#ff4d6d"), 8))
	_body.add_child(_wrap("Волн пройдено: %d. Время: %d с." % [int(results.get("waves_cleared", 0)), int(results.get("seconds", 0))]))
	var names: Dictionary = results.get("names", {})
	var players: Dictionary = results.get("players", {})
	for id: Variant in players:
		var p := players[id] as Dictionary
		var who := str(names.get(id, names.get(int(id), "Енот")))
		_body.add_child(UiStyle.label("%s: убито %d, урон %d" % [who, int(p["kills"]), int(p["damage"])], 22, UiStyle.TEXT, 5))
		if not bool(results.get("practice", false)):
			var extra := "  ·  подняла напарника: %d" % int(p.get("revives", 0)) if int(p.get("revives", 0)) > 0 else ""
			_body.add_child(UiStyle.label("награда по расчёту: %d монет, %d опыта%s" % [int(p["coins"]), int(p["xp"]), extra], 17, UiStyle.TEXT_DIM, 4))
	if bool(results.get("practice", false)):
		_body.add_child(_wrap("Тренировка: награды и очки не выдаются."))
	else:
		var reward_box := VBoxContainer.new()
		reward_box.name = "RewardBox"
		reward_box.add_theme_constant_override("separation", 6)
		_body.add_child(reward_box)
		_claim_reward(reward_box)
	var again := UiStyle.button("В МЕНЮ КООПА", UiStyle.HOT, 24, Vector2(0, 66))
	again.pressed.connect(func() -> void:
		if _net != null and mode == Mode.RESULTS and not _room.is_empty():
			mode = Mode.ROOM
			_show_lobby()
		else:
			_show_menu())
	_body.add_child(again)


## Награды и очки считает и записывает сервер; клиент только забирает своё (один раз). Сервер пишет в базу через секунду-две, поэтому спрашиваем несколько раз.
func _claim_reward(box: VBoxContainer) -> void:
	var status := UiStyle.label("Сервер считает награду...", 20, UiStyle.TEXT_DIM, 4)
	status.name = "RewardStatus"
	box.add_child(status)
	if not Cloud.has_code():
		status.text = "Награды выдаются игрокам с аккаунтом."
		return
	for attempt in 7:
		await get_tree().create_timer(1.5 if attempt == 0 else 2.0).timeout
		if not is_instance_valid(status):
			return
		var got := await Cloud.coop_claim_rewards()
		if not bool(got.get("ok", false)):
			continue
		var fresh := int(got.get("last_run_age", -1))
		if int(got.get("runs", 0)) > 0 or (fresh >= 0 and fresh < 90 and attempt >= 1):
			_apply_claim(got)
			if is_instance_valid(status):
				_show_claim(box, status, got)
			return
	if is_instance_valid(status):
		status.text = "Не дождались сервера. Награда не пропадёт: заберёшь её при следующем входе в кооп."


func _apply_claim(got: Dictionary) -> void:
	var coins := int(got.get("coins", 0))
	var xp := int(got.get("xp", 0))
	if coins > 0:
		SaveService.add_coins(coins)
	if xp > 0:
		SaveService.add_account_xp(xp)
	SaveService.data["coop_rating"] = int(got.get("rating", 0))
	SaveService.data["coop_tier"] = str(got.get("tier", "Ржавый"))
	SaveService.save_data()


func _show_claim(box: VBoxContainer, status: Label, got: Dictionary) -> void:
	var delta := int(got.get("last_delta", 0))
	status.text = "Получено: %d монет, %d опыта" % [int(got.get("coins", 0)), int(got.get("xp", 0))]
	status.add_theme_color_override("font_color", UiStyle.GOLD)
	var rating := UiStyle.label("Рейтинг коопа: %d (%s%d)  ·  %s" % [int(got.get("rating", 0)), "+" if delta >= 0 else "", delta, str(got.get("tier", ""))], 22, Color("#35c46a") if delta >= 0 else Color("#ff4d6d"), 5)
	rating.name = "RatingLine"
	box.add_child(rating)


## При входе в лобби: забираем награды, которые не успели получить после прошлых забегов, и обновляем свой рейтинг.
func _claim_pending() -> void:
	if _pending_checked or not Cloud.has_code():
		return
	_pending_checked = true
	var got := await Cloud.coop_claim_rewards()
	if not bool(got.get("ok", false)) or not is_inside_tree():
		return
	if int(got.get("coins", 0)) > 0 or int(got.get("xp", 0)) > 0:
		_apply_claim(got)
		_toast("Получено за кооп: %d монет, %d опыта" % [int(got.get("coins", 0)), int(got.get("xp", 0))])
	else:
		SaveService.data["coop_rating"] = int(got.get("rating", 0))
		SaveService.data["coop_tier"] = str(got.get("tier", "Ржавый"))
		SaveService.save_data()
	if mode == Mode.MENU or mode == Mode.ROOM:
		_show_lobby()


# =========================== вспомогательное ===========================

func _reset_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _wrap(text: String) -> Label:
	var label := UiStyle.label(text, 19, UiStyle.TEXT_DIM, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(minf(GlassPopup.panel_width(), 620.0) - 20.0, 0)
	return label


func _say(text: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text


func _cleanup_net() -> void:
	if _net != null and is_instance_valid(_net):
		_net.queue_free()
	_net = null
	_room = {}
	if Net.is_active():
		Net.disconnect_all()
