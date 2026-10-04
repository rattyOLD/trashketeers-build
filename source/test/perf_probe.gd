extends Node
## Замер CPU: сколько мс на кадр даёт каждая ветка сцены (скрипты и физика). PROBE_STORY=1 для сюжета.
func _ready() -> void:
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	var game := Game.new()
	if OS.get_environment("PROBE_STORY") == "1":
		game.story_mission = "m1"
	add_child(game)
	game.start(&"")
	await get_tree().create_timer(8.0).timeout
	var base := await _cpu()
	print("PROBE base ms/frame=%.2f nodes=%d" % [base, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	var kinds := {}
	_kinds(game, kinds)
	var rows := []
	for key in kinds:
		var list: Array = kinds[key]
		if list.size() < 3:
			continue
		for n: Node in list:
			n.process_mode = Node.PROCESS_MODE_DISABLED
		var t := await _cpu()
		for n: Node in list:
			n.process_mode = Node.PROCESS_MODE_INHERIT
		rows.append([key, base - t, list.size()])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	for r in rows.slice(0, 18):
		print("PROBE %-34s saves=%.2fms count=%d" % [r[0], r[1], r[2]])
	get_tree().quit()


func _cpu() -> float:
	var sum := 0.0
	for i in 60:
		await get_tree().process_frame
		sum += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	return sum / 60.0


func _kinds(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		var key := str(child.get_script().get_global_name()) if child.get_script() != null and str(child.get_script().get_global_name()) != "" else child.get_class()
		if key == "":
			key = child.get_class()
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(child)
		_kinds(child, out)
