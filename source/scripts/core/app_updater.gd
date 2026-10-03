class_name AppUpdater
extends Node
## Обновление тестовой сборки Android без Firebase-приложения: при запуске сравнивает свою версию
## (config/version = "beta.N", её ставит сборка на GitHub) с файлом версии последнего релиза на GitHub.
## Вышла новее — окно «ОБНОВИТЬ»: качается APK, Android предлагает установить поверх (прогресс сохраняется).
## Молча, без нажатия «Установить», Android ставить приложения не из магазина не разрешает.

const RELEASE := "https://github.com/rattyOLD/trashketeers-build/releases/download/android-beta/"
const VERSION_URL := RELEASE + "android-version.json"
const APK_URL := RELEASE + "TrashSquad.apk"
const FIRST_CHECK := 4.0

var _http: HTTPRequest
var _offered := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.max_redirects = 8
	_http.request_completed.connect(_on_version)
	add_child(_http)
	get_tree().create_timer(FIRST_CHECK).timeout.connect(check)


## Номер своей сборки: "beta.37" → 37; локальная/веб-сборка ("dev") не обновляется.
static func local_code() -> int:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return int(version.trim_prefix("beta.")) if version.begins_with("beta.") else -1


func check() -> void:
	if local_code() < 0:
		return
	_http.request(VERSION_URL + "?t=%d" % Time.get_unix_time_from_system())


func _on_version(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	var remote := int((data as Dictionary).get("code", 0))
	if remote <= local_code() or remote <= _offered:
		return
	_offered = remote
	Platform.note_event("update offered beta.%d" % remote)
	_show(str((data as Dictionary).get("name", "beta.%d" % remote)), str((data as Dictionary).get("notes", "")))


func _notification(what: int) -> void:
	# Вернулся в игру (свернул и развернул) — проверяем ещё раз: обнова могла выйти, пока играл.
	if what == NOTIFICATION_APPLICATION_RESUMED and _http != null:
		check()


func _show(name: String, notes: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var popup := GlassPopup.new("ОБНОВЛЕНИЕ")
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(popup)
	var text := "Вышла TrashSquad %s.\nОбнови, чтобы играть в свежую версию." % name
	if not notes.is_empty():
		text += "\n\n" + notes.left(200)
	var label := UiStyle.label(text, 22, UiStyle.TEXT, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(minf(GlassPopup.panel_width() - 60.0, 560.0), 0)
	popup.content.add_child(label)
	var update := UiStyle.button("ОБНОВИТЬ", UiStyle.GOLD, 30)
	update.pressed.connect(func() -> void:
		Platform.note_event("update accepted")
		OS.shell_open(APK_URL)
		popup.close())
	popup.content.add_child(update)
	var later := UiStyle.button("ПОЗЖЕ", UiStyle.TEXT_DIM, 24, Vector2(0, 64))
	later.pressed.connect(popup.close)
	popup.content.add_child(later)
	popup.closed.connect(layer.queue_free)
	popup.open()
