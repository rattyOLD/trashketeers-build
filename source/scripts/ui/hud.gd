class_name Hud
extends CanvasLayer
## Боевой интерфейс. PROCESS_MODE_ALWAYS — чтобы окна прокачки, паузы и результата
## работали, пока дерево на паузе. Джойстик внутри явно PAUSABLE.
## Раскладка под портрет: сверху HP/XP, волна по центру, монеты и пауза справа (+ мини-карта);
## снизу слева — джойстик, справа — полупрозрачные кнопки РЫВОК и карточка ствола.

signal upgrade_chosen(upgrade: UpgradeData)
signal reroll_requested
signal upgrade_pressed
signal restart_pressed
signal menu_pressed
signal dash_pressed
signal skill_pressed
signal slot_pressed(index: int)
signal interact_pressed
signal weapon_swiped
signal orders_requested
signal pause_pressed
signal resume_pressed
signal revive_requested(with_ad: bool)
signal revive_declined

var joystick: VirtualJoystick

var _root: Control
var _hp_bar: HudWidgets.OutlineBar
var _hp_label: Label
var _hp_last := -1.0
var _level_last := -1
var _wave_last := -1
var _kills_last := 0
var _low_said := false
var _hp_flash := 0.0
var _xp_bar: HudWidgets.OutlineBar
var _xp_title: Label
var _portrait: HudWidgets.DamagePortrait
var _xp_row: HBoxContainer
var _level_label: Label
var _xp_label: Label
var _nuts_label: Label
var _nuts_row: HBoxContainer
var _time_label: Label
var _kills_label: Label
var _loot_label: Label
var _fps_label: Label
var _wave_label: Label
var _wave_box: PanelContainer
var _barks: HudBarks
var _enemies_chip: PanelContainer
var _enemies_label: Label
var _kills_chip: PanelContainer
var _level_badge: Control
var _boss_bar: BossBar
var _banner: Label
var _wave_title: Label
var _title_tween: Tween
var _wave_sub: Label
var _countdown: Label
var _toast: PanelContainer
var _toast_title: Label
var _toast_text: Label
var _weapon_chip: PanelContainer
var _weapon_icon: WeaponIcons.IconRect
var _weapon_name: Label
var _dash: DashButton
const HUD_TEXT_BOOST := 1.3
var _skill: SkillButton
var _rail_combo: Label
var _slot_bar: BattleControls.SlotBar
var _interact: BattleControls.InteractButton
var _layout_revision := -1
var _hold: LayoutHold
var _editor: BattleLayoutEditor
var _pause_button: Button
var _story_meter: Control
var _items_clock := 0.0
var _minimap_slot: Control
var _level_up: LevelUpPanel
var _result: ResultPanel
var _thermos: Button
var _pause: PausePanel
var _revive: BattlePanels.RevivePanel
var _run_result: BattlePanels.RunResultPanel
var _chapter_card: BattlePanels.ChapterCard
var _hint: HintBubble
var _left_column: VBoxContainer
var _order_card: OrderCard
var _story_bar: StoryBar
var _minimap: Minimap
var _toast_queue: Array = []
var _toast_busy := false
var _toast_y := 168.0 if Orient.portrait else 440.0
var _minimal := false
var _wanted_label: Label
var _low_hp := false
var _pulse := 0.0


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func build(currency_icon: Texture2D, weapon: WeaponData) -> void:
	_minimal = bool(SaveService.data.get("min_hud", false))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	joystick = VirtualJoystick.new()
	_root.add_child(joystick)

	_root.add_child(_build_top_bar(currency_icon))
	_root.add_child(_build_boss_bar())
	_root.add_child(_build_banner())
	_root.add_child(_build_wave_titles())
	_root.add_child(_build_minimap_slot())
	_root.move_child(_minimap_slot, 0)
	_root.add_child(_wave_box)
	_barks = HudBarks.new()
	UiStyle.anchor(_barks, Vector2(1.0, 0.0), Rect2(-388, 192, 176, 176))
	_root.add_child(_barks)
	_rail_combo = UiStyle.label("", 46, UiStyle.GOLD, 12)
	_rail_combo.anchor_left = 0.0
	_rail_combo.anchor_right = 1.0
	_rail_combo.offset_top = 250.0
	_rail_combo.offset_bottom = 320.0
	_rail_combo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_combo.visible = false
	_root.add_child(_rail_combo)
	_root.add_child(_build_weapon_chip(weapon))
	_weapon_chip.visible = false
	var swipe := BattleControls.SwipeSwitch.new()
	swipe.swiped.connect(func() -> void: weapon_swiped.emit())
	_root.add_child(swipe)
	_dash = DashButton.new()
	_dash.pressed.connect(func() -> void: dash_pressed.emit())
	_root.add_child(_dash)
	_skill = SkillButton.new()
	_skill.visible = false
	_skill.pressed.connect(func() -> void: skill_pressed.emit())
	_root.add_child(_skill)
	_slot_bar = BattleControls.SlotBar.new()
	_slot_bar.slot_pressed.connect(func(i: int) -> void: slot_pressed.emit(i))
	_root.add_child(_slot_bar)
	_interact = BattleControls.InteractButton.new()
	_interact.pressed.connect(func() -> void: interact_pressed.emit())
	_root.add_child(_interact)
	_root.resized.connect(apply_layout)
	_root.add_child(_build_toast())
	_chapter_card = BattlePanels.ChapterCard.new()
	_root.add_child(_chapter_card)

	_level_up = LevelUpPanel.new()
	_level_up.chosen.connect(func(u: UpgradeData) -> void: upgrade_chosen.emit(u))
	_level_up.reroll_requested.connect(func() -> void: reroll_requested.emit())
	_root.add_child(_level_up)

	_pause = PausePanel.new()
	_pause.resumed.connect(func() -> void: resume_pressed.emit())
	_pause.exit_pressed.connect(func() -> void: menu_pressed.emit())
	_pause.restart_pressed.connect(func() -> void: restart_pressed.emit())
	_root.add_child(_pause)

	_result = ResultPanel.new()
	_result.restart_pressed.connect(func() -> void: restart_pressed.emit())
	_result.menu_pressed.connect(func() -> void: menu_pressed.emit())
	_result.upgrade_pressed.connect(func() -> void: upgrade_pressed.emit())
	_root.add_child(_result)

	_revive = BattlePanels.RevivePanel.new()
	_revive.revive.connect(func(with_ad: bool) -> void: revive_requested.emit(with_ad))
	_revive.expired.connect(func() -> void: revive_declined.emit())
	_revive.exit_pressed.connect(func() -> void: menu_pressed.emit())
	_root.add_child(_revive)

	_run_result = BattlePanels.RunResultPanel.new(currency_icon)
	_run_result.restart_pressed.connect(func() -> void: restart_pressed.emit())
	_run_result.menu_pressed.connect(func() -> void: menu_pressed.emit())
	_run_result.upgrade_pressed.connect(func() -> void: upgrade_pressed.emit())
	_root.add_child(_run_result)
	_fps_label.visible = bool(SaveService.data["show_fps"]) and not _minimal
	_kills_chip.visible = not _minimal
	_hint = HintBubble.new()
	_root.add_child(_hint)
	if Platform.is_touch():
		var panels: Array[Node] = [_level_up, _pause, _result, _revive, _run_result, _chapter_card, _hint]
		for child in _root.get_children():
			if not panels.has(child):
				UiStyle.boost_labels(child, HUD_TEXT_BOOST)
	_wire_hints()
	_hold = LayoutHold.new()
	_hold.targets = {
		"dash": _hold_dash,
		"slots": _hold_slots,
		"interact": _hold_interact,
	}
	for id in Controls.HUD_ELEMENTS:
		if id != "pause":
			_hold.targets[id] = hud_node.bind(id)
	_hold.requested.connect(_open_layout_editor)
	_root.add_child(_hold)
	_dash.held.connect(func() -> void: _hint.show_for(_dash, "Рывок: быстрый бросок от удара."))
	_slot_bar.slot_held.connect(_on_slot_held)


## Тап по элементу интерфейса показывает рядом короткую подсказку, что это.
func _wire_hints() -> void:
	HintBubble.attach(_hp_label.get_parent(), _hint, "Здоровье. Лечат аптечки, освобождённые пленники и вход в новую зону.")
	HintBubble.attach(_nuts_row, _hint, "Монеты, собранные за забег.")
	HintBubble.attach(_time_label, _hint, "Время забега.")
	HintBubble.attach(_kills_chip, _hint, "Сколько врагов побеждено за забег.")
	HintBubble.attach(_enemies_chip, _hint, "Сколько врагов осталось в волне · сколько их сейчас на карте.")
	HintBubble.attach(_loot_label, _hint, "Оружие, которое лежит на карте и ждёт, когда его подберут.")


func _on_slot_held(index: int) -> void:
	var weapon: WeaponData = _slot_bar.weapons[index] if index < _slot_bar.weapons.size() else null
	if weapon == null:
		_hint.show_for(_slot_bar, "Пустой слот. Подобранное оружие встанет сюда.")
		return
	_hint.show_for(_slot_bar, "Слот %d: %s. %s. Тап по слоту — взять это оружие." % [index + 1, weapon.get_title(), Tips.stat_line(weapon).capitalize()])


## Сюжет: на месте опыта — шкала деталей супер-ствола и плашки очков, жизней и зоны.
func dock_story_meter(meter: Control) -> void:
	_story_meter = meter
	meter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left_column.add_child(meter)
	_dock_barks()
	HintBubble.attach(meter, _hint, "Детали супер-ствола. Собери все 6 из зачищенных комнат и получишь 30 секунд режима аннигиляции.")


func set_story_layout(minimap: Minimap) -> void:
	_wave_box.visible = false
	_enemies_chip.visible = false
	_toast_y = 556.0 if Orient.portrait else 440.0
	_story_bar = StoryBar.new()
	_left_column.add_child(_story_bar)
	_order_card = OrderCard.new()
	_order_card.minimal = _minimal
	_order_card.pressed.connect(func() -> void: orders_requested.emit())
	_left_column.add_child(_order_card)
	_story_bar.chip_tapped.connect(func(chip: Control, text: String) -> void: _hint.show_for(chip, text))
	_dock_barks()
	if Orient.portrait:
		UiStyle.anchor(_boss_bar, Vector2(0.5, 0.0), Rect2(-240, 462, 480, 84))
	else:
		_boss_bar.anchor_left = 0.0
		_boss_bar.anchor_right = 1.0
		_boss_bar.anchor_top = 0.0
		_boss_bar.anchor_bottom = 0.0
		_boss_bar.offset_left = 300.0
		_boss_bar.offset_right = -300.0
		_boss_bar.offset_top = 600.0
		_boss_bar.offset_bottom = 684.0
	UiStyle.anchor(_minimap_slot, Vector2(1.0, 0.0), Rect2(-150, 520, 132, 230) if Orient.portrait else Rect2(-150, 150, 132, 230))
	_minimap = minimap
	minimap.tapped.connect(func(overview: bool) -> void:
		_hint.show_for(_minimap_slot, "Карта. Тап: %s." % ("крупный план" if overview else "вся карта")))


## Заказ Нэлл выполнен: плашка вспыхивает и сменяется новым заказом.
func order_completed(info: Dictionary) -> void:
	if _order_card != null:
		_order_card.celebrate(str(info.get("title", "")), int(info.get("goal", 1)))


func set_survival_order(order: Dictionary) -> void:
	if _order_card == null:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, 44.0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_left_column.add_child(spacer)
		_order_card = OrderCard.new()
		_order_card.minimal = _minimal
		_order_card.pressed.connect(func() -> void: orders_requested.emit())
		_left_column.add_child(_order_card)
		_dock_barks()
	_order_card.set_order(str(order.get("title", "")), int(order.get("progress", 0)), int(order.get("goal", 1)), bool(order.get("done", false)))


func set_story_status(score: int, lives: int, zone_number: int, zone_count: int, zone_name: String, enemies_left: int = -1, order: Dictionary = {}, goals: Array = []) -> void:
	if _order_card != null:
		_order_card.set_goals(goals)
		_order_card.set_order(str(order.get("title", "")), int(order.get("progress", 0)), int(order.get("goal", 1)), bool(order.get("done", false)))
	if _story_bar != null:
		_story_bar.update(score, lives, zone_number, zone_count, zone_name, enemies_left)


# --- Показатели ------------------------------------------------------------------------------

func set_health(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	if _hp_last >= 0.0 and hp > _hp_last + 0.3 and hp < max_hp + 0.01:
		_hp_flash = maxf(_hp_flash, clampf((hp - _hp_last) / 6.0, 0.35, 1.0))
	var healed := _hp_last >= 0.0 and hp > _hp_last + max_hp * 0.2
	_hp_last = hp
	_low_hp = max_hp > 0.0 and hp / max_hp < 0.3 and hp > 0.0
	if _barks != null:
		if _low_hp and not _low_said:
			_low_said = true
			_barks.say("low_hp", true)
		elif hp / maxf(max_hp, 1.0) > 0.6:
			_low_said = false
		if healed:
			_barks.say("heal")
	if not _low_hp:
		_hp_bar.modulate = Color.WHITE
	_hp_bar.value = hp
	var frac := hp / maxf(max_hp, 1.0)
	_hp_bar.fill_index = 0 if frac > 0.35 else (1 if frac > 0.15 else 2)
	_portrait.set_health(frac)
	_hp_label.text = "%d / %d" % [ceili(hp), roundi(max_hp)]


func set_xp(xp: int, needed: int, level: int) -> void:
	_xp_bar.max_value = needed
	_xp_bar.value = xp
	if _barks != null and _level_last >= 0 and level > _level_last:
		_barks.say("level", true)
	_level_last = level
	_level_label.text = str(level)
	_xp_title.text = "УР %d" % level
	_xp_label.text = "%d/%d" % [xp, needed]


func set_nuts(amount: int) -> void:
	_nuts_label.text = str(amount)


## Счётчик монет «подпрыгивает» при подборе.
func punch_nuts() -> void:
	UiStyle.keep_pivot_centered(_nuts_row)
	var tween := _nuts_row.create_tween()
	tween.tween_property(_nuts_row, "scale", Vector2.ONE * 1.25, 0.06)
	tween.tween_property(_nuts_row, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)


func flash_xp() -> void:
	var tween := _xp_bar.create_tween()
	_xp_bar.modulate = Color(1.8, 1.8, 1.8)
	tween.tween_property(_xp_bar, "modulate", Color.WHITE, 0.25)


func set_time(seconds: float) -> void:
	_time_label.text = BattleBase.format_time(seconds)


func set_time_text(text: String, color: Color = UiStyle.TEXT) -> void:
	_time_label.text = text
	_time_label.add_theme_color_override("font_color", color)


## Налёт: без опыта, волн, мини-карты и счётчика крыс.
func configure_for_raid() -> void:
	_xp_row.visible = false
	_level_badge.visible = false
	_kills_chip.visible = false
	_enemies_chip.visible = false
	_wave_box.visible = false
	_minimap_slot.visible = false


func set_loot_left(count: int) -> void:
	_loot_label.visible = count > 0 and not _minimal
	if count > 0:
		_loot_label.text = "Лут на карте: %d" % count


func set_kills(kills: int) -> void:
	if _barks != null and kills / 100 > _kills_last / 100:
		_barks.say("kills")
	_kills_last = kills
	_kills_label.text = "Убито: %d" % kills


func set_wave(number: int, enemies_left: int, chapter: int = 0, alive: int = -1) -> void:
	if _barks != null and number != _wave_last:
		_barks.say("start" if _wave_last < 0 else "wave")
	_wave_last = number
	_wave_label.text = "ГЛ.%d · ВОЛНА %d" % [chapter, number] if chapter > 0 else "ВОЛНА %d" % number
	_enemies_chip.visible = enemies_left > 0 and not _minimal and _story_bar == null
	_enemies_label.text = "%d · %d" % [enemies_left, alive] if alive >= 0 else str(enemies_left)


## Сюжетный режим без ио-механик: скрываем опыт и уровень.
func set_story_mode() -> void:
	_xp_row.visible = false
	_level_badge.visible = false
	_slot_bar.visible = false


func set_wave_text(text: String) -> void:
	_wave_label.text = text


func set_weapon(weapon: WeaponData) -> void:
	_weapon_icon.set_weapon(weapon.icon, weapon.effect_color)
	_weapon_name.text = weapon.get_title()
	_weapon_name.add_theme_color_override("font_color", weapon.get_rarity_color())
	_weapon_chip.add_theme_stylebox_override("panel", UiStyle.box(Color(0.08, 0.05, 0.15, 0.55), Color(weapon.get_rarity_color(), 0.8), 3, 16))
	UiStyle.pop_in(_weapon_chip, 0.4)


func set_slots(weapons: Array, active: int, count: int) -> void:
	_slot_bar.set_slots(weapons, active, count)
	apply_layout()


func set_interact(weapon: WeaponData, note: String = "") -> void:
	_interact.show_for(weapon, note)


func _hold_dash() -> Control:
	if _skill.visible:
		return _skill
	return _dash


func _hold_slots() -> Control:
	return _slot_bar


func _hold_interact() -> Control:
	return _interact


func hud_node(id: String) -> Control:
	match id:
		"hp":
			return _hp_label.get_parent() as Control
		"xp":
			return _xp_row
		"coins":
			return _nuts_row
		"pause":
			return _pause_button
		"time":
			return _time_label
		"kills":
			return _kills_chip
		"loot":
			return _loot_label
		"fps":
			return _fps_label
		"wave":
			return _wave_box
		"barks":
			return _barks
		"boss":
			return _boss_bar
		"minimap":
			return _minimap_slot
		"order":
			return _order_card
		"story_bar":
			return _story_bar
		"story_meter":
			return _story_meter
		"wanted":
			return _wanted_label
	return null


func element_node(id: String) -> Control:
	match id:
		"dash":
			return _hold_dash()
		"slots":
			return _slot_bar
		"interact":
			return _interact
	return hud_node(id)


func editable_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in ["dash", "slots", "interact"]:
		if _visible_node(element_node(id)):
			ids.append(id)
	for id in Controls.HUD_ELEMENTS:
		if _visible_node(hud_node(id)):
			ids.append(id)
	return ids


func element_rect(id: String) -> Rect2:
	var node := element_node(id)
	if not _visible_node(node):
		return Rect2()
	return Rect2(node.get_global_position(), node.size * node.get_global_transform().get_scale())


func _visible_node(node: Control) -> bool:
	return node != null and node.is_visible_in_tree() and node.size.x > 1.0


func _pin(node: Control, center: Vector2) -> void:
	if not node.has_meta("hud_orig"):
		node.set_meta("hud_orig", {
			"anchors": [node.anchor_left, node.anchor_top, node.anchor_right, node.anchor_bottom],
			"offsets": [node.offset_left, node.offset_top, node.offset_right, node.offset_bottom],
			"size": node.size,
		})
		var parent := node.get_parent() as Control
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			node.set_anchor(side as Side, 0.0, true, false)
		node.top_level = true
		if parent is Container:
			(parent as Container).queue_sort()
	var orig: Dictionary = node.get_meta("hud_orig")
	var base: Vector2 = orig["size"]
	node.size = base
	node.position = center - base * 0.5


func _unpin(node: Control) -> void:
	if not node.has_meta("hud_orig"):
		return
	var orig: Dictionary = node.get_meta("hud_orig")
	node.remove_meta("hud_orig")
	node.top_level = false
	var anchors: Array = orig["anchors"]
	var offsets: Array = orig["offsets"]
	node.anchor_left = float(anchors[0])
	node.anchor_top = float(anchors[1])
	node.anchor_right = float(anchors[2])
	node.anchor_bottom = float(anchors[3])
	node.offset_left = float(offsets[0])
	node.offset_top = float(offsets[1])
	node.offset_right = float(offsets[2])
	node.offset_bottom = float(offsets[3])
	var parent := node.get_parent() as Control
	if parent is Container:
		(parent as Container).queue_sort()


func _apply_hud_items() -> void:
	var area := _root.size
	for id in Controls.HUD_ELEMENTS:
		var node := hud_node(id)
		if node == null:
			continue
		var item := Controls.hud_item(id)
		var factor := clampf(float(item.get("s", 1.0)), 0.5, 1.8)
		var alpha := clampf(float(item.get("o", 1.0)), 0.2, 1.0)
		if item.has("x") and item.has("y"):
			var base: Vector2 = node.get_meta("hud_orig")["size"] if node.has_meta("hud_orig") else node.size
			if base.x > 1.0:
				_pin(node, Vector2(float(item["x"]) * area.x, float(item["y"]) * area.y))
		else:
			_unpin(node)
		node.pivot_offset = node.size * 0.5
		node.set_meta("ui_scale", factor)
		node.set_meta("ui_alpha", alpha)
		node.scale = Vector2.ONE * factor
		node.modulate.a = alpha


## Правка интерфейса прямо в бою: пауза, фон прозрачный, любой элемент двигается, меняет размер и прозрачность.
func _open_layout_editor(id: String) -> void:
	if _editor != null or get_tree().paused or _result.visible or _revive.visible:
		return
	get_tree().paused = true
	var fake_boss := not _boss_bar.visible
	if fake_boss:
		show_boss("Босс", 1.0, 1.0)
	_editor = BattleLayoutEditor.new()
	_editor.hud = self
	_root.add_child(_editor)
	_editor.size = _root.size
	_editor.select(id)
	_editor.closed.connect(func() -> void:
		_editor.queue_free()
		_editor = null
		if fake_boss:
			hide_boss()
		apply_layout()
		get_tree().paused = false)
	_editor.open()


func apply_layout() -> void:
	if _root == null or _slot_bar == null:
		return
	var area := _root.size
	Controls.place(_dash, "dash", area)
	Controls.place(_skill, "dash", area)
	Controls.place(_slot_bar, "slots", area, BattleControls.slots_base_size(_slot_bar.count))
	Controls.place(_interact, "interact", area)
	_resolve_button_overlap(area)
	var opacity := clampf(float(Controls.get_value("opacity")), 0.3, 1.0)
	_dash.modulate.a = opacity * Controls.element_opacity("dash")
	_skill.modulate.a = opacity * Controls.element_opacity("dash")
	_slot_bar.modulate.a = opacity * Controls.element_opacity("slots")
	_interact.modulate.a = Controls.element_opacity("interact")
	joystick.modulate.a = opacity
	_apply_hud_items()
	_layout_revision = Controls.revision


func _resolve_button_overlap(area: Vector2) -> void:
	var main_btn: Control = _skill if _skill.visible else _dash
	var slot_rect := Rect2(_slot_bar.position, _slot_bar.size).grow(6.0)
	if not slot_rect.intersects(Rect2(main_btn.position, main_btn.size)):
		return
	var gap := 14.0
	var left_side := main_btn.position.x + main_btn.size.x * 0.5 > area.x * 0.5
	var x := main_btn.position.x - gap - _slot_bar.size.x if left_side else main_btn.position.x + main_btn.size.x + gap
	var y := main_btn.position.y + main_btn.size.y - _slot_bar.size.y
	_slot_bar.position = Vector2(clampf(x, 4.0, area.x - _slot_bar.size.x - 4.0), maxf(y, 4.0))


func set_skill(title: String, color: Color) -> void:
	_skill.visible = not title.is_empty()
	_dash.visible = title.is_empty()
	_skill.title = title
	_skill.accent = color
	_skill.queue_redraw()


func set_skill_cooldown(fraction: float) -> void:
	_skill.cooldown = clampf(fraction, 0.0, 1.0)


func set_dash_cooldown(fraction: float) -> void:
	_dash.cooldown = clampf(fraction, 0.0, 1.0)


## Рельс-комбо для рельсотрона: 0 — скрыть. Цвет от золотого к розовому по мере роста.
func set_rail_combo(count: int) -> void:
	if count <= 0:
		_rail_combo.visible = false
		return
	_rail_combo.visible = true
	_rail_combo.text = "РЕЛЬС-КОМБО ×%d" % count
	var heat := clampf(float(count) / 60.0, 0.0, 1.0)
	_rail_combo.add_theme_color_override("font_color", UiStyle.GOLD.lerp(Color("#ff4fd8"), heat))
	_rail_combo.pivot_offset = _rail_combo.size * 0.5
	_rail_combo.scale = Vector2.ONE * (1.18 + 0.1 * heat)
	create_tween().tween_property(_rail_combo, "scale", Vector2.ONE, 0.18)


func set_dash_charges(charges: int, max_charges: int) -> void:
	_dash.set_charges(charges, max_charges)


func set_minimap(minimap: Control) -> void:
	_minimap = minimap as Minimap
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_slot.add_child(minimap)
	minimap.visible = SaveService.is_minimap_enabled()
	_minimap_slot.visible = minimap.visible
	minimap.enlarge_toggled.connect(_on_minimap_enlarge)


## Тап по миникарте выживания: увеличить (в два раза) или вернуть как было.
func _on_minimap_enlarge(big: bool) -> void:
	var rect := Rect2(-314, 192, 296, 296) if big else Rect2(-194, 192, 176, 176)
	UiStyle.anchor(_minimap_slot, Vector2(1.0, 0.0), rect)
	if _barks != null:
		_barks.visible = not big
	_hint.show_for(_minimap_slot, "Карта крупно. Тап по ней: уменьшить." if big else "Карта обычная. Тап: увеличить.")


# --- Босс, баннеры, заставки ------------------------------------------------------------------

func show_boss(boss_name: String, hp: float, max_hp: float, winged: bool = false) -> void:
	_boss_bar.configure(boss_name, winged)
	if _barks != null and not _boss_bar.visible:
		_barks.say("boss", true)
	update_boss(hp, max_hp)
	_boss_bar.visible = true
	UiStyle.pop_in(_boss_bar, 0.5)


func update_boss(hp: float, max_hp: float) -> void:
	_boss_bar.set_health(hp, max_hp)


func set_boss_posture(fraction: float, broken: bool) -> void:
	_boss_bar.set_posture(fraction, broken)


func set_boss_title(text: String) -> void:
	_boss_bar.set_title(text)


## Кнопка лечебного термоса налёта у правого края экрана.
func add_thermos(callback: Callable) -> Button:
	var button := UiStyle.button("ТЕРМОС ×2", Color("#d9782a"), 22, Vector2(150, 96))
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.5
	button.anchor_bottom = 0.5
	button.offset_left = -180.0
	button.offset_right = -24.0
	button.offset_top = -48.0
	button.offset_bottom = 48.0
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	_root.add_child(button)
	_thermos = button
	return button


func _hide_thermos() -> void:
	if _thermos != null:
		_thermos.visible = false


func set_boss_fury() -> void:
	_boss_bar.set_fury()


func hide_boss() -> void:
	_boss_bar.visible = false


func show_banner(text: String, color: Color, duration: float = 2.2) -> void:
	duration = minf(duration, 1.8)
	var half := minf(350.0, (_root.size.x - 28.0) * 0.5)
	_banner.offset_left = -half
	_banner.offset_right = half
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner.modulate.a = 1.0
	UiStyle.pop_in(_banner, 0.5)
	var tween := _banner.create_tween()
	tween.tween_interval(duration)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void: _banner.visible = false)


## Заставка волны: крупное «ВОЛНА N» влетает сверху, подзаголовок — снизу.
func show_wave_intro(number: int, title: String, is_boss: bool, chapter: int = 0) -> void:
	_wave_title.text = "ГЛАВА %d · ВОЛНА %d" % [chapter, number] if chapter > 0 else "ВОЛНА %d" % number
	_wave_title.add_theme_font_size_override("font_size", (78 if Orient.portrait else 56) if chapter <= 0 else (50 if Orient.portrait else 40))
	_wave_title.add_theme_color_override("font_color", UiStyle.DANGER if is_boss else UiStyle.GOLD)
	_wave_sub.text = ("БОСС: " + title) if is_boss else title
	_animate_titles(1.0)


func show_wave_cleared(bonus_nuts: int) -> void:
	_wave_title.add_theme_font_size_override("font_size", 78 if Orient.portrait else 56)
	_wave_title.text = "ВОЛНА ОЧИЩЕНА!"
	_wave_title.add_theme_color_override("font_color", Color("#7cff6b"))
	_wave_sub.text = "+%s · лечение +15%%" % SaveService.format_coins(bonus_nuts)
	_animate_titles(0.9)


func show_countdown(seconds: int) -> void:
	_countdown.text = "Следующая волна через %d" % seconds
	_countdown.visible = true
	_countdown.modulate.a = 1.0
	UiStyle.keep_pivot_centered(_countdown)
	_countdown.scale = Vector2.ONE * 1.3
	var tween := _countdown.create_tween()
	tween.tween_property(_countdown, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(0.55)
	tween.tween_property(_countdown, "modulate:a", 0.0, 0.2)


func set_wanted(level: int) -> void:
	if _wanted_label == null:
		_wanted_label = UiStyle.label("", 18, Color("#ff6a6a"), 5)
		_wanted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_wanted_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_left_column.add_child(_wanted_label)
		_dock_barks()
	_wanted_label.text = ("РОЗЫСК %s" % "★".repeat(level)) if level > 0 else ""
	_wanted_label.visible = level > 0


func show_mod_badge(title: String) -> void:
	var badge := UiStyle.label("МОД: %s ×%.1f" % [title, RunMods.mult_of(RunMods.active)], 15, Color("#ff9a3d"), 5)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_child(badge)
	_dock_barks()
	if RunMods.has(&"no_dash"):
		_dash.modulate.a = 0.25


func toast(title: String, text: String, color: Color = UiStyle.GOLD) -> void:
	_toast_queue.append([title, text, color])
	if not _toast_busy:
		_next_toast()


func show_level_up(choices: Array[UpgradeData], level: int, stats: RunStats, bonus: bool = false, reroll_text: String = "", reroll_ok: bool = false) -> void:
	_clear_wave_titles()
	_level_up.open(choices, level, stats, bonus, reroll_text, reroll_ok)


func show_result(victory: bool, lines: PackedStringArray, title: String = "", can_upgrade: bool = true) -> void:
	_clear_wave_titles()
	_pause.visible = false
	_hide_thermos()
	_result.open(victory, lines, title, can_upgrade)


func show_chapter(subtitle: String, title: String, accent: Color = UiStyle.NEON) -> void:
	_chapter_card.play(subtitle, title, accent)


func show_revive(cost: int, gems: int, ad_available: bool, summary: Dictionary) -> void:
	_clear_wave_titles()
	_pause.visible = false
	_level_up.visible = false
	_revive.open(cost, gems, ad_available, summary)


func hide_revive() -> void:
	_revive.close()


func revive_failed(message: String) -> void:
	_revive.fail(message)


func show_run_result(summary: Dictionary) -> void:
	_clear_wave_titles()
	_pause.visible = false
	_hide_thermos()
	_revive.close()
	_run_result.open(summary)


func show_pause(lines: PackedStringArray) -> void:
	_clear_wave_titles()
	_pause.open(lines)


func is_pause_open() -> bool:
	return _pause.visible


func _process(delta: float) -> void:
	_items_clock += delta
	if _layout_revision != Controls.revision or _items_clock >= 0.25:
		_items_clock = 0.0
		apply_layout()
	if _hp_flash > 0.0:
		_hp_flash = maxf(_hp_flash - delta * 3.0, 0.0)
		_hp_bar.modulate = Color.WHITE.lerp(Color(0.6, 1.6, 0.75), _hp_flash)
	elif _low_hp:
		_pulse += delta * 7.0
		_hp_bar.modulate = Color.WHITE.lerp(Color(1.7, 0.45, 0.45), 0.5 + 0.5 * sin(_pulse))
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


## Любое окно поверх боя (пауза, прокачка, итог) сразу убирает крупную надпись волны, иначе она торчит из-под окна.
func _clear_wave_titles() -> void:
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	for label in [_wave_title, _wave_sub]:
		if label != null:
			label.modulate.a = 0.0


func _animate_titles(hold: float) -> void:
	for label in [_wave_title, _wave_sub]:
		label.visible = true
		label.modulate.a = 0.0
	UiStyle.keep_pivot_centered(_wave_title)
	_wave_title.scale = Vector2.ONE * 2.2
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	var tween := _wave_title.create_tween().set_parallel(true)
	_title_tween = tween
	tween.tween_property(_wave_title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_wave_title, "modulate:a", 1.0, 0.2)
	tween.tween_property(_wave_sub, "modulate:a", 1.0, 0.3).set_delay(0.2)
	tween.chain().tween_interval(hold)
	tween.chain().tween_property(_wave_title, "modulate:a", 0.0, 0.35)
	tween.parallel().tween_property(_wave_sub, "modulate:a", 0.0, 0.35)


## Однострочная подпись: кегль уменьшается, пока текст не влезет в ширину.
func _fit_font(label: Label, base: int, max_width: float) -> void:
	var font := label.get_theme_font("font")
	var size := base
	while size > 12 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > max_width:
		size -= 1
	label.add_theme_font_size_override("font_size", size)


func _next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	var item: Array = _toast_queue.pop_front()
	var half := minf(300.0, (_root.size.x - 36.0) * 0.5)
	_toast.offset_left = -half
	_toast.offset_right = half
	_toast_title.custom_minimum_size.x = half * 2.0 - 40.0
	_toast_text.custom_minimum_size.x = half * 2.0 - 40.0
	_toast.custom_minimum_size = Vector2(half * 2.0, 0.0)
	_toast_title.text = item[0]
	_toast_text.text = item[1]
	_fit_font(_toast_title, 28, half * 2.0 - 48.0)
	_fit_font(_toast_text, 20, half * 2.0 - 48.0)
	_toast.size = Vector2(half * 2.0, 0.0)
	_toast.reset_size.call_deferred()
	_toast_title.add_theme_color_override("font_color", item[2])
	_toast.visible = true
	_toast.position.y = -140.0
	var tween := _toast.create_tween()
	tween.tween_property(_toast, "position:y", _toast_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.8)
	tween.tween_property(_toast, "position:y", -140.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_toast.visible = false
		_next_toast())


# --- Построение ----------------------------------------------------------------------------------

## Чат друзей всегда в конце левой колонки: под заданием и прочими плашками.
func _dock_barks() -> void:
	if _barks == null or _left_column == null or _barks.get_parent() != _left_column:
		return
	_left_column.move_child(_barks, _left_column.get_child_count() - 1)


func _build_top_bar(currency_icon: Texture2D) -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 18)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(580 if Orient.portrait else 440, 0)
	row.add_child(left)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_left_column = left

	# Шапка как в современных мобильных экшенах: портрет с уровнем, широкие полосы HP и опыта, ниже ряд плашек.
	# Оправа портрета и полоса здоровья стыкуются в одну деталь: полоса «выходит» из-под кольца.
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 108)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(head)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.anchor_right = 1.0
	bars.offset_left = 92.0
	bars.offset_top = 10.0
	head.add_child(bars)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(0, 40)
	bars.add_child(hp_stack)
	_hp_bar = HudWidgets.OutlineBar.new(HudWidgets.OutlineBar.HP_COLORS)
	_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_stack.add_child(_hp_bar)
	_hp_label = UiStyle.label("", 22, UiStyle.TEXT, 6)
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_stack.add_child(_hp_label)

	_xp_row = HBoxContainer.new()
	_xp_row.add_theme_constant_override("separation", 6)
	_xp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(_xp_row)
	var xp_gap := Control.new()
	xp_gap.custom_minimum_size = Vector2(0, 0)
	xp_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_row.add_child(xp_gap)
	_xp_title = UiStyle.label("УР 1", 20, UiStyle.NEON, 5)
	_xp_title.custom_minimum_size = Vector2(0, 0)
	_xp_title.visible = false
	_xp_row.add_child(_xp_title)
	var xp_stack := Control.new()
	xp_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_stack.custom_minimum_size = Vector2(0, 24)
	_xp_row.add_child(xp_stack)
	_xp_bar = HudWidgets.OutlineBar.new(HudWidgets.OutlineBar.XP_COLORS)
	_xp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_stack.add_child(_xp_bar)
	_xp_label = UiStyle.label("0/10", 15, UiStyle.TEXT, 4)
	_xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_stack.add_child(_xp_label)

	_portrait = HudWidgets.DamagePortrait.new()
	_portrait.position = Vector2(0, 0)
	_portrait.set_character(SaveService.get_character())
	head.add_child(_portrait)
	_level_badge = PanelContainer.new()
	_level_badge.add_theme_stylebox_override("panel", UiStyle.box(Color("#1a1030"), UiStyle.GOLD, 3, 10))
	_level_badge.custom_minimum_size = Vector2(40, 32)
	_level_badge.position = Vector2(62, 70)
	_level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_level_badge)
	_level_label = UiStyle.label("1", 22, UiStyle.GOLD, 5)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_badge.add_child(_level_label)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(chips)
	_build_wave_chip()
	_enemies_chip = _chip(BattlePanels.icon("skull"))
	_enemies_label = _enemies_chip.get_child(0).get_child(1) as Label
	chips.add_child(_enemies_chip)
	_kills_chip = _chip(BattlePanels.icon("swords"))
	_kills_label = _kills_chip.get_child(0).get_child(1) as Label
	_kills_label.text = "Убито: 0"
	chips.add_child(_kills_chip)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(180, 0)
	right.add_theme_constant_override("separation", 2)
	row.add_child(right)

	var top_right := HBoxContainer.new()
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_theme_constant_override("separation", 10)
	right.add_child(top_right)
	_nuts_row = HBoxContainer.new()
	_nuts_row.add_theme_constant_override("separation", 4)
	top_right.add_child(_nuts_row)
	var icon := TextureRect.new()
	icon.texture = currency_icon
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_nuts_row.add_child(icon)
	_nuts_label = UiStyle.label("0", 32, UiStyle.GOLD, 8)
	_nuts_row.add_child(_nuts_label)
	var pause := UiStyle.flat_button(Vector2(76, 76))
	_pause_button = pause
	var pause_icon := BattlePanels.icon_rect(BattlePanels.icon("pause"), 76)
	pause_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.add_child(pause_icon)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	top_right.add_child(pause)

	_time_label = UiStyle.label("0:00", 26, UiStyle.TEXT, 6)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_time_label)
	_loot_label = UiStyle.label("", 17, UiStyle.GOLD, 4)
	_loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loot_label.visible = false
	right.add_child(_loot_label)
	_fps_label = UiStyle.label("", 16, UiStyle.TEXT_DIM, 4)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_fps_label)
	return margin


func _build_wave_chip() -> Control:
	_wave_box = PanelContainer.new()
	_wave_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.08, 0.05, 0.15, 0.6), Color(UiStyle.GOLD, 0.7), 3, 20))
	_wave_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor(_wave_box, Vector2(1.0, 0.0), Rect2(-194, 140, 176, 34))
	_wave_label = UiStyle.label("ВОЛНА 1", 15, UiStyle.GOLD, 4)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_box.add_child(_wave_label)
	return _wave_box


## Плашка шапки: иконка и подпись в рамке.
func _chip(icon: Texture2D) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiStyle.box(Color(0.08, 0.05, 0.15, 0.72), Color(UiStyle.TEXT_DIM, 0.55), 3, 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(BattlePanels.icon_rect(icon, 26))
	var label := UiStyle.label("", 19, UiStyle.TEXT, 5)
	row.add_child(label)
	chip.custom_minimum_size = Vector2(0, 38)
	return chip


func _build_boss_bar() -> Control:
	_boss_bar = BossBar.new()
	UiStyle.anchor(_boss_bar, Vector2(0.5, 0.0), Rect2(-240, 384, 480, 84))
	_boss_bar.visible = false
	return _boss_bar


func _build_banner() -> Control:
	_banner = UiStyle.label("", 34, UiStyle.DANGER, 10)
	UiStyle.anchor(_banner, Vector2(0.5, 0.5), Rect2(-350, -380, 700, 110) if Orient.portrait else Rect2(-350, -280, 700, 80))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.visible = false
	return _banner


func _build_wave_titles() -> Control:
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_title = UiStyle.label("", 78 if Orient.portrait else 56, UiStyle.GOLD, 16)
	UiStyle.anchor(_wave_title, Vector2(0.5, 0.5), Rect2(-360, -250, 720, 110) if Orient.portrait else Rect2(-360, -60, 720, 80))
	_wave_title.visible = false
	box.add_child(_wave_title)
	_wave_sub = UiStyle.label("", 30, UiStyle.TEXT, 8)
	UiStyle.anchor(_wave_sub, Vector2(0.5, 0.5), Rect2(-360, -150, 720, 50) if Orient.portrait else Rect2(-360, 20, 720, 40))
	_wave_sub.visible = false
	box.add_child(_wave_sub)
	_countdown = UiStyle.label("", 30, UiStyle.NEON, 8)
	UiStyle.anchor(_countdown, Vector2(0.5, 0.5), Rect2(-360, -60, 720, 50) if Orient.portrait else Rect2(-360, 70, 720, 40))
	_countdown.visible = false
	box.add_child(_countdown)
	return box


func _build_minimap_slot() -> Control:
	_minimap_slot = Control.new()
	_minimap_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor(_minimap_slot, Vector2(1.0, 0.0), Rect2(-194, 192, 176, 176))
	return _minimap_slot


func _build_weapon_chip(weapon: WeaponData) -> Control:
	_weapon_chip = PanelContainer.new()
	_weapon_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor(_weapon_chip, Vector2(1.0, 1.0), Rect2(-250, -350, 232, 84))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_chip.add_child(column)
	_weapon_icon = WeaponIcons.IconRect.new(weapon.icon, weapon.effect_color, Vector2(200, 44))
	column.add_child(_weapon_icon)
	_weapon_name = UiStyle.label("", 18, UiStyle.TEXT, 5)
	column.add_child(_weapon_name)
	set_weapon(weapon)
	return _weapon_chip


func _build_toast() -> Control:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.06, 0.2, 0.92), UiStyle.GOLD, 4, 22))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -300.0
	_toast.offset_right = 300.0
	_toast.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_toast.add_child(column)
	_toast_title = UiStyle.label("", 24, UiStyle.GOLD, 7)
	column.add_child(_toast_title)
	_toast_text = UiStyle.label("", 17, UiStyle.TEXT, 4)
	column.add_child(_toast_text)
	return _toast


## Полупрозрачная круглая кнопка рывка с сектором перезарядки. Слушает сырые касания
## (ScreenTouch), а не GUI: второй палец при зажатом джойстике GUI не получает.
class SkillButton:
	extends Control
	signal pressed

	var title := ""
	var accent := UiStyle.GOLD
	var cooldown := 0.0:
		set(value):
			if not is_equal_approx(value, cooldown):
				cooldown = value
				queue_redraw()
	var _press := 0.0
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree() or get_tree().paused:
			return
		if event is InputEventScreenTouch and event.pressed:
			if (event as InputEventScreenTouch).position.distance_to(get_global_rect().get_center()) < size.x * 0.55:
				_press = 1.0
				pressed.emit()
				get_viewport().set_input_as_handled()

	var _redraw_gap := 0.0

	func _process(delta: float) -> void:
		_time += delta
		if _press > 0.0:
			_press = maxf(_press - delta * 5.0, 0.0)
		_redraw_gap -= delta
		if is_visible_in_tree() and (cooldown <= 0.001 or _press > 0.0) and (_press > 0.0 or _redraw_gap <= 0.0):
			_redraw_gap = 0.05
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.46 * (1.0 - 0.08 * _press)
		var ready := cooldown <= 0.001
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		draw_circle(c, r, Color(0.06, 0.03, 0.12, 0.5))
		draw_arc(c, r, 0.0, TAU, 48, Color(accent, (0.65 + 0.3 * pulse) if ready else 0.3), 5.0, true)
		if not ready:
			var sweep := PackedVector2Array([c])
			for i in 33:
				sweep.append(c + Vector2.from_angle(-PI * 0.5 + TAU * cooldown * i / 32.0) * r)
			draw_colored_polygon(sweep, Color(0, 0, 0, 0.5))
		var font := ThemeDB.fallback_font
		var alpha := 1.0 if ready else 0.5
		draw_string_outline(font, Vector2(0, c.y - 4.0), "НАВЫК", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.2), 6, Color(0.06, 0.03, 0.1))
		draw_string(font, Vector2(0, c.y - 4.0), "НАВЫК", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.2), Color(accent, alpha))
		draw_string_outline(font, Vector2(6, c.y + size.x * 0.2), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 12.0, int(size.x * 0.15), 5, Color(0.06, 0.03, 0.1))
		draw_string(font, Vector2(6, c.y + size.x * 0.2), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 12.0, int(size.x * 0.15), Color(1, 1, 1, alpha * 0.85))


class DashButton:
	extends Control
	signal pressed
	signal held

	const HOLD_MS := 550

	var _hold_start := -1

	var cooldown := 0.0:
		set(value):
			if not is_equal_approx(value, cooldown):
				cooldown = value
				queue_redraw()
	var _press := 0.0
	var _charges := 1
	var _max_charges := 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_charges(charges: int, max_charges: int) -> void:
		if charges != _charges or max_charges != _max_charges:
			_charges = charges
			_max_charges = max_charges
			queue_redraw()

	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and not event.pressed:
			_hold_start = -1
		if not is_visible_in_tree() or get_tree().paused:
			return
		if event is InputEventScreenTouch and event.pressed:
			var center := get_global_rect().get_center()
			if (event as InputEventScreenTouch).position.distance_to(center) < size.x * 0.55:
				_hold_start = Time.get_ticks_msec()
				_press = 1.0
				queue_redraw()
				pressed.emit()
				get_viewport().set_input_as_handled()

	func _process(delta: float) -> void:
		if _press > 0.0:
			_press = maxf(_press - delta * 5.0, 0.0)
			queue_redraw()
		if _hold_start >= 0 and Time.get_ticks_msec() - _hold_start >= HOLD_MS:
			_hold_start = -1
			held.emit()

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.46 * (1.0 - 0.08 * _press)
		var ready := cooldown <= 0.001
		draw_circle(c, r, Color(0.06, 0.03, 0.12, 0.42))
		draw_arc(c, r, 0.0, TAU, 48, Color(UiStyle.NEON, 0.75 if ready else 0.3), 5.0, true)
		if not ready:
			var sweep := PackedVector2Array([c])
			var steps := 32
			for i in steps + 1:
				sweep.append(c + Vector2.from_angle(-PI * 0.5 + TAU * cooldown * i / steps) * r)
			draw_colored_polygon(sweep, Color(0, 0, 0, 0.45))
		var alpha := 0.95 if ready else 0.45
		if _max_charges > 1:
			for i in _max_charges:
				var dot := c + Vector2((i - (_max_charges - 1) * 0.5) * 22.0, r * 0.66)
				draw_circle(dot, 7.0, Color(0.5, 1.0, 1.0, 0.95) if i < _charges else Color(0.1, 0.2, 0.3, 0.7))
		var tip := c + Vector2(30, 0)
		var arrow := PackedVector2Array([tip, c + Vector2(4, -22), c + Vector2(4, -9), c + Vector2(-20, -9), c + Vector2(-20, 9), c + Vector2(4, 9), c + Vector2(4, 22)])
		draw_colored_polygon(arrow, Color(1, 1, 1, alpha))
		for k in 3:
			var y := -14.0 + k * 14.0
			draw_line(c + Vector2(-44, y), c + Vector2(-28, y), Color(UiStyle.NEON, alpha), 4.0)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(0, size.y + 4), "РЫВОК", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 6, Color(0.05, 0.02, 0.1, 0.8))
		draw_string(font, Vector2(0, size.y + 4), "РЫВОК", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(1, 1, 1, alpha))


## Пауза: плашки статистики, громкость, вибрация, крупное «Продолжить», ниже «Заново» / «В хаб».
class PausePanel:
	extends Control
	signal resumed
	signal exit_pressed
	signal restart_pressed

	var _panel: PanelContainer
	var _chips: VBoxContainer
	var _settings: MenuPopups.Settings
	var _editor: ControlEditor
	var _tester: TesterPopup
	var _tips_button: Button

	func _refresh_tips_button() -> void:
		_tips_button.text = "ПОДСКАЗКИ: ВКЛ" if Tips.enabled() else "ПОДСКАЗКИ: ВЫКЛ"

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
		style.set_content_margin_all(26)
		_panel.add_theme_stylebox_override("panel", style)
		center.add_child(_panel)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(600, 0)
		box.add_theme_constant_override("separation", 14)
		_panel.add_child(box)

		var head := HBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_theme_constant_override("separation", 12)
		head.add_child(BattlePanels.icon_rect(BattlePanels.icon("pause"), 46))
		head.add_child(UiStyle.label("ПАУЗА", 56, UiStyle.TEXT, 14))
		box.add_child(head)

		_chips = VBoxContainer.new()
		_chips.add_theme_constant_override("separation", 6)
		box.add_child(_chips)

		var sound := PanelContainer.new()
		var sound_style := UiStyle.box(Color("#1f1738"), Color(UiStyle.NEON, 0.35), 3, 18)
		sound_style.set_content_margin_all(14)
		sound.add_theme_stylebox_override("panel", sound_style)
		box.add_child(sound)
		var sound_box := VBoxContainer.new()
		sound_box.add_theme_constant_override("separation", 8)
		sound.add_child(sound_box)
		sound_box.add_child(VolumeSlider.new("Музыка", "music"))
		sound_box.add_child(VolumeSlider.new("Эффекты", "sfx"))

		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 10)
		box.add_child(tools)
		tools.add_child(_tool_button("ГРАФИКА", Color("#2a86c9"), func() -> void: _open_settings()))
		tools.add_child(_tool_button("УПРАВЛЕНИЕ", Color("#8a4fd6"), func() -> void: _open_editor()))
		tools.add_child(_tool_button("ТЕСТЕР", Color("#c98b1a"), func() -> void: _open_tester()))

		_tips_button = UiStyle.button("", Color("#2d6a5a"), 22, Vector2(0, 60))
		_tips_button.pressed.connect(func() -> void:
			Tips.set_enabled(not Tips.enabled())
			_refresh_tips_button())
		box.add_child(_tips_button)
		_refresh_tips_button()

		var resume := BattlePanels.icon_button(BattlePanels.icon("play"), "ПРОДОЛЖИТЬ", "", Color("#35c46a"), 100)
		resume.pressed.connect(_resume)
		box.add_child(resume)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var again := UiStyle.button("ЗАНОВО", UiStyle.HOT, 26, Vector2(0, 76))
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		again.pressed.connect(func() -> void:
			visible = false
			restart_pressed.emit())
		row.add_child(again)
		var leave := UiStyle.button("НА БАЗУ", UiStyle.PANEL_LIGHT, 26, Vector2(0, 76))
		leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leave.pressed.connect(func() -> void:
			visible = false
			exit_pressed.emit())
		row.add_child(leave)

	func _tool_button(caption: String, color: Color, action: Callable) -> Button:
		var button := UiStyle.button(caption, color, 22, Vector2(0, 72))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(action)
		return button

	## Окна открываются поверх паузы и создаются при первом нажатии, чтобы не тормозить старт боя.
	func _open_settings() -> void:
		if _settings == null:
			_settings = MenuPopups.Settings.new()
			_settings.editor_requested.connect(_open_editor)
			add_child(_settings)
		_settings.open()

	func _open_editor() -> void:
		if _editor == null:
			_editor = ControlEditor.new()
			add_child(_editor)
		_editor.open()

	func _open_tester() -> void:
		if _tester == null:
			_tester = TesterPopup.new()
			add_child(_tester)
		_tester.open()

	func open(lines: PackedStringArray) -> void:
		for child in _chips.get_children():
			child.queue_free()
		for line in lines:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var parts := line.split(" · ")
			for part in parts:
				var chip := PanelContainer.new()
				chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				chip.add_theme_stylebox_override("panel", UiStyle.box(Color("#1f1738"), Color(UiStyle.GOLD, 0.55), 3, 14))
				chip.add_child(UiStyle.label(part, 22 if parts.size() > 1 else 24, UiStyle.TEXT, 5))
				row.add_child(chip)
			_chips.add_child(row)
		_refresh_tips_button()
		visible = true
		UiStyle.pop_in(_panel, 0.45)

	func _resume() -> void:
		visible = false
		SaveService.save_data()
		resumed.emit()


## Ползунок громкости (музыка / эффекты): 0–100%, сохраняется при отпускании.
class VolumeSlider:
	extends HBoxContainer
	var _channel := ""
	var _value_label: Label

	func _init(caption: String, channel: String) -> void:
		_channel = channel
		add_theme_constant_override("separation", 14)
		var name_label := UiStyle.label(caption, 26, UiStyle.TEXT, 6)
		name_label.custom_minimum_size = Vector2(150, 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = SoundManager.get_volume(channel)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size = Vector2(0, 44)
		slider.focus_mode = Control.FOCUS_NONE
		var track := UiStyle.box(Color("#140f24"), UiStyle.OUTLINE, 3, 10)
		track.content_margin_top = 6
		track.content_margin_bottom = 6
		slider.add_theme_stylebox_override("slider", track)
		var filled := UiStyle.box(UiStyle.NEON, UiStyle.OUTLINE, 3, 10)
		slider.add_theme_stylebox_override("grabber_area", filled)
		slider.add_theme_stylebox_override("grabber_area_highlight", filled)
		slider.add_theme_icon_override("grabber", _knob(Color.WHITE))
		slider.add_theme_icon_override("grabber_highlight", _knob(UiStyle.GOLD))
		slider.value_changed.connect(_on_changed)
		slider.drag_ended.connect(func(_changed: bool) -> void: SaveService.save_data())
		add_child(slider)
		_value_label = UiStyle.label("%d%%" % roundi(slider.value * 100.0), 22, UiStyle.TEXT_DIM, 5)
		_value_label.custom_minimum_size = Vector2(70, 0)
		add_child(_value_label)

	func _on_changed(value: float) -> void:
		SoundManager.set_volume(_channel, value)
		_value_label.text = "%d%%" % roundi(value * 100.0)
		if _channel == "sfx":
			SoundManager.play(&"ui_click")

	static func _knob(color: Color) -> ImageTexture:
		var size := 36
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c := Vector2(size, size) * 0.5
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				if d <= 17.0:
					image.set_pixel(x, y, UiStyle.OUTLINE if d > 13.0 else color)
		return ImageTexture.create_from_image(image)
