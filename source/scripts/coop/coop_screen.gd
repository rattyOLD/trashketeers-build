class_name CoopScreen
extends Control
## Экран коопа «Выживание на двоих»: меню (тренировка с ботом, комната на сервере), лобби комнаты, бой и итоги.
## Тренировка работает целиком на устройстве (арена считается локально, второй игрок бот), сервер не нужен.
## Комната на сервере работает через CoopNet; адрес сервера в data/platform.json (coop_host) или в настройке тестера.

signal closed

enum Mode { MENU, CONNECTING, ROOM, RUN, RESULTS }

const HOST_KEY := "trk_coop_host"
const CONNECT_TIMEOUT := 8.0

var mode: Mode = Mode.MENU
var _body: VBoxContainer
var _status: Label
var _view: CoopView
var _net: CoopNet
var _arena: CoopArena
var _local := false
var _acc := 0.0
var _ticks := 0
var _my_id := 0
var _room: Dictionary = {}
var _code_edit: LineEdit
var _results: Dictionary = {}


## Адрес игрового сервера: настройка тестера, иначе data/platform.json. Пусто — комнат на сервере пока нет.
static func host() -> String:
	var custom := Platform.storage_get(HOST_KEY).strip_edges()
	if not custom.is_empty():
		return custom
	var file := FileAccess.open("res://data/platform.json", FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return str((parsed as Dictionary).get("coop_host", "")) if parsed is Dictionary else ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("#14102a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(minf(GlassPopup.panel_width(), 620.0), 0)
	_body.add_theme_constant_override("separation", 12)
	center.add_child(_body)


func _ready() -> void:
	_show_menu()


func _exit_tree() -> void:
	_cleanup_net()


# =========================== меню ===========================

func _show_menu() -> void:
	mode = Mode.MENU
	_clear_run()
	_reset_body()
	_body.add_child(UiStyle.label("КООП НА ДВОИХ", 38, UiStyle.GOLD, 8))
	_body.add_child(UiStyle.label("Режим «Выживание»: вдвоём веселее вонять", 20, UiStyle.TEXT_DIM, 4))
	_status = _wrap("Сервер считает бой сам, поэтому читерить и крутить награды нельзя." if not host().is_empty() else "Игровой сервер ещё не подключён. Пока можно потренироваться с ботом.")
	_body.add_child(_status)
	var trainer := UiStyle.button("ТРЕНИРОВКА С БОТОМ", UiStyle.HOT, 26, Vector2(0, 72))
	trainer.pressed.connect(_start_trainer)
	_body.add_child(trainer)
	if not host().is_empty():
		var create := UiStyle.button("СОЗДАТЬ КОМНАТУ", UiStyle.PANEL_LIGHT, 24, Vector2(0, 66))
		create.pressed.connect(_connect_then.bind("create"))
		_body.add_child(create)
		_code_edit = LineEdit.new()
		_code_edit.placeholder_text = "Код комнаты друга"
		_code_edit.custom_minimum_size = Vector2(0, 56)
		_code_edit.max_length = 12
		SearchBar.style(_code_edit, 22)
		SearchBar.attach_touch_input(_code_edit, "Код комнаты друга")
		_body.add_child(_code_edit)
		var join := UiStyle.button("ВОЙТИ В КОМНАТУ", UiStyle.PANEL_LIGHT, 24, Vector2(0, 66))
		join.pressed.connect(func() -> void:
			if _code_edit.text.strip_edges().is_empty():
				_say("Впиши код комнаты друга")
				return
			_connect_then("join"))
		_body.add_child(join)
	if SaveService.get_insider() >= 0:
		var host_edit := LineEdit.new()
		host_edit.placeholder_text = "Адрес сервера (play.example.com), для тестеров"
		host_edit.text = Platform.storage_get(HOST_KEY)
		host_edit.custom_minimum_size = Vector2(0, 52)
		SearchBar.style(host_edit, 18)
		SearchBar.attach_touch_input(host_edit, "Адрес сервера коопа")
		host_edit.text_submitted.connect(func(value: String) -> void:
			Platform.storage_set(HOST_KEY, value.strip_edges())
			_show_menu())
		host_edit.focus_exited.connect(func() -> void:
			if host_edit.text.strip_edges() != Platform.storage_get(HOST_KEY):
				Platform.storage_set(HOST_KEY, host_edit.text.strip_edges()))
		_body.add_child(host_edit)
	var back := UiStyle.button("НАЗАД", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	back.pressed.connect(_close)
	_body.add_child(back)


func _close() -> void:
	_cleanup_net()
	closed.emit()
	queue_free()


# =========================== тренировка (локально) ===========================

func _start_trainer() -> void:
	_local = true
	_arena = CoopArena.new()
	if not _arena.setup(0):
		_say("Не удалось загрузить данные арены")
		return
	_my_id = 1
	_arena.add_player(1)
	_arena.add_player(2)
	_arena.set_bot(2)
	_arena.finished.connect(func(_won: bool) -> void: _finish_local())
	_begin_run({1: "Ты", 2: "Бот Рико"}, _arena.type_names())


func _finish_local() -> void:
	var results := _arena.results()
	results["names"] = {1: "Ты", 2: "Бот Рико"}
	results["practice"] = true
	_show_results(results)


# =========================== сервер ===========================

func _connect_then(action: String) -> void:
	mode = Mode.CONNECTING
	var address := host()
	_status.text = "Подключаюсь к серверу..."
	_cleanup_net()
	_net = CoopNet.new()
	_net.name = "CoopNet"
	get_tree().root.add_child(_net)
	_net.room_state.connect(_on_room_state)
	_net.room_error.connect(_on_room_error)
	_net.snapshot_received.connect(_on_snapshot)
	_net.run_finished.connect(func(results: Dictionary) -> void: _show_results(results))
	var api := multiplayer as SceneMultiplayer
	var done := [false]
	var on_connected := func() -> void:
		if done[0]:
			return
		done[0] = true
		_my_id = multiplayer.get_unique_id()
		if action == "create":
			_net.create_room()
		else:
			_net.join_room(_code_edit.text)
	api.connected_to_server.connect(on_connected, CONNECT_ONE_SHOT)
	Net.failed.connect(func(reason: String) -> void:
		if mode == Mode.CONNECTING or mode == Mode.ROOM:
			_fail_connection(reason), CONNECT_ONE_SHOT)
	if not Net.connect_to(address):
		_fail_connection("start")
		return
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func() -> void:
		if not done[0] and mode == Mode.CONNECTING:
			_fail_connection("timeout"))


func _fail_connection(reason: String) -> void:
	_cleanup_net()
	_show_menu()
	_say("Не удалось подключиться к серверу коопа (%s). Проверь адрес и связь." % reason)


func _on_room_state(state: Dictionary) -> void:
	_room = state
	if bool(state.get("running", false)):
		if mode != Mode.RUN:
			var names: Dictionary = {}
			for member: Variant in state["members"]:
				names[int((member as Dictionary)["id"])] = str((member as Dictionary)["name"])
			_begin_run(names, [])
		return
	if mode == Mode.RESULTS:
		return
	_show_room()


func _on_room_error(code: String) -> void:
	var texts := {"no_room": "Такой комнаты нет. Проверь код.", "room_full": "В комнате уже двое.", "run_in_progress": "Бой уже идёт.",
		"already_in_room": "Ты уже в комнате.", "room_exists": "Твоя комната уже открыта.", "arena_failed": "Сервер не смог запустить арену."}
	_cleanup_net()
	_show_menu()
	_say(str(texts.get(code, "Ошибка: %s" % code)))


func _show_room() -> void:
	mode = Mode.ROOM
	_reset_body()
	_body.add_child(UiStyle.label("КОМНАТА", 34, UiStyle.GOLD, 8))
	_body.add_child(_wrap("Код комнаты: %s. Друг вводит его в окне коопа." % str(_room.get("code", ""))))
	var me_ready := false
	for member: Variant in _room.get("members", []):
		var m := member as Dictionary
		var row := PanelContainer.new()
		var style := UiStyle.box(Color("#2a2046"), Color("#00e5ff") if bool(m["host"]) else Color("#ff2ea6"), 3, 14)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		var name_label := UiStyle.label("%s%s" % ["★ " if bool(m["host"]) else "", str(m["name"])], 24, UiStyle.TEXT, 5)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(UiStyle.label("ГОТОВ" if bool(m["ready"]) else "ждём", 20, Color("#35c46a") if bool(m["ready"]) else UiStyle.TEXT_DIM, 4))
		row.add_child(line)
		_body.add_child(row)
		if int(m["id"]) == _my_id:
			me_ready = bool(m["ready"])
	var missing := int(_room.get("min", 2)) - (_room.get("members", []) as Array).size()
	if missing > 0:
		_body.add_child(_wrap("Ждём друга. Для старта нужно игроков: %d." % int(_room.get("min", 2))))
	var ready := UiStyle.button("Я НЕ ГОТОВ" if me_ready else "Я ГОТОВ", UiStyle.PANEL_LIGHT if me_ready else UiStyle.HOT, 26, Vector2(0, 72))
	ready.pressed.connect(func() -> void: _net.set_ready(not me_ready))
	_body.add_child(ready)
	var leave := UiStyle.button("ВЫЙТИ ИЗ КОМНАТЫ", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	leave.pressed.connect(func() -> void:
		_cleanup_net()
		_show_menu())
	_body.add_child(leave)


func _on_snapshot(data: Dictionary) -> void:
	if _view != null:
		_view.apply_snapshot(data)


# =========================== бой ===========================

func _begin_run(names: Dictionary, types: Array[String]) -> void:
	mode = Mode.RUN
	_reset_body()
	_body.get_parent().visible = false
	_view = CoopView.new()
	_view.my_id = _my_id
	_view.names = names
	_view.set_types(types)
	add_child(_view)
	var quit := UiStyle.button("ВЫЙТИ", Color("#a3283e"), 20, Vector2(120, 48))
	quit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quit.offset_left = -144
	quit.offset_right = -24
	quit.offset_top = 20
	quit.offset_bottom = 68
	quit.name = "QuitButton"
	quit.pressed.connect(func() -> void:
		_cleanup_net()
		_show_menu())
	add_child(quit)
	_acc = 0.0
	_ticks = 0
	if _local and _arena != null:
		_view.apply_snapshot(_arena.snapshot())
	var net_timer := Timer.new()
	net_timer.name = "MoveTimer"
	net_timer.wait_time = 0.05
	net_timer.timeout.connect(func() -> void:
		if not _local and _net != null and _view != null:
			_net.send_move(_view.move))
	add_child(net_timer)
	net_timer.start()


func _physics_process(delta: float) -> void:
	if mode != Mode.RUN or not _local or _arena == null or _view == null:
		return
	_acc += delta
	while _acc >= CoopArena.TICK:
		_acc -= CoopArena.TICK
		_arena.set_input(1, _view.move)
		_arena.tick(CoopArena.TICK)
		_ticks += 1
		if _ticks % CoopNet.SNAPSHOT_EVERY == 0 and _view != null:
			_view.apply_snapshot(_arena.snapshot())


func _clear_run() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	for node_name in ["QuitButton", "MoveTimer"]:
		var node := get_node_or_null(node_name)
		if node != null:
			node.queue_free()
	if _body != null and _body.get_parent() != null:
		(_body.get_parent() as Control).visible = true
	_arena = null
	_local = false


# =========================== итоги ===========================

func _show_results(results: Dictionary) -> void:
	_results = results
	_clear_run()
	mode = Mode.RESULTS
	_reset_body()
	var won := bool(results.get("won", false))
	_body.add_child(UiStyle.label("ПОБЕДА!" if won else "ЗАБЕГ ОКОНЧЕН", 38, UiStyle.GOLD if won else Color("#ff4d6d"), 8))
	_body.add_child(_wrap("Волн пройдено: %d. Время: %d с." % [int(results.get("waves_cleared", 0)), int(results.get("seconds", 0))]))
	var names: Dictionary = results.get("names", {})
	var players: Dictionary = results.get("players", {})
	for id: Variant in players:
		var p := players[id] as Dictionary
		var who := str(names.get(id, names.get(int(id), "Енот")))
		_body.add_child(UiStyle.label("%s: убито %d, урон %d" % [who, int(p["kills"]), int(p["damage"])], 22, UiStyle.TEXT, 5))
		if not bool(results.get("practice", false)):
			_body.add_child(UiStyle.label("награда: %d монет, %d опыта" % [int(p["coins"]), int(p["xp"])], 18, UiStyle.GOLD, 4))
	_body.add_child(_wrap("Тренировка: награды не выдаются." if bool(results.get("practice", false)) else "Награды проверит и выдаст сервер."))
	var again := UiStyle.button("В МЕНЮ КООПА", UiStyle.HOT, 24, Vector2(0, 66))
	again.pressed.connect(func() -> void:
		if _net != null and mode == Mode.RESULTS and not _room.is_empty():
			_show_room()
		else:
			_show_menu())
	_body.add_child(again)


# =========================== вспомогательное ===========================

func _reset_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _wrap(text: String) -> Label:
	var label := UiStyle.label(text, 19, UiStyle.TEXT_DIM, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(minf(GlassPopup.panel_width(), 620.0) - 20.0, 0)
	return label


func _say(text: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text


func _cleanup_net() -> void:
	if _net != null and is_instance_valid(_net):
		_net.queue_free()
	_net = null
	_room = {}
	if Net.is_active():
		Net.disconnect_all()
