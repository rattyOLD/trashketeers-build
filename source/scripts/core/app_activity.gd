extends Node
## Сворачивание APK и скрытая вкладка: бой остаётся на паузе, служебные узлы и рендер засыпают.

signal backgrounding

const BACKGROUND_FPS := 5

var backgrounded := false
var _native_paused := false
var _native_unfocused := false
var _page_hidden := false
var _was_paused := false
var _foreground_fps := 60
var _render_loop := true
var _suspended: Dictionary = {}
var _document: JavaScriptObject
var _window: JavaScriptObject
var _visibility_callback: JavaScriptObject
var _hide_callback: JavaScriptObject
var _show_callback: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	get_tree().node_added.connect(_on_node_added)
	if not Platform.is_web:
		return
	_document = JavaScriptBridge.get_interface("document")
	_window = JavaScriptBridge.get_interface("window")
	if _document == null or _window == null:
		return
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility)
	_hide_callback = JavaScriptBridge.create_callback(_on_pagehide)
	_show_callback = JavaScriptBridge.create_callback(_on_pageshow)
	_document.addEventListener("visibilitychange", _visibility_callback)
	_window.addEventListener("trashorientationchange", _visibility_callback)
	_window.addEventListener("pagehide", _hide_callback)
	_window.addEventListener("pageshow", _show_callback)
	_sync_web.call_deferred()


func _notification(what: int) -> void:
	if not Platform.is_native_app:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_native_paused = true
		NOTIFICATION_APPLICATION_RESUMED:
			_native_paused = false
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_native_unfocused = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_native_unfocused = false
		_:
			return
	_set_backgrounded(_native_paused or _native_unfocused)


func _on_visibility(_args: Array) -> void:
	_sync_web()


func _on_pagehide(_args: Array) -> void:
	_page_hidden = true
	_sync_web()


func _on_pageshow(_args: Array) -> void:
	_page_hidden = false
	_sync_web()


func _sync_web() -> void:
	_set_backgrounded(_page_hidden or bool(_document.hidden) or bool(_window.__trash_landscape_blocked))


func _set_backgrounded(value: bool) -> void:
	if value == backgrounded:
		return
	backgrounded = value
	Platform.trail("приложение фон" if value else "приложение активно")
	if value:
		# Сначала обычное окно паузы боя; уже открытый level-up/результат остаётся на месте.
		backgrounding.emit()
		_was_paused = get_tree().paused
		get_tree().paused = true
		for action in InputMap.get_actions():
			Input.action_release(action)
		SaveService.save_data()
		_foreground_fps = Engine.max_fps
		_render_loop = RenderingServer.is_render_loop_enabled()
		SoundManager.set_backgrounded(true)
		_suspend_branch(get_tree().root)
		RenderingServer.set_render_loop_enabled(false)
		Engine.max_fps = BACKGROUND_FPS
		set_process(true)
	else:
		set_process(false)
		for entry: Dictionary in _suspended.values():
			var node: Node = (entry["node"] as WeakRef).get_ref() as Node
			if is_instance_valid(node) and node.is_inside_tree():
				node.process_mode = int(entry["mode"])
		_suspended.clear()
		get_tree().paused = _was_paused
		Engine.max_fps = _foreground_fps
		RenderingServer.set_render_loop_enabled(_render_loop)
		SoundManager.set_backgrounded(false)


func _process(_delta: float) -> void:
	# Отложенный переход/ответ сети не должен снова включать бой в скрытой вкладке.
	if not get_tree().paused:
		backgrounding.emit()
		_was_paused = get_tree().paused
		get_tree().paused = true
	Engine.max_fps = BACKGROUND_FPS


func _suspend_branch(node: Node) -> void:
	_suspend_node(node)
	for child in node.get_children():
		_suspend_branch(child)


func _suspend_node(node: Node) -> void:
	if node == self or node.process_mode not in [Node.PROCESS_MODE_ALWAYS, Node.PROCESS_MODE_WHEN_PAUSED]:
		return
	var id := node.get_instance_id()
	if not _suspended.has(id):
		_suspended[id] = {"node": weakref(node), "mode": node.process_mode}
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _on_node_added(node: Node) -> void:
	if backgrounded:
		_suspend_added.call_deferred(weakref(node))


func _suspend_added(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if backgrounded and is_instance_valid(node) and node.is_inside_tree():
		_suspend_node(node)
