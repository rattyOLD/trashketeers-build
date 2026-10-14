extends Node
## Меню запускается отдельно от материалов боя; ресурсные пакеты сохраняют исходные байты.
var _mounted: Dictionary = {}
var _waiting := false


func declared(path: String) -> bool:
	return Platform.is_web and bool(JavaScriptBridge.eval("!!(window.trashPacks && window.trashPacks.resources[%s])" % JSON.stringify(path)))


func available(path: String) -> bool:
	if declared(path):
		var group: Variant = JavaScriptBridge.eval("window.trashPacks.resources[%s]" % JSON.stringify(path))
		return _mounted.has(str(group))
	return ResourceLoader.exists(path)


func _groups_for_enemies(ids: Array) -> PackedStringArray:
	var result := PackedStringArray(["enemy_common"])
	if not Platform.is_web:
		return result
	var groups: Variant = JavaScriptBridge.eval("JSON.stringify(window.trashPacks ? window.trashPacks.enemyGroups(%s) : [])" % JSON.stringify(ids))
	var parsed: Variant = JSON.parse_string(str(groups))
	if parsed is Array:
		for group: String in parsed:
			if not result.has(group): result.append(group)
	return result


func chapter_enemy_ids(chapter: Dictionary) -> Array:
	var ids: Array = ["dash_rat", "rat_punk", "throne_speaker"]
	# Розыск и события не входят в веса волн, но могут появиться в любой главе.
	for group: Array in Wanted.GROUPS:
		for id: StringName in group:
			if not ids.has(str(id)): ids.append(str(id))
	if not str(chapter.get("boss", "")).is_empty(): ids.append(str(chapter["boss"]))
	for wave: Dictionary in chapter.get("waves", []):
		for id in (wave.get("weights", {}) as Dictionary):
			if not ids.has(str(id)): ids.append(str(id))
		for key in ["boss", "miniboss"]:
			if not str(wave.get(key, "")).is_empty() and not ids.has(str(wave[key])): ids.append(str(wave[key]))
	var escort: Dictionary = chapter.get("escort", {})
	if escort.has("enemy") and not ids.has(str(escort["enemy"])): ids.append(str(escort["enemy"]))
	var map_id := MapCards.chosen()
	if not map_id.is_empty():
		var featured := str(MapCards.info(map_id).get("enemy", ""))
		if not featured.is_empty() and not ids.has(featured): ids.append(featured)
	var cursor := 0
	while cursor < ids.size():
		var data := ContentDB.get_enemy(StringName(ids[cursor]))
		if data != null and data.split_into != &"" and not ids.has(str(data.split_into)):
			ids.append(str(data.split_into))
		cursor += 1
	return ids


func chapter_groups(chapter: Dictionary) -> PackedStringArray:
	var result := PackedStringArray(["world", "loading_street"])
	if SaveService.get_character_id() != "raccoon": result.append("heroes")
	result.append_array(_groups_for_enemies(chapter_enemy_ids(chapter)))
	return result


func all_battle_groups() -> PackedStringArray:
	var ids: Array = []
	for id in ContentDB.get_enemy_ids(): ids.append(str(id))
	var result := PackedStringArray(["world", "loading_street", "heroes", "raid"])
	result.append_array(_groups_for_enemies(ids))
	return result


func ensure(groups: PackedStringArray) -> bool:
	if not Platform.is_web or not bool(JavaScriptBridge.eval("!!window.trashPacks")):
		return true
	while _waiting:
		await get_tree().process_frame
	var missing := PackedStringArray()
	for group in groups:
		if not _mounted.has(group): missing.append(group)
	if missing.is_empty(): return true
	_waiting = true
	# Лобби может запросить материалы из _ready, пока корень строит дочерние узлы.
	await get_tree().process_frame
	var panel := DownloadPanel.new()
	get_tree().root.add_child(panel)
	var result := false
	while is_instance_valid(panel):
		var ticket := int(JavaScriptBridge.eval("window.trashPacks.start(%s)" % JSON.stringify(Array(missing))))
		panel.begin_attempt()
		while is_instance_valid(panel):
			if panel.cancelled: break
			var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.trashPacks.status(%d))" % ticket)
			var state: Dictionary = JSON.parse_string(str(raw))
			panel.progress(state)
			if str(state.get("state", "")) == "ready":
				result = true
				for file: Dictionary in state["files"]:
					if ProjectSettings.load_resource_pack(str(file["path"])):
						_mounted[str(file["group"])] = true
					else: result = false
				if result: break
				panel.fail()
			elif str(state.get("state", "")) == "error":
				panel.fail()
			if panel.retry or panel.cancelled: break
			await get_tree().create_timer(0.1, true, false, true).timeout
		if result or not is_instance_valid(panel) or panel.cancelled: break
	if is_instance_valid(panel): panel.queue_free()
	_waiting = false
	return result


class DownloadPanel:
	extends CanvasLayer
	var retry := false
	var cancelled := false
	var _status: Label
	var _bar: ProgressBar
	var _buttons: HBoxContainer

	func _init() -> void:
		layer = 120
		process_mode = Node.PROCESS_MODE_ALWAYS
		var screen := ColorRect.new()
		screen.color = Color(0.035, 0.04, 0.05, 0.98)
		screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(screen)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		screen.add_child(center)
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 400
		box.add_theme_constant_override("separation", 16)
		center.add_child(box)
		box.add_child(UiStyle.label("TRASH SQUAD", 36, UiStyle.GOLD))
		_status = UiStyle.label("Загружаем материалы…", 18, UiStyle.TEXT)
		_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_status)
		_bar = ProgressBar.new()
		_bar.custom_minimum_size.y = 24
		box.add_child(_bar)
		_buttons = HBoxContainer.new()
		_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(_buttons)
		var again := UiStyle.button("ПОВТОРИТЬ", UiStyle.GOLD, 18, Vector2(180, 44))
		again.pressed.connect(func() -> void: retry = true)
		_buttons.add_child(again)
		var back := UiStyle.button("НАЗАД", UiStyle.TEXT, 18, Vector2(180, 44))
		back.pressed.connect(func() -> void: cancelled = true)
		_buttons.add_child(back)
		_buttons.hide()

	func begin_attempt() -> void:
		retry = false
		cancelled = false
		_buttons.hide()

	func progress(state: Dictionary) -> void:
		if _buttons.visible: return
		var total := maxf(float(state.get("total", 0)), 1.0)
		var loaded := float(state.get("loaded", 0))
		_bar.value = minf(loaded / total * 100.0, 99.0)
		_status.text = "Загружаем материалы · %.1f из %.1f МБ" % [loaded / 1048576.0, total / 1048576.0]

	func fail() -> void:
		_status.text = "Не удалось загрузить материалы.\nПроверь интернет и попробуй ещё раз."
		_buttons.show()
