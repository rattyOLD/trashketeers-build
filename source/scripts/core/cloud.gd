extends Node
## Связь с сервером Supabase: анонимный вход без регистрации, профиль, друзья по коду, оценки реплик.
## Всё необязательно: без связи игра работает как раньше, методы возвращают пустой результат.

signal profile_synced

const URL := "https://ylclwkprhhlzavhahrko.supabase.co"
const KEY := "sb_publishable_7xeZ6_3lc4Bi44z35wf4BQ__P6Maunz"
const SESSION_KEY := "trk_cloud_session"
const TIMEOUT := 10.0
const EXPIRY_MARGIN := 60

var friend_code := ""
var online := false

var _uid := ""
var _access := ""
var _refresh := ""
var _expires := 0
var _session_busy := false
var _profile_busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()
	if Platform.is_web:
		get_tree().create_timer(4.0).timeout.connect(sync_profile)


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
	var result := await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/sync_profile", body)
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
