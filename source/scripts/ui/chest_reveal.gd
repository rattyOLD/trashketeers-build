class_name ChestReveal
extends Control
## Раскрытие сундука в духе Brawl Stars: сундук трясётся, вспышка, награды по одной по возрастанию
## редкости (лучшая — последней), затем итог. Тап — дальше. Всё на Control и твинах, без частиц-нод.

signal finished

const SHAKE_MIN := 0.9
const RARITY_RANK := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
const CHEST_SIZE := Vector2(300, 260)

var _rewards: Array[Dictionary] = []
var _chest_color := Color.WHITE
var _stage := 0
var _index := -1
var _age := 0.0
var _chest: ChestIcon
var _stack: CenterContainer
var _flash: ColorRect
var _hint: Label
var _tween: Tween


func _init(rewards: Array[Dictionary], chest_id: String, chest_color: Color, chest_title: String) -> void:
	_rewards = rewards.duplicate()
	_rewards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(RARITY_RANK.get(str(a.get("rarity", "common")), 0)) < int(RARITY_RANK.get(str(b.get("rarity", "common")), 0)))
	_chest_color = chest_color
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.064, 0.062, 0.058, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_stack = CenterContainer.new()
	_stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)

	_chest = ChestIcon.new(chest_color, chest_id)
	_stack.add_child(_chest)

	var title := UiStyle.label(chest_title.to_upper(), 44, chest_color, 12)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 90.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	_hint = UiStyle.label("Тапни, чтобы открыть", 28, UiStyle.TEXT_DIM, 6)
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -150.0
	_hint.offset_bottom = -90.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	gui_input.connect(_on_input)


func _ready() -> void:
	_chest.start_shake()
	SoundManager.play(&"crate_break", -4.0, false)


func _process(delta: float) -> void:
	_age += delta


func _on_input(event: InputEvent) -> void:
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tapped:
		return
	accept_event()
	if _stage == 0:
		if _age >= SHAKE_MIN:
			_burst()
	elif _stage == 1:
		_next()
	elif _stage == 2:
		return


func _burst() -> void:
	_stage = 2
	_chest.open_lid()
	_hint.text = "Тап — дальше"
	SoundManager.play(&"explosion", -8.0, false)
	_flash_screen(Color.WHITE, 0.6)
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_chest.visible = false
		_stage = 1
		_next())


func _flash_screen(color: Color, strength: float) -> void:
	_flash.color = Color(color, strength)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.45)


func _next() -> void:
	for child in _stack.get_children():
		if child != _chest:
			child.queue_free()
	_index += 1
	if _index >= _rewards.size():
		_show_summary()
		return
	var card := _make_card(_rewards[_index])
	_stack.add_child(card)
	card.pivot_offset = card.get_combined_minimum_size() * 0.5
	card.scale = Vector2(0.2, 0.2)
	card.modulate.a = 0.0
	var rarity := str(_rewards[_index].get("rarity", "common"))
	var rank := int(RARITY_RANK.get(rarity, 0))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.12)
	_flash_screen(WeaponData.RARITY_COLORS.get(rarity, Color.WHITE), 0.15 + 0.12 * rank)
	match rank:
		3:
			SoundManager.play(&"level_up", 0.0, false)
		2:
			SoundManager.play(&"merge", 0.0, false)
		1:
			SoundManager.play(&"star_dust", 0.0, false)
		_:
			SoundManager.play(&"ui_confirm", -4.0, false)
	if rank >= 2:
		UiStyle.pulse(card, 0.03, 0.7)


func _make_card(reward: Dictionary) -> Control:
	var rarity := str(reward.get("rarity", "common"))
	var color: Color = WeaponData.RARITY_COLORS.get(rarity, Color.WHITE)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 470)
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.166, 0.159, 0.149, 0.98), color, 10, 30))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header: String = str(WeaponData.RARITY_NAMES.get(rarity, rarity)).to_upper()
	if str(reward.get("type", "")) == "xp":
		header = "ОПЫТ АККАУНТА"
		color = Color("#ffab53")
		panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.184, 0.177, 0.166, 0.98), color, 10, 30))
	column.add_child(UiStyle.label(header, 30, color, 8))

	var type := str(reward.get("type", ""))
	var art := CenterContainer.new()
	art.custom_minimum_size = Vector2(0, 150)
	var key := str(reward.get("key", ""))
	if key.begins_with("weapon:"):
		var weapon := WeaponDB.get_weapon(StringName(Economy.item_id(key)))
		if weapon != null:
			var icon := WeaponIcons.IconRect.new(weapon.icon, weapon.effect_color, Vector2(300, 130))
			art.add_child(icon)
	elif type == "coins" or type == "dup":
		art.add_child(_texture_rect("res://assets/ui/hub/coin.png", 130))
	elif type == "gems":
		art.add_child(_texture_rect("res://assets/ui/hub/neonite.png", 130))
	elif type == "xp":
		art.add_child(XpBadge.new())
	elif type == "shard":
		art.add_child(_texture_rect("res://assets/ui/hub/blueprint.png", 140))
	else:
		art.add_child(XpBadge.new(true))
	column.add_child(art)

	var title := UiStyle.label(str(reward.get("title", "")), 40, UiStyle.TEXT, 10)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(500, 0)
	column.add_child(title)
	var subtitle := str(reward.get("subtitle", ""))
	if type == "shard":
		var need := Economy.SHARDS_PER_ITEM
		subtitle = "%s · %d/%d" % [subtitle, int(reward.get("progress", 0)), need]
		if reward.get("assembled", false):
			subtitle = "%s · СОБРАН!" % str(reward.get("subtitle", ""))
	if not subtitle.is_empty():
		var sub := UiStyle.label(subtitle, 26, UiStyle.TEXT_DIM, 6)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(500, 0)
		column.add_child(sub)
	if type == "item":
		column.add_child(UiStyle.label("НОВОЕ!" if not reward.get("guaranteed", false) else "ГАРАНТИЯ СЕРИИ!", 30, UiStyle.GOLD, 8))
	if type == "shard":
		var bar := UiStyle.progress_bar(color, 20)
		bar.max_value = float(Economy.SHARDS_PER_ITEM)
		bar.value = float(reward.get("progress", 0))
		column.add_child(bar)
	return panel


func _texture_rect(path: String, side: float) -> Control:
	var rect := TextureRect.new()
	rect.texture = ArenaProp.texture_of(path)
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


## Склеивает одинаковое: все монеты — одной строкой, опыт — одной, одинаковые чертежи — суммой.
func _merged_rewards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var coins := 0
	var gems := 0
	var xp := 0
	var shards: Dictionary = {}
	var shard_rarity: Dictionary = {}
	var shard_order: Array[String] = []
	for reward in _rewards:
		var type := str(reward.get("type", ""))
		match type:
			"coins":
				coins += int(reward.get("amount", 0))
			"gems":
				gems += int(reward.get("amount", 0))
			"xp":
				xp += int(reward.get("amount", 0))
			"shard":
				var key := str(reward.get("subtitle", ""))
				if not shards.has(key):
					shard_order.append(key)
					shards[key] = 0
					shard_rarity[key] = str(reward.get("rarity", "common"))
				shards[key] = int(shards[key]) + int(reward.get("amount", 1))
			_:
				var line := str(reward.get("title", ""))
				var subtitle := str(reward.get("subtitle", ""))
				if not subtitle.is_empty():
					line += " · " + subtitle
				out.append({"line": line, "rarity": str(reward.get("rarity", "common"))})
	var head: Array[Dictionary] = []
	if coins > 0:
		head.append({"line": SaveService.format_coins(coins), "rarity": "common"})
	if gems > 0:
		head.append({"line": Economy.format_gems(gems), "rarity": "epic"})
	if xp > 0:
		head.append({"line": "+%d опыта" % xp, "rarity": "common"})
	for key in shard_order:
		head.append({"line": "Чертёж ×%d · %s" % [int(shards[key]), key], "rarity": str(shard_rarity[key])})
	head.append_array(out)
	return head


func _show_summary() -> void:
	_stage = 2
	_hint.text = ""
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.166, 0.159, 0.149, 0.98), _chest_color, 8, 28))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(UiStyle.label("ПОЛУЧЕНО", 44, UiStyle.GOLD, 12))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 0)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	column.add_child(scroll)
	for entry in _merged_rewards():
		var color: Color = WeaponData.RARITY_COLORS.get(str(entry["rarity"]), Color.WHITE)
		var label := UiStyle.label(str(entry["line"]), 24, color, 6)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(500, 0)
		list.add_child(label)
	# Высота списка не больше экрана: «ПОЛУЧЕНО» и «ЗАБРАТЬ» всегда видны, длинный список прокручивается.
	var room := maxf(160.0, get_viewport_rect().size.y - 330.0)
	scroll.custom_minimum_size.y = minf(room, float(maxi(1, list.get_child_count())) * 40.0)
	var done := UiStyle.button("ЗАБРАТЬ", Color("#2fae5f"), 32, Vector2(0, 80))
	done.pressed.connect(func() -> void:
		SoundManager.play(&"ui_confirm")
		finished.emit()
		queue_free())
	column.add_child(done)
	_stack.add_child(panel)
	UiStyle.pop_in(panel, 0.5)


## Сундук из Control: корпус, крышка, замок. Тряска нарастает и ведёт к вспышке.
class ChestIcon:
	extends Control
	var color: Color
	var texture: Texture2D
	var open_texture: Texture2D
	var _time := 0.0
	var _shaking := false

	func _init(chest_color: Color, chest_id: String) -> void:
		color = chest_color
		texture = ArenaProp.texture_of("res://assets/ui/chests_v2/%s.png" % chest_id)
		open_texture = ArenaProp.texture_of("res://assets/ui/chests_v2/%s_open.png" % chest_id)
		custom_minimum_size = ChestReveal.CHEST_SIZE
		pivot_offset = ChestReveal.CHEST_SIZE * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func start_shake() -> void:
		_shaking = true

	func open_lid() -> void:
		_shaking = false
		rotation = 0.0
		scale = Vector2.ONE
		if open_texture != null:
			texture = open_texture
		queue_redraw()

	func _process(delta: float) -> void:
		if not _shaking:
			return
		_time += delta
		var power := clampf(_time / 1.4, 0.0, 1.0)
		rotation = sin(_time * (18.0 + 14.0 * power)) * (0.05 + 0.13 * power)
		scale = Vector2.ONE * (1.0 + 0.06 * power + 0.03 * sin(_time * 30.0))
		queue_redraw()

	func _draw() -> void:
		var w := ChestReveal.CHEST_SIZE.x
		var h := ChestReveal.CHEST_SIZE.y
		var glow := clampf(_time / 1.4, 0.0, 1.0)
		draw_circle(Vector2(w, h) * 0.5, w * (0.62 + 0.25 * glow), Color(color, 0.10 + 0.22 * glow))
		if texture != null:
			var fit := minf(w / texture.get_width(), h / texture.get_height()) * 1.15
			var size := texture.get_size() * fit
			draw_texture_rect(texture, Rect2((Vector2(w, h) - size) * 0.5, size), false)
			return
		var body := Rect2(30, h * 0.44, w - 60, h * 0.46)
		var lid := Rect2(20, h * 0.16, w - 40, h * 0.32)
		draw_rect(body, color.darkened(0.55))
		draw_rect(body, color, false, 8.0)
		draw_rect(lid, color.darkened(0.35))
		draw_rect(lid, color.lightened(0.2), false, 8.0)
		for i in 3:
			var x := body.position.x + body.size.x * (0.2 + 0.3 * i)
			draw_line(Vector2(x, body.position.y), Vector2(x, body.end.y), Color(color, 0.5), 4.0)
		draw_rect(Rect2(w * 0.5 - 24, h * 0.42, 48, 56), Color("#ffd257"))
		draw_rect(Rect2(w * 0.5 - 24, h * 0.42, 48, 56), Color("#8a5a00"), false, 4.0)
		draw_circle(Vector2(w * 0.5, h * 0.42 + 26), 7.0, Color("#3a2400"))


## Значок опыта: гранёная медаль с молнией-звездой и подписью XP — читается без текста рядом.
## bare = true рисует тот же значок без подписи (для наград без своей иконки).
class XpBadge:
	extends Control
	const SIZE := Vector2(150, 150)
	const STAR_PATH := "res://assets/ui/icons/xp_star.png"
	var _bare := false
	var _time := 0.0

	func _init(bare: bool = false) -> void:
		_bare = bare
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not bare:
			var tag := UiStyle.label("XP", 30, Color.WHITE, 10)
			tag.position = Vector2(0, 92)
			tag.size = Vector2(SIZE.x, 40)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			add_child(tag)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _hex(center: Vector2, radius: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(center + Vector2.from_angle(-PI * 0.5 + TAU * i / 6.0) * radius)
		return pts

	func _draw() -> void:
		var c := SIZE * 0.5
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		draw_circle(c, 78.0 + 4.0 * pulse, Color(0.36, 0.95, 1.0, 0.10 + 0.08 * pulse))
		var art := ArenaProp.texture_of(STAR_PATH)
		if art != null:
			var size := Vector2(150.0, 150.0 * art.get_height() / art.get_width()) * (1.0 + 0.04 * pulse)
			draw_texture_rect(art, Rect2(c - size * 0.5 - Vector2(0, 6), size), false)
			return
		draw_colored_polygon(_hex(c, 70.0), Color("#474440"))
		draw_colored_polygon(_hex(c, 62.0), Color("#df7f1c"))
		draw_colored_polygon(_hex(c, 52.0), Color("#ffc181"))
		draw_polyline(_hex(c, 70.0) + PackedVector2Array([_hex(c, 70.0)[0]]), Color("#e8fdff"), 4.0, true)
		var star := PackedVector2Array()
		var center := c + Vector2(0, -12 if not _bare else 0)
		for i in 10:
			var r := 34.0 if i % 2 == 0 else 15.0
			star.append(center + Vector2.from_angle(-PI * 0.5 + TAU * i / 10.0) * r)
		draw_colored_polygon(star, Color("#ffd257"))
		star.append(star[0])
		draw_polyline(star, Color("#8a5a00"), 3.0, true)
