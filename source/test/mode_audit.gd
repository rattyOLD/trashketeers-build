extends Node
## Аудит режимов: MODE=survival|story|raid|mod:<id>|boss:<id>. Бот бегает и стреляет ~N секунд, ошибки видны в логе (SCRIPT ERROR).
var main: Node
var t := 0.0
var started := false
var mode := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mode = OS.get_environment("MODE")
	Engine.time_scale = 2.0
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	if mode.begins_with("mod:"):
		SaveService.data["run_mod"] = mode.trim_prefix("mod:")
	main = Node.new()
	main.set_script(load("res://scripts/main.gd"))
	get_tree().root.add_child.call_deferred(main)


func _physics_process(delta: float) -> void:
	t += delta
	if t > 0.6 and not started:
		started = true
		var weapon := SaveService.get_selected_weapon()
		match mode:
			"story":
				main._start_story(weapon)
			"raid":
				main._start_raid(weapon)
			_:
				main._start_game(weapon)
	var screen: Node = main._screen
	if screen != null and not screen is MainMenuUI and screen.get("player") != null:
		var p: Variant = screen.get("player")
		if is_instance_valid(p):
			if OS.get_environment("DIE") == "1" and t > 14.0:
				if not screen.get_meta("killed", false):
					screen.set_meta("killed", true)
					p.hp = 0.0
					p.died.emit()
			else:
				p.hp = p.max_hp
			p.move_input = Vector2(cos(t * 0.7), sin(t * 0.7))
			if screen.has_method("_request_dash"):
				screen._request_dash()
		if screen is Game and mode.begins_with("boss:") and not screen.get_meta("boss_done", false):
			screen.set_meta("boss_done", true)
			screen.debug_boss(StringName(mode.trim_prefix("boss:")))
		if get_tree().paused and screen is Game and screen._level_up_open:
			screen.hud._level_up._pick(0)
	if t > 40.0 and OS.get_environment("DIE") == "1":
		var panel: Variant = screen.get("hud") if screen != null else null
		print("DIE_CHECK screen=", screen.get_class() if screen != null else "null")
	if t > 40.0:
		print("MODE_AUDIT_DONE ", mode, " screen=", screen.get_class() if screen != null else "null")
		get_tree().quit()
