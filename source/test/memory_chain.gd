extends Node
## Выживание → меню → сюжет → меню: видеопамять на каждом шаге (освобождается ли память боя) и ошибки.
var main: Node
var t := 0.0
var step := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	get_tree().root.add_child.call_deferred(main)


func _vram() -> String:
	return "vram=%.0fMB tex=%.0fMB static=%.0fMB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]


func _physics_process(delta: float) -> void:
	t += delta
	var screen: Node = main._screen
	if screen != null and screen.get("player") != null and is_instance_valid(screen.get("player")):
		screen.get("player").hp = screen.get("player").max_hp
		if get_tree().paused and screen is Game and screen._level_up_open:
			screen.hud._level_up._armed_at = 0
			screen.hud._level_up._pick(0)
	match step:
		0:
			if t > 1.0:
				print("MENU0 ", _vram())
				main._start_game(SaveService.get_selected_weapon())
				step = 1
		1:
			if t > 16.0:
				print("SURVIVAL ", _vram())
				screen._on_menu_pressed()
				step = 2
		2:
			if t > 20.0:
				print("MENU1 ", _vram())
				main._start_story(SaveService.get_selected_weapon())
				step = 3
		3:
			if t > 35.0:
				print("STORY ", _vram())
				screen._on_menu_pressed()
				step = 4
		4:
			if t > 39.0:
				print("MENU2 ", _vram())
				print("CHAIN_DONE")
				get_tree().quit()
