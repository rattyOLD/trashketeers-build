extends Node
## Кто даёт draw calls: прячем узлы одного типа и смотрим, сколько вызовов ушло.
var game: Game


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	Engine.max_fps = 60
	Orient.portrait = true
	get_window().content_scale_size = Orient.PORTRAIT_SIZE
	SaveService.data["quality"] = int(OS.get_environment("PROBE_Q")) if OS.get_environment("PROBE_Q") != "" else 0
	var state: Dictionary = SaveService.data["tester"]
	state["god"] = true
	state["start_wave"] = int(OS.get_environment("PROBE_WAVE")) if OS.get_environment("PROBE_WAVE") != "" else 1
	var battle: BattleBase
	if OS.get_environment("PROBE_MODE") == "raid":
		battle = Raid.new()
	else:
		game = Game.new()
		if OS.get_environment("PROBE_STORY") != "":
			game.story_mission = OS.get_environment("PROBE_STORY")
		battle = game
	add_child(battle)
	battle.start(&"")
	var t := 0.0
	while t < 20.0:
		await get_tree().create_timer(0.3, true).timeout
		t += 0.3
		if get_tree().paused:
			for panel in get_tree().root.find_children("*", "LevelUpPanel", true, false):
				panel.queue_free()
			get_tree().paused = false
	get_tree().paused = true
	Engine.time_scale = 0.0
	var samples := []
	for i in 20:
		samples.append(await _draws())
	print("DRAW noise ", samples, " objs=", int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	if OS.get_environment("PROBE_NOISE") == "1":
		get_tree().quit()
		return
	var kinds := {}
	_kinds(get_tree().root, kinds)
	var rows := []
	for key in kinds:
		var list: Array = kinds[key]
		var hidden: Array = []
		for n: CanvasItem in list:
			if n.is_visible_in_tree():
				hidden.append(n)
		if hidden.is_empty():
			continue
		var diffs: Array[int] = []
		var b0 := 0
		for rep in 3:
			b0 = await _draws()
			for n: CanvasItem in hidden:
				n.visible = false
			var d := await _draws()
			for n: CanvasItem in hidden:
				n.visible = true
			var b1 := await _draws()
			diffs.append((b0 + b1) / 2 - d)
		diffs.sort()
		rows.append([key, diffs[1], hidden.size()])
		print("ROW %-40s saves=%4d visible=%d base=%d diffs=%s" % [key, diffs[1], hidden.size(), b0, str(diffs)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	for r in rows.slice(0, 45):
		print("DRAW %-40s saves=%4d visible=%d" % [r[0], r[1], r[2]])
	get_tree().quit()


func _draws() -> int:
	for i in 3:
		await RenderingServer.frame_post_draw
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _kinds(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child is CanvasItem and not (child is Container or child is Game or child is BiomeLayers or ((child.get_class() == "Control" or child.get_class() == "Node2D") and child.get_script() == null)):
			var sname := str(child.get_script().get_global_name()) if child.get_script() != null else ""
			var key := sname if sname != "" else child.get_class()
			if sname == "" and child.get_script() != null:
				var sc: Script = child.get_script()
				key = child.get_class() + "<" + sc.resource_path.get_file() + ":" + str(sc.get_instance_id() % 1000) + "> @" + str(child.get_parent().name)
			if not out.has(key):
				out[key] = []
			(out[key] as Array).append(child)
		_kinds(child, out)
