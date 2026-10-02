extends Node
## Локальный тест сети: godot --headless --path . res://test/net_test.tscn -- --net-test server|client [--ws]
## Сервер ждёт двух клиентов, шлёт каждому «hello», клиенты проверяют, что получили, и выходят с кодом 0.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "server" in args:
		_server()
	else:
		_client()


func _server() -> void:
	var seen: Array[int] = []
	Net.joined.connect(func(id: int, profile: Dictionary) -> void:
		print("SERVER joined %d %s" % [id, str(profile.get("nickname", ""))])
		seen.append(id)
		if seen.size() == 2:
			await get_tree().create_timer(0.5).timeout
			Net.say_to_all("hello")
			await get_tree().create_timer(1.5).timeout
			print("SERVER_DONE")
			get_tree().quit(0))
	Net.failed.connect(func(reason: String) -> void: print("SERVER failed %s" % reason))
	if not Net.start_server(17777, 17778):
		get_tree().quit(2)
		return
	await get_tree().create_timer(15.0).timeout
	print("SERVER_TIMEOUT")
	get_tree().quit(3)


func _client() -> void:
	Net.server_said.connect(func(text: String) -> void:
		print("CLIENT got %s" % text)
		get_tree().quit(0 if text == "hello" else 4))
	Net.failed.connect(func(reason: String) -> void: print("CLIENT failed %s" % reason))
	if not Net.connect_to("127.0.0.1", 17777, 17778):
		get_tree().quit(2)
		return
	await get_tree().create_timer(12.0).timeout
	print("CLIENT_TIMEOUT")
	get_tree().quit(3)
