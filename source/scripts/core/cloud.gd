extends Node
## Связь с сервером Supabase: анонимный вход без регистрации, профиль, друзья по коду, оценки реплик.
## Всё необязательно: без связи игра работает как раньше, методы возвращают пустой результат.

signal profile_synced
signal unread_changed

## Вход по почте скрыт, пока в Supabase не настроены SMTP и шаблоны писем.
const EMAIL_LOGIN := false
const URL := "https://ylclwkprhhlzavhahrko.supabase.co"
const KEY := "sb_publishable_7xeZ6_3lc4Bi44z35wf4BQ__P6Maunz"
const SESSION_KEY := "trk_cloud_session"
const LOST_KEY := "trk_cloud_lost"
const RECOVERY_KEY := "trk_recovery_code"
const EMAIL_KEY := "trk_cloud_email"
const UPLOAD_DELAY := 8.0
const TIMEOUT := 10.0
const EXPIRY_MARGIN := 60

var friend_code := ""
var recovery_code := ""
var email := ""
var online := false
var unread := 0

var _uid := ""
var _access := ""
var _refresh := ""
var _expires := 0
var _session_busy := false
var _profile_busy := false
var _upload_pending := false


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
			profile_synced.emit()
	return has_code()


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
func queue_upload() -> void:
	if _upload_pending or not Platform.is_web:
		return
	_upload_pending = true
	get_tree().create_timer(UPLOAD_DELAY).timeout.connect(func() -> void:
		_upload_pending = false
		upload_save())


## Кладёт сохранение в облако и возвращает код восстановления (пусто, если связи нет).
func upload_save() -> String:
	if not await sync_profile():
		return ""
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/upload_save", {"p_data": SaveService.export_code()})
	if bool(result["ok"]) and result["data"] is String and not str(result["data"]).is_empty():
		recovery_code = str(result["data"])
		Platform.storage_set(RECOVERY_KEY, recovery_code)
	return recovery_code


## Возвращает код сохранения из облака по коду восстановления или пустую строку.
func restore_save(code: String) -> String:
	if not await sync_profile():
		return ""
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/restore_save", {"p_code": code})
	if bool(result["ok"]) and result["data"] is String:
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


## Привязка почты к текущему профилю: "sent", "exists", "limit", "invalid" или "offline".
func link_email(address: String) -> String:
	var result := await _call(HTTPClient.METHOD_PUT, "/auth/v1/user", {"email": address.strip_edges().to_lower()})
	return _email_status(result, true)


## Подтверждение привязки кодом из письма.
func confirm_link(address: String, token: String) -> bool:
	var reply := await _verify("email_change", address, token)
	if not _store_session(reply):
		return false
	_remember_email(address)
	return true


## Вход по почте на новом устройстве: "sent", "not_found", "limit" или "offline".
func request_login(address: String) -> String:
	var headers := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	var reply := await _raw(HTTPClient.METHOD_POST, URL + "/auth/v1/otp", headers, JSON.stringify({"email": address.strip_edges().to_lower(), "create_user": false}))
	return _email_status(reply, false)


## Подтверждение входа кодом из письма; профиль подменяется на привязанный к почте.
func confirm_login(address: String, token: String) -> bool:
	var reply := await _verify("email", address, token)
	if not _store_session(reply):
		return false
	_remember_email(address)
	friend_code = ""
	recovery_code = ""
	Platform.storage_set(RECOVERY_KEY, "")
	return true


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
	if not await sync_profile():
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
