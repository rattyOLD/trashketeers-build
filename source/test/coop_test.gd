extends Node
## Сетевой тест комнат и боя: сервер + два клиента (хозяин и гость).
## godot --headless --path . res://test/coop_test.tscn -- --net-test server|host|guest [--ws]
## Хозяин создаёт комнату, гость входит по коду, оба жмут «готов», сервер запускает арену, оба шлют движение и получают снимки.

var _coop: CoopNet
var _log := PackedStringArray()


func _ready() -> void:
	_coop = CoopNet.new()
	_coop.name = "CoopNet"
	get_tree().root.add_child.call_deferred(_coop)   # путь /root/CoopNet должен совпадать на сервере и у клиентов
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if "server" in args:
		_server()
	else:
		_client("host" in args)


func _server() -> void:
	Net.joined.connect(func(id: int, profile: Dictionary) -> void: print("SERVER joined %d %s code=%s" % [id, str(profile.get("nickname")), str(profile.get("friend_code"))]))
	if not Net.start_server(17777, 17778):
		get_tree().quit(2)
		return
	var stat := [0, 0]   # тики, участники (массив: лямбда копирует числа, а не ссылается на них)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(func() -> void:
		for code: String in _coop.rooms:
			var room: Dictionary = _coop.rooms[code]
			stat[0] = maxi(stat[0], int(room["ticks"]))
			stat[1] = maxi(stat[1], (room["members"] as Array).size()))
	add_child(timer)
	timer.start()
	await get_tree().create_timer(22.0).timeout
	var ok: bool = stat[0] > 200 and stat[1] == 2
	print("SERVER ticks=%d members=%d" % [stat[0], stat[1]])
	print("SERVER_DONE %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 3)


func _client(is_host: bool) -> void:
	var tag := "HOST" if is_host else "GUEST"
	var seen := [0]
	var best_enemies := [0]
	var states: Array[Dictionary] = []
	var errors: Array[String] = []
	_coop.room_state.connect(func(state: Dictionary) -> void:
		states.append(state)
		if is_host == false and states.size() == 1:
			pass)
	_coop.room_error.connect(func(code: String) -> void: errors.append(code))
	var notices: Array[String] = []
	_coop.notice.connect(func(kind: String, who: String) -> void: notices.append("%s:%s" % [kind, who]))
	_coop.snapshot_received.connect(func(data: Dictionary) -> void:
		seen[0] += 1
		best_enemies[0] = maxi(best_enemies[0], (data["e"] as Array).size()))
	if not Net.connect_to("127.0.0.1", 17777, 17778):
		get_tree().quit(2)
		return
	await get_tree().create_timer(1.5 if is_host else 3.0).timeout
	if is_host:
		_coop.create_room()
	else:
		_coop.join_room("a!")                       # плохой код -> bad_code
		_coop._join_room.rpc_id(1, "THOST", 0)      # старая версия -> old_version
		await get_tree().create_timer(0.5).timeout
		_coop.join_room("THOST")
	await get_tree().create_timer(1.0).timeout
	_coop.set_ready(true)
	var t := 0.0
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(func() -> void:
		t += 0.05
		_coop.send_move(Vector2.from_angle(t * 0.7)))
	add_child(timer)
	timer.start()
	await get_tree().create_timer(12.0).timeout
	var last_members := 0
	var running := false
	var counted := false
	for state in states:
		last_members = maxi(last_members, (state["members"] as Array).size())
		running = bool(state["running"]) or running
		counted = counted or float(state["countdown"]) > 0.0
	print("%s states=%d members=%d running=%s snapshots=%d max_enemies=%d errors=%s countdown=%s notices=%s" % [tag, states.size(), last_members, str(running), seen[0], best_enemies[0], str(errors), str(counted), str(notices)])
	var errors_ok := errors.is_empty() if is_host else errors == ["bad_code", "old_version"]
	var notices_ok := notices == ["joined:GUEST"] if is_host else notices.size() <= 1 and (notices.is_empty() or notices[0] == "left:HOST")
	var ok: bool = seen[0] > 40 and best_enemies[0] > 0 and last_members == 2 and running and errors_ok and counted and notices_ok
	print("%s_DONE %s" % [tag, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 4)
