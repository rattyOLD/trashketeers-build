extends Node
## Сетевой тест коопа: сервер + два бота-клиента. godot --headless --path . res://test/coop_test.tscn -- --net-test server|client [--ws]
## Клиенты шлют движение, получают снимки; сервер считает арену и выдаёт итоги.

var _coop: CoopNet


func _ready() -> void:
	_coop = CoopNet.new()
	_coop.name = "CoopNet"
	add_child(_coop)
	if "server" in OS.get_cmdline_user_args():
		_server()
	else:
		_client()


func _server() -> void:
	var ids: Array[int] = []
	Net.joined.connect(func(id: int, _profile: Dictionary) -> void:
		ids.append(id)
		print("SERVER joined %d" % id)
		if ids.size() == 2:
			print("SERVER arena start %s" % str(_coop.start_server_arena(0, ids))))
	if not Net.start_server(17777, 17778):
		get_tree().quit(2)
		return
	await get_tree().create_timer(16.0).timeout
	var ok := _coop.arena != null and _coop.arena.tick_count > 100
	var res := _coop.arena.results() if _coop.arena != null else {}
	print("SERVER ticks=%d enemies=%d results=%s" % [_coop.arena.tick_count if _coop.arena != null else 0, _coop.arena.alive_enemy_count() if _coop.arena != null else 0, JSON.stringify(res)])
	print("SERVER_DONE %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 3)


func _client() -> void:
	var seen := [0]
	var best_enemies := [0]
	var last_wave := [0]
	_coop.snapshot_received.connect(func(data: Dictionary) -> void:
		seen[0] += 1
		best_enemies[0] = maxi(best_enemies[0], (data["e"] as Array).size())
		last_wave[0] = int(data["wave"]))
	if not Net.connect_to("127.0.0.1", 17777, 17778):
		get_tree().quit(2)
		return
	var t := 0.0
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(func() -> void:
		t += 0.05
		_coop.send_move(Vector2.from_angle(t * 0.7)))
	add_child(timer)
	timer.start()
	await get_tree().create_timer(13.0).timeout
	print("CLIENT snapshots=%d max_enemies=%d wave=%d" % [seen[0], best_enemies[0], last_wave[0]])
	var ok: bool = seen[0] > 40 and best_enemies[0] > 0
	print("CLIENT_DONE %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 4)
