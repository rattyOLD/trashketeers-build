extends "res://test/mode_audit.gd"
## Длительный прогон по реальному времени, включая фон и возврат.
var _started_at := 0
var _next_sample := 20.0
var _background_tested := false
var _samples := 0
var _failures := 0
var _peak_vram := 0.0
var _size := Vector2i.ZERO
var _render_size := Vector2i.ZERO
var _next_shot := 60.0
var _finishing := false

func _ready() -> void:
	OS.set_environment("DURATION", "10000")
	super._ready()
	if OS.get_environment("STABILITY_NATIVE") == "1":
		Platform.is_native_app = true
		Platform._touch = 1
		Platform._a13 = 0
	SaveService.data["quality"] = int(OS.get_environment("STABILITY_QUALITY")) if not OS.get_environment("STABILITY_QUALITY").is_empty() else 0
	SaveService.data["tester"]["god"] = true
	SaveService.data["tips_off"] = true
	SaveService.apply_quality()
	_started_at = Time.get_ticks_msec()
	_size = get_window().size
	_render_size = get_window().content_scale_size

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("STABILITY_SOAK: " + message)

func _background_roundtrip() -> void:
	AppActivity._set_backgrounded(true)
	await get_tree().create_timer(5.0, true, false, true).timeout
	AppActivity._set_backgrounded(false)
	var game := main._screen as Game
	_check(not AppActivity.backgrounded and game != null, "foreground restores battle")
	if game != null and game.hud._pause.visible:
		game.hud._pause._resume()
	_check(not get_tree().paused, "gameplay continues after dismissing return pause")

func _process(_delta: float) -> void:
	if _finishing:
		return
	var wall := (Time.get_ticks_msec() - _started_at) / 1000.0
	if not is_instance_valid(main):
		return
	var game := main._screen as Game
	if game != null:
		game.process_mode = Node.PROCESS_MODE_PAUSABLE
	if game != null and get_tree().paused and not AppActivity.backgrounded:
		if game.hud._level_up.visible:
			game.hud._level_up._armed_at = 0
			if game._dealer_open:
				game._on_reroll_requested()
			else:
				game.hud._level_up._pick(0)
		for child in game.get_children():
			if child is ChoiceCard and not child._done:
				child._opened_ms = 0
				child._pick(0)
			if child is RunEncounter and not child._resolved:
				child._resolve(false)
	if game != null and not get_tree().paused and game._portal != null and game._portal.visible:
		game._enter_portal()
	if wall < _next_sample:
		return
	_next_sample = wall + 5.0
	_check(game != null and not game.finished, "survival stays active")
	if game == null:
		get_tree().quit(1)
		return
	_check(get_window().size == _size, "window resolution stays fixed")
	_check(get_window().content_scale_size == _render_size, "chosen render resolution stays fixed")
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans == 0, "gameplay has no orphan nodes")
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_peak_vram = maxf(_peak_vram, vram)
	_samples += 1
	print("STABILITY_SAMPLE wall=%.1f game=%.1f wave=%d vram=%.1fMB nodes=%d orphans=%d size=%s" % [wall, game.director.elapsed, game.director.wave_number, vram, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), orphans, _size])
	if not _background_tested and wall > 45:
		_background_tested = true
		_background_roundtrip()
	var shot_folder := OS.get_environment("STABILITY_OUT")
	if not shot_folder.is_empty() and wall >= _next_shot:
		_next_shot = wall + 540.0
		var image := get_viewport().get_texture().get_image()
		image.save_png(shot_folder.path_join("native-%ds.png" % int(wall)))
	var limit := float(OS.get_environment("STABILITY_SECONDS")) if not OS.get_environment("STABILITY_SECONDS").is_empty() else 650.0
	if wall >= limit:
		_finishing = true
		_check(game.director.elapsed >= 300.0, "battle simulation advances for at least five minutes")
		print("STABILITY_SOAK failures=%d wall=%.1f samples=%d peak_vram=%.1fMB background=%s" % [_failures, wall, _samples, _peak_vram, _background_tested])
		_finish.call_deferred()

func _finish() -> void:
	set_physics_process(false)
	get_tree().paused = false
	main.free()
	BattleMemory.release()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.2).timeout
	SoundManager._music.stream = null
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(1 if _failures else 0)
