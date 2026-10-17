class_name NativeTelemetry
extends Node
## Отчёты из приложения (Android/iOS) в тот же журнал, что и веб-версия (Google Apps Script):
## начало/конец сессии, пульс, производительность и рывки из боя (Platform.send_report), ошибки
## движка и скриптов (читаются из файла журнала на лету) и вылеты прошлого запуска (флаг боя +
## хвост журнала прошлого запуска). В вебе и в редакторе не работает — там своё.

const REPORT_URL := "https://script.google.com/macros/s/AKfycbxVyy-SnRANW0Im-1Blne2TcUbca93WqzyBulpADwWWD7YH6x3KIygBYImTe8VfP5pp/exec"
const REPORT_CAP := 250
const HEARTBEAT := 60.0
const LOG_POLL := 5.0
const LOG_READ_LIMIT := 32768
const LOG_LINE_LIMIT := 4096
const LOG_PATH := "user://logs/godot.log"
const LOG_DIR := "user://logs"
const UID_KEY := "trk_uid"
const CTX_KEY := "__trash_ctx"
## «Приложение живо»: снимается при уходе в фон/закрытии. Осталась при старте — прошлый запуск убит.
const ALIVE_KEY := "__trash_alive"

## Адрес приёма отчётов (тест подставляет свой).
var endpoint := REPORT_URL
var session_id := ""
var _uid := ""
var _start_ms := 0
var _sent := {}
var _count := 0
var _queue: Array[String] = []
var _http: HTTPRequest
var _busy := false
var _events: PackedStringArray = PackedStringArray()
var _trail: PackedStringArray = PackedStringArray()
var _context := ""
var _heartbeat := HEARTBEAT
var _log_poll := LOG_POLL
var _log_pos := 0
var _pending_error := ""
var _log_line := PackedByteArray()
var _discard_line := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	session_id = _random_id(6)
	_uid = Platform.storage_get(UID_KEY)
	if _uid.is_empty():
		_uid = _random_id(8)
		Platform.storage_set(UID_KEY, _uid)
	_context = Platform.storage_get(CTX_KEY)


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.request_completed.connect(_on_sent)
	add_child(_http)
	report("session_start", device_info())
	_report_previous_crash()
	var current_log := FileAccess.open(LOG_PATH, FileAccess.READ)
	if current_log != null:
		_log_pos = current_log.get_length()


func _process(delta: float) -> void:
	_heartbeat -= delta
	if _heartbeat <= 0.0:
		_heartbeat = HEARTBEAT
		report("heartbeat", _context)
	_log_poll -= delta
	if _log_poll <= 0.0:
		_log_poll = LOG_POLL
		_scan_log()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			Platform.storage_set(ALIVE_KEY, "")
			note("app paused")
			_scan_log()
			report("session_end", "%ds | paused | last: %s" % [_age(), _context])
		NOTIFICATION_APPLICATION_RESUMED:
			Platform.storage_set(ALIVE_KEY, "1")
			note("app resumed")
		NOTIFICATION_WM_CLOSE_REQUEST:
			Platform.storage_set(ALIVE_KEY, "")
			report("session_end", "%ds | closed | last: %s" % [_age(), _context])


func set_context(text: String) -> void:
	_context = text
	Platform.storage_set(CTX_KEY, text)


func last_context() -> String:
	return _context


func note(text: String) -> void:
	_events.append("%ds %s" % [_age(), text.left(160)])
	if _events.size() > 25:
		_events.remove_at(0)


func trail(text: String) -> void:
	_trail.append("%ds %s" % [_age(), text.left(80)])
	if _trail.size() > 20:
		_trail.remove_at(0)


func report(kind: String, text: String, extra: String = "") -> void:
	if not Platform.telemetry_allowed():
		return
	if _count >= REPORT_CAP:
		return
	var key := kind + text.left(100)
	if _sent.has(key):
		return
	_sent[key] = true
	_count += 1
	var heavy := kind != "heartbeat" and kind != "session_start"
	var env := _env()
	var full := "[%s +%ds] %s" % [session_id, _age(), text.left(3000)]
	full += "\nENV " + JSON.stringify(env)
	if heavy:
		full += "\nEVENTS " + " ; ".join(_events) + "\nWHERE " + _context.left(300) + "\nTRAIL " + " ; ".join(_trail)
	full = full.left(8000)
	if not extra.is_empty():
		full += "\nSHOT " + extra.left(30000)
	var payload := {
		"kind": kind,
		"text": full,
		"time": Time.get_datetime_string_from_system(true) + "Z",
		"build": build_label(),
		"buildId": str(ProjectSettings.get_setting("application/config/version", "")),
		"session": session_id,
		"env": env,
	}
	if heavy:
		payload["events"] = Array(_events)
	_queue.append(JSON.stringify(payload))
	_flush()


func build_label() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return ("TrashSquad " + version).strip_edges() + " · " + OS.get_name()


func device_info() -> String:
	var memory := OS.get_memory_info()
	return "%s | %s %s | %s ×%d | mem %dMB | gpu %s %s | %s | screen %s dpi %d" % [
		OS.get_model_name(), OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(),
		int(memory.get("physical", 0)) / 1048576, RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		str(DisplayServer.screen_get_size()), DisplayServer.screen_get_dpi()]


func _env() -> Dictionary:
	var memory := OS.get_memory_info()
	return {
		"uid": _uid,
		"model": OS.get_model_name(),
		"os": OS.get_name() + " " + OS.get_version(),
		"arch": Engine.get_architecture_name(),
		"cpu": "%s ×%d" % [OS.get_processor_name(), OS.get_processor_count()],
		"mem": "%d/%dMB free" % [int(memory.get("available", 0)) / 1048576, int(memory.get("physical", 0)) / 1048576],
		"gpu": RenderingServer.get_video_adapter_name(),
		"vram": "%dMB" % int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"static_mem": "%dMB" % int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"fps": Engine.get_frames_per_second(),
		"screen": str(DisplayServer.screen_get_size()),
		"window": str(DisplayServer.window_get_size()),
		"lang": OS.get_locale(),
		"tz": str(Time.get_time_zone_from_system().get("name", "")),
	}


func _flush() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	_busy = true
	var body: String = _queue.pop_front()
	if _http.request(endpoint, PackedStringArray(["Content-Type: text/plain;charset=UTF-8"]), HTTPClient.METHOD_POST, body) != OK:
		_busy = false


func _on_sent(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy = false
	_flush()


## Новые строки журнала движка: ERROR / SCRIPT ERROR вместе со строкой «at:» — отдельным отчётом.
func _scan_log() -> void:
	_scan_log_file(LOG_PATH)


func _scan_log_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
	var length := file.get_length()
	if length < _log_pos:
		_log_pos = 0
		_log_line.clear()
		_discard_line = false
		_pending_error = ""
	if length == _log_pos: return
	file.seek(_log_pos)
	var chunk := file.get_buffer(mini(length - _log_pos, LOG_READ_LIMIT))
	_log_pos = file.get_position()
	for byte in chunk:
		if byte == 10:
			_consume_log_line(_log_line.get_string_from_utf8())
			_log_line.clear()
			_discard_line = false
		elif not _discard_line:
			_log_line.append(byte)
			if _log_line.size() > LOG_LINE_LIMIT:
				var boundary := LOG_LINE_LIMIT
				while boundary > 0 and (_log_line[boundary] & 0xc0) == 0x80: boundary -= 1
				_log_line.resize(boundary)
				_discard_line = true
	if _log_pos == length and _log_line.is_empty() and not _pending_error.is_empty():
		_send_error(_pending_error)
		_pending_error = ""


func _consume_log_line(line: String) -> void:
	var stripped := line.strip_edges()
	if stripped.begins_with("at:") and not _pending_error.is_empty():
		_send_error(_pending_error + " | " + stripped.left(600))
		_pending_error = ""
	elif stripped.begins_with("ERROR:") or stripped.begins_with("SCRIPT ERROR:") or stripped.begins_with("USER ERROR:"):
		if not _pending_error.is_empty(): _send_error(_pending_error)
		_pending_error = stripped.left(600)


static func _read_log_tail(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var start := maxi(file.get_length() - LOG_READ_LIMIT, 0)
	file.seek(start)
	var bytes := file.get_buffer(LOG_READ_LIMIT)
	if start > 0:
		var newline := bytes.find(10)
		bytes = bytes.slice(newline + 1) if newline >= 0 else PackedByteArray()
	var lines := bytes.get_string_from_utf8().split("\n")
	return "\n".join(lines.slice(maxi(lines.size() - 40, 0)))


func _send_error(text: String) -> void:
	note("error: " + text.left(120))
	report("error", text)


## Прошлый запуск убит (вылет, нехватка памяти, ANR) или упал движок: последнее состояние и хвост его
## журнала — какие ошибки были перед смертью. Флаг оборванного боя отдельно сообщает main.gd (unclean_exit).
func _report_previous_crash() -> void:
	var killed := Platform.storage_get(ALIVE_KEY) == "1"
	Platform.storage_set(ALIVE_KEY, "1")
	var previous := _previous_log()
	var tail := ""
	var crashed := false
	if not previous.is_empty():
		tail = _read_log_tail(previous)
		crashed = tail.contains("Program crashed") or tail.contains("CrashHandler") or tail.contains("signal 11") or tail.contains("Fatal")
	if crashed or killed:
		report("prev_session_died", "previous session %s | last: %s\nLOG TAIL\n%s" % [
			"ended with an engine crash" if crashed else "was killed without a clean exit", _context, tail.left(4000)])


## Журнал прошлого запуска: движок переименовывает его при старте (godot<дата>.log).
func _previous_log() -> String:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return ""
	var newest := ""
	for name in dir.get_files():
		if name.begins_with("godot") and name.ends_with(".log") and name != "godot.log" and name > newest:
			newest = name
	return LOG_DIR.path_join(newest) if not newest.is_empty() else ""


func _age() -> int:
	return (Time.get_ticks_msec() - _start_ms) / 1000


static func _random_id(length: int) -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := ""
	for i in length:
		out += chars[randi() % chars.length()]
	return out
