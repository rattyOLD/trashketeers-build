class_name BattlePanels
extends RefCounted
## Окна боя поверх HUD: заставка главы, второй шанс (возрождение), итоги забега.
## Все окна живут в Hud (PROCESS_MODE_ALWAYS) и работают при паузе дерева.

const ICON_DIR := "res://assets/ui/icons/"
## Рисованные иконки хаба заменяют сгенерированные там, где они есть.
const HUB_ICONS := {
	"neonite": "res://assets/ui/hub/neonite.png",
	"play": "res://assets/ui/hub/play.png",
	"blueprint": "res://assets/ui/hub/blueprint.png",
	"trophy": "res://assets/ui/hub/achievements.png",
	"upgrade": "res://assets/ui/hub/upgrade.png",
	"coin": "res://assets/ui/hub/coin.png",
}
const NEONITE := Color("#c77dff")


static func icon(name: String) -> Texture2D:
	if HUB_ICONS.has(name):
		return ArenaProp.texture_of(HUB_ICONS[name])
	return ArenaProp.texture_of(ICON_DIR + name + ".png")


static func icon_rect(texture: Texture2D, side: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.03, 0.01, 0.08, 0.8)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	return d


## Кнопка «иконка + подпись (+ строка под ней)» в общем стиле UiStyle.button.
static func icon_button(texture: Texture2D, text: String, sub: String, color: Color, height: float) -> Button:
	var b := UiStyle.button("", color, 30, Vector2(0, height))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -6
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	if texture != null:
		row.add_child(icon_rect(texture, height * 0.46))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", -4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	var title := UiStyle.label(text, 30, UiStyle.TEXT, 8)
	title.name = "Title"
	column.add_child(title)
	if not sub.is_empty():
		var sub_label := UiStyle.label(sub, 18, Color(1, 1, 1, 0.85), 5)
		sub_label.name = "Sub"
		column.add_child(sub_label)
	return b


## Заставка главы: «ГЛАВА N» и название влетают сверху и гаснут.
class ChapterCard:
	extends Control

	var _chapter: Label
	var _title: Label
	var _line: ColorRect
	var _tween: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiStyle.anchor(self, Vector2(0.5, 0.5), Rect2(-360, -330, 720, 170))
		visible = false
		_chapter = UiStyle.label("", 28, UiStyle.NEON, 8)
		_chapter.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_chapter.offset_bottom = 40
		add_child(_chapter)
		_title = UiStyle.label("", 64, UiStyle.GOLD, 14)
		_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_title.offset_top = 36
		_title.offset_bottom = 120
		add_child(_title)
		_line = ColorRect.new()
		_line.color = UiStyle.NEON
		_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiStyle.anchor(_line, Vector2(0.5, 0.0), Rect2(-180, 128, 360, 5))
		add_child(_line)

	func play(chapter_text: String, title: String, accent: Color) -> void:
		_chapter.text = chapter_text.to_upper()
		_title.text = title.to_upper()
		_chapter.add_theme_color_override("font_color", accent)
		_line.color = accent
		visible = true
		modulate.a = 0.0
		if _tween != null:
			_tween.kill()
		_line.scale.x = 0.0
		_line.pivot_offset = Vector2(180, 2)
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "modulate:a", 1.0, 0.35)
		_tween.tween_property(self, "offset_top", -330.0, 0.5).from(-390.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "offset_bottom", -160.0, 0.5).from(-220.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_line, "scale:x", 1.0, 0.5).set_delay(0.25)
		_tween.chain().tween_interval(2.3)
		_tween.chain().tween_property(self, "modulate:a", 0.0, 0.5)
		_tween.chain().tween_callback(func() -> void: visible = false)


## Кольцо-таймер возрождения: сектор убывает, в центре — секунды и сердечко.
class TimerRing:
	extends Control

	var fraction := 1.0
	var seconds := 10

	func _init() -> void:
		custom_minimum_size = Vector2(190, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_time(left: float, total: float) -> void:
		fraction = clampf(left / total, 0.0, 1.0)
		seconds = ceili(left)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r + 6.0, UiStyle.OUTLINE)
		draw_circle(c, r, Color("#1c1433"))
		var urgent := fraction < 0.3
		var color := UiStyle.DANGER if urgent else UiStyle.NEON
		draw_arc(c, r - 10.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 64, color, 16.0, true)
		var heart := PackedVector2Array()
		for i in 32:
			var t := TAU * i / 32.0
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			heart.append(c + Vector2(x, y) * 2.2 + Vector2(0, -26))
		draw_colored_polygon(heart, Color("#ff4d6d"))
		draw_polyline(heart + PackedVector2Array([heart[0]]), UiStyle.OUTLINE, 4.0, true)
		var font := ThemeDB.fallback_font
		var text := str(seconds)
		draw_string_outline(font, Vector2(0, c.y + 58), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 64, 12, UiStyle.OUTLINE)
		draw_string(font, Vector2(0, c.y + 58), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 64, UiStyle.TEXT if not urgent else Color("#ffb3c0"))


## Второй шанс: 10 секунд, реклама (раз за забег) или неонит, ниже — выход в меню.
class RevivePanel:
	extends Control
	signal revive(with_ad: bool)
	signal expired
	signal exit_pressed

	const DURATION := 10.0

	var _panel: PanelContainer
	var _ring: TimerRing
	var _info: Label
	var _error: Label
	var _ad: Button
	var _gems: Button
	var _left := DURATION
	var _waiting := false

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		visible = false
		add_child(BattlePanels.dim())
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		_panel = PanelContainer.new()
		var style := UiStyle.box(UiStyle.PANEL, UiStyle.OUTLINE, 6, 32)
		style.set_content_margin_all(28)
		_panel.add_theme_stylebox_override("panel", style)
		center.add_child(_panel)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(600, 0)
		box.add_theme_constant_override("separation", 14)
		_panel.add_child(box)
		box.add_child(UiStyle.label("ВТОРОЙ ШАНС", 54, UiStyle.GOLD, 14))
		var ring_row := CenterContainer.new()
		box.add_child(ring_row)
		_ring = TimerRing.new()
		ring_row.add_child(_ring)
		_info = UiStyle.label("", 22, UiStyle.TEXT_DIM, 5)
		box.add_child(_info)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		_ad = BattlePanels.icon_button(BattlePanels.icon("ad"), "СМОТРЕТЬ", "реклама · бесплатно", Color("#35c46a"), 112)
		_ad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ad.pressed.connect(_on_ad)
		row.add_child(_ad)
		_gems = BattlePanels.icon_button(BattlePanels.icon("neonite"), "10", "у тебя: 0", BattlePanels.NEONITE.darkened(0.2), 112)
		_gems.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_gems.pressed.connect(_on_gems)
		row.add_child(_gems)
		_error = UiStyle.label("", 22, UiStyle.DANGER, 6)
		_error.visible = false
		box.add_child(_error)
		var leave := UiStyle.button("В ГЛАВНОЕ МЕНЮ", UiStyle.PANEL_LIGHT, 24, Vector2(0, 70))
		leave.pressed.connect(func() -> void:
			visible = false
			exit_pressed.emit())
		box.add_child(leave)

	func open(cost: int, gems: int, ad_available: bool, summary: Dictionary) -> void:
		_left = DURATION
		_waiting = false
		_error.visible = false
		_info.text = "Волна %d · врагов %d · уровень %d" % [int(summary.get("wave", 0)) + 1, int(summary.get("kills", 0)), int(summary.get("level", 1))]
		_ad.disabled = not ad_available
		(_ad.find_child("Sub", true, false) as Label).text = "реклама · бесплатно" if ad_available else "уже использовано"
		(_gems.find_child("Title", true, false) as Label).text = str(cost)
		var sub := _gems.find_child("Sub", true, false) as Label
		sub.text = "у тебя: %d" % gems
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85) if gems >= cost else Color("#ffb3c0"))
		_ring.set_time(_left, DURATION)
		visible = true
		UiStyle.pop_in(_panel, 0.5)

	func close() -> void:
		visible = false
		_waiting = false

	func fail(message: String) -> void:
		_waiting = false
		_error.text = message
		_error.visible = true
		UiStyle.pop_in(_error, 0.35)
		Platform.haptic_notify("error")

	func _on_ad() -> void:
		if _waiting:
			return
		_waiting = true
		revive.emit(true)

	func _on_gems() -> void:
		if _waiting:
			return
		revive.emit(false)

	func _process(delta: float) -> void:
		if not visible or _waiting:
			return
		_left -= delta
		_ring.set_time(maxf(_left, 0.0), DURATION)
		if _left <= 0.0:
			visible = false
			expired.emit()


## Плитка статистики: иконка, крупное число, подпись.
class StatTile:
	extends PanelContainer

	var value_label: Label
	var _target := 0
	var _format := "%d"

	func _init(texture: Texture2D, caption: String, color: Color) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := UiStyle.box(Color("#1f1738"), Color(color, 0.9), 4, 18)
		style.set_content_margin_all(10)
		add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(column)
		if texture != null:
			var holder := CenterContainer.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(BattlePanels.icon_rect(texture, 40))
			column.add_child(holder)
		value_label = UiStyle.label("0", 38, color, 9)
		column.add_child(value_label)
		column.add_child(UiStyle.label(caption, 17, UiStyle.TEXT_DIM, 5))

	func set_text(text: String) -> void:
		value_label.text = text

	## Счётчик «набегает» от нуля — итоги читаются как награда.
	func count_to(value: int, delay: float, prefix: String = "") -> void:
		_target = value
		_format = prefix + "%d"
		value_label.text = _format % 0
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_method(func(v: float) -> void: value_label.text = _format % roundi(v), 0.0, float(value), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Трофей забега: квадратная плитка в рамке редкости (ствол или чертёж) и подпись.
class TrophyTile:
	extends VBoxContainer

	func _init(kind: String, key: String, tier: int) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(104, 92)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := ""
		var color := UiStyle.TEXT_DIM
		if kind == "weapon":
			var weapon := WeaponDB.get_weapon(StringName(key))
			color = weapon.get_rarity_color() if weapon != null else color
			var art := WeaponIcons.IconRect.new(weapon.icon if weapon != null else &"pistol", weapon.effect_color if weapon != null else Color.WHITE, Vector2(88, 56))
			frame.add_child(art)
			caption = (weapon.get_title() if weapon != null else key) + (" T%d" % tier if tier > 1 else "")
		else:
			color = Economy.rarity_color(Economy.item_rarity(key))
			var holder := CenterContainer.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(BattlePanels.icon_rect(BattlePanels.icon("blueprint"), 60))
			frame.add_child(holder)
			caption = "Чертёж: " + Economy.item_title(key)
		var style := UiStyle.box(Color(color, 0.22), color, 4, 14)
		style.set_content_margin_all(6)
		frame.add_theme_stylebox_override("panel", style)
		add_child(frame)
		var label := UiStyle.label(caption, 15, color.lightened(0.3), 4)
		label.custom_minimum_size = Vector2(104, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		add_child(label)


## Итоги забега: заголовок, 6 плиток статистики, трофеи, «Ещё раз» / «В хаб».
class RunResultPanel:
	extends Control
	signal restart_pressed
	signal menu_pressed
	signal upgrade_pressed

	var _panel: PanelContainer
	var _title: Label
	var _subtitle: Label
	var _tip_box: PanelContainer
	var _tip_label: Label
	var _upgrade_button: Button
	var _tiles: Dictionary = {}
	var _trophies: HFlowContainer
	var _no_trophies: Label
	var _total: Label
	var _coin_icon: Texture2D
	var _double_button: Button
	var _reward_coins := 0
	var _reward_gems := 0

	func _init(coin_icon: Texture2D) -> void:
		_coin_icon = coin_icon
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		visible = false
		add_child(BattlePanels.dim())
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		_panel = PanelContainer.new()
		var style := UiStyle.box(UiStyle.PANEL, UiStyle.OUTLINE, 6, 32)
		style.set_content_margin_all(26)
		_panel.add_theme_stylebox_override("panel", style)
		center.add_child(_panel)
		var page := BoxContainer.new()
		page.vertical = Orient.portrait
		page.add_theme_constant_override("separation", 26)
		_panel.add_child(page)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(640 if Orient.portrait else 560, 0)
		box.add_theme_constant_override("separation", 10)
		page.add_child(box)
		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(640 if Orient.portrait else 380, 0)
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		right.add_theme_constant_override("separation", 12)
		page.add_child(right)

		_title = UiStyle.label("ЗАБЕГ ОКОНЧЕН", 44, UiStyle.GOLD, 12)
		box.add_child(_title)
		_subtitle = UiStyle.label("", 22, UiStyle.TEXT_DIM, 5)
		box.add_child(_subtitle)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		box.add_child(grid)
		var specs := [
			["wave", "swords", "ВОЛН", UiStyle.GOLD],
			["kills", "skull", "ВРАГОВ", UiStyle.DANGER],
			["level", "upgrade", "УРОВЕНЬ", UiStyle.NEON],
			["time", "clock", "ВРЕМЯ", UiStyle.TEXT],
			["coins", "", "МОНЕТЫ", UiStyle.GOLD],
			["gems", "neonite", "НЕОНИТ", BattlePanels.NEONITE],
		]
		for spec in specs:
			var texture: Texture2D = BattlePanels.icon(spec[1]) if not str(spec[1]).is_empty() else null
			if spec[0] == "coins":
				texture = BattlePanels.icon("coin")
			var tile := StatTile.new(texture, spec[2], spec[3])
			grid.add_child(tile)
			_tiles[spec[0]] = tile

		var trophies_head := HBoxContainer.new()
		trophies_head.alignment = BoxContainer.ALIGNMENT_CENTER
		trophies_head.add_theme_constant_override("separation", 8)
		trophies_head.add_child(BattlePanels.icon_rect(BattlePanels.icon("trophy"), 34))
		trophies_head.add_child(UiStyle.label("ТРОФЕИ", 26, UiStyle.TEXT, 7))
		box.add_child(trophies_head)
		_trophies = HFlowContainer.new()
		_trophies.alignment = FlowContainer.ALIGNMENT_CENTER
		_trophies.add_theme_constant_override("h_separation", 10)
		_trophies.add_theme_constant_override("v_separation", 8)
		box.add_child(_trophies)
		_no_trophies = UiStyle.label("Пока пусто — стволы из ящиков и чертежи с боссов попадут сюда", 19, UiStyle.TEXT_DIM, 4)
		_no_trophies.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_no_trophies)
		_total = UiStyle.label("", 22, UiStyle.TEXT_DIM, 5)
		box.add_child(_total)
		_double_button = _make_double_button()
		right.add_child(_double_button)

		_tip_box = PanelContainer.new()
		_tip_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.16, 0.1, 0.05, 0.95), Color("#ff9a3d"), 4, 18))
		_tip_label = UiStyle.label("", 20, Color("#ffe2b8"), 5)
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_box.add_child(_tip_label)
		_tip_box.visible = false
		right.add_child(_tip_box)
		_upgrade_button = UiStyle.button("ПРОКАЧАТЬСЯ", Color("#2fae5f"), 34, Vector2(0, 92))
		_upgrade_button.pressed.connect(func() -> void: upgrade_pressed.emit())
		_upgrade_button.visible = false
		right.add_child(_upgrade_button)
		var again := BattlePanels.icon_button(BattlePanels.icon("play"), "ЕЩЁ РАЗ", "", UiStyle.HOT, 100)
		again.pressed.connect(func() -> void: restart_pressed.emit())
		right.add_child(again)
		var hub := UiStyle.button("НА БАЗУ", UiStyle.PANEL_LIGHT, 28, Vector2(0, 76))
		hub.pressed.connect(func() -> void: menu_pressed.emit())
		right.add_child(hub)

	func _make_double_button() -> Button:
		var button := UiStyle.button("УДВОИТЬ НАГРАДУ · реклама", Color("#2f7ae5"), 22, Vector2(0, 92))
		button.add_theme_stylebox_override("normal", _padded(button, "normal"))
		button.add_theme_stylebox_override("hover", _padded(button, "hover"))
		button.add_theme_stylebox_override("pressed", _padded(button, "pressed"))
		var icon := TextureRect.new()
		icon.texture = ArenaProp.texture_of("res://assets/ui/hub/ad_x2.png")
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		icon.offset_left = 10.0
		icon.offset_right = 86.0
		icon.offset_top = 6.0
		icon.offset_bottom = -6.0
		button.add_child(icon)
		button.pressed.connect(_on_double)
		return button

	func _padded(button: Button, state: String) -> StyleBox:
		var box := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		box.content_margin_left = 90.0
		return box

	func _on_double() -> void:
		Platform.show_rewarded_ad(func(ok: bool) -> void:
			if not ok or not _double_button.visible:
				return
			SaveService.add_coins(_reward_coins)
			SaveService.add_gems(_reward_gems)
			SoundManager.play(&"star_dust")
			(_tiles["coins"] as StatTile).count_to(_reward_coins * 2, 0.5, "+")
			(_tiles["gems"] as StatTile).count_to(_reward_gems * 2, 0.5, "+")
			_total.text = "На счету: %s · %s" % [SaveService.format_coins(SaveService.get_coins()), Economy.format_gems(SaveService.get_gems())]
			_double_button.visible = false)

	func open(summary: Dictionary) -> void:
		_reward_coins = int(summary.get("coins", 0))
		_reward_gems = int(summary.get("gems", 0))
		_double_button.visible = _reward_coins + _reward_gems > 0
		var record := bool(summary.get("record", false))
		var bosses := int(summary.get("bosses", 0))
		_title.text = "НОВЫЙ РЕКОРД!" if record else ("ГЛАВА ПРОЙДЕНА!" if bosses > 0 else "ЗАБЕГ ОКОНЧЕН")
		_title.add_theme_color_override("font_color", Color("#7cff6b") if record else UiStyle.GOLD)
		var line := "%s · лучший результат: %d волн" % [str(summary.get("chapter", "")), int(summary.get("best_wave", 0))]
		if bosses > 0:
			line += " · боссов: %d" % bosses
		_subtitle.text = line
		(_tiles["wave"] as StatTile).count_to(int(summary.get("wave", 0)), 0.15)
		(_tiles["kills"] as StatTile).count_to(int(summary.get("kills", 0)), 0.25)
		(_tiles["level"] as StatTile).count_to(int(summary.get("level", 1)), 0.35)
		(_tiles["time"] as StatTile).set_text(BattleBase.format_time(float(summary.get("time", 0.0))))
		(_tiles["coins"] as StatTile).count_to(int(summary.get("coins", 0)), 0.45, "+")
		(_tiles["gems"] as StatTile).count_to(int(summary.get("gems", 0)), 0.55, "+")
		for child in _trophies.get_children():
			child.queue_free()
		var loot: Array = summary.get("loot", [])
		for pair in loot:
			_trophies.add_child(TrophyTile.new("weapon", str(pair[0]), int(pair[1])))
		for key in summary.get("blueprints", []):
			_trophies.add_child(TrophyTile.new("blueprint", str(key), 1))
		_no_trophies.visible = loot.is_empty() and (summary.get("blueprints", []) as Array).is_empty()
		_trophies.visible = not _no_trophies.visible
		_total.text = "На счету: %s · %s" % [SaveService.format_coins(int(summary.get("total_coins", 0))), Economy.format_gems(SaveService.get_gems())]
		var tip := str(summary.get("tip", ""))
		_tip_box.visible = not tip.is_empty()
		_upgrade_button.visible = not tip.is_empty()
		_tip_label.text = tip
		visible = true
		UiStyle.pop_in(_panel, 0.6)
