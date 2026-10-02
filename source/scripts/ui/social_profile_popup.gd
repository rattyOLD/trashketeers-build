class_name SocialProfilePopup
extends GlassPopup
## Профиль друга с его статистикой: переписка, удаление из друзей, блокировка, жалоба; для входящей заявки — принять или отклонить.

signal changed

var friend_code := ""

var _status: Label
var _body: VBoxContainer


func _init(code: String) -> void:
	super("ПРОФИЛЬ")
	friend_code = code


func _refresh() -> void:
	var keep := content.get_child(0)
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	_status = UiStyle.label("Загружаю профиль...", 20, UiStyle.NEON, 5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	content.add_child(_status)
	var list := MenuPopups.scroll_list(content)
	_body = list
	_load()


func _load() -> void:
	var profile := await Cloud.friend_profile(friend_code)
	if not is_instance_valid(self) or not is_instance_valid(_body):
		return
	if profile.is_empty():
		_status.text = "Профиль недоступен: нет связи или игрок вас заблокировал."
		return
	_status.text = seen_text(str(profile.get("last_seen", "")))
	var raw_stats: Variant = profile.get("stats", {})
	var info: Dictionary = (raw_stats as Dictionary).duplicate() if raw_stats is Dictionary else {}
	info["n"] = str(profile.get("nickname", "Енот"))
	info["fc"] = friend_code
	info["ins"] = int(profile.get("insider", -1))
	info["w"] = int(profile.get("best_wave", 0))
	var card := FriendsPopup.CardView.new()
	card.info = info
	card.custom_minimum_size = Vector2(panel_width() - 110.0, (panel_width() - 110.0) * FriendsPopup.CARD_SIZE.y / FriendsPopup.CARD_SIZE.x)
	_body.add_child(card)
	var is_friend := bool(profile.get("is_friend", false))
	var is_self := friend_code == Cloud.friend_code
	if is_self:
		return
	_body.add_child(_compare_block(info))
	if not is_friend:
		var accept := UiStyle.button("ПРИНЯТЬ ЗАЯВКУ", Color("#2fae5f"), 24, Vector2(0, 62))
		accept.pressed.connect(func() -> void:
			var result := await Cloud.answer_request(friend_code, true)
			if is_instance_valid(self):
				_status.text = "Теперь вы друзья" if result == "ok" else "Не вышло, попробуй ещё раз"
				changed.emit()
				_load_again())
		_body.add_child(accept)
		var decline := UiStyle.button("ОТКЛОНИТЬ", UiStyle.PANEL_LIGHT, 22, Vector2(0, 56))
		decline.pressed.connect(func() -> void:
			await Cloud.answer_request(friend_code, false)
			changed.emit()
			close())
		_body.add_child(decline)
	else:
		var write := UiStyle.button("НАПИСАТЬ", UiStyle.HOT, 26, Vector2(0, 66))
		write.pressed.connect(func() -> void:
			var stats: Dictionary = profile.get("stats") if profile.get("stats") is Dictionary else {}
			var chat := ChatPopup.new(friend_code, str(profile.get("nickname", "Енот")), str(stats.get("c", "raccoon")))
			add_child(chat)
			chat.closed.connect(func() -> void:
				chat.queue_free()
				changed.emit())
			chat.open())
		_body.add_child(write)
		_body.add_child(_two_tap("Удалить из друзей", UiStyle.PANEL_LIGHT, func() -> void:
			await Cloud.remove_friend(friend_code)
			changed.emit()
			close()))
	_body.add_child(_two_tap("Пожаловаться", UiStyle.PANEL_LIGHT, func() -> void:
		var result := await Cloud.report_user(friend_code, "профиль")
		if is_instance_valid(self):
			_status.text = "Жалоба отправлена, спасибо" if result == "ok" else "Не удалось отправить жалобу"))
	if SaveService.is_dev():
		_body.add_child(_two_tap("DeV: бан чата по ID", UiStyle.HOT, func() -> void:
			var r := await Cloud.dev_call("dev_set_chat_ban", {"p_code": friend_code, "p_banned": true})
			if is_instance_valid(self):
				_status.text = "Чат для этого игрока отключён" if bool(r["ok"]) and str(r["data"]) == "ok" else "Не вышло (нужен DeV и SQL v7)"))
	if SaveService.is_dev():
		_body.add_child(_two_tap("DeV: выдать Insider", UiStyle.PANEL_LIGHT, func() -> void:
			var r := await Cloud.dev_call("dev_set_badge", {"p_code": friend_code, "p_level": 1})
			if is_instance_valid(self):
				_status.text = "Insider выдан" if bool(r["ok"]) and str(r["data"]) == "ok" else "Не вышло (игрок уже DeV или нет SQL v7)"))
	_body.add_child(_two_tap("Заблокировать", Color("#a3283e"), func() -> void:
		var done := await Cloud.block_user(friend_code)
		if is_instance_valid(self) and done:
			changed.emit()
			close()))


const COMPARE_ROWS := [["УРОВЕНЬ", "lv"], ["ЛУЧШАЯ ВОЛНА", "w"], ["БОССОВ УБИТО", "bk"], ["ОСКОЛКИ СЮЖЕТА", "sh"], ["КРЫС УБИТО", "k"], ["ЗАБЕГОВ", "r"]]
const VERDICT_WIN := ["Ты его размазал. Скромно промолчи.", "Счёт в твою пользу. Можно написать «изи» и убежать.", "Енот-чемпион на связи. Он пусть тренируется."]
const VERDICT_LOSE := ["Он впереди. Но свалка большая, догонишь.", "Тебя обошли. Пора кого-нибудь пострелять.", "Проигрываешь. Зато красиво выглядишь."]
const VERDICT_DRAW := ["Ничья. Два енота, один мусорный бак.", "Идёте ноздря в ноздрю. Кто-то должен моргнуть."]


## Сравнение «ты против него»: по каждой строке подсвечивается победитель, внизу шуточный вердикт.
func _compare_block(theirs: Dictionary) -> Control:
	var mine := SaveService.public_stats()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiStyle.label("ТЫ ПРОТИВ НЕГО", 24, UiStyle.GOLD, 7))
	var my_wins := 0
	var his_wins := 0
	for entry in COMPARE_ROWS:
		var key := str((entry as Array)[1])
		var a := int(mine.get(key, 0))
		var b := int(theirs.get(key, 0))
		if a > b:
			my_wins += 1
		elif b > a:
			his_wins += 1
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color("#1f3d4a"), Color(UiStyle.NEON, 0.35), 2, 12))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var left := UiStyle.label(str(a), 26, Color("#5fe08a") if a > b else (UiStyle.TEXT_DIM if a < b else UiStyle.TEXT), 6)
		left.custom_minimum_size = Vector2(110, 0)
		row.add_child(left)
		var title := UiStyle.label(str((entry as Array)[0]), 18, UiStyle.TEXT_DIM, 4)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		row.add_child(title)
		var right := UiStyle.label(str(b), 26, Color("#5fe08a") if b > a else (UiStyle.TEXT_DIM if b < a else UiStyle.TEXT), 6)
		right.custom_minimum_size = Vector2(110, 0)
		row.add_child(right)
		box.add_child(panel)
	var verdict_list: Array = VERDICT_WIN if my_wins > his_wins else (VERDICT_LOSE if his_wins > my_wins else VERDICT_DRAW)
	var verdict := UiStyle.label("%d:%d. %s" % [my_wins, his_wins, str(verdict_list.pick_random())], 20, UiStyle.NEON, 5)
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	box.add_child(verdict)
	return box


func _load_again() -> void:
	MenuPopups.clear(_body)
	_load()


func _two_tap(text: String, color: Color, action: Callable) -> Button:
	var button := UiStyle.button(text, color, 21, Vector2(0, 56))
	var armed := [false]
	button.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			button.text = "Точно? Нажми ещё раз"
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if is_instance_valid(button):
					armed[0] = false
					button.text = text)
			return
		armed[0] = false
		button.text = text
		action.call())
	return button


@warning_ignore("integer_division")
static func seen_text(stamp: String) -> String:
	if stamp.length() < 19:
		return ""
	var seen := Time.get_unix_time_from_datetime_string(stamp.substr(0, 19))
	var ago := int(Time.get_unix_time_from_system()) - int(seen)
	if ago < 180:
		return "Сейчас в сети"
	if ago < 3600:
		return "Был(а) в сети %d мин назад" % (ago / 60)
	if ago < 86400:
		return "Был(а) в сети %d ч назад" % (ago / 3600)
	return "Был(а) в сети %d дн назад" % (ago / 86400)
