extends Node
var failures := 0
var output := ""

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CATALOG_INTERFACE: " + message)

func _settle() -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	await RenderingServer.frame_post_draw

func _shot(name: String) -> void:
	if not output.is_empty():
		get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func _button(root: Node, prefix: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text.begins_with(prefix):
			return node
	return null

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	Orient.portrait = false
	ThemeDB.fallback_font = load("res://assets/fonts/RussoOne-Regular.ttf")
	output = OS.get_environment("CATALOG_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	var weapon: WeaponData
	for candidate in WeaponDB.get_player_weapons():
		if candidate.has_tiers() and Economy.is_buyable(candidate) and candidate.id != StringName(SaveService.START_WEAPON):
			weapon = candidate
			break
	_check(weapon != null, "buyable tiered fixture exists")
	if weapon == null:
		get_tree().quit(1)
		return
	var armory := MenuPopups.Armory.new()
	add_child(armory)
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1560, 720)]:
		get_window().size = dimensions
		get_window().content_scale_size = dimensions
		SaveService.data["nuts"] = 123456789
		SaveService.data["star_dust"] = 987654
		armory.open()
		await _settle()
		_check(SaveService.get_coins() == 123456789 and SaveService.get_gems() == 987654, "fixture contains actual large balances")
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bounds.grow(1).encloses(armory._panel.get_global_rect()), "catalog fits " + str(dimensions))
		var search := armory.find_children("*", "LineEdit", true, false)[0] as LineEdit
		_check(search.size.x >= 240, "large balance cannot squeeze search " + str(dimensions))
		_check(absf(search.get_global_rect().position.y - armory._balance.get_global_rect().position.y) < 20, "balance and search keep original shared row")
		_check(armory._filters[1].visible, "filters remain visible in the original layout")
		var balance := armory._balance
		var balance_width := balance.get_theme_font("font").get_string_size(balance.text, HORIZONTAL_ALIGNMENT_LEFT, -1, balance.get_theme_font_size("font_size")).x
		_check(balance_width <= balance.size.x - 12 + 1, "entire balance fits after refresh")
		if dimensions.x >= 1120:
			for grid: GridContainer in armory._list.find_children("*", "GridContainer", true, false):
				_check(grid.columns == 3, "wide catalog keeps three columns")
		_shot("catalog-%d" % dimensions.x)
		armory._open_detail(weapon.id, 1)
		await _settle()
		_check(bounds.grow(1).encloses(armory._panel.get_global_rect()), "detail fits " + str(dimensions))
		for child: Control in armory._list.find_children("*", "Control", true, false):
			var rect := child.get_global_rect()
			_check(rect.position.x >= armory._panel.get_global_rect().position.x - 1 and rect.end.x <= armory._panel.get_global_rect().end.x + 1, "detail has no horizontal clipping: " + child.get_class())
		_shot("detail-%d" % dimensions.x)
		armory._detail = &""
	SaveService.data["nuts"] = 0
	SaveService.data["star_dust"] = 0
	var tile := armory._make_tile(weapon)
	armory._list.add_child(tile)
	await _settle()
	var buy := _button(tile, "КУПИТЬ")
	_check(buy != null and buy.disabled, "unaffordable purchase is disabled")
	var has_reason := false
	for label: Label in tile.find_children("*", "Label", true, false):
		has_reason = has_reason or label.text.contains("монет") or label.text.contains("неонита")
	_check(has_reason, "unaffordable purchase shows its price")
	tile.free()
	SaveService.add_weapon(weapon.id, 1)
	SaveService.add_weapon(weapon.id, 1)
	SaveService.data["nuts"] = 123456789
	SaveService.data["star_dust"] = 987654
	# Three readable actions coexist on a typical three-column tile.
	tile = armory._make_tile(weapon)
	tile.custom_minimum_size.x = 318
	var holder := Control.new()
	holder.size = Vector2(318, 500)
	add_child(holder)
	holder.add_child(tile)
	tile.size = Vector2(318, 0)
	await _settle()
	buy = _button(tile, "+КОПИЯ")
	var equip := _button(tile, "В РУКИ")
	_check(buy != null and equip != null, "owned weapon has equip and copy actions")
	if buy != null and equip != null:
		_check(absf(buy.get_global_rect().position.y - equip.get_global_rect().position.y) < 1, "equip and purchase keep a single action row")
		_check(buy.get_theme_font_size("font_size") >= 11, "purchase has a bounded font on a three-column tile")
	for action: Button in tile.find_children("*", "Button", true, false):
		var size := action.get_theme_font("font").get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, action.get_theme_font_size("font_size")).x
		var style := action.get_theme_stylebox("normal")
		var available := action.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT) - action.get_theme_constant("outline_size") * 2
		_check(size <= available + 1, "action caption is not clipped: " + action.text)
	holder.free()
	armory.queue_free()
	for i in 4:
		await get_tree().process_frame
	print("CATALOG_INTERFACE failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
