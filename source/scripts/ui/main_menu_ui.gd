class_name MainMenuUI
extends Control
## Хаб в стиле .io-игр (альбомный):
##   фон — живая Неоновая Свалка (MenuBackdrop) под тёмным градиентом;
##   верх — аватарка, уровень, валюты, шестерёнка;
##   логотип Trashketeers.io, на надписи сидит Енот в текущем скине;
##   поле ника с кубиком случайного имени, большая зелёная [ ИГРАТЬ ], выбор режима;
##   низ — ПРОКАЧКА · ОРУЖИЕ + MERGE · ГЕРОИ (гардероб) · АЧИВКИ.
## Альбомная раскладка: слева сцена с Енотом и боковыми кнопками, справа логотип, ствол, режим и ИГРАТЬ, снизу дока.

signal start_requested(weapon_id: StringName)
signal raid_requested(weapon_id: StringName)
signal story_requested(weapon_id: StringName)

enum Mode { SURVIVAL, RAID, STORY }

const RIGHT_WIDTH := 540.0
const COLUMN_WIDTH := 680.0
const PLAY_GREEN := Color("#7ed321")
const LOGO_FONT := "res://assets/fonts/LilitaOne-Regular.ttf"
const CAPSULE := Color("#c9c3d6")

var _mode: Mode = Mode.SURVIVAL
var _preview: MenuWidgets.RaccoonPreview
var _avatar: MenuWidgets.Avatar
var _profile: MenuPopups.Profile
var _editor: ControlEditor
var _nick_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _side_buttons: Dictionary = {}
var _nav_upgrades: MenuWidgets.NavButton
var _nuts_label: Label
var _dust_label: Label
var _weapon_title: Label
var _record_label: Label
var _weapon_icon: Control
var _weapon_holder: HBoxContainer
var _daily: DailyPopup
var _currency: CurrencyPopup
var _vip: VipPopup
var _pass: BattlePassPopup
var _odds: OddsPopup
var _mode_buttons: Array[Button] = []
var _settings: MenuPopups.Settings
var _shop: HeroPopup
var _skins: MenuPopups.Shop
var _tester: TesterPopup
var _chests: ChestsPopup
var _changelog: ChangelogPopup
var _armory: MenuPopups.Armory
var _upgrades: MenuPopups.Upgrades
var _achievements: MenuPopups.Achievements
var _chronicle: ChroniclePopup
var _backdrop: MenuBackdrop
## Кнопка «Прокачаться» на экране смерти: хаб сразу открывает Прокачку.
static var open_upgrades_next := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	SoundManager.play_music(&"menu")
	SoundManager.stop_ambient()
	if open_upgrades_next:
		open_upgrades_next = false
		_upgrades.open.call_deferred()


func _build() -> void:
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	_backdrop.build(get_viewport_rect().size)
	var shade := ShadeOverlay.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var column: Control = _build_portrait_layout() if Orient.portrait else _build_landscape_layout()

	_settings = MenuPopups.Settings.new()
	_shop = HeroPopup.new()
	_shop.skin_changed.connect(_on_skin_changed)
	_skins = MenuPopups.Shop.new(true)
	_skins.skin_changed.connect(_on_skin_changed)
	_armory = MenuPopups.Armory.new()
	_armory.weapon_changed.connect(_on_weapon_changed)
	_upgrades = MenuPopups.Upgrades.new()
	_achievements = MenuPopups.Achievements.new()
	_profile = MenuPopups.Profile.new()
	_profile.achievements_requested.connect(func() -> void:
		_profile.close()
		_achievements.open())
	_chronicle = ChroniclePopup.new()
	_profile.chronicle_requested.connect(func() -> void:
		_profile.close()
		_chronicle.open())
	_tester = TesterPopup.new()
	_chests = ChestsPopup.new()
	_chests.changed.connect(_refresh)
	_changelog = ChangelogPopup.new()
	_changelog.changed.connect(_refresh)
	_vip = VipPopup.new()
	_vip.changed.connect(_refresh)
	_pass = BattlePassPopup.new()
	_pass.changed.connect(_refresh)
	_odds = OddsPopup.new()
	_chests.odds_requested.connect(_odds.open_for)
	_currency = CurrencyPopup.new()
	_currency.changed.connect(_refresh)
	_daily = DailyPopup.new()
	_daily.claimed.connect(_refresh)
	_editor = ControlEditor.new()
	add_child(_editor)
	_settings.editor_requested.connect(func() -> void: _editor.open())
	for popup in [_settings, _shop, _skins, _armory, _upgrades, _achievements, _profile, _chronicle, _tester, _chests, _changelog, _daily, _currency, _vip, _pass, _odds]:
		add_child(popup)
		popup.closed.connect(_refresh)
	_refresh()
	UiStyle.pop_in(column, 0.8)


# --- Верхняя панель ---------------------------------------------------------------------------

func _build_portrait_layout() -> Control:
	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_bottom = 1.0
	column.offset_left = -COLUMN_WIDTH * 0.5
	column.offset_right = COLUMN_WIDTH * 0.5
	column.offset_top = 20.0
	column.offset_bottom = -20.0
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	column.add_child(_build_top_bar())
	column.add_child(_build_logo())
	column.add_child(_build_stage())
	column.add_child(_build_weapon_chip())
	column.add_child(_build_modes())
	column.add_child(_build_play())
	column.add_child(_build_dock())
	column.add_child(UiStyle.label("Trashketeers.io · Неоновая Свалка", 16, Color(UiStyle.TEXT_DIM, 0.7), 4))
	return column


func _build_landscape_layout() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_build_top_bar())
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 26)
	column.add_child(middle)
	var stage := _build_stage()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(stage)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 10)
	middle.add_child(side)
	side.add_child(_build_logo())
	side.add_child(_build_weapon_chip())
	side.add_child(_build_modes())
	side.add_child(_build_play())
	column.add_child(_build_dock())
	return column


func _build_top_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_avatar = MenuWidgets.Avatar.new()
	_avatar.custom_minimum_size = Vector2(76, 76)
	_avatar.mouse_filter = Control.MOUSE_FILTER_STOP
	_avatar.gui_input.connect(_on_profile_input)
	row.add_child(_avatar)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	info.gui_input.connect(_on_profile_input)
	_nick_label = UiStyle.label("", 26, UiStyle.GOLD, 7)
	_nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_nick_label.clip_text = true
	_nick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_nick_label)
	_level_label = UiStyle.label("", 18, UiStyle.TEXT_DIM, 4)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_level_label)
	_xp_bar = UiStyle.progress_bar(UiStyle.NEON, 12)
	_xp_bar.max_value = 1.0
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_xp_bar)
	row.add_child(info)

	_nuts_label = _add_capsule(row, ArenaProp.texture_of("res://assets/ui/hub/coin.png"), "coins")
	_dust_label = _add_capsule(row, ArenaProp.texture_of("res://assets/ui/hub/neonite.png"), "gems")
	if Platform.is_web:
		var full := MenuWidgets.FullscreenButton.new()
		full.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(full)
	var gear := MenuWidgets.GearButton.new()
	gear.custom_minimum_size = Vector2(64, 64)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.pressed.connect(func() -> void: _settings.open())
	row.add_child(gear)
	return row


func _on_profile_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if tapped:
		SoundManager.play(&"ui_click")
		_profile.open()


func _add_capsule(row: HBoxContainer, icon_texture: Texture2D, kind: String) -> Label:
	var capsule := PanelContainer.new()
	capsule.mouse_filter = Control.MOUSE_FILTER_STOP
	capsule.gui_input.connect(func(event: InputEvent) -> void:
		var tapped := false
		if event is InputEventMouseButton:
			tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			tapped = event.pressed
		if tapped:
			SoundManager.play(&"ui_click")
			_currency.open_kind(kind))
	var style := UiStyle.box(Color(CAPSULE, 0.92), UiStyle.OUTLINE, 4, 30)
	style.content_margin_left = 8
	style.content_margin_right = 8
	capsule.add_theme_stylebox_override("panel", style)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	capsule.add_child(box)
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := UiStyle.label("0", 24, Color("#2a1f40"), 0)
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(label)
	var plus := MenuWidgets.PlusBadge.new()
	plus.custom_minimum_size = Vector2(28, 28)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(plus)
	row.add_child(capsule)
	return label


# --- Логотип и Енот на надписи ----------------------------------------------------------------

## Боковая кнопка сцены: иконка без подписи; подпись и красная точка появляются, только когда есть что забрать.
func _make_side_button(key: String, icon_path: String, caption_text: String, right: bool, y: float, action: Callable, column: int = 0, px: float = 96.0) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.size = Vector2(px, px)
	button.custom_minimum_size = Vector2(px, px)
	if right:
		button.anchor_left = 1.0
		button.anchor_right = 1.0
		button.offset_left = -100.0
		button.offset_right = -4.0
	else:
		button.offset_left = 4.0 + column * (px + 8.0)
		button.offset_right = 4.0 + column * (px + 8.0) + px
	button.offset_top = y
	button.offset_bottom = y + px
	button.pressed.connect(func() -> void:
		SoundManager.play(&"ui_click")
		action.call())
	var icon := TextureRect.new()
	icon.texture = ArenaProp.texture_of(icon_path)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(icon)
	var caption := UiStyle.label(caption_text, 17 if px >= 90.0 else 12, UiStyle.GOLD, 5 if px >= 90.0 else 4)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -2.0
	caption.visible = false
	button.add_child(caption)
	var dot := _NotifyDot.new()
	dot.position = Vector2(px - 26.0, 0)
	dot.visible = false
	button.add_child(dot)
	if key == "news":
		caption.add_theme_font_size_override("font_size", 13 if px >= 90.0 else 9)
		caption.visible = true
	_side_buttons[key] = {"caption": caption, "dot": dot, "icon": icon}
	return button


## Боковая кнопка без иконки: цветная плашка с названием; красная точка - когда есть что забрать.
func _make_badge_button(key: String, text: String, color: Color, y: float, action: Callable) -> Button:
	var button := UiStyle.button(text, color.darkened(0.35), 16 if text.length() > 3 else 30, Vector2(88, 88))
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.offset_left = -92.0
	button.offset_right = -4.0
	button.offset_top = y
	button.offset_bottom = y + 88.0
	button.pressed.connect(func() -> void:
		SoundManager.play(&"ui_click")
		action.call())
	var dot := _NotifyDot.new()
	dot.position = Vector2(66, -2)
	dot.visible = false
	button.add_child(dot)
	_side_buttons[key] = {"caption": null, "dot": dot}
	return button


func _set_side_alert(key: String, alert: bool, caption_text: String = "") -> void:
	if not _side_buttons.has(key):
		return
	var entry: Dictionary = _side_buttons[key]
	(entry["dot"] as Control).visible = alert
	var caption := entry["caption"] as Label
	if caption == null or key == "pass" or key == "vip":
		return
	if key == "news":
		caption.visible = true
		return
	caption.visible = alert
	if alert and not caption_text.is_empty():
		caption.text = caption_text


func _build_tester_button() -> Button:
	var button := UiStyle.button("ТЕСТЕР", Color("#a3283e"), 15, Vector2(84, 84))
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.offset_left = -88.0
	button.offset_right = -4.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_top = -92.0
	button.offset_bottom = -8.0
	button.pressed.connect(func() -> void: _tester.open())
	return button


func _build_logo() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 150 if Orient.portrait else 118)
	var logo := LogoText.new()
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.font = load(LOGO_FONT) if ResourceLoader.exists(LOGO_FONT) else ThemeDB.fallback_font
	holder.add_child(logo)
	return holder


## Сцена героя: живой Енот в текущем скине на неоновой платформе — главный акцент экрана.
func _build_stage() -> Control:
	var stage := HeroStage.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 300 if Orient.portrait else 260)
	_preview = MenuWidgets.RaccoonPreview.new(SaveService.get_skin(), 2.5)
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_preview)
	if Orient.portrait:
		stage.add_child(_make_side_button("gift", "res://assets/ui/hub/daily_gift.png", "ПОДАРОК", false, 8.0, func() -> void: _daily.open()))
		stage.add_child(_make_side_button("chest", "res://assets/ui/hub/chest_free.png", "БЕСПЛАТНО", false, 132.0, func() -> void: _chests.open()))
		stage.add_child(_make_side_button("news", "res://assets/ui/hub/news.png", "ОБНОВЛЕНИЯ", true, 8.0, func() -> void: _changelog.open()))
		stage.add_child(_make_side_button("pass", "res://assets/ui/hub/pass.png", "ПРОПУСК", true, 124.0, func() -> void: _pass.open()))
		stage.add_child(_make_side_button("vip", "res://assets/ui/hub/vip.png", "VIP", true, 224.0, func() -> void: _vip.open()))
	else:
		var row := [
			["gift", "res://assets/ui/hub/daily_gift.png", "ПОДАРОК", func() -> void: _daily.open()],
			["chest", "res://assets/ui/hub/chest_free.png", "БЕСПЛАТНО", func() -> void: _chests.open()],
			["news", "res://assets/ui/hub/news.png", "ОБНОВЛЕНИЯ", func() -> void: _changelog.open()],
			["pass", "res://assets/ui/hub/pass.png", "ПРОПУСК", func() -> void: _pass.open()],
			["vip", "res://assets/ui/hub/vip.png", "VIP", func() -> void: _vip.open()],
		]
		for i in row.size():
			var spec: Array = row[i]
			stage.add_child(_make_side_button(spec[0], spec[1], spec[2], false, 6.0, spec[3], i, 76.0))
	for key in (["pass", "vip"] if Orient.portrait else ["gift", "chest", "news", "pass", "vip"]):
		(_side_buttons[key]["caption"] as Label).visible = true
	stage.add_child(_build_tester_button())
	stage.gui_input.connect(func(event: InputEvent) -> void:
		var tapped: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if tapped:
			_preview.celebrate()
			_preview.fire_burst())
	return stage


# --- Ник, ИГРАТЬ, режимы -------------------------------------------------------------------------

func _build_play() -> Control:
	var play := Button.new()
	play.text = "ИГРАТЬ"
	play.custom_minimum_size = Vector2(0, 136 if Orient.portrait else 108)
	play.focus_mode = Control.FOCUS_NONE
	play.add_theme_font_size_override("font_size", 60 if Orient.portrait else 54)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		play.add_theme_color_override(state, Color.WHITE)
	play.add_theme_color_override("font_outline_color", Color("#2c5a07"))
	play.add_theme_constant_override("outline_size", 14)
	var normal := UiStyle.box(PLAY_GREEN, Color("#2c5a07"), 6, 30)
	normal.border_width_bottom = 14
	var hover := UiStyle.box(PLAY_GREEN.lightened(0.15), Color("#2c5a07"), 6, 30)
	hover.border_width_bottom = 14
	var down := UiStyle.box(PLAY_GREEN.darkened(0.08), Color("#2c5a07"), 6, 30)
	down.border_width_bottom = 6
	play.add_theme_stylebox_override("normal", normal)
	play.add_theme_stylebox_override("hover", hover)
	play.add_theme_stylebox_override("pressed", down)
	play.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	play.pressed.connect(_on_play)
	UiStyle.pulse(play, 0.04, 1.1)
	return play


func _build_modes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var titles := ["ВЫЖИВАНИЕ", "ЛЕДЯНОЙ НАЛЁТ", "СЮЖЕТ"]
	for i in 3:
		var button := UiStyle.button(titles[i], UiStyle.PANEL, 22 if Orient.portrait else 20, Vector2(0, 68 if Orient.portrait else 60))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_select_mode.bind(i))
		row.add_child(button)
		_mode_buttons.append(button)
	_select_mode(Mode.SURVIVAL)
	return row


func _select_mode(mode: int) -> void:
	_mode = mode
	var colors := [Color("#ffb020"), Color("#7df9ff"), Color("#ff7ae0")]
	for i in _mode_buttons.size():
		var active := i == mode
		var b := _mode_buttons[i]
		b.set_pressed_no_signal(active)
		var style := UiStyle.box(Color(colors[i]).darkened(0.62) if active else Color(0.08, 0.05, 0.16, 0.75), colors[i] if active else UiStyle.OUTLINE, 5 if active else 3, 20)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", colors[i] if active else UiStyle.TEXT_DIM)
		b.add_theme_color_override("font_pressed_color", colors[i])
		b.add_theme_color_override("font_hover_pressed_color", colors[i])


# --- Карточка ствола и нижняя панель ----------------------------------------------------------------

func _build_weapon_chip() -> Control:
	var chip := Button.new()
	chip.custom_minimum_size = Vector2(0, 84 if Orient.portrait else 78)
	chip.focus_mode = Control.FOCUS_NONE
	var normal := UiStyle.box(Color(0.1, 0.07, 0.2, 0.88), Color("#ffb020"), 3, 20)
	chip.add_theme_stylebox_override("normal", normal)
	chip.add_theme_stylebox_override("hover", UiStyle.box(Color(0.15, 0.1, 0.28, 0.92), Color("#ffb020"), 4, 20))
	chip.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.2, 0.13, 0.34, 0.95), Color.WHITE, 4, 20))
	chip.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	chip.pressed.connect(func() -> void:
		SoundManager.play(&"ui_click")
		_armory.open())
	_weapon_holder = HBoxContainer.new()
	_weapon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	_weapon_holder.add_theme_constant_override("separation", 12)
	chip.add_child(_weapon_holder)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	_weapon_holder.add_child(texts)
	_weapon_title = UiStyle.label("", 22, UiStyle.TEXT, 6)
	_weapon_title.clip_text = true
	_weapon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(_weapon_title)
	_record_label = UiStyle.label("", 16, UiStyle.TEXT_DIM, 4)
	_record_label.clip_text = true
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(_record_label)
	var change := UiStyle.label("СМЕНИТЬ", 18, Color("#ffb020"), 4)
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_holder.add_child(change)
	return chip


func _build_dock() -> Control:
	var dock := PanelContainer.new()
	var style := UiStyle.box(Color(0.05, 0.03, 0.12, 0.88), Color("#3a2d60"), 3, 28)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	dock.add_theme_stylebox_override("panel", style)
	dock.add_child(_build_nav())
	return dock


func _build_nav() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var items := [
		[MenuWidgets.NavButton.Kind.UPGRADES, "ПРОКАЧКА", Color("#ff4d6d"), func() -> void: _upgrades.open(), "upgrade"],
		[MenuWidgets.NavButton.Kind.WEAPONS, "ОРУЖИЕ", Color("#ffb020"), func() -> void: _armory.open(), "armory"],
		[MenuWidgets.NavButton.Kind.SKINS, "ГЕРОИ", Color("#00e5ff"), func() -> void: _shop.open(), "hero"],
		[MenuWidgets.NavButton.Kind.OUTFITS, "СКИНЫ", Color("#ff5ce1"), func() -> void: _skins.open(), "outfit"],
	]
	for item in items:
		var button := MenuWidgets.NavButton.new(item[0], item[1], item[2], ArenaProp.texture_of("res://assets/ui/hub/%s.png" % item[4]))
		button.pressed.connect(item[3])
		if not Orient.portrait:
			button.custom_minimum_size = Vector2(0, 88)
		row.add_child(button)
		if item[0] == MenuWidgets.NavButton.Kind.UPGRADES:
			_nav_upgrades = button
	return row


func _can_afford_perk() -> bool:
	var coins := SaveService.get_coins()
	for perk_id in SaveService.PERKS:
		if not SaveService.is_perk_maxed(perk_id) and SaveService.get_perk_cost(perk_id) <= coins:
			return true
	return false


func _on_play() -> void:
	SoundManager.play(&"ui_confirm")
	if _mode == Mode.STORY:
		story_requested.emit(SaveService.get_selected_weapon())
	elif _mode == Mode.RAID:
		raid_requested.emit(SaveService.get_selected_weapon())
	else:
		start_requested.emit(SaveService.get_selected_weapon())


func _on_skin_changed() -> void:
	_preview.set_skin(SaveService.get_skin())
	_preview.celebrate()
	_avatar.queue_redraw()
	_refresh()


func _on_weapon_changed(_weapon_id: StringName) -> void:
	var weapon := SaveService.get_loadout()
	_preview.raccoon.weapon_icon = weapon.icon
	_preview.raccoon.weapon_color = weapon.effect_color
	_refresh()


func _refresh() -> void:
	_nick_label.text = SaveService.get_display_nickname()
	_level_label.text = "LVL %d" % SaveService.get_account_level() + (" · VIP %d" % Premium.level() if Premium.level() > 0 else "")
	_xp_bar.value = SaveService.get_level_progress()
	_nuts_label.text = str(SaveService.get_nuts())
	_dust_label.text = str(SaveService.get_star_dust())
	var weapon := SaveService.get_loadout()
	var best := int(SaveService.data["best_wave"])
	_weapon_title.text = weapon.get_title()
	_record_label.text = "Рекорд: волна %d" % best if best > 0 else "Рекорда пока нет - вперёд!"
	if _weapon_icon != null:
		_weapon_icon.queue_free()
	_weapon_icon = WeaponIcons.IconRect.new(weapon.icon, weapon.effect_color, Vector2(120, 54) if Orient.portrait else Vector2(96, 46))
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_holder.add_child(_weapon_icon)
	_weapon_holder.move_child(_weapon_icon, 0)
	_set_side_alert("gift", SaveService.can_claim_daily())
	_set_side_alert("chest", Economy.ad_chest_wait() <= 0)
	_set_side_alert("news", ChangelogPopup.has_unseen())
	_set_side_alert("pass", BattlePass.has_unclaimed())
	_set_side_alert("vip", false)
	if _nav_upgrades != null:
		_nav_upgrades.badge = _can_afford_perk()
		_nav_upgrades.queue_redraw()


class _NotifyDot:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(24, 24)

	func _draw() -> void:
		draw_circle(Vector2(12, 12), 12.0, Color("#1a0f2a"))
		draw_circle(Vector2(12, 12), 9.0, UiStyle.DANGER)


## Платформа под Енотом: свечение, неоновые кольца, поднимающиеся искры.
class HeroStage:
	extends Control
	var _time := 0.0
	var _sparks: Array[Vector3] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		for i in 14:
			_sparks.append(Vector3(randf(), randf(), randf_range(0.2, 0.6)))

	func _process(delta: float) -> void:
		_time += delta
		for i in _sparks.size():
			var spark := _sparks[i]
			spark.y -= delta * spark.z * 0.5
			if spark.y < 0.0:
				spark = Vector3(randf(), 1.0, randf_range(0.2, 0.6))
			_sparks[i] = spark
		queue_redraw()

	func _draw() -> void:
		var floor_center := Vector2(size.x * 0.5, size.y * 0.5 + 118.0)
		for i in 6:
			draw_circle(Vector2(size.x * 0.5, size.y * 0.5 + 20.0), 250.0 - i * 34.0, Color(1.0, 0.18, 0.65, 0.035))
		draw_set_transform(floor_center, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, 200.0, Color(0.03, 0.01, 0.08, 0.75))
		draw_arc(Vector2.ZERO, 200.0, 0.0, TAU, 64, Color("#ff2ea6"), 8.0, true)
		draw_arc(Vector2.ZERO, 158.0, 0.0, TAU, 64, Color(0.0, 0.96, 1.0, 0.75), 5.0, true)
		var pulse := fmod(_time * 0.6, 1.0)
		draw_arc(Vector2.ZERO, 60.0 + pulse * 130.0, 0.0, TAU, 48, Color(0.0, 0.96, 1.0, (1.0 - pulse) * 0.5), 4.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for spark in _sparks:
			var pos := Vector2(size.x * (0.2 + spark.x * 0.6), size.y * spark.y)
			draw_circle(pos, 3.0 + spark.z * 4.0, Color(1.0, 0.85, 0.4, sin(spark.y * PI) * 0.7))


## Тёмный градиент поверх живого фона: читаемость интерфейса.
class ShadeOverlay:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		var steps := 24
		for i in steps:
			var t := float(i) / (steps - 1)
			var alpha := lerpf(0.72, 0.35, sin(t * PI)) if t < 0.5 else lerpf(0.35, 0.85, (t - 0.5) * 2.0)
			draw_rect(Rect2(0, h * i / steps, size.x, h / steps + 1.0), Color(0.03, 0.01, 0.08, alpha))


## Логотип «Trashketeers.io»: толстая обводка, двухцветная заливка, наклон и тень.
class LogoText:
	extends Control
	var font: Font
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var base := Vector2(0, size.y - 46.0)
		var wobble := sin(_time * 1.6) * 0.012
		draw_set_transform(Vector2(size.x * 0.5, base.y), -0.05 + wobble, Vector2.ONE)
		var title := "Trashketeers"
		var probe := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x + font.get_string_size(".io", HORIZONTAL_ALIGNMENT_LEFT, -1, 63).x
		var font_size := int(100.0 * minf(1.0, size.x * 0.9 / maxf(probe, 1.0)))
		var io_size := int(font_size * 0.63)
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var io_width := font.get_string_size(".io", HORIZONTAL_ALIGNMENT_LEFT, -1, io_size).x
		var start := Vector2(-(width + io_width) * 0.5, 0)
		draw_string_outline(font, start + Vector2(0, 10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 34, Color(0, 0, 0, 0.45))
		draw_string_outline(font, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 26, Color("#1a0f2a"))
		draw_string(font, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#ffc93c"))
		draw_string(font, start + Vector2(0, -4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.93, 0.55, 0.55))
		var io := start + Vector2(width + 6, 0)
		draw_string_outline(font, io, ".io", HORIZONTAL_ALIGNMENT_LEFT, -1, io_size, 20, Color("#1a0f2a"))
		draw_string(font, io, ".io", HORIZONTAL_ALIGNMENT_LEFT, -1, io_size, Color("#00f5ff"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tagline := "Енот-налётчик против крыс и свиней"
		draw_string_outline(ThemeDB.fallback_font, Vector2(0, size.y - 6), tagline, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 7, Color("#1a0f2a"))
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 6), tagline, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color("#ff9fd8"))
