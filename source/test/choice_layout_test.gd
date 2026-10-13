extends Node
var failures := 0
var picked := -1

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHOICE_LAYOUT: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for dimensions in [Vector2i(640, 360), Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1560, 720)]:
		var view := SubViewport.new()
		view.size = dimensions
		view.process_mode = Node.PROCESS_MODE_ALWAYS
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		var card := ChoiceCard.new()
		view.add_child(card)
		card.chosen.connect(func(index: int) -> void: picked = index)
		card.open({"title": "Пивной Барон на коленях", "image": "res://assets/story/surrender/baron_surrender.png", "text": "Выбери награду и реши, что пригодится твоему билду. ".repeat(12), "options": [
			{"label": "ПОЩАДИТЬ", "bullets": ["Полное лечение", "Бесплатный реролл", "Редкий ствол"]},
			{"label": "ОГРАБИТЬ", "bullets": ["Эпический ствол", "+50% неонита", "-Без лечения"]}]})
		await get_tree().create_timer(0.8, true, false, true).timeout
		for frame in 5:
			await get_tree().process_frame
		var screen := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(screen.encloses(card._panel.get_global_rect()), "panel fits " + str(dimensions))
		_check(screen.encloses(card._options.get_global_rect()), "both choices visible " + str(dimensions))
		_check(not card._options.get_global_rect().intersects(card._scroll.get_global_rect()), "description cannot cover choices")
		_check(card._scroll.get_v_scroll_bar().max_value > card._scroll.size.y, "long description scrolls")
		var before := card._options.get_global_rect()
		card._scroll.scroll_vertical = 100
		await get_tree().process_frame
		_check(card._options.get_global_rect() == before, "choices stay pinned during scrolling")
		card._opened_ms = Time.get_ticks_msec()
		card._pick(1)
		_check(not card._done, "opening touch cannot choose reward")
		if not OS.get_environment("CHOICE_OUT").is_empty():
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(OS.get_environment("CHOICE_OUT").path_join("choice-%dx%d.png" % [dimensions.x, dimensions.y]))
		var resized := Vector2i(960, 540) if dimensions.x < 960 else Vector2i(640, 360)
		view.size = resized
		await get_tree().create_timer(0.3, true, false, true).timeout
		_check(Rect2(Vector2.ZERO, Vector2(resized)).encloses(card._panel.get_global_rect()), "open card follows viewport resize")
		_check(Rect2(Vector2.ZERO, Vector2(resized)).encloses(card._options.get_global_rect()), "choices remain visible after resize")
		card._opened_ms = 0
		card._pick(1)
		_check(picked == 1 and not get_tree().paused, "choice applies and restores pause state")
		view.queue_free()
		await get_tree().process_frame
	print("CHOICE_LAYOUT failures=", failures)
	for i in 4:
		await get_tree().process_frame
	get_tree().quit.call_deferred(1 if failures else 0)
