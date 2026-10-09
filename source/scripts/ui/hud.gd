class_name Hud
extends CanvasLayer
## Боевой интерфейс. PROCESS_MODE_ALWAYS — чтобы окна прокачки, паузы и результата
## работали, пока дерево на паузе. Джойстик внутри явно PAUSABLE.
## Раскладка под портрет: сверху HP/XP, волна по центру, монеты и пауза справа (+ мини-карта);
## снизу слева — джойстик, справа — полупрозрачная кнопка навыка и карточка ствола.

signal upgrade_chosen(upgrade: UpgradeData)
signal reroll_requested
signal upgrade_pressed
signal restart_pressed
signal menu_pressed
signal dash_pressed
signal skill_pressed
signal slot_pressed(index: int)
signal interact_pressed
signal orders_requested
signal pause_pressed
signal resume_pressed
signal revive_requested(with_ad: bool)
signal revive_declined

var joystick: VirtualJoystick
var aim_stick: AimStick
var _move_home: Control
var _aim_home: Control
var combat_feed: CombatFeed

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
var _siren_icon: TextureRect
const SIREN_ICON := "res://assets/world/siren.png"
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
var _toast_item: Array = []
var _toast_tween: Tween
var _wave_sub: Label
var _countdown: Label
var _toast: PanelContainer
var _toast_title: Label
var _toast_text: Label
var _weapon_chip: PanelContainer
var _weapon_icon: WeaponIcons.IconRect
var _weapon_name: Label
const HUD_TEXT_BOOST := 1.1
var _skill: SkillButton
var _dash: SkillButton
var _rail_combo: Label
var _slot_bar: BattleControls.SlotBar
var _interact: BattleControls.InteractButton
var _layout_revision := -1
var _hold: LayoutHold
var _editor: BattleLayoutEditor
var _pause_button: Button
const HUD_SCALE := 1.0
## Левая колонка и правый край (монеты, пауза) должны уместиться в 720 px без вылета за экран.
const LEFT_W := 468.0
var _story_meter: Control
var _bars_box: VBoxContainer
var _chips_row: HBoxContainer
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
var _toast_y := 700.0 if Orient.portrait else 116.0
## Телефон (портрет): вся шапка — один блок BAND_W×BAND_H в своих координатах, который масштабируется,
## чтобы занимать сверху не больше BAND_SHARE высоты экрана; ниже — только игра и кнопки управления.
## Нижняя строка блока — лента событий (заставки волн, отсчёт, глава, баннеры, тосты, комбо).
const BAND_W := 720.0
const BAND_SHARE := 0.225
const EVENT_TOP := 306.0
const EVENT_H := 66.0
const MAP_BOTTOM := 282.0
const RADIO_RECT := Rect2(18, 212, 468, 86)
const PORTRAIT_SCALE := 0.78
var _band: Control
var _top_bar: Control
var _event_top := EVENT_TOP
var _minimal := false
var _wanted_label: Label
var _wanted_stars: HBoxContainer
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
	joystick.blocker = _point_on_buttons
	_root.add_child(joystick)
	# Невидимые «дома» стиков: их таскают в редакторе управления (рамка = зона стика).
	_move_home = Control.new()
	_move_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_move_home)
	_aim_home = Control.new()
	_aim_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_aim_home)
	# Под кнопками: касание кнопки забирает интерфейс, стик получает только пустое место.
	aim_stick = AimStick.new()
	_root.add_child(aim_stick)
	combat_feed = CombatFeed.new()
	_root.add_child(combat_feed)

	var top: Control = _root
	if Orient.portrait:
		_band = Control.new()
		_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band.size = Vector2(BAND_W, EVENT_TOP + EVENT_H)
		_root.add_child(_band)
		top = _band
	_top_bar = _build_top_bar(currency_icon)
	top.add_child(_top_bar)
	if _band != null:
		_top_bar.minimum_size_changed.connect(_fit_band, CONNECT_DEFERRED)
		_left_column.minimum_size_changed.connect(_fit_band, CONNECT_DEFERRED)
	top.add_child(_build_boss_bar())
	top.add_child(_build_banner())
	top.add_child(_build_wave_titles())
	top.add_child(_build_minimap_slot())
	top.move_child(_minimap_slot, 0)
	top.add_child(_wave_box)
	_barks = HudBarks.new()
	# Рация живёт в левой колонке под заданиями: так её не перекрывают ни карта, ни плашка заказа.
	_barks.custom_minimum_size = RADIO_RECT.size if Orient.portrait else Vector2(360, 94)
	_barks.clip_contents = true
	_barks.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left_column.add_child(_barks)
	_rail_combo = UiStyle.label("", 22, UiStyle.GOLD, 8)
	_rail_combo.anchor_left = 0.0
	_rail_combo.anchor_right = 0.0
	_rail_combo.offset_left = 18.0
	_rail_combo.offset_right = 18.0 + LEFT_W
	_rail_combo.offset_top = 224.0
	_rail_combo.offset_bottom = 254.0
	if Orient.portrait:
		UiStyle.anchor(_rail_combo, Vector2(0.5, 0.0), Rect2(-350, EVENT_TOP + 38.0, 700, 26))
	_rail_combo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_combo.visible = false
	top.add_child(_rail_combo)
	_root.add_child(_build_weapon_chip(weapon))
	_weapon_chip.visible = false
	_skill = SkillButton.new()
	_skill.visible = false
	_skill.pressed.connect(func() -> void: skill_pressed.emit())
	_root.add_child(_skill)
	_dash = SkillButton.new()
	_dash.caption = "РЫВОК"
	_dash.title = "Уклонение"
	_dash.action = &"dodge"
	_dash.accent = Color("#6adcff")
	_dash.pressed.connect(func() -> void: dash_pressed.emit())
	_root.add_child(_dash)
	_slot_bar = BattleControls.SlotBar.new()
	_slot_bar.slot_pressed.connect(func(i: int) -> void: slot_pressed.emit(i))
	_root.add_child(_slot_bar)
	_interact = BattleControls.InteractButton.new()
	_interact.pressed.connect(func() -> void: interact_pressed.emit())
	_root.add_child(_interact)
	_root.resized.connect(apply_layout)
	top.add_child(_build_toast())
	_chapter_card = BattlePanels.ChapterCard.new()
	if Orient.portrait:
		_chapter_card.dock(EVENT_TOP, _band_font(18), _band_font(30))
	top.add_child(_chapter_card)

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
		"dodge": element_node.bind("dodge"),
		"slots": _hold_slots,
		"interact": _hold_interact,
	}
	for id in Controls.HUD_ELEMENTS:
		if id != "pause":
			_hold.targets[id] = hud_node.bind(id)
	_hold.requested.connect(_open_layout_editor)
	_root.add_child(_hold)
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
	_chips_row.add_child(meter)
	_dock_barks()
	HintBubble.attach(meter, _hint, "Детали супер-ствола. Собери все 6 из зачищенных комнат и получишь 30 секунд режима аннигиляции.")


func set_story_layout(minimap: Minimap) -> void:
	_xp_row.visible = false
	_wave_box.visible = false
	_enemies_chip.visible = false
	_toast_y = 700.0 if Orient.portrait else 116.0
	if _band == null:
		_rail_combo.offset_top = 480.0
		_rail_combo.offset_bottom = 512.0
	_story_bar = StoryBar.new()
	_story_bar.compact()
	_bars_box.add_child(_story_bar)
	_order_card = OrderCard.new()
	_order_card.minimal = _minimal
	_order_card.pressed.connect(func() -> void: orders_requested.emit())
	_left_column.add_child(_order_card)
	_story_bar.chip_tapped.connect(func(chip: Control, text: String) -> void: _hint.show_for(chip, text))
	_dock_barks()
	if Orient.portrait:
		UiStyle.anchor(_boss_bar, Vector2(0.0, 0.0), RADIO_RECT)
	else:
		_boss_bar.anchor_left = 0.0
		_boss_bar.anchor_right = 1.0
		_boss_bar.anchor_top = 0.0
		_boss_bar.anchor_bottom = 0.0
		_boss_bar.offset_left = 300.0
		_boss_bar.offset_right = -300.0
		_boss_bar.offset_top = 30.0
		_boss_bar.offset_bottom = 96.0
	UiStyle.anchor(_minimap_slot, Vector2(1.0, 0.0), Rect2(-142, 172, 124, 110) if Orient.portrait else Rect2(-162, 186, 144, 144))
	_minimap = minimap
	minimap.tapped.connect(func(overview: bool) -> void:
		_hint.show_for(_minimap_slot, "Карта. Тап: %s." % ("крупный план" if overview else "вся карта")))


## Заказ Нэлл выполнен: плашка вспыхивает и сменяется новым заказом.
func order_completed(info: Dictionary) -> void:
	if _order_card != null:
		_order_card.celebrate(str(info.get("title", "")), int(info.get("goal", 1)))


func set_survival_order(order: Dictionary) -> void:
	if _order_card == null:
		if not Orient.portrait:
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
	if combat_feed != null:
		combat_feed.set_low_hp(clampf((0.3 - hp / max_hp) / 0.3 + 0.35, 0.0, 1.0) if _low_hp else 0.0)
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
	_apply_level_medal(level)
	# Медаль растёт влево, правый нижний угол остаётся приваренным к рамке: влезает до 999.
	var wide := 54.0 if level >= 100 else 38.0
	_level_label.add_theme_font_size_override("font_size", 17 if level >= 100 else 20)
	_level_badge.custom_minimum_size = Vector2(wide, 36.0)
	_level_badge.size = Vector2(wide, 36.0)
	_level_badge.position = Vector2(136.0 - wide, 76.0)
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


## Мигающая сирена (арт Астры, assets/world/siren.png) слева от таймера смены: до выхода босса меньше минуты.
func set_time_alert(on: bool) -> void:
	if on and _siren_icon == null and ResourceLoader.exists(SIREN_ICON):
		_siren_icon = TextureRect.new()
		_siren_icon.texture = load(SIREN_ICON)
		_siren_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_siren_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_siren_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_siren_icon.size = Vector2(36, 36)
		_time_label.add_child(_siren_icon)
	if _siren_icon == null:
		return
	_siren_icon.visible = on
	if on:
		var font := _time_label.get_theme_font("font")
		var text_w := font.get_string_size(_time_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _time_label.get_theme_font_size("font_size")).x
		_siren_icon.position = Vector2(_time_label.size.x - text_w - 44.0, (_time_label.size.y - 36.0) * 0.5)
		_siren_icon.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.006))


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
	var wave_text := "ГЛ.%d · ВОЛНА %d" % [chapter, number] if chapter > 0 else "ВОЛНА %d" % number
	_wave_label.text = wave_text
	if Orient.portrait:
		_wave_box.visible = false
	_enemies_chip.visible = enemies_left > 0 and not _minimal and _story_bar == null
	# Сначала волна, ниже: сколько осталось убить и сколько врагов сейчас на карте.
	_enemies_label.text = ("Волна %d · Врагов %d" if _band != null else "Волна %d\nВрагов %d") % [number, enemies_left]


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
	_weapon_chip.add_theme_stylebox_override("panel", UiStyle.box(Color(0.138, 0.132, 0.124, 0.55), Color(weapon.get_rarity_color(), 0.8), 3, 16))
	UiStyle.pop_in(_weapon_chip, 0.4)


func reset_background_input() -> void:
	joystick._reset()
	aim_stick._reset()
	_slot_bar._hold_index = -1
	_interact._touch = -1
	_hold._cancel()


func set_slots(weapons: Array, active: int, count: int) -> void:
	_slot_bar.set_slots(weapons, active, count)
	apply_layout()


func set_interact(weapon: WeaponData, note: String = "") -> void:
	_interact.show_for(weapon, note)


func _hold_dash() -> Control:
	return _skill


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
		"dodge":
			return _dash
		"slots":
			return _slot_bar
		"interact":
			return _interact
		"move":
			return _move_home
		"aim":
			return _aim_home
	return hud_node(id)


## Касание по кнопке боя — джойстик его не забирает (стик могли сдвинуть к кнопкам).
func _point_on_buttons(point: Vector2) -> bool:
	for node: Control in [_skill, _dash, _slot_bar, _interact]:
		if _visible_node(node) and Rect2(node.get_global_position(), node.size * node.get_global_transform().get_scale()).grow(8.0).has_point(point):
			return true
	return false


func editable_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in Controls.ELEMENTS:
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


## Кегль надписей ленты событий: на сенсорных экранах подписи шапки увеличены (HUD_TEXT_BOOST),
## а эти задаются после увеличения — учитываем его здесь.
func _band_font(base: int) -> int:
	return int(round(base * (HUD_TEXT_BOOST if Platform.is_touch() else 1.0)))


## Лента событий встаёт сразу под фактический низ шапки (кегли на телефоне увеличены, высота колонки
## заранее не известна), а весь блок масштабируется по своей реальной высоте до BAND_SHARE экрана.
func _fit_band() -> void:
	if _band == null:
		return
	var column := 18.0 + _left_column.get_combined_minimum_size().y * _left_column.scale.y
	_event_top = maxf(maxf(_top_bar.get_combined_minimum_size().y, column), MAP_BOTTOM) + 6.0
	var band_h := _event_top + EVENT_H
	var k := minf(minf(1.0, _root.size.y * BAND_SHARE / band_h), _root.size.x / BAND_W)
	_band.scale = Vector2(k, k)
	_band.position = Vector2.ZERO
	_band.size = Vector2(_root.size.x / k, band_h)
	for label: Control in [_wave_title, _countdown, _banner]:
		label.offset_top = _event_top
		label.offset_bottom = _event_top + 40.0
	for label: Control in [_wave_sub, _rail_combo]:
		label.offset_top = _event_top + 38.0
		label.offset_bottom = _event_top + 64.0
	_chapter_card.dock(_event_top, _band_font(18), _band_font(30))
	_dock_boss_bar.call_deferred()


## Полоса босса — на месте рации (рация на время боя с боссом скрыта).
func _dock_boss_bar() -> void:
	if _band == null or _barks == null or not _barks.is_inside_tree():
		return
	var inverse := _band.get_global_transform().affine_inverse()
	var top_left := inverse * _barks.get_global_rect().position
	_boss_bar.compact = true
	_boss_bar.custom_minimum_size = Vector2.ZERO
	UiStyle.anchor(_boss_bar, Vector2(0.0, 0.0), Rect2(top_left, Vector2(RADIO_RECT.size.x, _barks.size.y)))


func apply_layout() -> void:
	if _root == null or _slot_bar == null:
		return
	ScreenSafeArea.fit(_root, get_viewport().get_visible_rect().size)
	_fit_band()
	var area := _root.size
	Controls.place(_skill, "dash", area)
	Controls.place(_dash, "dodge", area)
	Controls.place(_slot_bar, "slots", area, BattleControls.slots_base_size(_slot_bar.count))
	Controls.place(_interact, "interact", area)
	Controls.place(_move_home, "move", area, Controls.ELEMENT_SIZE["move"] * float(Controls.get_value("joystick_scale")))
	Controls.place(_aim_home, "aim", area)
	joystick.queue_redraw()
	aim_stick.queue_redraw()
	Controls.resolve_overlap(_skill, _dash, _slot_bar, area)
	var opacity := clampf(float(Controls.get_value("opacity")), 0.3, 1.0)
	_skill.modulate.a = opacity * Controls.element_opacity("dash")
	_dash.modulate.a = opacity * Controls.element_opacity("dodge")
	_slot_bar.modulate.a = opacity * Controls.element_opacity("slots")
	_interact.modulate.a = Controls.element_opacity("interact")
	joystick.modulate.a = opacity * Controls.element_opacity("move")
	aim_stick.modulate.a = Controls.element_opacity("aim")
	_apply_hud_items()
	_layout_revision = Controls.revision


func set_skill(title: String, color: Color) -> void:
	_skill.visible = not title.is_empty()
	_skill.title = title
	_skill.accent = color
	_skill.queue_redraw()


func set_dash_cooldown(remaining: float, total: float) -> void:
	_dash.cooldown = clampf(remaining / maxf(total, 0.001), 0.0, 1.0)
	_dash.seconds = remaining


func set_skill_cooldown(fraction: float) -> void:
	_skill.cooldown = clampf(fraction, 0.0, 1.0)


## Рельс-комбо для рельсотрона: 0 — скрыть. Цвет от золотого к розовому по мере роста.
func set_rail_combo(count: int) -> void:
	if count <= 0:
		_rail_combo.visible = false
		return
	_rail_combo.visible = true
	_rail_combo.text = "РЕЛЬС-КОМБО ×%d · подряд" % count
	var heat := clampf(float(count) / 60.0, 0.0, 1.0)
	_rail_combo.add_theme_color_override("font_color", UiStyle.GOLD.lerp(Color("#ff4fd8"), heat))
	_rail_combo.pivot_offset = _rail_combo.size * 0.5
	_rail_combo.scale = Vector2.ONE * (1.1 + 0.08 * heat)
	create_tween().tween_property(_rail_combo, "scale", Vector2.ONE, 0.18)


func set_minimap(minimap: Control) -> void:
	_minimap = minimap as Minimap
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_slot.add_child(minimap)
	minimap.visible = SaveService.is_minimap_enabled()
	_minimap_slot.visible = minimap.visible
	minimap.enlarge_toggled.connect(_on_minimap_enlarge)


## Тап по миникарте выживания: увеличить (в два раза) или вернуть как было.
func _on_minimap_enlarge(big: bool) -> void:
	UiStyle.anchor(_minimap_slot, Vector2(1.0, 0.0), _minimap_rect(big))
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
	if _band != null and _barks != null:
		_barks.set_muted(true)
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
	if _barks != null:
		_barks.set_muted(false)


func show_banner(text: String, color: Color, duration: float = 2.2) -> void:
	if _band != null:
		# Строка событий одна: баннер ждёт, пока уйдут заставка главы, заголовок волны и прошлый баннер.
		if (_chapter_card != null and _chapter_card.visible) or _titles_showing() or _banner.visible:
			get_tree().create_timer(0.3, false).timeout.connect(show_banner.bind(text, color, duration))
			return
		_hide_toast_now()
	duration = minf(duration, 1.8)
	var half := 350.0 if _band != null else minf(350.0, (_root.size.x - 28.0) * 0.5)
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
	_wave_title.text = "ВОЛНА %d" % number
	_wave_title.add_theme_font_size_override("font_size", _title_font() if Orient.portrait else 56)
	_wave_title.add_theme_color_override("font_color", UiStyle.DANGER if is_boss else UiStyle.GOLD)
	var sub := ("БОСС: " + title) if is_boss else title
	_wave_sub.text = ("Глава %d · %s" % [chapter, sub]) if chapter > 0 else sub
	_animate_titles(1.0)


func show_wave_cleared(bonus_nuts: int) -> void:
	_wave_title.add_theme_font_size_override("font_size", _title_font() if Orient.portrait else 56)
	_wave_title.text = "ВОЛНА ЗАЧИЩЕНА!"
	_wave_title.add_theme_color_override("font_color", Color("#7cff6b"))
	_wave_sub.text = "+%s · лечение +15%%" % SaveService.format_coins(bonus_nuts)
	_animate_titles(0.9)


func show_countdown(seconds: int) -> void:
	if _band != null:
		# Пока видна другая надпись, этот тик отсчёта пропускаем: следующий покажется через секунду.
		if (_chapter_card != null and _chapter_card.visible) or _banner.visible or (_wave_title.visible and _wave_title.modulate.a > 0.05):
			return
		_hide_toast_now()
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
	_wanted_label.visible = level > 0
	# Звёзды Розыска — арт Астры (assets/ui/hud/wanted_star_full/empty.png); без файлов — звёздочки текстом.
	if not ResourceLoader.exists("res://assets/ui/hud/wanted_star_full.png"):
		_wanted_label.text = ("РОЗЫСК %s" % "★".repeat(level)) if level > 0 else ""
		return
	_wanted_label.text = "РОЗЫСК" if level > 0 else ""
	if _wanted_stars == null:
		_wanted_stars = HBoxContainer.new()
		_wanted_stars.add_theme_constant_override("separation", 1)
		_wanted_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 5:
			var star := TextureRect.new()
			star.custom_minimum_size = Vector2(22, 22)
			star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_wanted_stars.add_child(star)
		_wanted_label.add_child(_wanted_stars)
	var font := _wanted_label.get_theme_font("font")
	_wanted_stars.position = Vector2(font.get_string_size("РОЗЫСК", HORIZONTAL_ALIGNMENT_LEFT, -1, _wanted_label.get_theme_font_size("font_size")).x + 8.0, 0.0)
	var full: Texture2D = load("res://assets/ui/hud/wanted_star_full.png")
	var empty: Texture2D = load("res://assets/ui/hud/wanted_star_empty.png")
	for i in 5:
		(_wanted_stars.get_child(i) as TextureRect).texture = full if i < level else empty


func show_mod_badge(title: String) -> void:
	var badge := UiStyle.label("МОД: %s ×%.1f" % [title, RunMods.mult_of(RunMods.active)], 15, Color("#ff9a3d"), 5)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_child(badge)
	_dock_barks()


func toast(title: String, text: String, color: Color = UiStyle.GOLD) -> void:
	_toast_queue.append([title, text, color])
	if not _toast_busy:
		_next_toast()


func show_level_up(choices: Array[UpgradeData], level: int, stats: RunStats, bonus: bool = false, reroll_text: String = "", reroll_ok: bool = false, title: String = "") -> void:
	_clear_wave_titles()
	if _portrait != null:
		_portrait.react("grin", 1.6)
	_level_up.open(choices, level, stats, bonus, reroll_text, reroll_ok, title)


func show_result(victory: bool, lines: PackedStringArray, title: String = "", can_upgrade: bool = true) -> void:
	_clear_wave_titles()
	_pause.visible = false
	_hide_thermos()
	_result.open(victory, lines, title, can_upgrade)


func show_chapter(subtitle: String, title: String, accent: Color = UiStyle.NEON) -> void:
	_hide_toast_now()
	_chapter_card.play(subtitle, title, accent)


## Лента событий в шапке одна: важное (отсчёт, волна, глава, баннер) убирает текущий тост, а тост
## возвращается в начало очереди и покажется целиком, когда строка освободится.
func _hide_toast_now() -> void:
	if _band == null or _toast == null or not _toast.visible:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.visible = false
	if not _toast_item.is_empty():
		_toast_queue.push_front(_toast_item)
		_toast_item = []
	get_tree().create_timer(0.4, false).timeout.connect(_next_toast)


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
	_pause.move_to_front()
	_pause.open(lines)


func is_pause_open() -> bool:
	return _pause.visible


func _process(delta: float) -> void:
	# Мини-карта прячется под любым окном (пауза, прокачка, сундук): иначе вылезает поверх интерфейса.
	if _minimap_slot != null:
		_minimap_slot.modulate.a = 0.0 if get_tree().paused else 1.0
	if _band != null and _rail_combo.visible:
		_rail_combo.modulate.a = 0.0 if (_chapter_card.visible or _toast.visible or _banner.visible or (_wave_sub.visible and _wave_sub.modulate.a > 0.05)) else 1.0
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
func _title_font() -> int:
	return _band_font(30)


## Лента событий одна: заставка главы, заголовки волн и тосты не наезжают друг на друга.
func _event_busy() -> bool:
	if _band == null:
		return false
	if _chapter_card != null and _chapter_card.visible:
		return true
	if _banner != null and _banner.visible:
		return true
	return _titles_showing()


func _titles_showing() -> bool:
	for label: Label in [_wave_title, _countdown]:
		if label != null and label.visible and label.modulate.a > 0.05:
			return true
	return false


func _clear_wave_titles() -> void:
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	for label in [_wave_title, _wave_sub]:
		if label != null:
			label.modulate.a = 0.0


func _animate_titles(hold: float) -> void:
	if _band != null and ((_chapter_card != null and _chapter_card.visible) or _banner.visible):
		get_tree().create_timer(0.3, false).timeout.connect(_animate_titles.bind(hold))
		return
	_hide_toast_now()
	for label in [_wave_title, _wave_sub]:
		label.visible = true
		label.modulate.a = 0.0
	UiStyle.keep_pivot_centered(_wave_title)
	_wave_title.scale = Vector2.ONE * (1.4 if _band != null else 2.2)
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
	if _toast.visible:
		return
	if _toast_queue.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	if _chapter_card != null and _chapter_card.visible:
		# Не лезем поверх заставки главы: ждём, пока она уйдёт.
		get_tree().create_timer(0.4, false).timeout.connect(_next_toast)
		return
	if _event_busy():
		get_tree().create_timer(0.4, false).timeout.connect(_next_toast)
		return
	var item: Array = _toast_queue.pop_front()
	_toast_item = item
	var half := minf(240.0, (_root.size.x - 36.0) * 0.5)
	var shift := 0.0
	if _band != null:
		half = 350.0
	elif Orient.portrait and _story_bar == null:
		half = 250.0
		shift = -50.0  # правый край левее колонки слотов оружия
	_toast.offset_left = -half + shift
	_toast.offset_right = half + shift
	_toast_title.custom_minimum_size.x = half * 2.0 - 40.0
	_toast_text.custom_minimum_size.x = half * 2.0 - 40.0
	_toast.custom_minimum_size = Vector2(half * 2.0, 0.0)
	_toast_title.text = item[0]
	_toast_text.text = item[1]
	_fit_font(_toast_title, _band_font(18) if _band != null else 20, half * 2.0 - 48.0)
	_fit_font(_toast_text, _band_font(13) if _band != null else 16, half * 2.0 - 48.0)
	# Не влезло даже мелким шрифтом — переносим на строки по ширине плашки, а не даём вылезать за края.
	var text_font := _toast_text.get_theme_font("font")
	var too_long := text_font.get_string_size(_toast_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _toast_text.get_theme_font_size("font_size")).x > half * 2.0 - 48.0
	_toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if too_long else TextServer.AUTOWRAP_OFF
	_toast_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if too_long:
		_toast_text.add_theme_font_size_override("font_size", maxi(_band_font(13) if _band != null else 16, 14) - 1)
	if _band != null:
		# Тост целиком помещается в строку событий (EVENT_H) и не заходит за нижнюю границу шапки.
		var panel := _toast.get_theme_stylebox("panel") as StyleBoxFlat
		panel.content_margin_top = 5
		panel.content_margin_bottom = 5
		_toast.get_child(0).add_theme_constant_override("separation", 0)
	_toast.size = Vector2(half * 2.0, 0.0)
	_toast.reset_size.call_deferred()
	_toast_title.add_theme_color_override("font_color", item[2])
	_toast.visible = true
	var hidden_y := -140.0
	var shown_y := _toast_y
	if _band != null:
		shown_y = _event_top + 2.0
		hidden_y = shown_y + 14.0
		_toast.modulate.a = 0.0
		_toast.create_tween().tween_property(_toast, "modulate:a", 1.0, 0.25)
	_toast.position.y = hidden_y
	var tween := _toast.create_tween()
	_toast_tween = tween
	tween.tween_property(_toast, "position:y", shown_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.8)
	if _band != null:
		tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	else:
		tween.tween_property(_toast, "position:y", hidden_y, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_toast.visible = false
		_toast_item = []
		_next_toast())


# --- Построение ----------------------------------------------------------------------------------

## Чат друзей всегда в конце левой колонки: под заданием и прочими плашками.
## Квадрат «Рация»: сюда идут и фоновые реплики сюжета, и болтовня героев.
func radio() -> HudBarks:
	return _barks


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
	left.custom_minimum_size = Vector2(LEFT_W if Orient.portrait else 360, 0)
	if Orient.portrait:
		# Контейнеры сбрасывают масштаб, поэтому колонка живёт в обёртке и увеличена вручную.
		var wrap := Control.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.custom_minimum_size = Vector2(LEFT_W * HUD_SCALE, 0.0)
		wrap.add_child(left)
		left.scale = Vector2(HUD_SCALE, HUD_SCALE)
		row.add_child(wrap)
	else:
		row.add_child(left)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_left_column = left

	# Шапка как в современных мобильных экшенах: портрет с уровнем, широкие полосы HP и опыта, ниже ряд плашек.
	# Оправа портрета и полоса здоровья стыкуются в одну деталь: полоса «выходит» из-под кольца.
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 86)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(head)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	_bars_box = bars
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.anchor_right = 1.0
	bars.offset_left = 72.0
	bars.offset_top = 10.0
	head.add_child(bars)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(0, 34)
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
	# Отступ из-под круга портрета: «УР N» целиком видно.
	xp_gap.custom_minimum_size = Vector2(16, 0)
	xp_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_row.add_child(xp_gap)
	# Уровень — крупно перед полосой опыта (медаль у портрета перекрывали плашки).
	_xp_title = UiStyle.label("УР 1", 19, UiStyle.GOLD, 6)
	_xp_title.custom_minimum_size = Vector2(0, 0)
	_xp_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_row.add_child(_xp_title)
	var xp_stack := Control.new()
	xp_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_stack.custom_minimum_size = Vector2(0, 20)
	_xp_row.add_child(xp_stack)
	_xp_bar = HudWidgets.OutlineBar.new(HudWidgets.OutlineBar.XP_COLORS)
	_xp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_stack.add_child(_xp_bar)
	_xp_label = UiStyle.label("0/10", 15, Color("#bfe8ff"), 4)
	_xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_stack.add_child(_xp_label)

	_portrait = HudWidgets.DamagePortrait.new()
	_portrait.position = Vector2(0, 0)
	_portrait.scale = Vector2.ONE * 0.74
	_portrait.set_character(SaveService.get_character())
	# Лицо реагирует: серия убийств — гордость, новый уровень — ухмылка (попадание и испуг — в самом портрете).
	if combat_feed != null:
		combat_feed.medaled.connect(func() -> void: _portrait.react("proud", 1.6))
	head.add_child(_portrait)
	if Orient.portrait:
		# Шапка телефона компактнее: портрет меньше, полосы и медаль уровня сдвинуты за ним.
		_portrait.scale = Vector2.ONE * PORTRAIT_SCALE
		head.custom_minimum_size.y = 108.0 * PORTRAIT_SCALE + 2.0
		bars.offset_left = 92.0 * PORTRAIT_SCALE
		bars.offset_top = 4.0
	# Значок уровня: круглая «медаль», приваренная к рамке портрета снизу справа, как её продолжение.
	_level_badge = PanelContainer.new()
	var medal := UiStyle.box(Color("#1d1f1e"), UiStyle.NEON, 4, 20)
	medal.set_content_margin_all(0)
	medal.shadow_color = Color(0, 0, 0, 0.55)
	medal.shadow_size = 3
	_level_badge.add_theme_stylebox_override("panel", medal)
	_level_badge.custom_minimum_size = Vector2(38, 36)
	_level_badge.position = Vector2(98, 76) * (PORTRAIT_SCALE if Orient.portrait else 0.74)
	if Orient.portrait:
		_level_badge.scale = Vector2.ONE * PORTRAIT_SCALE
	_level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_badge.visible = false
	head.add_child(_level_badge)
	_level_label = UiStyle.label("1", 20, UiStyle.GOLD, 4)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_badge.add_child(_level_label)
	_apply_level_medal(1)

	var chips := HBoxContainer.new()
	_chips_row = chips
	chips.add_theme_constant_override("separation", 8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(chips)
	_build_wave_chip()
	_enemies_chip = _chip(BattlePanels.icon("skull"))
	_enemies_label = _enemies_chip.get_child(0).get_child(1) as Label
	_enemies_label.add_theme_font_size_override("font_size", 15)
	_enemies_label.add_theme_constant_override("line_spacing", -3)
	chips.add_child(_enemies_chip)
	_kills_chip = _chip(BattlePanels.icon("swords"))
	_kills_label = _kills_chip.get_child(0).get_child(1) as Label
	_kills_label.text = "Убито: 0"
	chips.add_child(_kills_chip)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(170, 0)
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
	_wave_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.138, 0.132, 0.124, 0.6), Color(UiStyle.GOLD, 0.7), 3, 20))
	_wave_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor(_wave_box, Vector2(1.0, 0.0), Rect2(-162, 154, 144, 30))
	_wave_label = UiStyle.label("ВОЛНА 1", 15, UiStyle.GOLD, 4)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_box.add_child(_wave_label)
	return _wave_box


## Плашка шапки: иконка и подпись в рамке.
func _chip(icon: Texture2D) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiStyle.box(Color(0.138, 0.132, 0.124, 0.72), Color(UiStyle.TEXT_DIM, 0.55), 3, 16))
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
	if Orient.portrait:
		UiStyle.anchor(_boss_bar, Vector2(0.0, 0.0), RADIO_RECT)
	else:
		UiStyle.anchor(_boss_bar, Vector2(0.5, 0.0), Rect2(-170, 30, 340, 66))
	_boss_bar.visible = false
	return _boss_bar


func _build_banner() -> Control:
	_banner = UiStyle.label("", 34, UiStyle.DANGER, 10)
	if Orient.portrait:
		UiStyle.anchor(_banner, Vector2(0.5, 0.0), Rect2(-350, EVENT_TOP, 700, 40))
		_banner.add_theme_font_size_override("font_size", _band_font(24))
	else:
		UiStyle.anchor(_banner, Vector2(0.5, 0.5), Rect2(-350, -280, 700, 80))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.visible = false
	return _banner


func _build_wave_titles() -> Control:
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_title = UiStyle.label("", _title_font() if Orient.portrait else 56, UiStyle.GOLD, 10 if Orient.portrait else 16)
	if Orient.portrait:
		UiStyle.anchor(_wave_title, Vector2(0.5, 0.0), Rect2(-350, EVENT_TOP, 700, 40))
	else:
		UiStyle.anchor(_wave_title, Vector2(0.5, 0.5), Rect2(-360, -60, 720, 80))
	_wave_title.visible = false
	box.add_child(_wave_title)
	_wave_sub = UiStyle.label("", _band_font(16) if Orient.portrait else 30, UiStyle.TEXT, 5 if Orient.portrait else 8)
	if Orient.portrait:
		UiStyle.anchor(_wave_sub, Vector2(0.5, 0.0), Rect2(-350, EVENT_TOP + 38.0, 700, 26))
	else:
		UiStyle.anchor(_wave_sub, Vector2(0.5, 0.5), Rect2(-360, 20, 720, 40))
	_wave_sub.visible = false
	box.add_child(_wave_sub)
	_countdown = UiStyle.label("", _band_font(22) if Orient.portrait else 30, UiStyle.NEON, 6 if Orient.portrait else 8)
	if Orient.portrait:
		UiStyle.anchor(_countdown, Vector2(0.5, 0.0), Rect2(-350, EVENT_TOP, 700, 40))
	else:
		UiStyle.anchor(_countdown, Vector2(0.5, 0.5), Rect2(-360, 70, 720, 40))
	_countdown.visible = false
	box.add_child(_countdown)
	return box


func _build_minimap_slot() -> Control:
	_minimap_slot = Control.new()
	_minimap_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor(_minimap_slot, Vector2(1.0, 0.0), _minimap_rect(false))
	return _minimap_slot


func _minimap_rect(big: bool) -> Rect2:
	if Orient.portrait:
		return Rect2(-314, 172, 296, 296) if big else Rect2(-128, 172, 110, 110)
	return Rect2(-314, 186, 296, 296) if big else Rect2(-162, 186, 144, 144)


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
	_toast.add_theme_stylebox_override("panel", UiStyle.box(Color(0.184, 0.177, 0.166, 0.92), UiStyle.GOLD, 4, 22))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -240.0
	_toast.offset_right = 240.0
	_toast.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_toast.add_child(column)
	_toast_title = UiStyle.label("", 24, UiStyle.GOLD, 7)
	column.add_child(_toast_title)
	_toast_text = UiStyle.label("", 17, UiStyle.TEXT, 4)
	column.add_child(_toast_text)
	return _toast


## Полупрозрачная круглая кнопка навыка с сектором перезарядки. Слушает сырые касания
## (ScreenTouch), а не GUI: второй палец при зажатом джойстике GUI не получает.
class SkillButton:
	extends Control

	var _batch := PolyBatch.new()
	signal pressed

	var title := ""
	var caption := "НАВЫК"
	var action: StringName = &"dash"
	var seconds := 0.0
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
		if size.x < 2.0:
			return
		var c := size * 0.5
		var r := size.x * 0.46 * (1.0 - 0.08 * _press)
		var ready := cooldown <= 0.001
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_batch.circle(c, r, Color(0.06, 0.03, 0.12, 0.5))
		_batch.arc(c, r, 0.0, TAU, 48, Color(accent, (0.65 + 0.3 * pulse) if ready else 0.3), 5.0, true)
		if not ready:
			var sweep := PackedVector2Array([c])
			for i in 33:
				sweep.append(c + Vector2.from_angle(-PI * 0.5 + TAU * cooldown * i / 32.0) * r)
			_batch.polygon(sweep, Color(0, 0, 0, 0.5))
		_batch.flush(self)
		var font := ThemeDB.fallback_font
		var alpha := 1.0 if ready else 0.5
		# Заголовок по ширине круга: «РЫВОК»/«НАВЫК» не упираются в обводку.
		var cap_size := int(size.x * 0.2)
		while cap_size > 10 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size).x > size.x * 0.68:
			cap_size -= 1
		draw_string_outline(font, Vector2(0, c.y - 4.0), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, cap_size, 6, Color(0.06, 0.03, 0.1))
		draw_string(font, Vector2(0, c.y - 4.0), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, cap_size, Color(accent, alpha))
		var words := title.split(" ")
		var lines: Array[String] = [""]
		var small := int(size.x * 0.115)
		for word in words:
			var combined: String = (lines.back() + " " + word).strip_edges()
			if font.get_string_size(combined, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x > size.x * 0.82 and not lines.back().is_empty():
				lines.append(word)
			else:
				lines[lines.size() - 1] = combined
		for i in mini(lines.size(), 2):
			var text: String = lines[i]
			while font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x > size.x * 0.82 and text.length() > 2:
				text = text.substr(0, text.length() - 2) + "…"
			draw_string(font, Vector2(size.x * 0.09, c.y + size.x * (0.11 + i * 0.13)), text, HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.82, small, Color(1, 1, 1, alpha * 0.9))
		var status := ("%.1f с" % seconds if seconds > 0.01 else "ЗАРЯДКА") if not ready else "ГОТОВО"
		if not Platform.is_touch() and ready:
			var keys := Controls.keys_for(action)
			if not keys.is_empty():
				status = Controls.key_title(int(keys[0]))
		draw_string(font, Vector2(0, size.y * 0.86), status, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.1), Color(accent, alpha))


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
		box.custom_minimum_size = Vector2(1000, 0)
		box.add_theme_constant_override("separation", 14)
		_panel.add_child(box)

		var head := HBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_theme_constant_override("separation", 12)
		head.add_child(BattlePanels.icon_rect(BattlePanels.icon("pause"), 46))
		head.add_child(UiStyle.label("ПАУЗА", 56, UiStyle.TEXT, 14))
		box.add_child(head)
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", 24)
		box.add_child(body)
		var summary := VBoxContainer.new()
		summary.custom_minimum_size = Vector2(440, 0)
		summary.add_theme_constant_override("separation", 14)
		body.add_child(summary)
		var actions := VBoxContainer.new()
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_theme_constant_override("separation", 14)
		body.add_child(actions)

		_chips = VBoxContainer.new()
		_chips.add_theme_constant_override("separation", 6)
		summary.add_child(_chips)

		var sound := PanelContainer.new()
		var sound_style := UiStyle.box(Color("#34312e"), Color(UiStyle.NEON, 0.35), 3, 18)
		sound_style.set_content_margin_all(14)
		sound.add_theme_stylebox_override("panel", sound_style)
		summary.add_child(sound)
		var sound_box := VBoxContainer.new()
		sound_box.add_theme_constant_override("separation", 8)
		sound.add_child(sound_box)
		sound_box.add_child(VolumeSlider.new("Музыка", "music"))
		sound_box.add_child(VolumeSlider.new("Эффекты", "sfx"))

		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 10)
		actions.add_child(tools)
		tools.add_child(_tool_button("ГРАФИКА", Color("#c97926"), func() -> void: _open_settings()))
		tools.add_child(_tool_button("УПРАВЛЕНИЕ", Color("#d69c5f"), func() -> void: _open_editor()))
		tools.add_child(_tool_button("ТЕСТЕР", Color("#c98b1a"), func() -> void: _open_tester()))

		_tips_button = UiStyle.button("", Color("#625e58"), 22, Vector2(0, 60))
		_tips_button.pressed.connect(func() -> void:
			Tips.set_enabled(not Tips.enabled())
			_refresh_tips_button())
		actions.add_child(_tips_button)
		_refresh_tips_button()

		var resume := BattlePanels.icon_button(BattlePanels.icon("play"), "ПРОДОЛЖИТЬ", "", Color("#35c46a"), 100)
		resume.pressed.connect(_resume)
		actions.add_child(resume)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		actions.add_child(row)
		var again := UiStyle.button("ПЕРЕЗАПУСК", UiStyle.HOT, 26, Vector2(0, 76))
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
			# Свой слой: внутри паузы редактор наследовал её полупрозрачность — меню просвечивало сквозь него.
			var layer := CanvasLayer.new()
			layer.layer = 60
			add_child(layer)
			_editor = ControlEditor.new()
			layer.add_child(_editor)
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
				chip.add_theme_stylebox_override("panel", UiStyle.box(Color("#34312e"), Color(UiStyle.GOLD, 0.55), 3, 14))
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
		var track := UiStyle.box(Color("#21201e"), UiStyle.OUTLINE, 3, 10)
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

func _apply_level_medal(level: int) -> void:
	var gold := level >= 10
	if _level_badge.has_meta("gold_medal") and bool(_level_badge.get_meta("gold_medal")) == gold:
		return
	_level_badge.set_meta("gold_medal", gold)
	var path := "res://assets/ui/hud/level_medal%s.png" % ("_gold" if level >= 10 else "")
	if not ResourceLoader.exists(path):
		return
	var medal := StyleBoxTexture.new()
	medal.texture = load(path) as Texture2D
	medal.set_content_margin_all(0)
	(_level_badge as PanelContainer).add_theme_stylebox_override("panel", medal)
