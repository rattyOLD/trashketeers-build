class_name DevPopup
extends GlassPopup
## Панель DeV: серверная статистика, жалобы, стоп-слова, выдача Insider и проверка сервера.
## Все действия проверяются на сервере (is_dev по аккаунту), здесь только интерфейс.

const HEALTH_RPCS := {
	"my_badge": {}, "my_save": {}, "claim_badge": {"p_secret": "x"}, "inbox": {}, "list_requests": {}, "list_blocks": {}, "unread_total": {},
	"request_friend": {"p_code": "ZZZZZZ"}, "friend_profile": {"p_code": "ZZZZZZ"}, "send_message": {"p_code": "ZZZZZZ", "p_body": ""},
	"get_messages": {"p_code": "ZZZZZZ", "p_after": 0}, "dev_stats": {}, "dev_reports": {}, "dev_words": {}, "dev_badge_log": {},
	"dev_password_log": {}, "dev_accounts": {"p_query": ""}, "dev_errors": {"p_limit": 1}, "dev_error_summary": {}, "my_devices": {},
}

var _status: Label
var _list: VBoxContainer
var _stats_label: Label
var _reports_box: VBoxContainer
var _words_label: Label
var _log_label: Label
var _find: LineEdit
var _found: VBoxContainer
var _reset_login: LineEdit
var _reset_pass: LineEdit
var _reset_log: Label
var _health_label: Label
var _errors_label: Label
var _edit: LineEdit
var _word_edit: LineEdit


func _init() -> void:
	super("ПАНЕЛЬ DeV")


func _refresh() -> void:
	var keep := content.get_child(0)
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	_status = UiStyle.label("", 20, UiStyle.NEON, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	content.add_child(_status)
	_list = MenuPopups.scroll_list(content)
	_list.add_theme_constant_override("separation", 10)

	_list.add_child(UiStyle.label("СЕРВЕР", 22, UiStyle.TEXT_DIM, 5))
	_stats_label = _wrap("Загружаю...")
	_list.add_child(_stats_label)
	var health := UiStyle.button("Проверить функции сервера", UiStyle.PANEL_LIGHT, 21, Vector2(0, 56))
	health.pressed.connect(_check_health)
	_list.add_child(health)
	_health_label = _wrap("")
	_list.add_child(_health_label)

	_list.add_child(UiStyle.label("ОШИБКИ ИГРОКОВ", 22, UiStyle.TEXT_DIM, 5))
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 8)
	var summary := UiStyle.button("Сводка за сутки", UiStyle.PANEL_LIGHT, 20, Vector2(0, 54))
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.pressed.connect(_load_error_summary)
	erow.add_child(summary)
	var recent := UiStyle.button("Последние 25", UiStyle.PANEL_LIGHT, 20, Vector2(0, 54))
	recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent.pressed.connect(_load_errors)
	erow.add_child(recent)
	_list.add_child(erow)
	_errors_label = _wrap("Игра сама присылает сюда ошибки, без Excel. Нужен SQL v15.")
	_list.add_child(_errors_label)

	_list.add_child(UiStyle.label("ССЫЛКИ ДЛЯ ТЕГОВ", 22, UiStyle.TEXT_DIM, 5))
	_list.add_child(_link_button("Новая ссылка DeV (старая умрёт)", 0, "dev"))
	_list.add_child(_link_button("Новая ссылка Insider (старая умрёт)", 1, "insider"))
	_list.add_child(_wrap("Ссылка показывается один раз и копируется в буфер. DeV-ссылка работает на 3 входа, Insider на 50 (нужен SQL v9)."))

	_list.add_child(UiStyle.label("СБРОС ПАРОЛЯ ИГРОКА", 22, UiStyle.TEXT_DIM, 5))
	_find = _field("Поиск: логин, ник или ID")
	_list.add_child(_find)
	var find_button := UiStyle.button("Найти аккаунты", UiStyle.PANEL_LIGHT, 21, Vector2(0, 52))
	find_button.pressed.connect(_search_accounts)
	_list.add_child(find_button)
	_found = VBoxContainer.new()
	_found.add_theme_constant_override("separation", 6)
	_list.add_child(_found)
	_reset_login = _field("Логин игрока")
	_list.add_child(_reset_login)
	_reset_pass = _field("Новый временный пароль (от 6 знаков)")
	_list.add_child(_reset_pass)
	var reset := UiStyle.button("Сбросить пароль", UiStyle.HOT, 22, Vector2(0, 56))
	reset.pressed.connect(_reset_password)
	_list.add_child(reset)
	_list.add_child(_wrap("Не больше 2 сбросов в сутки на логин. Прежде чем сбрасывать, проверь, что пишет хозяин: ник, ID с визитки, лучшая волна."))
	_reset_log = _wrap("...")
	_list.add_child(_reset_log)

	_list.add_child(UiStyle.label("ЖУРНАЛ ТЕГОВ", 22, UiStyle.TEXT_DIM, 5))
	_log_label = _wrap("...")
	_list.add_child(_log_label)

	_list.add_child(UiStyle.label("ЖАЛОБЫ", 22, UiStyle.TEXT_DIM, 5))
	_reports_box = VBoxContainer.new()
	_reports_box.add_theme_constant_override("separation", 8)
	_list.add_child(_reports_box)

	_list.add_child(UiStyle.label("ВЫДАТЬ / СНЯТЬ INSIDER ПО ID", 22, UiStyle.TEXT_DIM, 5))
	_edit = _field("ID игрока (6 знаков)")
	_list.add_child(_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_badge_button("Выдать Insider", 1))
	row.add_child(_badge_button("Снять тег", -1))
	_list.add_child(row)

	_list.add_child(UiStyle.label("СТОП-СЛОВА ЧАТА", 22, UiStyle.TEXT_DIM, 5))
	_words_label = _wrap("...")
	_list.add_child(_words_label)
	_word_edit = _field("Корень слова")
	_list.add_child(_word_edit)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	wrow.add_child(_word_button("Добавить", "dev_add_word"))
	wrow.add_child(_word_button("Убрать", "dev_remove_word"))
	_list.add_child(wrow)
	_load_all()


func _link_button(text: String, level: int, param: String) -> Button:
	var b := UiStyle.button(text, UiStyle.PANEL_LIGHT, 20, Vector2(0, 56))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(func() -> void:
		var r := await Cloud.dev_call("dev_rotate_link", {"p_level": level})
		var secret := str(r["data"]) if bool(r["ok"]) and r["data"] is String else ""
		if secret.is_empty():
			_status.text = "Не вышло: нет доступа DeV или сервер без v7"
			return
		var link := "%s?%s=%s" % [Platform.page_url(), param, secret]
		DisplayServer.clipboard_set(link)
		_status.text = "Новая ссылка скопирована в буфер:\n" + link)
	return b


func _wrap(text: String) -> Label:
	var label := UiStyle.label(text, 19, UiStyle.TEXT, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	return label


func _field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 56)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SearchBar.style(edit, 22)
	SearchBar.attach_touch_input(edit, placeholder)
	return edit


func _badge_button(text: String, level: int) -> Button:
	var b := UiStyle.button(text, UiStyle.PANEL_LIGHT, 21, Vector2(0, 56))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		var r := await Cloud.dev_call("dev_set_badge", {"p_code": _edit.text, "p_level": level})
		_status.text = "Готово" if _ok(r) else "Не вышло (проверь ID)")
	return b


func _word_button(text: String, rpc: String) -> Button:
	var b := UiStyle.button(text, UiStyle.PANEL_LIGHT, 21, Vector2(0, 56))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		var r := await Cloud.dev_call(rpc, {"p_word": _word_edit.text})
		_status.text = "Готово" if _ok(r) else "Не вышло (3–30 знаков)"
		_word_edit.text = ""
		_load_words())
	return b


func _ok(r: Dictionary) -> bool:
	return bool(r["ok"]) and str(r["data"]) == "ok"


func _load_all() -> void:
	var r := await Cloud.dev_call("dev_stats")
	if not is_instance_valid(_stats_label):
		return
	var d: Variant = r["data"]
	if d is Dictionary:
		var s: Dictionary = d
		_stats_label.text = "Игроков: %s · онлайн за час: %s · за сутки: %s\nДружб: %s · сообщений за сутки: %s (всего %s)\nОткрытых жалоб: %s · в бане чата: %s\nDeV-аккаунтов: %s · Insider: %s" % [
			s.get("players"), s.get("active_1h"), s.get("active_24h"), s.get("friendships"),
			s.get("messages_24h"), s.get("messages_all"), s.get("reports_open"), s.get("banned"), s.get("devs"), s.get("insiders")]
		if s.has("guests"):
			var last := "ещё не было" if s.get("cleanup_at") == null else "%s, удалено %s" % [str(s.get("cleanup_at")).substr(5, 11).replace("T", " "), s.get("cleanup_removed")]
			_stats_label.text += "\nГостей: %s · со скрытым входом: %s · с логином: %s\nЧистка пустых гостей: %s" % [s.get("guests"), s.get("guest_logins"), s.get("accounts"), last]
		else:
			_stats_label.text += "\nСчётчики гостей появятся после SQL v18."
		if int(s.get("devs", 1)) > 1:
			_stats_label.text += "\nDeV-аккаунтов несколько (твои телефон и мини-апка считаются). Если их больше, чем твоих устройств, перевыпусти ссылку и проверь журнал тегов."
	else:
		_stats_label.text = "Нет доступа: тег DeV не подтверждён сервером. Открой секретную ссылку ?dev=… заново."
		return
	_load_reports()
	_load_words()
	_load_log()
	_load_reset_log()


func _search_accounts() -> void:
	var r := await Cloud.dev_call("dev_accounts", {"p_query": _find.text})
	if not is_instance_valid(_found):
		return
	for child in _found.get_children():
		child.queue_free()
	if int(r["code"]) == 404:
		_found.add_child(_wrap("Нужен SQL v13 (schema_v13_dev_accounts.sql)"))
		return
	var rows := Cloud._rows(r)
	if rows.is_empty():
		_found.add_child(_wrap("Ничего не найдено"))
		return
	for row: Variant in rows:
		var d := row as Dictionary
		var login := str(d.get("login", ""))
		var b := UiStyle.button("%s · %s · %s" % [login, d.get("nickname"), d.get("friend_code")], UiStyle.PANEL_LIGHT, 19, Vector2(0, 50))
		b.clip_text = true
		b.pressed.connect(func() -> void:
			_reset_login.text = login
			_status.text = "Логин «%s» подставлен в сброс пароля" % login)
		_found.add_child(b)


func _reset_password() -> void:
	var r := await Cloud.dev_call("dev_reset_password", {"p_login": _reset_login.text, "p_password": _reset_pass.text})
	if not is_instance_valid(_status):
		return
	var code := str(r["data"]) if bool(r["ok"]) else "offline"
	var texts := {"ok": "Пароль сброшен. Передай его игроку, пусть сменит в профиле.", "limit": "Лимит: 2 сброса в сутки на этот логин.",
		"not_found": "Такого логина нет.", "bad": "Логин: 3–20 знаков, пароль от 6.", "denied": "Нужен DeV.", "offline": "Нет связи или нет SQL v11."}
	_status.text = str(texts.get(code, code))
	if code == "ok":
		_reset_pass.text = ""
	_load_reset_log()


func _load_reset_log() -> void:
	var r := await Cloud.dev_call("dev_password_log")
	if not is_instance_valid(_reset_log):
		return
	if int(r["code"]) == 404:
		_reset_log.text = "Нужен SQL v11 (schema_v11_password_reset.sql)"
		return
	var lines: Array[String] = []
	for row: Variant in Cloud._rows(r):
		var d := row as Dictionary
		lines.append("%s · %s · %s" % [str(d.get("at", "")).substr(5, 11).replace("T", " "), d.get("login"), d.get("result")])
	_reset_log.text = "\n".join(lines) if not lines.is_empty() else "Сбросов не было"


func _load_error_summary() -> void:
	_errors_label.text = "Загружаю..."
	var r := await Cloud.dev_call("dev_error_summary")
	if not is_instance_valid(_errors_label):
		return
	if int(r["code"]) == 404:
		_errors_label.text = "Нужен SQL v15 (schema_v15_client_errors.sql)"
		return
	var lines: Array[String] = []
	for row: Variant in Cloud._rows(r):
		var d := row as Dictionary
		lines.append("×%d (игроков %d) · %s\n   %s" % [int(d.get("hits", 0)), int(d.get("players", 0)), d.get("builds"), d.get("head")])
	_errors_label.text = "\n".join(lines) if not lines.is_empty() else ("За сутки ошибок нет. Енот доволен." if bool(r["ok"]) else "Не загрузилось: " + Cloud.last_error)


func _load_errors() -> void:
	_errors_label.text = "Загружаю..."
	var r := await Cloud.dev_call("dev_errors", {"p_limit": 25, "p_build": ""})
	if not is_instance_valid(_errors_label):
		return
	if int(r["code"]) == 404:
		_errors_label.text = "Нужен SQL v15 (schema_v15_client_errors.sql)"
		return
	var lines: Array[String] = []
	for row: Variant in Cloud._rows(r):
		var d := row as Dictionary
		var body := str(d.get("body", ""))
		var trail := body.get_slice("TRAIL ", 1).left(220) if body.contains("TRAIL ") else ""
		lines.append("%s · %s · %s [%s]\n   %s%s" % [str(d.get("created_at", "")).substr(5, 11).replace("T", " "), d.get("build"),
			d.get("nickname"), d.get("friend_code"), body.get_slice("\n", 0).left(160), ("\n   путь: " + trail) if not trail.is_empty() else ""])
	_errors_label.text = "\n".join(lines) if not lines.is_empty() else ("Ошибок нет." if bool(r["ok"]) else "Не загрузилось: " + Cloud.last_error)


func _load_log() -> void:
	var r := await Cloud.dev_call("dev_badge_log")
	if not is_instance_valid(_log_label):
		return
	if int(r["code"]) == 404:
		_log_label.text = "Нужен SQL v8 (schema_v8_badge_log.sql)"
		return
	var lines: Array[String] = []
	for row: Variant in Cloud._rows(r):
		var d := row as Dictionary
		var who := "—" if d.get("friend_code") == null else "%s [%s]" % [d.get("nickname"), d.get("friend_code")]
		var tag := "DeV" if int(d.get("level", -1)) == 0 else ("Insider" if int(d.get("level", -1)) == 1 else "снят")
		lines.append("%s · %s · %s · %s" % [str(d.get("at", "")).substr(5, 11).replace("T", " "), tag, who, d.get("how")])
	_log_label.text = "\n".join(lines) if not lines.is_empty() else "Пока никому не выдавали"


func _load_words() -> void:
	var r := await Cloud.dev_call("dev_words")
	if not is_instance_valid(_words_label):
		return
	var words: Array[String] = []
	for row: Variant in Cloud._rows(r):
		words.append(str((row as Dictionary).get("stem", "")))
	_words_label.text = ", ".join(words) if not words.is_empty() else "Список пуст"


func _load_reports() -> void:
	var r := await Cloud.dev_call("dev_reports")
	if not is_instance_valid(_reports_box):
		return
	for child in _reports_box.get_children():
		child.queue_free()
	var rows := Cloud._rows(r)
	if rows.is_empty():
		_reports_box.add_child(_wrap("Жалоб нет. Тишина, как на кладбище мусорных баков."))
		return
	for row: Variant in rows:
		_reports_box.add_child(_report_row(row as Dictionary))


func _report_row(item: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var text := "#%s · %s → %s [%s]\n«%s»\n%s" % [item.get("id"), item.get("reporter"), item.get("target"), item.get("target_code"),
		str(item.get("reason", "")), str(item.get("body", "") if item.get("body") != null else "")]
	box.add_child(_wrap(text))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var code := str(item.get("target_code", ""))
	var banned := bool(item.get("banned", false))
	var ban := UiStyle.button("Снять бан" if banned else "Бан чата", UiStyle.HOT if not banned else UiStyle.PANEL_LIGHT, 20, Vector2(0, 52))
	ban.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ban.pressed.connect(func() -> void:
		await Cloud.dev_call("dev_set_chat_ban", {"p_code": code, "p_banned": not banned})
		_load_reports())
	row.add_child(ban)
	var close := UiStyle.button("Закрыть", UiStyle.PANEL_LIGHT, 20, Vector2(0, 52))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void:
		await Cloud.dev_call("dev_resolve_report", {"p_id": int(item.get("id", 0))})
		_load_reports())
	row.add_child(close)
	box.add_child(row)
	return box


func _check_health() -> void:
	_health_label.text = "Проверяю..."
	var lines: Array[String] = []
	for name: String in HEALTH_RPCS:
		var r := await Cloud._call(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + name, HEALTH_RPCS[name])
		var code := int(r["code"])
		var mark := "НЕТ на сервере (нужен SQL)" if code == 404 else ("ок" if code < 400 else "ответ %d" % code)
		lines.append("%s: %s" % [name, mark])
		if not is_instance_valid(_health_label):
			return
	_health_label.text = "\n".join(lines)
