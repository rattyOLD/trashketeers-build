extends Node
## Бой для профайлера: бессмертие, старт с волны PROBE_WAVE, выход через PROBE_SECS.
var _acc := 0.0
var _frames := 0


func _ready() -> void:
	Controls.apply_keys()
	seed(17032)
	Engine.max_fps = 60
	if OS.get_environment("PROBE_UNCAP") == "1":
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Orient.portrait = true
	get_window().content_scale_size = Orient.PORTRAIT_SIZE
	SaveService.data["quality"] = 0
	var state: Dictionary = SaveService.data["tester"]
	state["god"] = true
	state["start_wave"] = int(OS.get_environment("PROBE_WAVE")) if OS.get_environment("PROBE_WAVE") != "" else 1
	var game := Game.new()
	add_child(game)
	game.start(&"")
	var secs := float(OS.get_environment("PROBE_SECS")) if OS.get_environment("PROBE_SECS") != "" else 40.0
	if OS.get_environment("PROBE_STRESS") == "1":
		_stress(game)
	var t := 0.0
	while t < secs:
		await get_tree().create_timer(5.0).timeout
		t += 5.0
		var em: Variant = game.get("enemies")
		print("PROF t=%d draws=%d objs=%d vmem=%dMB tex=%dMB nodes=%d enemies=%d fps=%d" % [t, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), (em as EnemyManager).get_active().size() if em != null else -1, int(Performance.get_monitor(Performance.TIME_FPS))])
	get_tree().quit()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


var _unpause := 0.0
var _last_us := 0


func _process(delta: float) -> void:
	_acc += delta
	_frames += 1
	if _acc >= 5.0:
		print("FRAMEMS %.3f" % (_acc / _frames * 1000.0))
		_acc = 0.0
		_frames = 0
	var now := Time.get_ticks_usec()
	if _last_us > 0 and now - _last_us > 30000:
		print("SPIKE at=%.2fs ms=%.1f" % [now / 1000000.0, (now - _last_us) / 1000.0])
	_last_us = now
	_unpause += delta
	if _unpause > 0.3 and get_tree().paused:
		_unpause = 0.0
		for panel in get_tree().root.find_children("*", "LevelUpPanel", true, false):
			panel.queue_free()
		get_tree().paused = false


func _stress(game: Game) -> void:
	while is_inside_tree():
		var d: WaveDirector = game.get("director")
		if d != null:
			d._max_alive = 90
			d.remaining_to_spawn = 999
			d._interval = 0.08
		var pm: PickupManager = game.pickups
		if pm != null and pm.get_count() < 250:
			for i in 10:
				pm.spawn_xp(game.player.global_position + Vector2(randf_range(-500, 500), randf_range(-800, 800)), 2)
		await get_tree().create_timer(0.5).timeout
