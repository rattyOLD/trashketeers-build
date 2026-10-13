extends Node
var failures := 0
var output := ""

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("REWARD_INTERACTIONS: " + message)

func _ready() -> void:
	_run.call_deferred()

func _settle() -> void:
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw

func _button(root: Node, prefix: String) -> Button:
	for button: Button in root.find_children("*", "Button", true, false):
		if button.text.begins_with(prefix): return button
	return null

func _touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func _tap(point: Vector2) -> void:
	await _touch(point, true)
	await _touch(point, false)
	await _settle()

func _fresh() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["quality"] = 0
	SaveService.data["star_dust"] = 2000

func _run() -> void:
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	output = OS.get_environment("REWARDS_OUT")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		await _test_daily(dimensions)
		await _test_pass(dimensions)
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1).timeout
	SoundManager._music.stop()
	SoundManager._music.stream = null
	for frame in 4: await get_tree().process_frame
	print("REWARD_INTERACTIONS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _test_daily(dimensions: Vector2i) -> void:
	for day in [1,4,7]:
		_fresh()
		SaveService.data["daily_day"] = SaveService.today() - 1
		SaveService.data["daily_streak"] = day - 1
		var popup := DailyPopup.new()
		add_child(popup)
		popup.open()
		await _settle()
		var tile: Control = popup._grid.get_child(day - 1) if day < 7 else popup._finale.get_child(0)
		popup._content_scroll_view.ensure_control_visible(tile)
		await _settle()
		var stage: Control = tile.get_child(0).get_child(1)
		var point := stage.get_global_rect().get_center()
		var before := SaveService.get_coins()
		var gems := SaveService.get_gems()
		var points := BattlePass.points()
		var reward := SaveService.get_daily_reward()
		# Drag starts on the same live reward tile: release must not claim it.
		await _touch(point, true)
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = point + Vector2(0,-45)
		drag.relative = Vector2(0,-45)
		drag.velocity = Vector2.ZERO
		Input.parse_input_event(drag)
		await get_tree().process_frame
		await _touch(drag.position, false)
		_check(SaveService.get_coins() == before and SaveService.can_claim_daily(), "drag over today's gift does not claim it")
		popup._content_scroll_view._velocity = 0
		popup._content_scroll_view.ensure_control_visible(tile)
		await _settle()
		point = stage.get_global_rect().get_center()
		await _tap(point)
		_check(not SaveService.can_claim_daily() and SaveService.get_coins() == before + reward, "tap on the gift's artwork credits the exact daily reward")
		_check(SaveService.get_gems() == gems + int(SaveService.DAILY_GEMS.get(day,0)) * Premium.daily_mult(), "gift includes the correct neonte reward")
		_check(BattlePass.points() == points + BattlePass.DAILY_POINTS, "daily gift advances the battle pass once")
		await _tap(point)
		_check(SaveService.get_coins() == before + reward and BattlePass.points() == points + BattlePass.DAILY_POINTS, "repeated tap cannot claim twice")
		if day == 4 and not output.is_empty(): get_viewport().get_texture().get_image().save_png(output.path_join("daily-%d.png" % dimensions.x))
		popup.free()
		for frame in 3: await get_tree().process_frame

func _test_pass(dimensions: Vector2i) -> void:
	_fresh()
	var popup := BattlePassPopup.new()
	add_child(popup)
	popup.open()
	await _settle()
	var scroll := popup._scroll_box.get_parent().get_parent() as DragScroll
	var button := _button(popup,"ПРОПУСТИТЬ УРОВЕНЬ")
	scroll.ensure_control_visible(button)
	await _settle()
	var before := SaveService.get_gems()
	var offset := scroll.scroll_vertical
	var position_before := button.get_global_rect().get_center()
	for purchase in 8:
		button = _button(popup,"ПРОПУСТИТЬ УРОВЕНЬ")
		await _tap(button.get_global_rect().get_center())
		_check(BattlePass.tier() == purchase + 1 and SaveService.get_gems() == before - (purchase + 1) * BattlePass.SKIP_COST, "each consecutive tap buys exactly one level at the unchanged cost")
		button = _button(popup,"ПРОПУСТИТЬ УРОВЕНЬ")
		_check(abs(scroll.scroll_vertical - offset) <= 2, "level purchase preserves the scroll position")
		_check(button.get_global_rect().get_center().distance_to(position_before) <= 2, "buy button stays under the finger across milestone changes")
	# Receiving a reward from the middle of the pass also keeps the chosen view.
	scroll.scroll_vertical = 2400
	await _settle()
	offset = scroll.scroll_vertical
	_check(BattlePass.claim("free",1), "earned pass reward can be claimed")
	popup._refresh()
	await _settle()
	_check(abs(scroll.scroll_vertical - offset) <= 2, "claim refresh retains a deep list position")
	if not output.is_empty(): get_viewport().get_texture().get_image().save_png(output.path_join("pass-%d.png" % dimensions.x))
	# No funds and the final level retain their purchase guards.
	SaveService.data["star_dust"] = 0
	popup._refresh()
	await _settle()
	button = _button(popup,"ПРОПУСТИТЬ УРОВЕНЬ")
	_check(button != null and button.disabled and not BattlePass.skip_tier(), "insufficient funds cannot buy a level")
	SaveService.data["star_dust"] = 2000
	BattlePass._state()["points"] = 29 * BattlePass.POINTS_PER_TIER
	popup._refresh()
	await _settle()
	button = _button(popup,"ПРОПУСТИТЬ УРОВЕНЬ")
	scroll.ensure_control_visible(button)
	await _settle()
	await _tap(button.get_global_rect().get_center())
	_check(BattlePass.tier() == 30 and SaveService.get_gems() == 1960 and _button(popup,"ПРОПУСТИТЬ УРОВЕНЬ") == null and not BattlePass.skip_tier(), "last level is paid once and cannot be overspent")
	popup.free()
	for frame in 3: await get_tree().process_frame
	# Close during deferred restoration: delayed callbacks belong to the popup.
	popup = BattlePassPopup.new()
	add_child(popup)
	popup.open()
	popup._refresh()
	popup.free()
	await _settle()
