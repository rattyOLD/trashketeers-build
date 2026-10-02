extends Node
## Экран коопа поверх настоящей сети: хозяин создаёт комнату, гость входит по коду, оба готовы, оба видят бой.
## godot --headless --path . res://test/screen_net_test.tscn -- --net-test host|guest --net-name=Имя [--ws] (сервер: coop_test.tscn -- --net-test server)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var is_host := "host" in args
	Platform.storage_set(CoopScreen.HOST_KEY, "127.0.0.1:17778" if "--ws" in args else "127.0.0.1:17777")
	print("HOSTADDR '%s'" % CoopScreen.host())
	multiplayer.connected_to_server.connect(func() -> void: print("EVENT connected_to_server"))
	Net.failed.connect(func(r: String) -> void: print("EVENT failed %s" % r))
	var screen := CoopScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fails := 0
	if is_host:
		screen._connect_then("create")
	else:
		await get_tree().create_timer(2.0).timeout
		screen._code_edit.text = "THOST"
		screen._connect_then("join")
	await get_tree().create_timer(3.0).timeout
	if screen.mode != CoopScreen.Mode.ROOM:
		print("FAIL: не в комнате, mode=%d status=%s" % [screen.mode, screen._status.text if screen._status != null else ""])
		fails += 1
	else:
		screen._net.set_ready(true)
	await get_tree().create_timer(3.0).timeout
	if screen.mode != CoopScreen.Mode.RUN or screen._view == null:
		print("FAIL: бой не начался, mode=%d" % screen.mode)
		fails += 1
	else:
		screen._view.move = Vector2.RIGHT
		await get_tree().create_timer(2.5).timeout
		var snap := screen._view.snap
		print("VIEW wave=%s players=%d tick=%s" % [str(snap.get("wave")), (snap.get("p", []) as Array).size(), str(snap.get("tick"))])
		if (snap.get("p", []) as Array).size() != 2 or int(snap.get("tick", 0)) < 100:
			print("FAIL: снимки не доходят")
			fails += 1
		await get_tree().create_timer(5.0).timeout   # оба остаются в бою, пока другой проверяет
	print("%s_SCREEN %s" % ["HOST" if is_host else "GUEST", "PASS" if fails == 0 else "FAIL %d" % fails])
	get_tree().quit(0 if fails == 0 else 1)
