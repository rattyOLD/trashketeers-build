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
## Приложение на телефоне (не редактор): отчёты шлёт NativeTelemetry.
var is_native_app := false
var telemetry: NativeTelemetry
var is_telegram := false

var _cloud_wait := -1.0
var _cloud_poll := 0.0
var _back_callback: JavaScriptObject
var _back_visible := false
var _ad_wait := -1.0
var _ad_callback: Callable
var _ad_simulated := false


## Прокрутка списков пальцем не должна нажимать кнопки: если палец уехал дальше SCROLL_SLOP,
## кнопка под ним внутри ScrollContainer отпускается без нажатия (жалоба тестеров: «тапаются опции, когда скролишь»).
const SCROLL_SLOP := 14.0
var _touch_from := Vector2.INF
var _touch_moved := false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_touch_from = touch.position if touch.pressed else Vector2.INF
		if touch.pressed:
			_touch_moved = false
	elif event is InputEventScreenDrag and not _touch_moved and _touch_from != Vector2.INF:
		if (event as InputEventScreenDrag).position.distance_to(_touch_from) > SCROLL_SLOP:
			_touch_moved = true
			_cancel_scroll_press()


## Текущее (или только что отпущенное) касание уехало дальше SCROLL_SLOP — это прокрутка, не тап.
func touch_moved() -> bool:
	return _touch_moved


func _cancel_scroll_press() -> void:
	var viewport := get_viewport()
	if viewport == null or not viewport.has_method("gui_get_hovered_control"):
		return
	var node: Node = viewport.call("gui_get_hovered_control")
	var button: BaseButton = null
	while node != null:
		if button == null and node is BaseButton:
			button = node as BaseButton
		if node is ScrollContainer:
			if button != null and not button.disabled:
				button.disabled = true
				button.set_deferred("disabled", false)
				# Отмена нажатия не присылает button_up — утопленную кнопку возвращаем сами.
				var press: Variant = button.get_meta(&"press_tween") if button.has_meta(&"press_tween") else null
				if press is Tween and (press as Tween).is_valid():
					(press as Tween).kill()
				button.scale = Vector2.ONE
			return
		node = node.get_parent()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_web = OS.has_feature("web")
	is_native_app = OS.has_feature("mobile") and not OS.has_feature("editor")
	if is_native_app:
		telemetry = NativeTelemetry.new()
		add_child.call_deferred(telemetry)
		add_child.call_deferred(AppUpdater.new())
	if not is_web:
		return
	_js("if (navigator.storage && navigator.storage.persist) { navigator.storage.persist(); } return true;")
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
## iPhone/iPad в браузере (iPadOS притворяется Маком, выдаёт его сенсор).
func is_ios() -> bool:
	if _ios < 0:
		_ios = 1 if is_web and _js_bool("/iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && (navigator.maxTouchPoints || 0) > 1)") else 0
	return _ios == 1


var _ios := -1
var _touch := -1
var _a13 := -1
var native_render_scale := 1.0


func is_galaxy_a13() -> bool:
	if _a13 < 0:
		var model := OS.get_model_name() if is_native_app else ""
		if is_web:
			var ua: Variant = _js("return navigator.userAgent;")
			var re := RegEx.new()
			re.compile("(?i)SM-A13[567][A-Z0-9/]*")
			var match_model := re.search(str(ua))
			model = match_model.get_string() if match_model != null else ""
		_a13 = 1 if DevicePerformance.is_galaxy_a13(model) else 0
	return _a13 == 1


func is_touch() -> bool:
	if _touch < 0:
		_touch = 1 if (is_native_app or (_js_bool("!!window.__trash_is_touch || ('ontouchstart' in window) || (navigator.maxTouchPoints || 0) > 0") if is_web else DisplayServer.is_touchscreen_available())) else 0
	return _touch == 1


## Потолок плотности пикселей холста (web/render_scale.js): движок подхватывает его со следующего кадра.
func set_render_cap(cap: float) -> void:
	if is_web:
		_js("window.__trash_dpr_cap = %s;" % str(cap))
	elif is_native_app and is_inside_tree():
		native_render_scale = DevicePerformance.native_render_scale(cap)
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		Orient.refresh(get_tree().root)


const BATTLE_FLAG := "__trash_battle"


## Флаг «бой идёт»: ставится на старте боя и снимается через несколько секунд стабильной работы
## или при выходе. Если при следующем запуске он остался — вкладку убила система (нехватка памяти).
func mark_battle(active: bool, info: String = "") -> void:
	if is_native_app:
		storage_set(BATTLE_FLAG, info if active else "")
		return
	if not is_web:
		return
	if active:
		_js("window.localStorage.setItem('%s', %s);" % [BATTLE_FLAG, JSON.stringify(info)])
	else:
		_js("window.localStorage.removeItem('%s');" % BATTLE_FLAG)


func consume_unclean_exit() -> String:
	if is_native_app:
		var flag := storage_get(BATTLE_FLAG)
		storage_set(BATTLE_FLAG, "")
		return flag
	if not is_web:
		return ""
	var value: Variant = _js("var v = window.localStorage.getItem('%s'); window.localStorage.removeItem('%s'); return v;" % [BATTLE_FLAG, BATTLE_FLAG])
	return "" if value == null else str(value)


func build_label() -> String:
	if is_native_app and telemetry != null:
		return telemetry.build_label()
	if not is_web:
		return "редактор"
	var value: Variant = _js("return window.__trash_build ? window.__trash_build.label + ' · ' + window.__trash_build.time : '';")
	return "" if value == null else str(value)


func fullscreen_supported() -> bool:
	if not is_web:
		return true
	return _js_bool("!!(document.documentElement.requestFullscreen || document.documentElement.webkitRequestFullscreen)")


## В вебе запрос идёт напрямую из обработчика тапа: браузер разрешает полноэкранный режим только по жесту пользователя.
func set_fullscreen(on: bool) -> void:
	if is_web:
		if on:
			_js("var e = document.documentElement; var f = e.requestFullscreen || e.webkitRequestFullscreen; if (f) { var r = f.call(e, {navigationUI: 'hide'}); if (r && r.then) { r.then(function () { try { screen.orientation.lock('landscape').catch(function () {}); } catch (x) {} }).catch(function () {}); } }")
		else:
			_js("var f = document.exitFullscreen || document.webkitExitFullscreen; if (f) f.call(document);")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func can_install() -> bool:
	return is_web and _js_bool("return !!window.__trash_install_evt;")


func is_standalone() -> bool:
	return is_web and _js_bool("return !!(window.matchMedia('(display-mode: standalone)').matches || window.matchMedia('(display-mode: fullscreen)').matches || navigator.standalone);")


func install_app() -> void:
	if is_web:
		_js("if (window.__trash_install) window.__trash_install();")


func is_fullscreen() -> bool:
	if is_web:
		return _js_bool("return !!(document.fullscreenElement || document.webkitFullscreenElement);")
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func set_context(text: String) -> void:
	if telemetry != null:
		telemetry.set_context(text)
	if is_web:
		_js("window.localStorage.setItem('__trash_ctx', %s);" % JSON.stringify(text))


## Идёт бой: плашку «Вышла новая версия» прячем, иначе она закрывает шапку боя и случайный тап перезагрузит страницу посреди забега.
func set_in_battle(on: bool) -> void:
	if is_web:
		_js("window.__trkBattle = %s; if (window.__trkUpdateUi) { window.__trkUpdateUi(); } if (!%s && window.__trkCheck) { window.__trkCheck(); }" % ["true" if on else "false", "true" if on else "false"])


## Хлебные крошки для отчётов об ошибках: последние 20 действий (экран, окно, запрос к серверу).
func trail(text: String) -> void:
	if telemetry != null:
		telemetry.trail(text)
	if is_web:
		_js("var t = window.__trash_trail = window.__trash_trail || []; t.push(%s); if (t.length > 20) { t.shift(); }" % JSON.stringify("%ds %s" % [Time.get_ticks_msec() / 1000, text.left(80)]))


func last_context() -> String:
	if telemetry != null:
		return telemetry.last_context()
	if not is_web:
		return ""
	var value: Variant = _js("return window.localStorage.getItem('__trash_ctx');")
	return "" if value == null else str(value)


func device_info() -> String:
	if telemetry != null:
		return telemetry.device_info()
	if not is_web:
		return OS.get_name()
	return str(_js("return navigator.userAgent + ' | mem ' + (navigator.deviceMemory || '?') + 'GB | dpr ' + (window.__trash_real_dpr ? window.__trash_real_dpr() : window.devicePixelRatio);"))


func note_event(text: String) -> void:
	if telemetry != null:
		telemetry.note(text)
	if is_web:
		_js("if (window.trkNote) { window.trkNote(%s); }" % JSON.stringify(text))


func send_report(kind: String, text: String, extra: String = "") -> void:
	if telemetry != null:
		telemetry.report(kind, text, extra)
	if is_web:
		_js("if (window.trkReport) { window.trkReport(%s, %s, %s); }" % [JSON.stringify(kind), JSON.stringify(text), JSON.stringify(extra)])


func store_snapshot(base64_jpeg: String) -> void:
	if is_native_app:
		storage_set("__trash_shot", base64_jpeg)
	if is_web:
		_js("window.localStorage.setItem('__trash_shot', %s);" % JSON.stringify(base64_jpeg))


## Последний снимок экрана перед вылетом; забирается один раз.
func take_snapshot() -> String:
	if is_native_app:
		var shot := storage_get("__trash_shot")
		storage_set("__trash_shot", "")
		return shot
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
	if not bool(SaveService.data.get("haptics", true)):
		return
	if is_telegram:
		_js("Telegram.WebApp.HapticFeedback.impactOccurred(%s);" % JSON.stringify(style))
	else:
		var ms: int = {"light": 8, "soft": 8, "medium": 14, "rigid": 14, "heavy": 24}.get(style, 10)
		if is_web:
			_js("if (navigator.vibrate) navigator.vibrate(%d);" % ms)
		elif OS.has_feature("mobile"):
			Input.vibrate_handheld(ms * 2)


## kind: "success" | "warning" | "error".
func haptic_notify(kind: String) -> void:
	if not bool(SaveService.data.get("haptics", true)):
		return
	if is_telegram:
		_js("Telegram.WebApp.HapticFeedback.notificationOccurred(%s);" % JSON.stringify(kind))
	elif is_web:
		_js("if (navigator.vibrate) navigator.vibrate(%s);" % ("[30, 40, 30]" if kind == "error" else "18"))


func haptic_select() -> void:
	if not bool(SaveService.data.get("haptics", true)):
		return
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


## Адрес страницы игры без параметров и якоря.
func page_url() -> String:
	if not is_web:
		return ""
	var href = _js("return location.origin + location.pathname;")
	return str(href) if typeof(href) == TYPE_STRING else ""


## Значение параметра адреса (?name=...); после чтения параметр убирается из адреса.
func consume_url_param(key: String) -> String:
	if not is_web:
		return ""
	var value = _js("var p = new URLSearchParams(location.search); var v = p.get(%s); if (v !== null) { p.delete(%s); var q = p.toString(); history.replaceState(null, '', location.pathname + (q ? '?' + q : '') + location.hash); } return v || '';" % [JSON.stringify(key), JSON.stringify(key)])
	return str(value) if typeof(value) == TYPE_STRING else ""


## Перезагрузка страницы без ?restore= в адресе (иначе мини-апка вернёт прежний аккаунт).
func reload_clean() -> void:
	_js("history.replaceState(null, '', location.pathname); location.reload(); return true;")


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


## Отправка картинки (PNG в base64): меню «Поделиться» с файлом, иначе скачивание. Вызывать из обработчика нажатия.
func share_image(base64_png: String, file_name: String, text: String) -> String:
	if not is_web or base64_png.is_empty():
		return ""
	var body := "var b = atob(%s); var a = new Uint8Array(b.length); for (var i = 0; i < b.length; i++) a[i] = b.charCodeAt(i);" % JSON.stringify(base64_png)
	body += " var f = new File([a], %s, {type: 'image/png'});" % JSON.stringify(file_name)
	body += " if (navigator.canShare && navigator.canShare({files: [f]})) { navigator.share({files: [f], text: %s}).catch(function(){}); return 'share'; }" % JSON.stringify(text)
	body += " var u = URL.createObjectURL(f); var l = document.createElement('a'); l.href = u; l.download = %s; document.body.appendChild(l); l.click(); document.body.removeChild(l); setTimeout(function(){ URL.revokeObjectURL(u); }, 4000); return 'save';" % JSON.stringify(file_name)
	var mode: Variant = _js(body)
	if mode == "share":
		return "Выбери, куда отправить"
	if mode == "save":
		return "Визитка сохранена в загрузки"
	return ""


## Нативная кнопка «Назад» Telegram в шапке; нажатие — сигнал back_pressed.
func set_back_button(visible: bool) -> void:
	if not is_telegram or visible == _back_visible:
		return
	_back_visible = visible
	_js("Telegram.WebApp.BackButton.%s();" % ("show" if visible else "hide"))


func _on_js_back(_args: Array) -> void:
	back_pressed.emit()


## Настоящее поле ввода браузера поверх игрового (id — любое имя). На телефоне игрок тапает прямо в него,
## поэтому клавиатура открывается сама, текст печатается на месте, работают автозамена, вставка и эмодзи.
## rect — прямоугольник поля в координатах окна игры.
func native_input_show(id: String, rect: Rect2, placeholder: String, secret: bool, max_length: int, font_px: float, dark: bool = false) -> void:
	if not is_web:
		return
	var view := get_viewport().get_visible_rect().size
	_js("""
var c = document.getElementById('canvas') || document.querySelector('canvas'); if (!c) return;
var r = c.getBoundingClientRect(); var k = r.width / %f;
var id = 'trk_in_' + %s; var el = document.getElementById(id);
if (!el) {
  el = document.createElement('input'); el.id = id; el.autocomplete = 'off'; el.setAttribute('autocapitalize', 'sentences');
  el.style.cssText = 'position:fixed;z-index:20;box-sizing:border-box;border:0;outline:0;background:transparent;color:#0c1d29;padding:0 14px;font-family:system-ui,-apple-system,sans-serif;-webkit-appearance:none;border-radius:16px';
  el.addEventListener('keydown', function (e) { if (e.key === 'Enter') { el.dataset.enter = '1'; e.preventDefault(); } });
  el.addEventListener('input', function () { el.dataset.changed = '1'; });
  var dock = function () { var v = window.visualViewport; document.documentElement.style.setProperty('--trk-vt', (v ? v.offsetTop : 0) + 'px'); };
  el.addEventListener('focus', function () { dock(); el.classList.add('trk_docked'); if (window.visualViewport) { window.visualViewport.addEventListener('scroll', dock); window.visualViewport.addEventListener('resize', dock); } });
  el.addEventListener('blur', function () { el.classList.remove('trk_docked'); if (window.visualViewport) { window.visualViewport.removeEventListener('scroll', dock); window.visualViewport.removeEventListener('resize', dock); } });
  document.body.appendChild(el);
}
el.type = %s; el.placeholder = %s; el.maxLength = %d; el.style.color = %s; el.style.caretColor = '#ff2ea6'; el.classList.toggle('trk_dark', %s);
el.dataset.vw = %f; el.dataset.gx = %f; el.dataset.gy = %f; el.dataset.gw = %f; el.dataset.gh = %f;
el.style.left = (r.left + %f * k) + 'px'; el.style.top = (r.top + %f * k) + 'px';
el.style.width = (%f * k) + 'px'; el.style.height = (%f * k) + 'px';
el.style.fontSize = Math.max(16, %f * k) + 'px'; el.style.display = 'block';
if (!document.getElementById('trk_in_css')) { var st = document.createElement('style'); st.id = 'trk_in_css'; st.textContent = 'input[id^=trk_in_]{font-family:"Russo One",system-ui,sans-serif !important;letter-spacing:.5px} input[id^=trk_in_]::placeholder{font-size:0.72em;color:#9a8266;opacity:1} input.trk_docked{left:12px !important;right:12px !important;width:auto !important;top:calc(var(--trk-vt,0px) + 14px) !important;height:62px !important;font-size:22px !important;background:#17120e !important;color:#ffe9cf !important;border:3px solid #ff8a3d !important;border-radius:16px !important;box-shadow:0 6px 24px rgba(0,0,0,.65),0 0 18px rgba(255,138,61,.35);z-index:40 !important}'; document.head.appendChild(st); }
""" % [view.x, JSON.stringify(id), JSON.stringify("password" if secret else "text"), JSON.stringify(placeholder), max_length if max_length > 0 else 500,
		JSON.stringify("#ffe9cf"), "true" if dark else "false",
		view.x, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		rect.position.x, rect.position.y, rect.size.x, rect.size.y, font_px])


## Состояние поля: {"text", "enter" (нажали Enter), "changed" (печатали с прошлого опроса), "focused"}.
func native_input_poll(id: String) -> Dictionary:
	if not is_web:
		return {}
	var raw: Variant = _js("""
var el = document.getElementById('trk_in_' + %s); if (!el) return '';
var out = JSON.stringify({text: el.value, enter: el.dataset.enter === '1', changed: el.dataset.changed === '1', focused: document.activeElement === el});
el.dataset.enter = ''; el.dataset.changed = ''; return out;
""" % JSON.stringify(id))
	var parsed: Variant = JSON.parse_string(str(raw)) if raw is String and not str(raw).is_empty() else null
	return parsed as Dictionary if parsed is Dictionary else {}


## Сколько логических пикселей холста закрыла экранная клавиатура (iOS не меняет размер страницы, а сужает «видимое окно»).
## Пока открыто браузерное поле, страница в шаблоне сдвигает холст за видимой областью, поэтому закрыт всегда низ.
func keyboard_inset() -> float:
	if not is_web:
		return 0.0
	var view := get_viewport().get_visible_rect().size
	var value: Variant = _js("""
var vv = window.visualViewport; var c = document.getElementById('canvas') || document.querySelector('canvas'); if (!vv || !c) return 0;
var h = c.getBoundingClientRect().height; if (h <= 0) return 0;
var hidden = Math.max(0, h - vv.height);
return hidden / h * %f;
""" % view.y)
	return maxf(0.0, float(value)) if value is float or value is int else 0.0


## Сейчас печатают в браузерном поле (открыта экранная клавиатура).
func native_input_active() -> bool:
	return is_web and _js_bool("!!(document.activeElement && String(document.activeElement.id).indexOf('trk_in_') === 0)")


func native_input_set(id: String, text: String) -> void:
	if is_web:
		_js("var el = document.getElementById('trk_in_' + %s); if (el) { el.value = %s; }" % [JSON.stringify(id), JSON.stringify(text)])


func native_input_hide(id: String) -> void:
	if is_web:
		_js("var el = document.getElementById('trk_in_' + %s); if (el) { el.blur(); el.remove(); }" % JSON.stringify(id))


## Выбор файла с телефона/компьютера. Вызывать из нажатия кнопки. Результат забирать pick_file_result():
## null — ещё выбирают; {} — отменили; {"name", "type", "size", "data" (base64)} — файл.
func pick_file(accept: String, max_bytes: int) -> void:
	if OS.get_name() == "Android":
		_android_pick_file(max_bytes)
		return
	if not is_web:
		return
	_js("""
window.__trash_pick = null;
var inp = document.createElement('input'); inp.type = 'file'; inp.accept = %s; inp.style.display = 'none';
document.body.appendChild(inp);
inp.addEventListener('change', function () {
  var f = inp.files && inp.files[0]; inp.remove();
  if (!f) { window.__trash_pick = {}; return; }
  if (f.size > %d) { window.__trash_pick = {name: f.name, type: f.type, size: f.size, too_big: true}; return; }
  var rd = new FileReader();
  rd.onload = function () {
    var s = String(rd.result);
    var raw = {name: f.name, type: f.type, size: f.size, data: s.slice(s.indexOf(',') + 1)};
    if (String(f.type).indexOf('image/') !== 0) { window.__trash_pick = raw; return; }
    // Фото уменьшаем в браузере: он умеет HEIC с iPhone, а большие снимки не раздувают память игры.
    var img = new Image();
    img.onload = function () {
      try {
        var k = Math.min(1, 640 / Math.max(img.naturalWidth, img.naturalHeight, 1));
        var cv = document.createElement('canvas'); cv.width = Math.max(1, Math.round(img.naturalWidth * k)); cv.height = Math.max(1, Math.round(img.naturalHeight * k));
        cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
        var out = cv.toDataURL('image/jpeg', 0.9);
        window.__trash_pick = {name: f.name, type: 'image/jpeg', size: f.size, data: out.slice(out.indexOf(',') + 1)};
      } catch (e) { window.__trash_pick = raw; }
    };
    img.onerror = function () { window.__trash_pick = raw; };
    img.src = s;
  };
  rd.onerror = function () { window.__trash_pick = {}; };
  rd.readAsDataURL(f);
});
window.addEventListener('focus', function once() { window.removeEventListener('focus', once); setTimeout(function () { if (window.__trash_pick === null && !(inp.files && inp.files.length)) { window.__trash_pick = {}; } }, 1500); });
inp.click();
""" % [JSON.stringify(accept), max_bytes])


func pick_file_result() -> Variant:
	if OS.get_name() == "Android":
		var result: Variant = _android_pick
		if result != null:
			_android_pick = null
		return result
	if not is_web:
		return {}
	var raw: Variant = _js("var p = window.__trash_pick; if (p === null || p === undefined) return ''; window.__trash_pick = undefined; return JSON.stringify(p);")
	if not raw is String or str(raw).is_empty():
		return null
	var parsed: Variant = JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {}


var _android_pick: Variant = {}
var _android_pick_max := 0


## APK: системный выбор фото. Файл читается по пути, поэтому нужен доступ к фото (Android 13+ — READ_MEDIA_IMAGES).
func _android_pick_file(max_bytes: int) -> void:
	_android_pick_max = max_bytes
	var permission := "android.permission.READ_MEDIA_IMAGES" if int(OS.get_version().split(".")[0]) >= 13 else "android.permission.READ_EXTERNAL_STORAGE"
	if not OS.request_permission(permission):
		_android_pick = {"need_permission": true}
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_android_pick = {}
		return
	_android_pick = null
	var err := DisplayServer.file_dialog_show("Фото", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.jpg", "*.jpeg", "*.png", "*.webp"]), _on_android_picked)
	if err != OK:
		_android_pick = {}


func _on_android_picked(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if not status or paths.is_empty():
		_android_pick = {}
		return
	var path := paths[0]
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_android_pick = {"need_permission": true}
		return
	var ext := path.get_extension().to_lower()
	if bytes.size() > _android_pick_max:
		_android_pick = {"name": path.get_file(), "too_big": true}
		return
	_android_pick = {"name": path.get_file(), "type": "image/" + ("jpeg" if ext in ["jpg", "jpeg"] else ext),
		"size": bytes.size(), "data": Marshalls.raw_to_base64(bytes)}


## Открыть ссылку (файл из чата) в новой вкладке. Вызывать из нажатия кнопки.
func open_url(url: String) -> void:
	if is_web:
		_js("window.open(%s, '_blank');" % JSON.stringify(url))
	else:
		OS.shell_open(url)


## Системный диалог ввода браузера (единственный надёжный способ открыть клавиатуру на iOS); null — отмена.
func prompt_text(title: String, current: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return _js("return window.prompt(%s, %s);" % [JSON.stringify(title), JSON.stringify(current)])


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
