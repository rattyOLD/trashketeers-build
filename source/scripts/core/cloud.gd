extends Node
## Связь с сервером Supabase: анонимный вход без регистрации, профиль, друзья по коду, оценки реплик.
## Всё необязательно: без связи игра работает как раньше, методы возвращают пустой результат.

signal profile_synced
signal unread_changed

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
const UPLOAD_DELAY := 8.0
const TIMEOUT := 10.0
const EXPIRY_MARGIN := 60

var friend_code := ""
var recovery_code := ""
var email := ""
var online := false
var last_error := ""
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()
	recovery_code = Platform.storage_get(RECOVERY_KEY)
	email = Platform.storage_get(EMAIL_KEY)
	if Platform.is_web:
		get_tree().create_timer(4.0).timeout.connect(sync_profile)
		var poll := Timer.new()
		poll.wait_time = 45.0
		poll.timeout.connect(refresh_unread)
		add_child(poll)
		poll.start()
		get_tree().create_timer(9.0).timeout.connect(refresh_unread)
		var backup := Timer.new()
		backup.wait_time = 150.0
		backup.timeout.connect(_auto_backup)
		add_child(backup)
		backup.start()


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
			_last_sync = Time.get_ticks_msec() / 1000
			profile_synced.emit()
	if has_code():
		await _sync_badge()
		if recovery_code.is_empty():
			queue_upload()
	return has_code()


## Тег живёт на сервере. Если он не совпал с запомненным секретом (новая сессия) — выдаём заново.
func _sync_badge() -> void:
	var reply := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_badge", {})
	if not bool(reply["ok"]) or not (reply["data"] is int or reply["data"] is float):
		return
	var level := int(reply["data"])
	var secret := Platform.storage_get(BADGE_SECRET_KEY)
	if not secret.is_empty() and Platform.storage_get(BADGE_UID_KEY) != _uid:
		level = await claim_badge(secret, false)
	SaveService.set_badge_level(level)


## Секрет из ссылки -> тег. Возвращает уровень (0 DeV, 1 Insider) или -1.
func claim_badge(secret: String, remember: bool = true) -> int:
	if not await sync_profile():
		return -1
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
	if not has_code():
		return
	var snapshot := SaveService.export_code().sha256_text()
	if snapshot == _last_backup:
		return
	if not (await upload_save()).is_empty():
		_last_backup = snapshot


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
	if not await sync_profile():
		return ""
	var cloud := await fetch_cloud_save()
	if not bool(cloud["ok"]):
		return recovery_code
	var cloud_text := str(cloud["text"])
	if not cloud_text.is_empty():
		var theirs := SaveService.parse_backup(cloud_text)
		if not theirs.is_empty() and SaveService.score_of(theirs) > SaveService.progress_score():
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
		friend_code = ""
		await sync_profile()
		return str(result["data"])
	return ""


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
	if name.is_empty():
		return "invalid"
	if not await _ensure_session():
		return "offline"
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
	recovery_code = ""
	Platform.storage_set(RECOVERY_KEY, "")
	return "ok"


## Выход: прогресс сперва уходит в облако, затем на устройстве остаётся чистая игра. Вернуться можно логином и паролем.
func logout() -> void:
	await upload_save()
	for key in [SESSION_KEY, LOST_KEY, RECOVERY_KEY, EMAIL_KEY, BADGE_SECRET_KEY, BADGE_UID_KEY, SaveService.BADGE_KEY, "trk_badge_seen", "trk_acct_nag", SaveService.STORAGE_KEY]:
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


func send_vote(line_id: String, value: int, who: String, line_text: String) -> void:
	if not await sync_profile():
		return
	var row := {"user_id": _uid, "line_id": line_id, "value": value, "who": who, "line_text": line_text.left(300), "build": Platform.build_label(), "insider": SaveService.get_insider()}
	await _call(HTTPClient.METHOD_POST, "/rest/v1/line_votes?on_conflict=user_id,line_id", row, ["Prefer: resolution=merge-duplicates,return=minimal"])


func _call(method: int, path: String, body: Variant, extra: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not await _ensure_session():
		online = false
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
		var detail := str(reply["data"]).left(120) if reply["data"] != null else ""
		last_error = "%s -> HTTP %d %s" % [path.get_slice("/", 4).get_slice("?", 0), int(reply["code"]), detail]
	return reply


func _raw(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT
	add_child(request)
	if request.request(url, headers, method, body) != OK:
		request.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var reply: Array = await request.request_completed
	request.queue_free()
	if int(reply[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": 0, "data": null}
	var code := int(reply[1])
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
			var parsed: Variant = JSON.parse_string(Platform.storage_get(SESSION_KEY))
			var newer := str((parsed as Dictionary).get("refresh", "")) if parsed is Dictionary else ""
			if not newer.is_empty() and newer != _refresh:
				_refresh = newer
				reply = await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/token?grant_type=refresh_token", headers, JSON.stringify({"refresh_token": _refresh}))
				ok = _store_session(reply)
			if not ok and int(reply["code"]) >= 400 and int(reply["code"]) < 500:
				Platform.storage_set(LOST_KEY, JSON.stringify({"uid": _uid, "code": friend_code}))
				_refresh = ""
				_uid = ""
	if not ok and _refresh.is_empty():
		ok = _store_session(await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/signup", headers, "{}"))
	_session_busy = false
	return ok


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
	if _access.is_empty() or _uid.is_empty():
		return false
	Platform.storage_set(SESSION_KEY, JSON.stringify({"uid": _uid, "refresh": _refresh}))
	return true


func _load_session() -> void:
	var parsed: Variant = JSON.parse_string(Platform.storage_get(SESSION_KEY))
	if parsed is Dictionary:
		_uid = str((parsed as Dictionary).get("uid", ""))
		_refresh = str((parsed as Dictionary).get("refresh", ""))
