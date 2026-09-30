extends Node
## Autoload "Platform". Всё, что зависит от среды запуска (Web / Telegram WebView / десктоп),
## собрано здесь, чтобы игровой код не вызывал JavaScriptBridge напрямую.
## Каждый JS-вызов обёрнут в try/catch: в песочнице iframe localStorage и Telegram API могут бросать.
##
## Облако: Telegram CloudStorage (до 4096 символов на ключ) — сохранение режется на куски
## "<key>_0.._N" + счётчик "<key>_n". Ответ приходит асинхронно в JS-колбэк, который кладёт
## результат в window.__trash_cloud; здесь он опрашивается таймером — без хранения JS-колбэков
## на стороне GDScript (их легко потерять сборщиком мусора).

signal cloud_loaded(text: String)
signal back_pressed

const CLOUD_CHUNK := 3500
const CLOUD_POLL := 0.25
const CLOUD_TIMEOUT := 10.0
const AD_TIMEOUT := 45.0
const AD_SIMULATED_TIME := 1.2

var is_web := false
var is_telegram := false

var _cloud_wait := -1.0
var _cloud_poll := 0.0
var _back_callback: JavaScriptObject
var _back_visible := false
var _ad_wait := -1.0
var _ad_callback: Callable
var _ad_simulated := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_web = OS.has_feature("web")
	if not is_web:
		return
	is_telegram = _js_bool("!!(window.Telegram && window.Telegram.WebApp && window.Telegram.WebApp.initData)")
	if is_telegram:
		_js("Telegram.WebApp.ready(); Telegram.WebApp.expand(); if (Telegram.WebApp.disableVerticalSwipes) Telegram.WebApp.disableVerticalSwipes();")
		_back_callback = JavaScriptBridge.create_callback(_on_js_back)
		var webapp = JavaScriptBridge.get_interface("Telegram")
		if webapp != null:
			webapp.WebApp.BackButton.onClick(_back_callback)


func _process(delta: float) -> void:
	if _ad_wait >= 0.0:
		_poll_ad(delta)
	if _cloud_wait < 0.0:
		return
	_cloud_wait += delta
	_cloud_poll -= delta
	if _cloud_poll > 0.0:
		return
	_cloud_poll = CLOUD_POLL
	var state = _js("var r = window.__trash_cloud; return r ? JSON.stringify(r) : '';")
	if typeof(state) == TYPE_STRING and not (state as String).is_empty():
		_cloud_wait = -1.0
		var parsed = JSON.parse_string(state)
		var ok: bool = typeof(parsed) == TYPE_DICTIONARY and bool(parsed.get("ok", false))
		cloud_loaded.emit(str(parsed.get("text", "")) if ok else "")
	elif _cloud_wait > CLOUD_TIMEOUT:
		_cloud_wait = -1.0
		cloud_loaded.emit("")


# --- Локальное хранилище --------------------------------------------------------------------------

func storage_get(key: String) -> String:
	if is_web:
		var value = _js("return window.localStorage.getItem(%s);" % JSON.stringify(key))
		return value if typeof(value) == TYPE_STRING else ""
	var path := _file_path(key)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func storage_set(key: String, value: String) -> bool:
	if is_web:
		return _js_bool("window.localStorage.setItem(%s, %s); return true;" % [JSON.stringify(key), JSON.stringify(value)])
	var file := FileAccess.open(_file_path(key), FileAccess.WRITE)
	if file == null:
		push_error("Platform: не удалось записать %s (%s)" % [key, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(value)
	return true


# --- Облачное сохранение Telegram ------------------------------------------------------------------

func has_cloud() -> bool:
	return is_telegram and _js_bool("!!(Telegram.WebApp.CloudStorage && Telegram.WebApp.isVersionAtLeast && Telegram.WebApp.isVersionAtLeast('6.9'))")


func cloud_save(key: String, value: String) -> void:
	if not has_cloud():
		return
	var parts := PackedStringArray()
	var i := 0
	while i < value.length():
		parts.append(value.substr(i, CLOUD_CHUNK))
		i += CLOUD_CHUNK
	var body := "var cs = Telegram.WebApp.CloudStorage; var k = %s; var parts = %s;" % [JSON.stringify(key), JSON.stringify(Array(parts))]
	body += "for (var i = 0; i < parts.length; i++) cs.setItem(k + '_' + i, parts[i]);"
	body += "cs.setItem(k + '_n', String(parts.length));"
	_js(body)


## Результат придёт сигналом cloud_loaded (пустая строка — облака нет или ошибка).
func cloud_load(key: String) -> void:
	if not has_cloud():
		cloud_loaded.emit.call_deferred("")
		return
	var body := "window.__trash_cloud = null; var cs = Telegram.WebApp.CloudStorage; var k = %s;" % JSON.stringify(key)
	body += "cs.getItem(k + '_n', function (err, n) {"
	body += " if (err || !n) { window.__trash_cloud = {ok: false}; return; }"
	body += " var keys = []; for (var i = 0; i < parseInt(n, 10); i++) keys.push(k + '_' + i);"
	body += " cs.getItems(keys, function (err2, values) {"
	body += "  if (err2 || !values) { window.__trash_cloud = {ok: false}; return; }"
	body += "  var text = ''; for (var j = 0; j < keys.length; j++) text += values[keys[j]] || '';"
	body += "  window.__trash_cloud = {ok: true, text: text}; }); });"
	_js(body)
	_cloud_wait = 0.0
	_cloud_poll = CLOUD_POLL


# --- Графика ---------------------------------------------------------------------------------------

## Сенсорное устройство (телефон/планшет): для авто-качества графики.
func is_touch() -> bool:
	if is_web:
		return _js_bool("!!window.__trash_is_touch || ('ontouchstart' in window) || (navigator.maxTouchPoints || 0) > 0")
	return DisplayServer.is_touchscreen_available()


## Потолок плотности пикселей холста (web/render_scale.js): движок подхватывает его со следующего кадра.
func set_render_cap(cap: float) -> void:
	if is_web:
		_js("window.__trash_dpr_cap = %s;" % str(cap))


const BATTLE_FLAG := "__trash_battle"


## Флаг «бой идёт»: ставится на старте боя и снимается через несколько секунд стабильной работы
## или при выходе. Если при следующем запуске он остался — вкладку убила система (нехватка памяти).
func mark_battle(active: bool, info: String = "") -> void:
	if not is_web:
		return
	if active:
		_js("window.localStorage.setItem('%s', %s);" % [BATTLE_FLAG, JSON.stringify(info)])
	else:
		_js("window.localStorage.removeItem('%s');" % BATTLE_FLAG)


func consume_unclean_exit() -> String:
	if not is_web:
		return ""
	var value: Variant = _js("var v = window.localStorage.getItem('%s'); window.localStorage.removeItem('%s'); return v;" % [BATTLE_FLAG, BATTLE_FLAG])
	return "" if value == null else str(value)


func fullscreen_supported() -> bool:
	if not is_web:
		return true
	return _js_bool("!!(document.documentElement.requestFullscreen || document.documentElement.webkitRequestFullscreen)")


## В вебе запрос идёт напрямую из обработчика тапа: браузер разрешает полноэкранный режим только по жесту пользователя.
func set_fullscreen(on: bool) -> void:
	if is_web:
		if on:
			_js("var e = document.documentElement; var f = e.requestFullscreen || e.webkitRequestFullscreen; if (f) { var r = f.call(e, {navigationUI: 'hide'}); if (r && r.catch) r.catch(function () {}); }")
		else:
			_js("var f = document.exitFullscreen || document.webkitExitFullscreen; if (f) f.call(document);")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func is_fullscreen() -> bool:
	if is_web:
		return _js_bool("return !!(document.fullscreenElement || document.webkitFullscreenElement);")
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func set_context(text: String) -> void:
	if is_web:
		_js("window.localStorage.setItem('__trash_ctx', %s);" % JSON.stringify(text))


func last_context() -> String:
	if not is_web:
		return ""
	var value: Variant = _js("return window.localStorage.getItem('__trash_ctx');")
	return "" if value == null else str(value)


func device_info() -> String:
	if not is_web:
		return OS.get_name()
	return str(_js("return navigator.userAgent + ' | mem ' + (navigator.deviceMemory || '?') + 'GB | dpr ' + (window.__trash_real_dpr ? window.__trash_real_dpr() : window.devicePixelRatio);"))


func note_event(text: String) -> void:
	if is_web:
		_js("if (window.trkNote) { window.trkNote(%s); }" % JSON.stringify(text))


func send_report(kind: String, text: String, extra: String = "") -> void:
	if is_web:
		_js("if (window.trkReport) { window.trkReport(%s, %s, %s); }" % [JSON.stringify(kind), JSON.stringify(text), JSON.stringify(extra)])


func store_snapshot(base64_jpeg: String) -> void:
	if is_web:
		_js("window.localStorage.setItem('__trash_shot', %s);" % JSON.stringify(base64_jpeg))


## Последний снимок экрана перед вылетом; забирается один раз.
func take_snapshot() -> String:
	if not is_web:
		return ""
	var value: Variant = _js("var v = window.localStorage.getItem('__trash_shot'); window.localStorage.removeItem('__trash_shot'); return v;")
	return "" if value == null else str(value)


# --- Реклама за награду ---------------------------------------------------------------------------

## Показ рекламы за награду; callback(ok: bool) приходит один раз.
## Хостинг подключает SDK (например Adsgram) и кладёт в window.__trash_show_ad функцию,
## которая по окончании пишет в window.__trash_ad_result true/false. Без SDK (десктоп,
## тестовый билд) показ симулируется короткой задержкой — награда выдаётся.
func show_rewarded_ad(callback: Callable) -> void:
	if _ad_wait >= 0.0:
		callback.call(false)
		return
	_ad_callback = callback
	_ad_wait = 0.0
	_ad_simulated = not (is_web and _js_bool("typeof window.__trash_show_ad === 'function'"))
	if not _ad_simulated:
		_js("window.__trash_ad_result = null; window.__trash_show_ad();")


## Межстраничная реклама (не за награду): SDK кладёт window.__trash_show_interstitial и по окончании
## пишет window.__trash_ad_result. Без SDK ничего не показывается, callback вызывается сразу.
func show_interstitial(callback: Callable) -> void:
	var has_sdk := is_web and _ad_wait < 0.0 and _js_bool("typeof window.__trash_show_interstitial === 'function'")
	if Premium.ads_removed() or not has_sdk:
		callback.call()
		return
	_ad_callback = func(_ok: bool) -> void: callback.call()
	_ad_wait = 0.0
	_ad_simulated = false
	_js("window.__trash_ad_result = null; window.__trash_show_interstitial();")


func is_ad_showing() -> bool:
	return _ad_wait >= 0.0


func _poll_ad(delta: float) -> void:
	_ad_wait += delta
	if _ad_simulated:
		if _ad_wait >= AD_SIMULATED_TIME:
			_finish_ad(true)
		return
	var state = _js("var r = window.__trash_ad_result; return r === true ? 1 : (r === false ? 0 : -1);")
	if (typeof(state) == TYPE_INT or typeof(state) == TYPE_FLOAT) and state >= 0:
		_finish_ad(state > 0)
	elif _ad_wait > AD_TIMEOUT:
		_finish_ad(false)


func _finish_ad(ok: bool) -> void:
	_ad_wait = -1.0
	var callback := _ad_callback
	_ad_callback = Callable()
	if callback.is_valid():
		callback.call(ok)


# --- Тактильный отклик -----------------------------------------------------------------------------

## style: "light" | "medium" | "heavy" | "rigid" | "soft". Вне Telegram — короткая вибрация (Android).
func haptic(style: String = "light") -> void:
	if is_telegram:
		_js("Telegram.WebApp.HapticFeedback.impactOccurred(%s);" % JSON.stringify(style))
	elif is_web:
		var ms: int = {"light": 8, "soft": 8, "medium": 14, "rigid": 14, "heavy": 24}.get(style, 10)
		_js("if (navigator.vibrate) navigator.vibrate(%d);" % ms)


## kind: "success" | "warning" | "error".
func haptic_notify(kind: String) -> void:
	if is_telegram:
		_js("Telegram.WebApp.HapticFeedback.notificationOccurred(%s);" % JSON.stringify(kind))
	elif is_web:
		_js("if (navigator.vibrate) navigator.vibrate(%s);" % ("[30, 40, 30]" if kind == "error" else "18"))


func haptic_select() -> void:
	if is_telegram:
		_js("Telegram.WebApp.HapticFeedback.selectionChanged();")


# --- Тема, пользователь, шаринг --------------------------------------------------------------------

## "dark" | "light": тема Telegram, вне его — системная тема браузера.
func color_scheme() -> String:
	if not is_web:
		return "dark"
	var scheme = _js("if (window.Telegram && Telegram.WebApp && Telegram.WebApp.initData) return Telegram.WebApp.colorScheme; return (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';")
	return "light" if scheme == "light" else "dark"


## Цвет из Telegram.WebApp.themeParams (bg_color, text_color, button_color, ...) или fallback.
func theme_color(key: String, fallback: Color) -> Color:
	if not is_telegram:
		return fallback
	var value = _js("return Telegram.WebApp.themeParams[%s] || '';" % JSON.stringify(key))
	if typeof(value) == TYPE_STRING and Color.html_is_valid(value):
		return Color.html(value)
	return fallback


func set_header_color(color: Color) -> void:
	if is_telegram:
		var hex := "#" + color.to_html(false)
		_js("if (Telegram.WebApp.setHeaderColor) Telegram.WebApp.setHeaderColor(%s); if (Telegram.WebApp.setBackgroundColor) Telegram.WebApp.setBackgroundColor(%s);" % [JSON.stringify(hex), JSON.stringify(hex)])


func user_first_name() -> String:
	if not is_telegram:
		return ""
	var value = _js("var u = Telegram.WebApp.initDataUnsafe && Telegram.WebApp.initDataUnsafe.user; return u ? (u.first_name || u.username || '') : '';")
	return value if typeof(value) == TYPE_STRING else ""


func user_id() -> String:
	if not is_telegram:
		return ""
	var value = _js("var u = Telegram.WebApp.initDataUnsafe && Telegram.WebApp.initDataUnsafe.user; return u ? String(u.id) : '';")
	return value if typeof(value) == TYPE_STRING else ""


## Параметр запуска Mini App (t.me/bot/app?startapp=...) — здесь приходят реферальные коды.
func start_param() -> String:
	if not is_telegram:
		return ""
	var value = _js("return (Telegram.WebApp.initDataUnsafe && Telegram.WebApp.initDataUnsafe.start_param) || '';")
	return value if typeof(value) == TYPE_STRING else ""


## Ссылка-приглашение: bot_link из data/platform.json + startapp=ref_<id>;
## если бот ещё не настроен — адрес текущей страницы.
func invite_link() -> String:
	var bot_link := str(ConfigLoader.load_json("res://data/platform.json").get("bot_link", ""))
	if not bot_link.is_empty():
		var uid := user_id()
		return bot_link + ("?startapp=ref_%s" % uid if not uid.is_empty() else "")
	if is_web:
		var href = _js("return String(location.href).split('#')[0];")
		if typeof(href) == TYPE_STRING:
			return href
	return ""


## Telegram: нативное окно «Поделиться»; браузер: navigator.share или копирование в буфер.
## Возвращает текст-подсказку для тоста.
func share(text: String, url: String) -> String:
	if is_telegram:
		var link := "https://t.me/share/url?url=%s&text=%s" % [url.uri_encode(), text.uri_encode()]
		_js("Telegram.WebApp.openTelegramLink(%s);" % JSON.stringify(link))
		return "Выбери друзей в Telegram"
	if is_web:
		var mode = _js("if (navigator.share) { navigator.share({title: 'Игровая Сетка', text: %s, url: %s}).catch(function(){}); return 'share'; } if (navigator.clipboard) { navigator.clipboard.writeText(%s + ' ' + %s); return 'copy'; } return '';" % [JSON.stringify(text), JSON.stringify(url), JSON.stringify(text), JSON.stringify(url)])
		if mode == "copy":
			return "Ссылка скопирована"
		if mode == "share":
			return "Выбери, куда отправить"
	DisplayServer.clipboard_set(text + " " + url)
	return "Ссылка скопирована"


## Нативная кнопка «Назад» Telegram в шапке; нажатие — сигнал back_pressed.
func set_back_button(visible: bool) -> void:
	if not is_telegram or visible == _back_visible:
		return
	_back_visible = visible
	_js("Telegram.WebApp.BackButton.%s();" % ("show" if visible else "hide"))


func _on_js_back(_args: Array) -> void:
	back_pressed.emit()


func _js(body: String) -> Variant:
	return JavaScriptBridge.eval("(function(){ try { %s } catch (e) { return null; } })()" % body, true)


## JavaScriptBridge.eval в глобальном контексте отдаёт JS-булевы как числа (1/0), а сравнение
## int == bool в GDScript — ошибка выполнения (функция молча возвращала null). Приводим явно.
func _js_bool(body_or_expr: String) -> bool:
	var body := body_or_expr if body_or_expr.contains("return") else "return %s;" % body_or_expr
	var value: Variant = _js(body)
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
	return false


func _file_path(key: String) -> String:
	return "user://%s.json" % key.validate_filename()
