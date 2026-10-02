extends Node
## Тест экрана коопа без сети: тренировка с ботом, ввод джойстика, отрисовка снимков, итоги.
## godot --headless --path . res://test/screen_test.tscn

func _ready() -> void:
	var screen := CoopScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fails := 0
	if screen.mode != CoopScreen.Mode.MENU:
		print("FAIL: меню не открылось")
		fails += 1
	screen.show_demo()
	await get_tree().process_frame
	for node_name in ["FriendsPanel", "Tab_friends", "Tab_recent", "Tab_requests", "StartButton", "Invite_ABC123", "Chat_ABC123"]:
		if screen.find_child(node_name, true, false) == null:
			print("FAIL: в лобби нет " + node_name)
			fails += 1
	(screen.find_child("Tab_requests", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	if screen.find_child("Accept_NEW001", true, false) == null:
		print("FAIL: вкладка заявок пустая")
		fails += 1
	screen._remember_partner({"code": "ABC123", "name": "Тест", "c": "", "s": "classic", "lv": 3})
	(screen.find_child("Tab_recent", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	if screen.find_child("Recent_ABC123", true, false) == null:
		print("FAIL: недавние не показываются")
		fails += 1
	screen._room = {}
	screen._tab = "friends"
	screen._start_trainer()
	await get_tree().process_frame
	var view: CoopView = screen._view
	if screen.mode != CoopScreen.Mode.RUN or view == null:
		print("FAIL: бой не начался")
		get_tree().quit(1)
		return
	Engine.time_scale = 6.0
	# дёрнем «джойстик» как пальцем: нажатие, смещение, отпускание
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(300, 300)
	view._gui_input(down)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(400, 300)
	view._gui_input(drag)
	await get_tree().process_frame
	await get_tree().process_frame
	var moved := view.move
	print("STICK move=%s" % str(moved))
	if moved.length() < 0.9:
		print("FAIL: джойстик не двигает")
		fails += 1
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	view._gui_input(up)
	await get_tree().create_timer(14.0).timeout
	var snap := view.snap
	print("SNAP wave=%s phase=%s players=%d enemies=%d tick=%s" % [str(snap.get("wave")), str(snap.get("phase")), (snap.get("p", []) as Array).size(), (snap.get("e", []) as Array).size(), str(snap.get("tick"))])
	if int(snap.get("tick", 0)) < 300 or (snap.get("p", []) as Array).size() != 2:
		print("FAIL: снимки не идут")
		fails += 1
	Engine.time_scale = 1.0
	var results: Dictionary = screen._arena.results()
	results["names"] = {1: "Ты", 2: "Бот Рико"}
	results["practice"] = true
	screen._show_results(results)
	await get_tree().process_frame
	if screen.mode != CoopScreen.Mode.RESULTS or screen._view != null:
		print("FAIL: итоги не показались")
		fails += 1
	screen._show_menu()
	await get_tree().process_frame
	if screen.mode != CoopScreen.Mode.MENU:
		print("FAIL: возврат в меню")
		fails += 1
	print("SCREEN_TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(0 if fails == 0 else 1)
