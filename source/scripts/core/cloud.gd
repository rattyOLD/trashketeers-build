extends Node
## Связь с сервером Supabase: анонимный вход без регистрации, профиль, друзья по коду, оценки реплик.
## Всё необязательно: без связи игра работает как раньше, методы возвращают пустой результат.

signal profile_synced
signal unread_changed
## Сессия аккаунта с логином слетела: игра просит войти заново (новый гость не создаётся).
signal session_lost_changed
signal coop_invite_received(invite: Dictionary)

## Вход по почте скрыт, пока в Supabase не настроены SMTP и шаблоны писем.
const EMAIL_LOGIN := true
const ACCOUNT_DOMAIN := "@trashsquad.game"
const URL := "https://ylclwkprhhlzavhahrko.supabase.co"
const KEY := "sb_publishable_7xeZ6_3lc4Bi44z35wf4BQ__P6Maunz"
const SESSION_KEY := "trk_cloud_session"
const LOST_KEY := "trk_cloud_lost"
const BADGE_SECRET_KEY := "trk_badge_secret"
const BADGE_UID_KEY := "trk_badge_uid"
const RECOVERY_KEY := "trk_recovery_code"
const EMAIL_KEY := "trk_cloud_email"
## Скрытый вход гостя «guest_xxxxxxxxxxxx.пароль»: ссылка-вход по нему — это ВХОД в тот же аккаунт, а не перенос.
const GUEST_KEY := "trk_guest_key"
const GUEST_PREFIX := "guest_"
const UPLOAD_DELAY := 8.0
## Автосохранение в облако: раз в минуту, если что-то поменялось; через 5 с после роста прогресса (конец забега,
## уровень, награды); сразу, когда игру сворачивают. Пустые повторы не отправляются (сверка по хешу сохранения).
const BACKUP_EVERY := 60.0
const BACKUP_AFTER_PROGRESS := 5.0
const TIMEOUT := 10.0
const NET_ERRORS := {8: "двойная распаковка ответа", 2: "не подключиться", 3: "адрес не найден", 4: "обрыв связи", 5: "ошибка TLS", 6: "сервер промолчал", 9: "запрос сорвался (CORS или блокировка)", 13: "таймаут 10 с"}
const EXPIRY_MARGIN := 60

var friend_code := ""
var recovery_code := ""
var email := ""
var online := false
var last_error := ""
var _raw_note := ""
## Чистое устройство: гостевой аккаунт не создаём, пока игрок не ответит «Уже играл? Войди» (или не закроет окно).
var waiting_choice := false
var session_lost := false
## Аккаунт этого устройства перенесли на другое (мини-апка, новый телефон): здесь он больше не активен.
var moved_away := false
var guest_key := ""
var _guest_busy := false
var _hidden_mail := false
var _restore_after_signup := ""
var _last_sync := 0
var unread := 0

var _uid := ""
var _access := ""
var _refresh := ""
var _expires := 0
var _session_busy := false
var _profile_busy := false
var _upload_pending := false
var _last_backup := ""
var _backup_busy := false
var _errors_busy := false
var _backup_soon := false
var _last_score := -1
var _invites_seen: Dictionary = {}
var _hidden_callback: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()
	recovery_code = Platform.storage_get(RECOVERY_KEY)
	guest_key = Platform.storage_get(GUEST_KEY)
	email = Platform.storage_get(EMAIL_KEY)
	if Platform.is_web:
		waiting_choice = _refresh.is_empty() and SaveService.progress_score() == 0
		if not waiting_choice:
			get_tree().create_timer(4.0).timeout.connect(sync_profile)
		var poll := Timer.new()
		poll.wait_time = 45.0
		poll.timeout.connect(refresh_unread)
		add_child(poll)
		poll.start()
		get_tree().create_timer(9.0).timeout.connect(refresh_unread)
		var invites := Timer.new()
		invites.wait_time = 20.0
		invites.timeout.connect(poll_coop_invites)
		add_child(invites)
		invites.start()
		get_tree().create_timer(11.0).timeout.connect(poll_coop_invites)
		var backup := Timer.new()
		backup.wait_time = BACKUP_EVERY
		backup.timeout.connect(_auto_backup)
		add_child(backup)
		backup.start()
		SaveService.changed.connect(_on_save_changed)
		var errors := Timer.new()
		errors.wait_time = 30.0
		errors.timeout.connect(_flush_errors)
		add_child(errors)
		errors.start()
		_hidden_callback = JavaScriptBridge.create_callback(func(_args: Array) -> void:
			if bool(JavaScriptBridge.get_interface("document").hidden):
				_auto_backup())
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _hidden_callback)


func start_guest() -> void:
	if waiting_choice:
		waiting_choice = false
		sync_profile()


## Гостю тихо заводим скрытый логин и пароль (тот же uid, Supabase делает анонима постоянным).
## Тогда ссылка-вход открывает этот же аккаунт на втором устройстве, и оба остаются активными.
func _ensure_guest_key() -> void:
	if _guest_busy or not email.is_empty() or not guest_key.is_empty() or _uid.is_empty():
		return
	_guest_busy = true
	var name := GUEST_PREFIX + _random_text(12, "abcdefghijklmnopqrstuvwxyz0123456789")
	var password := _random_text(24, "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
	var result := await _call(HTTPClient.METHOD_PUT, "/auth/v1/user", {"email": name + ACCOUNT_DOMAIN, "password": password})
	var user: Variant = result["data"]
	var pending := user is Dictionary and not str((user as Dictionary).get("new_email", "")).is_empty()
	if bool(result["ok"]) and not pending:
		guest_key = "%s.%s" % [name, password]
		Platform.storage_set(GUEST_KEY, guest_key)
	_guest_busy = false


static func _random_text(length: int, alphabet: String) -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(length)
	var out := ""
	for i in length:
		out += alphabet[bytes[i] % alphabet.length()]
	return out


## У аккаунта уже есть скрытый логин guest_… (ключ мог потеряться, но почта на сервере осталась).
func email_is_hidden() -> bool:
	return _hidden_mail


## Параметр ссылки-входа: скрытый вход гостя (вход, без переноса) или старый код восстановления.
func entry_link_param() -> String:
	if not guest_key.is_empty():
		return "g=" + guest_key.uri_encode()
	if not recovery_code.is_empty():
		return "restore=" + recovery_code.uri_encode()
	return ""


## Вход по скрытому ключу гостя из ссылки: "ok", "wrong", "offline", "invalid".
func login_guest(key: String) -> String:
	var parts := key.strip_edges().split(".")
	if parts.size() != 2 or not parts[0].begins_with(GUEST_PREFIX) or parts[1].length() < 12:
		return "invalid"
	var headers := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	var reply := await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/token?grant_type=password", headers, JSON.stringify({"email": parts[0] + ACCOUNT_DOMAIN, "password": parts[1]}))
	if int(reply["code"]) == 0:
		return "offline"
	if not _store_session(reply):
		return "wrong"
	guest_key = key.strip_edges()
	Platform.storage_set(GUEST_KEY, guest_key)
	friend_code = ""
	moved_away = false
	return "ok"


func has_code() -> bool:
	return not friend_code.is_empty()


## Профиль и код друга: создаётся при первом вызове, дальше обновляет ник и рекорд волны.
func sync_profile() -> bool:
	if _profile_busy:
		while _profile_busy:
			await get_tree().process_frame
		return has_code()
	_profile_busy = true
	var body := {"p_nickname": SaveService.get_nickname(), "p_best_wave": SaveService.get_stat("best_wave"), "p_insider": SaveService.get_insider()}
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/sync_profile_v2", body.merged({"p_stats": SaveService.public_stats()}))
	if not bool(result["ok"]) and int(result["code"]) == 404:
		result = await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/sync_profile", body)
	_profile_busy = false
	if bool(result["ok"]):
		var rows: Variant = result["data"]
		if rows is Array and (rows as Array).size() > 0 and (rows as Array)[0] is Dictionary:
			friend_code = str(((rows as Array)[0] as Dictionary).get("friend_code", ""))
			if friend_code == "MOVED":
				# Этот гость переехал на другое устройство (по коду восстановления). Нового енота здесь не заводим.
				friend_code = ""
				if not moved_away:
					moved_away = true
					session_lost_changed.emit()
			_last_sync = Time.get_ticks_msec() / 1000
			profile_synced.emit()
	if has_code():
		await _sync_badge()
		if recovery_code.is_empty():
			queue_upload()
		if email.is_empty() and guest_key.is_empty():
			_ensure_guest_key()
	return has_code()


## Тег живёт на сервере. Если он не совпал с запомненным секретом (новая сессия) — выдаём заново.
func _sync_badge() -> void:
	var reply := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_badge", {})
	if not bool(reply["ok"]) or not (reply["data"] is int or reply["data"] is float):
		return
	var level := int(reply["data"])
	var secret := Platform.storage_get(BADGE_SECRET_KEY)
	if not secret.is_empty() and Platform.storage_get(BADGE_UID_KEY) != _uid:
		var again := await _claim(secret, false)
		if again >= 0:
			level = again
		else:
			Platform.storage_set(BADGE_UID_KEY, _uid)
	SaveService.set_badge_level(level)


## Секрет из ссылки -> тег. Возвращает уровень (0 DeV, 1 Insider) или -1.
func claim_badge(secret: String, remember: bool = true) -> int:
	if not await sync_profile():
		return -1
	return await _claim(secret, remember)


## Сам запрос тега без синхронизации профиля (её вызывает sync_profile, иначе вышла бы бесконечная петля).
func _claim(secret: String, remember: bool) -> int:
	var reply := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/claim_badge", {"p_secret": secret})
	var level := int(reply["data"]) if bool(reply["ok"]) and (reply["data"] is int or reply["data"] is float) else -1
	if level >= 0:
		Platform.storage_set(BADGE_UID_KEY, _uid)
	if level >= 0 and remember:
		Platform.storage_set(BADGE_SECRET_KEY, secret)
	if level >= 0:
		SaveService.set_badge_level(level)
	return level


func dev_call(name: String, body: Dictionary = {}) -> Dictionary:
	return await _rpc(name, body)


## "ok", "not_found", "self", "limit" или "offline".
func add_friend(code: String) -> String:
	if not await sync_profile():
		return "offline"
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/add_friend", {"p_code": code})
	if not bool(result["ok"]):
		return "offline"
	return str(result["data"])


func remove_friend(code: String) -> bool:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/remove_friend", {"p_code": code})
	return bool(result["ok"])


## {"ok": bool, "items": Array[Dictionary{nickname, friend_code, best_wave, insider}]}.
func list_friends() -> Dictionary:
	if not await sync_profile():
		return {"ok": false, "items": []}
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/list_friends", {})
	var items: Array = []
	if bool(result["ok"]) and result["data"] is Array:
		items = result["data"] as Array
	return {"ok": bool(result["ok"]), "items": items}


## Откладывает выгрузку сохранения, чтобы серия вызовов превратилась в один запрос.
## Раз в пару минут выгружает сохранение, если оно изменилось: код восстановления всегда актуален.
func _auto_backup() -> void:
	if not has_code() or _backup_busy:
		return
	var snapshot := _content_hash()
	if snapshot == _last_backup:
		return
	_backup_busy = true
	if not (await upload_save()).is_empty():
		_last_backup = snapshot
	_backup_busy = false


## Ошибки игры из очереди браузера -> журнал в базе (вкладка «Ошибки» у DeV). Не отправилось — попробуем позже.
func _flush_errors() -> void:
	if not has_code() or _errors_busy:
		return
	var raw: Variant = Platform._js("var q = window.localStorage.getItem('__trash_errq') || ''; window.localStorage.removeItem('__trash_errq'); return q;")
	var queue: Variant = _parse_or_null(str(raw)) if raw is String else null
	if not queue is Array or (queue as Array).is_empty():
		return
	_errors_busy = true
	var left: Array = (queue as Array).duplicate()
	while not left.is_empty():
		var reply := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/log_error", {"p_build": Platform.build_label(), "p_device": Platform.device_info().left(120), "p_body": str(left[0])})
		if not bool(reply["ok"]):
			if int(reply["code"]) != 404:
				Platform._js("var q = JSON.parse(window.localStorage.getItem('__trash_errq') || '[]'); window.localStorage.setItem('__trash_errq', JSON.stringify(%s.concat(q).slice(-20)));" % JSON.stringify(left))
			break
		left.pop_front()
	_errors_busy = false


## Отпечаток сохранения без отметки времени: иначе каждая минута выглядела бы как «изменения».
func _content_hash() -> String:
	var copy: Dictionary = SaveService.data.duplicate()
	copy.erase("saved_at")
	return JSON.stringify(copy).sha256_text()


## Прогресс вырос (забег, уровень, награда) — сохраняем в облако через пару секунд, не дожидаясь минутного таймера.
func _on_save_changed() -> void:
	var score := SaveService.progress_score()
	if score == _last_score:
		return
	var first := _last_score < 0
	_last_score = score
	if first or _backup_soon or not has_code():
		return
	_backup_soon = true
	get_tree().create_timer(BACKUP_AFTER_PROGRESS).timeout.connect(func() -> void:
		_backup_soon = false
		_auto_backup())


func queue_upload() -> void:
	if _upload_pending or not Platform.is_web:
		return
	_upload_pending = true
	get_tree().create_timer(UPLOAD_DELAY).timeout.connect(func() -> void:
		_upload_pending = false
		upload_save())


## Кладёт сохранение в облако и возвращает код восстановления (пусто, если связи нет).
## Защита от потери прогресса: перед записью смотрим, что лежит в облаке. Если облако богаче (на новом устройстве
## пустая игра), забираем его вместо перезаписи. Если проверить не удалось (нет функции my_save), не пишем ничего.
func upload_save() -> String:
	if not has_code() and not await sync_profile():
		return ""
	var cloud := await fetch_cloud_save()
	if not bool(cloud["ok"]):
		return recovery_code
	var cloud_text := str(cloud["text"])
	if not cloud_text.is_empty():
		var theirs := SaveService.parse_backup(cloud_text)
		if not theirs.is_empty() and SaveService.should_restore_cloud(theirs):
			SaveService.import_code(cloud_text)
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/upload_save", {"p_data": SaveService.export_code()})
	if bool(result["ok"]) and result["data"] is String and not str(result["data"]).is_empty():
		recovery_code = str(result["data"])
		Platform.storage_set(RECOVERY_KEY, recovery_code)
	return recovery_code


## {"ok": bool, "text": String}: ok=false, если функции my_save нет на сервере или нет связи; пустой text — в облаке пусто.
func fetch_cloud_save() -> Dictionary:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_save", {})
	if not bool(result["ok"]):
		return {"ok": false, "text": ""}
	return {"ok": true, "text": str(result["data"]) if result["data"] is String else ""}


## Возвращает код сохранения из облака по коду восстановления или пустую строку.
func restore_save(code: String) -> String:
	if not await sync_profile():
		return ""
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/restore_save", {"p_code": code})
	if bool(result["ok"]) and result["data"] is String and not str(result["data"]).is_empty():
		# «ACCOUNT:логин» — код от аккаунта с логином: его не переносят, на этом устройстве в него входят.
		if str(result["data"]).begins_with("ACCOUNT:"):
			return str(result["data"])
		friend_code = ""
		moved_away = false
		await sync_profile()
		return str(result["data"])
	return ""


## ---- Чат v2 (SQL v19): стикеры, картинки, файлы, «печатает», прочитано. ----

## "ok", "not_friends", "blocked", "rate", "empty", "banned", "bad", "offline", "no_server".
func send_chat(code: String, kind: String, body: String, attachment: Dictionary = {}) -> String:
	var result := await _rpc("send_message_v2", {"p_code": code, "p_kind": kind, "p_body": body, "p_attachment": attachment if not attachment.is_empty() else null})
	if int(result["code"]) == 404:
		if kind == "text":
			return await send_message(code, body)
		return "no_server"
	return str(result["data"]) if bool(result["ok"]) else "offline"


## {"ok": bool, "items": [{id, mine, body, created_at, kind, attachment, seen}]}; без SQL v19 — старый формат.
func get_chat(code: String, after_id: int) -> Dictionary:
	var result := await _rpc("get_messages_v2", {"p_code": code, "p_after": after_id})
	if int(result["code"]) == 404:
		return await get_messages(code, after_id)
	return {"ok": bool(result["ok"]), "items": _rows(result)}


## {"typing": bool, "last_seen": String, "read_upto": int} или пустой словарь.
func chat_peer(code: String) -> Dictionary:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/chat_peer", {"p_code": code})
	return result["data"] as Dictionary if bool(result["ok"]) and result["data"] is Dictionary else {}


func set_typing(code: String) -> void:
	await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/set_typing", {"p_code": code})


## Загрузка вложения другу: путь от сервера (только друзьям), затем файл в приватную корзину chat. Пусто — не вышло.
func upload_chat_file(code: String, ext: String, bytes: PackedByteArray, mime: String) -> String:
	var path_reply := await _rpc("chat_upload_path", {"p_code": code, "p_ext": ext})
	if not bool(path_reply["ok"]) or not path_reply["data"] is String or str(path_reply["data"]).is_empty():
		if not bool(path_reply["ok"]):
			last_error = "chat_upload_path -> HTTP %d" % int(path_reply["code"])
		return ""
	var path := str(path_reply["data"])
	var headers := PackedStringArray(["apikey: " + KEY, "Authorization: Bearer " + _access, "Content-Type: " + (mime if not mime.is_empty() else "application/octet-stream"), "x-upsert: false"])
	var reply := await _bytes_request(HTTPClient.METHOD_POST, URL + "/storage/v1/object/chat/" + path, headers, bytes)
	if int(reply["code"]) < 200 or int(reply["code"]) >= 300:
		last_error = "storage upload -> HTTP %d %s" % [int(reply["code"]), (reply["body"] as PackedByteArray).get_string_from_utf8().left(120)]
		return ""
	return path


## Скачивание вложения (для картинок в чате). Пустой массив — не вышло.
func download_chat_file(path: String) -> PackedByteArray:
	if not await _ensure_session():
		return PackedByteArray()
	var headers := PackedStringArray(["apikey: " + KEY, "Authorization: Bearer " + _access])
	var reply := await _bytes_request(HTTPClient.METHOD_GET, URL + "/storage/v1/object/authenticated/chat/" + path, headers, PackedByteArray())
	return reply["body"] if int(reply["code"]) == 200 else PackedByteArray()


## Временная ссылка на файл (1 час), чтобы открыть его в браузере. Пусто — не вышло.
func sign_chat_file(path: String) -> String:
	var result := await _call(HTTPClient.METHOD_POST, "/storage/v1/object/sign/chat/" + path, {"expiresIn": 3600})
	if bool(result["ok"]) and result["data"] is Dictionary:
		var signed := str((result["data"] as Dictionary).get("signedURL", ""))
		if not signed.is_empty():
			return URL + "/storage/v1" + signed if signed.begins_with("/") else signed
	return ""


func _bytes_request(method: int, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	if not await _ensure_session():
		return {"code": 0, "body": PackedByteArray()}
	headers[1] = "Authorization: Bearer " + _access
	var request := HTTPRequest.new()
	request.timeout = 60.0
	request.accept_gzip = not Platform.is_web
	add_child(request)
	var err := request.request_raw(url, headers, method, body) if not body.is_empty() else request.request(url, headers, method)
	if err != OK:
		request.queue_free()
		return {"code": 0, "body": PackedByteArray()}
	var reply: Array = await request.request_completed
	request.queue_free()
	Platform.trail("файл %s -> %d" % [url.get_slice("/", 6), int(reply[1])])
	return {"code": int(reply[1]) if int(reply[0]) == HTTPRequest.RESULT_SUCCESS else 0, "body": reply[3]}


## Выйти на всех остальных устройствах (Supabase logout scope=others). Это устройство остаётся в аккаунте.
func logout_others() -> bool:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/logout_others", {})
	if bool(result["ok"]) and (result["data"] is int or result["data"] is float) and int(result["data"]) >= 0:
		return true
	if int(result["code"]) == 404:
		var fallback := await _call(HTTPClient.METHOD_POST, "/auth/v1/logout?scope=others", {})
		return int(fallback["code"]) == 204 or bool(fallback["ok"])
	return false


## Реакция на сообщение: "like", "lol", "fire" или "" (убрать). true — сервер принял.
func react_message(id: int, emoji: String) -> bool:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/react_message", {"p_id": id, "p_emoji": emoji})
	return bool(result["ok"]) and str(result["data"]) == "ok"


## Удалить своё сообщение (у обоих). true — сервер принял.
func delete_message(id: int) -> bool:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/delete_message", {"p_id": id})
	return bool(result["ok"]) and str(result["data"]) == "ok"


## Реакции в переписке: [{id, mine, theirs}] (только сообщения, где они есть).
func chat_reactions(code: String) -> Array:
	return _rows(await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/chat_reactions", {"p_code": code}))


## Живые входы в этот аккаунт (устройства) за 30 дней; 0, если неизвестно (нет SQL v18 или связи).
func my_devices() -> int:
	if not has_code():
		return 0
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_devices", {})
	return int(result["data"]) if bool(result["ok"]) and (result["data"] is int or result["data"] is float) else 0


## {"ok": bool, "items": [{nickname, best_wave, insider}]} — лучшие игроки по волне.
func top_waves(limit: int = 20) -> Dictionary:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/top_waves", {"p_limit": limit})
	var items: Array = []
	if bool(result["ok"]) and result["data"] is Array:
		items = result["data"] as Array
	return {"ok": bool(result["ok"]), "items": items}


func has_email() -> bool:
	return not email.is_empty()


## Логин: латиница, цифры и «_», 3–20 знаков. Иначе пустая строка.
static func clean_login(text: String) -> String:
	var value := text.strip_edges().to_lower()
	if value.length() < 3 or value.length() > 20:
		return ""
	for i in value.length():
		var c := value.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return ""
	return value


## Аккаунт без почты: логин и пароль превращают анонимный профиль в постоянный.
## "ok", "taken", "weak", "invalid", "confirm" (в Supabase включено подтверждение почты) или "offline".
func register_account(login: String, password: String) -> String:
	var name := clean_login(login)
	if name.is_empty() or name.begins_with(GUEST_PREFIX):
		return "invalid"
	if not await _ensure_session():
		return "offline"
	# Гость со скрытым входом: почта у него уже есть, и её смена в Supabase требует письма. Логин меняет сервер (SQL v20),
	# а пароль ставим отдельно.
	if not guest_key.is_empty() or email_is_hidden():
		var claim := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/claim_login", {"p_login": name})
		if not bool(claim["ok"]):
			return "offline" if int(claim["code"]) == 0 else "invalid"
		var answer := str(claim["data"])
		if answer == "taken":
			return "taken"
		if answer != "ok":
			return "invalid"
		var pass_result := await _call(HTTPClient.METHOD_PUT, "/auth/v1/user", {"password": password})
		if not bool(pass_result["ok"]):
			_remember_email(name)
			guest_key = ""
			Platform.storage_set(GUEST_KEY, "")
			return "offline" if int(pass_result["code"]) == 0 else "weak"
		_remember_email(name)
		guest_key = ""
		Platform.storage_set(GUEST_KEY, "")
		return "ok"
	var result := await _call(HTTPClient.METHOD_PUT, "/auth/v1/user", {"email": name + ACCOUNT_DOMAIN, "password": password})
	if not bool(result["ok"]):
		var code := int(result["code"])
		var info := str(result["data"]).to_lower()
		if code == 0:
			return "offline"
		if info.contains("password"):
			return "weak"
		if info.contains("registered") or info.contains("exists") or code == 422 or code == 409:
			return "taken"
		return "invalid"
	var user: Variant = result["data"]
	if user is Dictionary and not str((user as Dictionary).get("new_email", "")).is_empty():
		return "confirm"
	_remember_email(name)
	guest_key = ""
	Platform.storage_set(GUEST_KEY, "")
	return "ok"


## Вход на новом устройстве: "ok", "wrong", "invalid" или "offline". Профиль подменяется на аккаунтный.
func login_account(login: String, password: String) -> String:
	var name := clean_login(login)
	if name.is_empty() or password.is_empty():
		return "invalid"
	var headers := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	var reply := await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/token?grant_type=password", headers, JSON.stringify({"email": name + ACCOUNT_DOMAIN, "password": password}))
	if int(reply["code"]) == 0:
		return "offline"
	if not _store_session(reply):
		return "wrong"
	_remember_email(name)
	friend_code = ""
	moved_away = false
	guest_key = ""
	Platform.storage_set(GUEST_KEY, "")
	recovery_code = ""
	Platform.storage_set(RECOVERY_KEY, "")
	return "ok"


## Выход: прогресс сперва уходит в облако, затем на устройстве остаётся чистая игра. Вернуться можно логином и паролем.
func logout() -> void:
	await upload_save()
	for key in [SESSION_KEY, LOST_KEY, RECOVERY_KEY, EMAIL_KEY, GUEST_KEY, BADGE_SECRET_KEY, BADGE_UID_KEY, SaveService.BADGE_KEY, "trk_badge_seen", "trk_acct_nag", SaveService.STORAGE_KEY]:
		Platform.storage_set(key, "")
	Platform.reload_clean()


## Смена пароля у вошедшего аккаунта: "ok", "weak" или "offline".
func change_password(password: String) -> String:
	if not await _ensure_session():
		return "offline"
	var result := await _call(HTTPClient.METHOD_PUT, "/auth/v1/user", {"password": password})
	if bool(result["ok"]):
		return "ok"
	return "offline" if int(result["code"]) == 0 else "weak"


## Сохранение, привязанное к текущему профилю (после входа по почте), либо пустая строка.
func my_save() -> String:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_save", {})
	if bool(result["ok"]) and result["data"] is String:
		return str(result["data"])
	return ""


func _verify(kind: String, address: String, token: String) -> Dictionary:
	var headers := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	var body := {"type": kind, "email": address.strip_edges().to_lower(), "token": token.strip_edges()}
	return await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/verify", headers, JSON.stringify(body))


func _remember_email(address: String) -> void:
	email = address.strip_edges().to_lower()
	Platform.storage_set(EMAIL_KEY, email)


func _email_status(reply: Dictionary, linking: bool) -> String:
	if bool(reply["ok"]):
		return "sent"
	var code := int(reply["code"])
	if code == 0:
		return "offline"
	if code == 429:
		return "limit"
	var info := str(reply["data"]).to_lower()
	if linking and (info.contains("exists") or info.contains("registered")):
		return "exists"
	if not linking and (code == 422 or code == 400):
		return "not_found"
	return "invalid"


# --- Социальная часть: заявки, профили, личные сообщения ------------------------------------

func _rpc(name: String, body: Dictionary) -> Dictionary:
	var fresh := has_code() and Time.get_ticks_msec() / 1000 - _last_sync < 90
	if not fresh and not await sync_profile():
		if last_error.is_empty():
			last_error = "профиль не синхронизировался (%s)" % _raw_note
		return {"ok": false, "code": 0, "data": null}
	return await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + name, body)


func _rows(result: Dictionary) -> Array:
	return (result["data"] as Array) if bool(result["ok"]) and result["data"] is Array else []


## Социальные функции есть на сервере (схема schema_v5_social.sql выполнена).
func social_ready(result: Dictionary) -> bool:
	return int(result["code"]) != 404


## "sent", "ok", "friends", "self", "not_found", "blocked", "limit", "offline", "no_server".
func request_friend(code: String) -> String:
	var result := await _rpc("request_friend", {"p_code": code})
	if not social_ready(result):
		return "no_server"
	return str(result["data"]) if bool(result["ok"]) else "offline"


func list_requests() -> Array:
	return _rows(await _rpc("list_requests", {}))


func answer_request(code: String, accept: bool) -> String:
	var result := await _rpc("answer_request", {"p_code": code, "p_accept": accept})
	return str(result["data"]) if bool(result["ok"]) else "offline"


## {"ok": bool, "items": [...], "no_server": bool}: друзья с последним сообщением и числом непрочитанных.
func inbox() -> Dictionary:
	var result := await _rpc("inbox", {})
	return {"ok": bool(result["ok"]), "items": _rows(result), "no_server": not social_ready(result)}


func friend_profile(code: String) -> Dictionary:
	var rows := _rows(await _rpc("friend_profile", {"p_code": code}))
	return rows[0] as Dictionary if not rows.is_empty() and rows[0] is Dictionary else {}


## "ok", "not_friends", "blocked", "rate", "empty", "banned", "offline".
func send_message(code: String, text: String) -> String:
	var result := await _rpc("send_message", {"p_code": code, "p_body": text})
	return str(result["data"]) if bool(result["ok"]) else "offline"


## {"ok": bool, "items": [{id, mine, body, created_at}]}; входящие помечаются прочитанными.
func get_messages(code: String, after_id: int) -> Dictionary:
	var result := await _rpc("get_messages", {"p_code": code, "p_after": after_id})
	return {"ok": bool(result["ok"]), "items": _rows(result)}


func block_user(code: String) -> bool:
	var result := await _rpc("block_user", {"p_code": code})
	return bool(result["ok"]) and str(result["data"]) == "ok"


func unblock_user(code: String) -> bool:
	return bool((await _rpc("unblock_user", {"p_code": code}))["ok"])


func list_blocks() -> Array:
	return _rows(await _rpc("list_blocks", {}))


func report_user(code: String, reason: String, message_id: int = 0) -> String:
	var body := {"p_code": code, "p_reason": reason}
	if message_id > 0:
		body["p_message_id"] = message_id
	var result := await _rpc("report_user", body)
	return str(result["data"]) if bool(result["ok"]) else "offline"


## Новые сообщения и заявки: число для значка в меню.
func refresh_unread() -> void:
	if not has_code():
		return
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/unread_total", {})
	if bool(result["ok"]):
		var count := int(result["data"])
		if count != unread:
			unread = count
			unread_changed.emit()


## Приглашения в кооп: свежие входящие. Каждое приглашение сообщается один раз.
func poll_coop_invites() -> void:
	if not has_code() or CoopScreen.host().is_empty():
		return
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/coop_inbox", {})
	for row in _rows(result):
		if row is Dictionary:
			var invite := row as Dictionary
			var id := int(invite.get("id", 0))
			if id > 0 and not _invites_seen.has(id):
				_invites_seen[id] = true
				coop_invite_received.emit(invite)


## "ok", "not_friends", "blocked", "banned", "rate", "bad", "auth", "offline", "no_server".
func send_coop_invite(code: String, room: String) -> String:
	var result := await _rpc("send_coop_invite", {"p_code": code, "p_room": room})
	if not social_ready(result):
		return "no_server"
	return str(result["data"]) if bool(result["ok"]) else "offline"


## Код комнаты при принятии, "declined" / "expired" / "bad", либо "offline".
func answer_coop_invite(id: int, accept: bool) -> String:
	var result := await _rpc("coop_invite_answer", {"p_id": id, "p_accept": accept})
	return str(result["data"]) if bool(result["ok"]) else "offline"


## POST с чужим токеном (игровой сервер проверяет право игрока войти в комнату).
func post_with_token(path: String, body: Dictionary, jwt: String) -> Dictionary:
	var headers := PackedStringArray(["apikey: " + KEY, "Authorization: Bearer " + jwt, "Content-Type: application/json"])
	var reply := await _raw(HTTPClient.METHOD_POST, URL + path, headers, JSON.stringify(body))
	return {"ok": bool(reply["ok"]), "code": int(reply["code"]), "data": reply["data"]}


func send_vote(line_id: String, value: int, who: String, line_text: String) -> void:
	if not await sync_profile():
		return
	var row := {"user_id": _uid, "line_id": line_id, "value": value, "who": who, "line_text": line_text.left(300), "build": Platform.build_label(), "insider": SaveService.get_insider()}
	await _call(HTTPClient.METHOD_POST, "/rest/v1/line_votes?on_conflict=user_id,line_id", row, ["Prefer: resolution=merge-duplicates,return=minimal"])


func _call(method: int, path: String, body: Variant, extra: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not await _ensure_session():
		online = false
		last_error = "сессия не создана (%s)" % _raw_note
		return {"ok": false, "code": 0, "data": null}
	var headers := PackedStringArray(["apikey: " + KEY, "Authorization: Bearer " + _access, "Content-Type: application/json"])
	headers.append_array(extra)
	var reply := await _raw(method, URL + path, headers, JSON.stringify(body) if body != null else "")
	if int(reply["code"]) == 401:
		_expires = 0
		if await _ensure_session():
			headers[1] = "Authorization: Bearer " + _access
			reply = await _raw(method, URL + path, headers, JSON.stringify(body) if body != null else "")
	online = int(reply["code"]) > 0
	if not bool(reply["ok"]):
		var detail := str(reply["data"]).left(120) if reply["data"] != null else _raw_note
		last_error = "%s -> HTTP %d %s" % [path.get_slice("/", 4).get_slice("?", 0), int(reply["code"]), detail]
	return reply


## Забрать начисленные сервером награды за кооп. {"ok", "coins", "xp", "runs", "rating", "tier", "last_delta", "last_run_age"} или {} при сбое.
func coop_claim_rewards() -> Dictionary:
	var result := await _rpc("coop_claim_rewards", {})
	return result["data"] as Dictionary if bool(result["ok"]) and result["data"] is Dictionary else {}


## {"ok", "rating", "tier", "season", "runs", "best_wave"} или {}.
func coop_my_rating() -> Dictionary:
	var result := await _rpc("coop_my_rating", {})
	return result["data"] as Dictionary if bool(result["ok"]) and result["data"] is Dictionary else {}


## scope: "friends" или "global". Строки: {place, nickname, rating, tier, mine}.
func coop_top(scope: String) -> Array:
	return _rows(await _rpc("coop_top", {"p_scope": scope}))


## POST от имени игрового сервера (ключ service_role берётся из окружения VPS и больше нигде не хранится).
func post_service(path: String, body: Dictionary, service_key: String) -> Dictionary:
	var headers := PackedStringArray(["apikey: " + service_key, "Authorization: Bearer " + service_key, "Content-Type: application/json"])
	var reply := await _raw(HTTPClient.METHOD_POST, URL + path, headers, JSON.stringify(body))
	return {"ok": bool(reply["ok"]), "code": int(reply["code"]), "data": reply["data"]}


## Токен текущей сессии (для входа на игровой сервер). Пустая строка, если сессии нет.
func access_token() -> String:
	return _access


## GET с чужим токеном (игровой сервер проверяет токен игрока). Ответ: {"ok", "code", "data"}, для списка ещё "row" (первая строка).
func fetch_with_token(path: String, jwt: String) -> Dictionary:
	var headers := PackedStringArray(["apikey: " + KEY, "Authorization: Bearer " + jwt])
	var reply := await _raw(HTTPClient.METHOD_GET, URL + path, headers, "")
	var out: Dictionary = {"ok": bool(reply["ok"]), "code": int(reply["code"]), "data": reply["data"]}
	var data: Variant = reply["data"]
	if data is Dictionary:
		out.merge(data as Dictionary)
	elif data is Array and not (data as Array).is_empty() and (data as Array)[0] is Dictionary:
		out["row"] = (data as Array)[0]
	return out


## Проверка связи: что отвечает, а что нет. Возвращает короткий отчёт для экрана и для тестера.
func ping() -> String:
	var headers := PackedStringArray(["apikey: " + KEY])
	var parts: Array[String] = []
	var started := Time.get_ticks_msec()
	var auth := await _raw(HTTPClient.METHOD_GET, URL + "/auth/v1/health", headers, "")
	parts.append("вход: %s" % (("HTTP %d" % int(auth["code"])) if int(auth["code"]) > 0 else _raw_note))
	var data := await _raw(HTTPClient.METHOD_GET, URL + "/rest/v1/", headers, "")
	parts.append("база: %s" % (("HTTP %d" % int(data["code"])) if int(data["code"]) > 0 else _raw_note))
	parts.append("%d мс" % (Time.get_ticks_msec() - started))
	parts.append(Platform.build_label())
	var text := " · ".join(parts)
	if int(auth["code"]) == 0 or int(data["code"]) == 0:
		Platform._js("try { var q = JSON.parse(window.localStorage.getItem('__trash_errq') || '[]'); q.push(%s); window.localStorage.setItem('__trash_errq', JSON.stringify(q.slice(-20))); } catch (e) {} return '';" % JSON.stringify("ПРОВЕРКА СВЯЗИ: " + text))
	return text


## Короткий код для тестера вместо скриншота.
func error_code() -> String:
	return ("[%s · %s]" % [_raw_note, Platform.build_label()]) if not _raw_note.is_empty() else ""


func _raw(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	# Как в онлайн-играх: короткий сбой сети не должен ломать действие. Повторяем с паузой, но только то, что безопасно:
	# чтение (GET) и случаи, когда запрос до сервера так и не дошёл (нет адреса, нет соединения, TLS).
	var attempt := 0
	while true:
		var out := await _raw_once(method, url, headers, body)
		if int(out["code"]) > 0 or attempt >= 2:
			return out
		var kind := int(out.get("result", -1))
		var safe := method == HTTPClient.METHOD_GET or kind in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR]
		if not safe:
			return out
		attempt += 1
		await get_tree().create_timer(0.7 * attempt).timeout
	return {"ok": false, "code": 0, "data": null}


func _raw_once(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT
	# В браузере ответ уже распакован самим браузером. Если Godot распаковывает его второй раз, большие ответы
	# (список друзей, топ, сохранение) падают с RESULT_BODY_DECOMPRESS_FAILED (код 8), а маленькие проходят.
	request.accept_gzip = not Platform.is_web
	add_child(request)
	if request.request(url, headers, method, body) != OK:
		request.queue_free()
		_raw_note = "запрос не ушёл"
		return {"ok": false, "code": 0, "data": null, "result": -1}
	var reply: Array = await request.request_completed
	request.queue_free()
	if int(reply[0]) != HTTPRequest.RESULT_SUCCESS:
		_raw_note = "нет ответа: %s" % NET_ERRORS.get(int(reply[0]), "код %d" % int(reply[0]))
		Platform.trail("сеть сбой %s: %s" % [url.get_slice("/", 6).get_slice("?", 0), _raw_note])
		return {"ok": false, "code": 0, "data": null, "result": int(reply[0])}
	var code := int(reply[1])
	_raw_note = "HTTP %d" % code
	Platform.trail("сеть %s -> %d" % [url.get_slice("/", 6).get_slice("?", 0) if url.contains("/rpc/") else url.get_slice(".co", 1).get_slice("?", 0), code])
	var text := (reply[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return {"ok": code >= 200 and code < 300, "code": code, "data": parsed}


func _ensure_session() -> bool:
	if _session_busy:
		while _session_busy:
			await get_tree().process_frame
		return not _access.is_empty()
	if not _access.is_empty() and Time.get_unix_time_from_system() < _expires - EXPIRY_MARGIN:
		return true
	_session_busy = true
	var ok := false
	var headers := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	if not _refresh.is_empty():
		var reply := await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/token?grant_type=refresh_token", headers, JSON.stringify({"refresh_token": _refresh}))
		ok = _store_session(reply)
		if not ok and int(reply["code"]) >= 400 and int(reply["code"]) < 500:
			await get_tree().create_timer(1.5).timeout
			var parsed: Variant = _parse_or_null(Platform.storage_get(SESSION_KEY))
			var newer := str((parsed as Dictionary).get("refresh", "")) if parsed is Dictionary else ""
			if not newer.is_empty() and newer != _refresh:
				_refresh = newer
				reply = await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/token?grant_type=refresh_token", headers, JSON.stringify({"refresh_token": _refresh}))
				ok = _store_session(reply)
			if not ok and int(reply["code"]) >= 400 and int(reply["code"]) < 500:
				Platform.storage_set(LOST_KEY, JSON.stringify({"uid": _uid, "code": friend_code}))
				_refresh = ""
				_uid = ""
				_access = ""
				# Сервер больше не принимает сессию. Молча заводить нового енота нельзя: аккаунт «менялся бы» у игрока.
				# С логином просим войти заново; у гостя есть код восстановления — переносим его аккаунт на новую сессию.
				if not guest_key.is_empty():
					var parts := guest_key.split(".")
					if parts.size() == 2:
						var again := await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/token?grant_type=password", headers, JSON.stringify({"email": parts[0] + ACCOUNT_DOMAIN, "password": parts[1]}))
						if _store_session(again):
							_session_busy = false
							return true
				if not email.is_empty():
					session_lost = true
					session_lost_changed.emit()
					_session_busy = false
					return false
				_restore_after_signup = recovery_code
	if not ok and _refresh.is_empty() and not session_lost:
		ok = _store_session(await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/signup", headers, "{}"))
	_session_busy = false
	if ok and not _restore_after_signup.is_empty():
		var code := _restore_after_signup
		_restore_after_signup = ""
		_auto_restore.call_deferred(code)
	return ok


## Гость потерял сессию: новая сессия забирает его прежний профиль, ID, друзей и облако по коду восстановления.
func _auto_restore(code: String) -> void:
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/restore_save", {"p_code": code})
	if bool(result["ok"]) and result["data"] is String and not str(result["data"]).is_empty() and not str(result["data"]).begins_with("ACCOUNT:"):
		friend_code = ""
		recovery_code = code
		Platform.storage_set(RECOVERY_KEY, code)
		Platform.storage_set(LOST_KEY, "")
		await sync_profile()


func _store_session(reply: Dictionary) -> bool:
	var data: Variant = reply["data"]
	if not bool(reply["ok"]) or not data is Dictionary:
		return false
	var session := data as Dictionary
	var user: Variant = session.get("user", {})
	_access = str(session.get("access_token", ""))
	_refresh = str(session.get("refresh_token", ""))
	_expires = int(Time.get_unix_time_from_system()) + int(session.get("expires_in", 3600))
	if user is Dictionary:
		_uid = str((user as Dictionary).get("id", _uid))
		_hidden_mail = str((user as Dictionary).get("email", "")).begins_with(GUEST_PREFIX)
	if _access.is_empty() or _uid.is_empty():
		return false
	Platform.storage_set(SESSION_KEY, JSON.stringify({"uid": _uid, "refresh": _refresh}))
	waiting_choice = false
	if session_lost:
		session_lost = false
		session_lost_changed.emit()
	return true


func _load_session() -> void:
	var parsed: Variant = _parse_or_null(Platform.storage_get(SESSION_KEY))
	if parsed is Dictionary:
		_uid = str((parsed as Dictionary).get("uid", ""))
		_refresh = str((parsed as Dictionary).get("refresh", ""))


static func _parse_or_null(text: String) -> Variant:
	return null if text.strip_edges().is_empty() else JSON.parse_string(text)
