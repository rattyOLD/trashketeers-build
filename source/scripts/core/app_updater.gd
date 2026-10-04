class_name AppUpdater
extends Node

const RELEASE := "https://github.com/rattyOLD/trashketeers-build/releases/download/android-beta/"
const VERSION_URL := RELEASE + "android-version.json"
const APK_URL := RELEASE + "TrashSquad.apk"
const TESTER_URL := "https://appdistribution.firebase.google.com/testerapps/1%3A80820379449%3Aandroid%3A83df21951e3a0f0fc7d2e8"
const FIRST_CHECK := 4.0
const UPDATE_DIR := "user://updates"
const MAX_APK_BYTES := 256 * 1024 * 1024

enum Stage { OFFER, DOWNLOADING, READY, PERMISSION, INSTALLING, ERROR }

var _http: HTTPRequest
var _download: HTTPRequest
var _native: Object
var _offered := 0
var _remote: Dictionary = {}
var _stage := Stage.OFFER
var _path := ""
var _popup: GlassPopup
var _status: Label
var _progress: ProgressBar
var _update: Button
var _later: Button
var _previous_pause := false
var _progress_clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.max_redirects = 8
	_http.request_completed.connect(_on_version)
	add_child(_http)
	_download = HTTPRequest.new()
	_download.use_threads = true
	_download.timeout = 900.0
	_download.max_redirects = 8
	_download.body_size_limit = MAX_APK_BYTES
	_download.request_completed.connect(_on_download)
	add_child(_download)
	if Engine.has_singleton("TrashSquadUpdater"):
		_native = Engine.get_singleton("TrashSquadUpdater")
		_native.connect("installer_error", _fail)
		_native.connect("installer_opened", _on_installer_opened)
	_cleanup()
	get_tree().create_timer(FIRST_CHECK).timeout.connect(check)


static func local_code() -> int:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return int(version.trim_prefix("beta.")) if version.begins_with("beta.") else -1


func check() -> void:
	if local_code() < 0 or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http.request(VERSION_URL + "?t=%d" % Time.get_unix_time_from_system())


static func valid_manifest(data: Dictionary) -> bool:
	var digest := str(data.get("sha256", "")).to_lower()
	if digest.length() != 64 or int(data.get("bytes", 0)) <= 0 or int(data.get("bytes", 0)) > MAX_APK_BYTES:
		return false
	for ch in digest:
		if not ch in "0123456789abcdef":
			return false
	return true


func _on_version(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var remote_code := int(data.get("code", 0))
	if remote_code <= local_code():
		return
	if not is_instance_valid(_popup) or _stage == Stage.ERROR:
		_remote = data
	if remote_code <= _offered or is_instance_valid(_popup):
		return
	_offered = remote_code
	Platform.note_event("update offered beta.%d" % remote_code)
	_show("beta.%d" % remote_code, "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _http != null:
		if _stage == Stage.PERMISSION and is_instance_valid(_popup):
			if _native != null and bool(_native.call("can_install_packages")):
				_install.call_deferred()
			else:
				_status.text = "Разреши обновления от TrashSquad в настройках Android, затем вернись в игру."
		check()


func _show(name: String, _notes: String) -> void:
	if is_instance_valid(_popup):
		return
	_stage = Stage.OFFER
	_previous_pause = get_tree().paused
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)
	_popup = GlassPopup.new("ОБНОВЛЕНИЕ")
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_popup)
	_status = UiStyle.label("Вышла TrashSquad %s.\nСкачаем обновление здесь и откроем установку. Прогресс сохранится." % name, 22, UiStyle.TEXT, 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(minf(GlassPopup.panel_width() - 60.0, 560.0), 0)
	_popup.content.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 24)
	_progress.show_percentage = false
	_progress.visible = false
	_popup.content.add_child(_progress)
	_update = UiStyle.button("ОБНОВИТЬ", UiStyle.GOLD, 30)
	_update.pressed.connect(_on_update_pressed)
	_popup.content.add_child(_update)
	_later = UiStyle.button("ПОЗЖЕ", UiStyle.TEXT_DIM, 24, Vector2(0, 64))
	_later.pressed.connect(_popup.close)
	_popup.content.add_child(_later)
	_popup.closed.connect(_on_closed)
	_popup.closed.connect(layer.queue_free)
	if _native == null or not valid_manifest(_remote):
		_status.text = "Вышла TrashSquad %s.\nЭту версию можно установить через App Tester. Следующие обновления будут скачиваться прямо в игре." % name
		_update.text = "ОТКРЫТЬ APP TESTER"
	_popup.open()


func _on_update_pressed() -> void:
	if _native == null or not valid_manifest(_remote):
		if _open_tester() == OK:
			Platform.note_event("update App Tester opened")
			_popup.close()
		else:
			_fail("Не удалось открыть App Tester. Установи его и попробуй ещё раз.")
		return
	if _stage in [Stage.READY, Stage.PERMISSION, Stage.INSTALLING]:
		_install()
	elif _stage != Stage.DOWNLOADING:
		_begin_download()


func _open_tester() -> Error:
	return OS.shell_open(TESTER_URL)


func _begin_download() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_DIR)) != OK:
		_fail("Не удалось сохранить обновление. Освободи немного места и попробуй ещё раз.")
		return
	_path = "%s/TrashSquad-beta.%d.apk" % [UPDATE_DIR, int(_remote["code"])]
	if FileAccess.file_exists(_path) and _verified_file():
		_stage = Stage.READY
		_install()
		return
	_remove_file()
	_download.download_file = _path + ".part"
	_stage = Stage.DOWNLOADING
	_update.disabled = true
	_update.text = "СКАЧИВАЕМ…"
	_progress.value = 0
	_progress.visible = true
	_later.text = "ОТМЕНА"
	_status.text = "Скачиваем обновление — 0%"
	Platform.note_event("update download started")
	var error := _download.request(APK_URL + "?v=%d" % int(_remote["code"]))
	if error != OK:
		_fail("Не удалось начать загрузку. Проверь интернет и попробуй ещё раз.")


func _process(delta: float) -> void:
	if _stage != Stage.DOWNLOADING or not is_instance_valid(_popup):
		return
	_progress_clock -= delta
	if _progress_clock > 0.0:
		return
	_progress_clock = 0.2
	var total := int(_remote.get("bytes", _download.get_body_size()))
	var downloaded := _download.get_downloaded_bytes()
	var percent := mini(99, int(100.0 * downloaded / maxf(total, 1.0)))
	_progress.value = percent
	_status.text = "Скачиваем обновление — %d%%\n%.1f из %.1f МБ" % [percent, downloaded / 1048576.0, total / 1048576.0]


func _on_download(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _stage != Stage.DOWNLOADING or not is_instance_valid(_popup):
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Загрузка не завершилась. Проверь интернет и свободное место, затем попробуй ещё раз.")
		return
	_status.text = "Проверяем обновление…"
	_progress.value = 100
	var partial := _path + ".part"
	if FileAccess.get_sha256(partial).to_lower() != str(_remote["sha256"]).to_lower():
		_fail("Файл обновления не прошёл проверку. Скачай его ещё раз.")
		check()
		return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(partial), ProjectSettings.globalize_path(_path)) != OK:
		_fail("Не удалось сохранить обновление. Освободи место и попробуй ещё раз.")
		return
	_stage = Stage.READY
	Platform.note_event("update download verified")
	_install()


func _verified_file() -> bool:
	return FileAccess.get_sha256(_path).to_lower() == str(_remote.get("sha256", "")).to_lower()


func _install() -> void:
	if _native == null or not FileAccess.file_exists(_path) or not is_instance_valid(_popup):
		_fail("Обновление не найдено. Скачай его ещё раз.")
		return
	_update.disabled = false
	_later.text = "ПОЗЖЕ"
	if not bool(_native.call("can_install_packages")):
		_stage = Stage.PERMISSION
		_status.text = "Android просит один раз разрешить обновления от TrashSquad. Включи разрешение и вернись в игру."
		_update.text = "РАЗРЕШИТЬ ОБНОВЛЕНИЯ"
		if not bool(_native.call("request_install_permission")):
			_fail("Не удалось открыть разрешение Android. Попробуй ещё раз.")
		return
	SaveService.save_data()
	_stage = Stage.INSTALLING
	_update.disabled = true
	_status.text = "Открываем установку Android…"
	if not bool(_native.call("install_apk", ProjectSettings.globalize_path(_path), int(_remote["code"]))):
		_fail("Android не принял обновление. Скачай файл ещё раз.")


func _on_installer_opened() -> void:
	if not is_instance_valid(_popup):
		return
	_stage = Stage.READY
	_status.text = "Подтверди установку в окне Android. Если закрыл его — нажми «Установить» ещё раз."
	_update.text = "УСТАНОВИТЬ"
	_update.disabled = false


func _fail(message: String) -> void:
	_stage = Stage.ERROR
	_download.cancel_request()
	_remove_file(true)
	if is_instance_valid(_popup):
		_status.text = message
		_update.text = "ПОВТОРИТЬ"
		_update.disabled = false
		_progress.visible = false
		_later.text = "ПОЗЖЕ"


func _remove_file(partial_only: bool = false) -> void:
	if _path.is_empty():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + ".part"))
	if not partial_only:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _on_closed() -> void:
	if _stage == Stage.DOWNLOADING:
		_download.cancel_request()
		_remove_file(true)
	_stage = Stage.OFFER
	_popup = null
	get_tree().paused = _previous_pause


func _cleanup() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(UPDATE_DIR)):
		return
	for file in DirAccess.get_files_at(UPDATE_DIR):
		var name := file.trim_prefix("TrashSquad-beta.").trim_suffix(".apk")
		if file.ends_with(".part") or (file.begins_with("TrashSquad-beta.") and file.ends_with(".apk") and int(name) <= local_code()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(UPDATE_DIR.path_join(file)))
