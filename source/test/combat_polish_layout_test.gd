extends Node
## Проверяет реальные отрисованные границы опасности и окно итогов в горизонтали.
var failures := 0
var output := ""

class BossZone:
	extends Node2D
	var brain := BossBrain.new()
	func _draw() -> void:
		brain._draw_zone(self, Vector2(260, 240), BossBrain.STOMP_RADIUS, 0.5)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("COMBAT_POLISH_LAYOUT FAIL: " + message)


func _screen_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform * Vector2.ZERO, control.size * transform.get_scale())


func _ready() -> void:
	_run.call_deferred()


func _settle() -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw


func _ring_pixels(view: SubViewport, center: Vector2, radius: float, title: String) -> void:
	await _settle()
	var img := view.get_texture().get_image()
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var point: Vector2i = Vector2i(center + dir * radius)
		var red := 0.0
		for y in range(-2, 3):
			for x in range(-2, 3):
				red = maxf(red, img.get_pixel(point.x + x, point.y + y).r)
		_check(red > 0.5, title + " warning reaches actual radius " + str(dir))
	if not output.is_empty():
		img.save_png(output.path_join(title + ".png"))


func _run() -> void:
	Orient.portrait = false
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["quality"] = 0
	output = OS.get_environment("COMBAT_POLISH_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	var view := SubViewport.new()
	view.size = Vector2i(600, 480)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var enemy := Enemy.new()
	view.add_child(enemy)
	enemy.data = ContentDB.get_enemy(&"bruiser")
	enemy.position = Vector2(200, 220)
	enemy.visible = true
	enemy._act = Enemy.Act.SLAM
	enemy._act_time = 0.5
	enemy._act_total = 1.0
	enemy._act_dir = Vector2.RIGHT
	enemy.queue_redraw()
	# Сплошная толпа закрывает мир; предупреждение должно остаться поверх неё.
	var crowd := ColorRect.new()
	crowd.color = Color("#181818")
	crowd.size = Vector2(view.size)
	view.add_child(crowd)
	await _ring_pixels(view, enemy.position + enemy._act_dir * enemy.data.slam_radius * 0.45, enemy.data.slam_radius, "slam")
	enemy.free()
	crowd.free()
	var boss := BossZone.new()
	view.add_child(boss)
	await _ring_pixels(view, Vector2(260, 240), BossBrain.STOMP_RADIUS, "boss_stomp")
	boss.free()
	var lob := LobPool.new()
	view.add_child(lob)
	lob.throw(Vector2(30, 30), Vector2(260, 240), 10.0, 100.0, 100.0, 20.0, Color.RED, null, null, 10.0)
	lob._time[0] = 5.0
	lob.set_physics_process(false)
	lob.queue_redraw()
	await _ring_pixels(view, Vector2(260, 240), 100.0, "lob")
	view.free()
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		var hud := Hud.new()
		add_child(hud)
		hud.build(load("res://assets/ui/hub/coin.png"), SaveService.get_loadout())
		var report := CombatReport.new()
		report.record_enemy(2500.0, 100.0, &"blast")
		report.record_received(125.0, &"projectile")
		hud.show_run_result({"wave": 6, "best_wave": 7, "kills": 120, "level": 15, "time": 260.0, "coins": 1234, "total_coins": 4321, "chapter": "Неоновая свалка", "combat_report": report.lines(true), "tip": report.avoidance_tip()})
		await _settle()
		var panel := hud._run_result
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bounds.encloses(_screen_rect(panel._panel)), "results stay on screen " + str(dimensions))
		_check(_screen_rect(panel._tip_box).encloses(_screen_rect(panel._tip_label)), "report stays inside plate")
		_check(panel._panel.scale.x >= (0.9 if dimensions.x == 1280 else 0.7), "readable result scale " + str(dimensions))
		if not output.is_empty():
			get_viewport().get_texture().get_image().save_png(output.path_join("result_%d.png" % dimensions.x))
		hud.free()
	print("COMBAT_POLISH_LAYOUT failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
