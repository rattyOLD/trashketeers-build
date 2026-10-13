extends Node
## Реальная компоновка меню, доступность длинных реплик и нативные жесты без случайных нажатий.
var failures := 0
var clicks := 0
var output := ""

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("INTERFACE_COMPLETE FAIL: " + message)

func _rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform * Vector2.ZERO, control.size * transform.get_scale())

func _settle() -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw

func _capture(title: String) -> void:
	if not output.is_empty():
		get_viewport().get_texture().get_image().save_png(output.path_join(title + ".png"))

func _touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = 0
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Orient.portrait = false
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService.data["runs"] = 9
	SaveService.data["nickname"] = "ДлинноеИмяТестировщика"
	SaveService.data["best_wave"] = 39
	SaveService.data["stats"]["story_missions"] = 1
	SaveService.data["ascension_max"] = 3
	SaveService.data["acct_hint"] = true
	SaveService.data["whatsnew_seen"] = ChangelogPopup.latest_key()
	SaveService.add_coins_silent(123456789)
	SaveService.add_gems(987654, false)
	Cloud.waiting_choice = true
	output = OS.get_environment("INTERFACE_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	var menu := MainMenuUI.new()
	add_child(menu)
	for dimensions in [Vector2i(1280,720), Vector2i(1560,720), Vector2i(960,540)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for mode in [MainMenuUI.Mode.SURVIVAL, MainMenuUI.Mode.RAID, MainMenuUI.Mode.STORY]:
			menu._mode = mode
			menu._refresh_mod_chip()
			await _settle()
			_check(bounds.grow(0.5).encloses(_rect(menu._menu_body)), "menu stays on screen " + str(dimensions))
			_check(_rect(menu._menu_body).end.y <= _rect(menu._dock).position.y, "menu above dock " + str(dimensions))
			_check(_rect(menu._menu_body).position.y >= _rect(menu._avatar).end.y, "menu below profile " + str(dimensions))
			_check(menu._menu_body.scale.x >= 0.9, "menu remains readable " + str(dimensions))
			for control in menu._mode_buttons + [menu._season_pill, menu._coop_button, menu._mod_chip, menu._map_chip, menu._asc_chip, menu._gear, menu._dock]:
				if control.is_visible_in_tree():
					_check(bounds.grow(0.5).encloses(_rect(control)), "menu action stays on screen " + str(dimensions))
			_capture("menu_%d_mode%d" % [dimensions.x,mode])
		_check(menu.find_children("*", "RaccoonVisual", true, false).is_empty(), "menu has no character")
		var whats := WhatsNewPopup.new()
		add_child(whats)
		await _settle()
		_check(bounds.grow(0.5).encloses(_rect(whats._card)), "update card fits " + str(dimensions))
		for button in whats.find_children("*", "Button", true, false):
			_check(bounds.encloses(_rect(button)), "update action accessible " + str(dimensions))
		_capture("update_%d" % dimensions.x)
		whats.free()
	menu.free()
	await _test_coop()
	await _test_scroll()
	await _test_dialog()
	# Меню запускает музыку при сенсорном вводе; автолоад переживает его закрытие.
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.1, true, false, true).timeout
	# Дочерние окна и их render-ресурсы освобождаются отложенно после закрытия.
	for frame in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("INTERFACE_COMPLETE failures=", failures)
	get_tree().quit.call_deferred(0 if failures == 0 else 1)

func _test_coop() -> void:
	Cloud.friend_code = ""
	SaveService.set_badge_level(0)
	var coop := CoopScreen.new()
	coop.auto_create = false
	add_child(coop)
	for dimensions in [Vector2i(1280,720), Vector2i(960,540)]:
		get_window().content_scale_size = dimensions
		get_window().size = dimensions
		await _settle()
		for tab in ["friends", "recent", "requests", "top"]:
			coop._tab = tab
			coop._show_lobby()
			await _settle()
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(_rect(coop._body)), "coop lobby fits " + str(dimensions))
			for path in ["BackButton", "FriendsPanel", "MuteButton", "StartButton"]:
				var control := coop.find_child(path,true,false) as Control
				_check(control != null and bounds.encloses(_rect(control)), "coop action accessible " + path)
			for button in coop.find_children("*", "Button", true, false):
				if button.text.contains("ТРЕНИРОВК"):
					_check(bounds.encloses(_rect(button)), "coop start remains visible")
			_capture("coop_%d_%s" % [dimensions.x,tab])
		_check(coop._backdrop.get_child_count() == 1, "resizing does not duplicate panorama")
	var editor := coop.find_children("*", "LineEdit", true, false)[0] as LineEdit
	editor.show()
	editor.text = "server.local"
	editor.grab_focus()
	get_window().size = Vector2i(1280,720)
	await _settle()
	_check(is_instance_valid(editor) and editor.text == "server.local" and editor.has_focus(), "lobby resize preserves focused editor")
	editor.hide()
	editor.release_focus()
	coop._start_trainer()
	await _settle()
	_check(coop.mode == CoopScreen.Mode.RUN and coop._view != null, "coop start opens local battle")
	coop._show_results({"practice":true,"won":true,"waves_cleared":6,"seconds":120,"players":{1:{"kills":120,"damage":2500}},"names":{1:"Тестировщик"}})
	await _settle()
	_check(get_viewport().get_visible_rect().encloses(_rect(coop._body)), "coop results fit")
	_capture("coop_results")
	coop.free()

func _test_scroll() -> void:
	var outer := DragScroll.new()
	outer.position = Vector2(100,100)
	outer.size = Vector2(500,400)
	add_child(outer)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var scroll := DragScroll.new()
	scroll.custom_minimum_size = Vector2(400,300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var tail := Control.new()
	tail.custom_minimum_size.y = 1000.0
	body.add_child(tail)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var button := UiStyle.button("Выбрать", UiStyle.HOT, 22, Vector2(0,80))
	button.pressed.connect(func() -> void: clicks += 1)
	column.add_child(button)
	var locked := UiStyle.button("Недоступно", UiStyle.PANEL, 22, Vector2(0,80))
	locked.disabled = true
	column.add_child(locked)
	for i in range(15):
		column.add_child(UiStyle.label("Строка %d" % i, 22, UiStyle.TEXT, 4))
	await _settle()
	var point := _rect(button).get_center()
	await _touch(point,true)
	await _touch(point,false)
	await get_tree().process_frame
	_check(clicks == 1, "native tap selects item once")
	await _touch(point,true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point - Vector2(0,80)
	drag.relative = Vector2(0,-80)
	drag.velocity = Vector2(0,-600)
	Input.parse_input_event(drag)
	await get_tree().process_frame
	await _touch(drag.position,false)
	await get_tree().process_frame
	_check(scroll.scroll_vertical > 0, "native swipe scrolls list")
	_check(outer.scroll_vertical == 0, "nested swipe leaves outer list still")
	_check(clicks == 1, "swipe does not select item")
	_check(not button.disabled and locked.disabled, "gesture restores only its pressed button")
	var position_before := scroll.scroll_vertical
	await get_tree().create_timer(0.08).timeout
	_check(scroll.scroll_vertical > position_before, "release preserves scroll inertia")
	scroll.hide()
	_check(not scroll._tracking and scroll._touch_index == -1 and scroll._velocity == 0.0, "hidden list cancels gesture")
	outer.free()

func _test_dialog() -> void:
	var dialog := DialogBox.new()
	add_child(dialog)
	var text := "Очень длинная сюжетная реплика: нужно прочитать каждое слово, а затем продолжить разговор. ".repeat(20)
	dialog.open([{"who":"npc","text":text},{"who":"npc","text":"Следующая реплика"}], {"npc":{"name":"Диспетчер базы","glyph":"!"}})
	await _settle()
	dialog._reveal_or_advance()
	await _settle()
	var bounds := get_viewport().get_visible_rect()
	_check(get_tree().paused, "dialog pauses battle")
	_check(bounds.encloses(_rect(dialog._panel)), "long dialog panel fits")
	_check(dialog._text.size.y > dialog._scroll.size.y, "long text has scroll range")
	dialog._process(10.0)
	_check(dialog._index == 0, "long text waits for reader")
	dialog._scroll.scroll_vertical = ceili(dialog._text.size.y)
	await _settle()
	_check(_rect(dialog._text).end.y <= _rect(dialog._scroll).end.y + 2.0, "last dialog line reachable")
	_capture("dialog_long")
	dialog._finish()
	await get_tree().process_frame
	_check(not get_tree().paused, "closing dialog resumes battle")
