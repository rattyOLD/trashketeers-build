class_name DevPopup
extends GlassPopup
## Панель DeV: серверная статистика, жалобы, стоп-слова, выдача Insider и проверка сервера.
## Все действия проверяются на сервере (is_dev по аккаунту), здесь только интерфейс.

const HEALTH_RPCS: Array[String] = ["sync_profile_v2", "my_badge", "claim_badge", "inbox", "dev_stats", "dev_reports", "dev_words"]

var _status: Label
var _list: VBoxContainer
var _stats_label: Label
var _reports_box: VBoxContainer
var _words_label: Label
var _log_label: Label
var _health_label: Label
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

	_list.add_child(UiStyle.label("ССЫЛКИ ДЛЯ ТЕГОВ", 22, UiStyle.TEXT_DIM, 5))
	_list.add_child(_link_button("Новая ссылка DeV (старая умрёт)", 0, "dev"))
	_list.add_child(_link_button("Новая ссылка Insider (старая умрёт)", 1, "insider"))
	_list.add_child(_wrap("Ссылка показывается один раз и копируется в буфер. DeV-ссылка работает на 3 входа, Insider — без лимита до замены."))

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
	else:
		_stats_label.text = "Нет доступа: тег DeV не подтверждён сервером. Открой секретную ссылку ?dev=… заново."
		return
	_load_reports()
	_load_words()
	_load_log()


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
	for name in HEALTH_RPCS:
		var r := await Cloud._call(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + name, {})
		var code := int(r["code"])
		var mark := "нет на сервере" if code == 404 else ("ок" if code < 500 else "ошибка %d" % code)
		lines.append("%s: %s" % [name, mark])
		if not is_instance_valid(_health_label):
			return
	_health_label.text = "\n".join(lines)
