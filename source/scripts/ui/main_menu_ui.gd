class_name MainMenuUI
extends Control
## Главный хаб: профиль и валюты сверху, выбор боя по центру, навигация снизу.
## Боковые награды и новости остаются доступны без сцены персонажа.

signal start_requested(weapon_id: StringName)
signal raid_requested(weapon_id: StringName)
signal story_requested(weapon_id: StringName)

enum Mode { SURVIVAL, RAID, STORY }

const RIGHT_WIDTH := 580.0
const COLUMN_WIDTH := 680.0
const PLAY_GREEN := Color("#7ed321")
const LOGO_FONT := "res://assets/fonts/RussoOne-Regular.ttf"
const CAPSULE := Color("#2b2f31")

var _mode: Mode = Mode.SURVIVAL
var _avatar: MenuWidgets.Avatar
var _profile: MenuPopups.Profile
var _editor: ControlEditor
var _nick_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _side_buttons: Dictionary = {}
var _nav_upgrades: MenuWidgets.NavButton
var _nav_pass: MenuWidgets.NavButton
var _mode_hint: HintBubble
var _nuts_label: Label
var _dust_label: Label
var _weapon_title: Label
var _record_label: Label
var _weapon_icon: Control
var _weapon_holder: HBoxContainer
var _daily: DailyPopup
var _currency: CurrencyPopup
var _vip: VipPopup
var _mode_intro: ModeIntroPopup
var _objects_intro: ObjectsIntroPopup
var _mod_chip: Button
var _map_chip: Button
var _chips_row: HBoxContainer
var _asc_chip: Button
var _chips_box: VBoxContainer
var _pass: BattlePassPopup
var _season_pill: Button
var _odds: OddsPopup
var _mode_buttons: Array[Button] = []
var _settings: MenuPopups.Settings
var _shop: HeroPopup
var _skins: MenuPopups.Shop
var _tester: TesterPopup
var _menu_body: VBoxContainer
var _menu_center: Control
var _dock: Control
var _gear: Control
var _stage: Control
var _tester_button: Button
var _account_banner: Control
var _nav_friends: Control
var _chests: ChestsPopup
var _bestiary: BestiaryPopup
var _changelog: ChangelogPopup
var _armory: MenuPopups.Armory
var _upgrades: MenuPopups.Upgrades
var _patches: PatchesPopup
var _camp: CampPopup
var _account: AccountPopup
var _achievements: MenuPopups.Achievements
var _from_profile := false
var _chronicle: ChroniclePopup
var _friends: FriendsPopup
var _coop_button: Button
var _backdrop: MenuBackdrop
## Кнопка «Прокачаться» на экране смерти: хаб сразу открывает Прокачку.
static var open_upgrades_next := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	SoundManager.play_music(&"menu")
	SoundManager.stop_ambient()
	if Cloud.EMAIL_LOGIN and int(SaveService.data["runs"]) >= 1 and not Cloud.has_email() and not bool(SaveService.data.get("acct_hint", false)) and Platform.is_web:
		SaveService.set_flag("acct_hint", true)
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if is_instance_valid(_account):
				_account.open())
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
	_patches = PatchesPopup.new()
	_upgrades.patches_requested.connect(func() -> void:
		_upgrades.close()
		_patches.open())
	_patches.purchased.connect(_refresh)
	_account = AccountPopup.new()
	_camp = CampPopup.new()
	_camp.departed.connect(func() -> void: story_requested.emit(SaveService.get_selected_weapon()))
	_achievements = MenuPopups.Achievements.new()
	_profile = MenuPopups.Profile.new()
	_bestiary = BestiaryPopup.new()
	_profile.bestiary_requested.connect(func() -> void:
		_profile.close()
		_from_profile = true
		_bestiary.open())
	_profile.achievements_requested.connect(func() -> void:
		_profile.close()
		_from_profile = true
		_achievements.open())
	_profile.account_requested.connect(func() -> void:
		_profile.close()
		_account.open())
	_chronicle = ChroniclePopup.new()
	_profile.chronicle_requested.connect(func() -> void:
		_profile.close()
		_from_profile = true
		_chronicle.open())
	_friends = FriendsPopup.new()
	_tester = TesterPopup.new()
	_chests = ChestsPopup.new()
	_chests.changed.connect(_refresh)
	_changelog = ChangelogPopup.new()
	_changelog.changed.connect(_refresh)
	_mode_intro = ModeIntroPopup.new()
	_objects_intro = ObjectsIntroPopup.new()
	_objects_intro.finished.connect(func() -> void: start_requested.emit(SaveService.get_selected_weapon()))
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
	SaveService.badge_changed.connect(_refresh)
	Cloud.unread_changed.connect(func() -> void:
		if is_instance_valid(_nav_friends):
			_nav_friends.set("badge", Cloud.unread > 0)
			_nav_friends.queue_redraw())
	Cloud.coop_invite_received.connect(_show_coop_invite)
	_editor = ControlEditor.new()
	add_child(_editor)
	_settings.editor_requested.connect(func() -> void: _editor.open())
	for popup in [_achievements, _chronicle, _friends, _bestiary]:
		popup.closed.connect(_back_to_profile.bind(popup))
	for popup in [_settings, _shop, _skins, _armory, _upgrades, _camp, _account, _achievements, _profile, _chronicle, _friends, _tester, _chests, _changelog, _daily, _currency, _vip, _pass, _odds, _mode_intro, _bestiary, _patches, _objects_intro]:
		add_child(popup)
		popup.closed.connect(_refresh)
	# Покупки внутри окон списывают монеты сразу — цифры в шапке меню за окном обновляем тут же, а не после закрытия.
	SaveService.changed.connect(_refresh_wallet)
	_refresh()
	UiStyle.pop_in(column, 0.8)
	get_tree().create_timer(1.6).timeout.connect(_maybe_whats_new)


## Закрыл ачивки/летопись, открытые из профиля: возвращаемся в профиль (просьба тестеров); из профиля — крестиком в меню.
func _back_to_profile(_popup: Control) -> void:
	if not _from_profile:
		return
	_from_profile = false
	_profile.open()


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
	column.add_child(_build_utility_area())
	column.add_child(_build_weapon_chip())
	column.add_child(_build_modes())
	column.add_child(_build_coop_button())
	column.add_child(_build_mod_chip())
	column.add_child(_build_play())
	column.add_child(_build_dock())
	var studio := str(ConfigLoader.load_json("res://data/brand.json").get("studio", "")).strip_edges()
	if not studio.is_empty():
		column.add_child(UiStyle.label("Сделано командой %s" % studio, 16, Color(UiStyle.NEON, 0.8), 4))
	return column


func _build_landscape_layout() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var fit_safe := func() -> void:
		if is_inside_tree(): ScreenSafeArea.fit(margin, get_viewport_rect().size)
	resized.connect(fit_safe)
	fit_safe.call_deferred()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_build_top_bar())
	var middle := _build_utility_area()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)
	var center := Control.new()
	_menu_center = center
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(center)
	center.resized.connect(_fit_menu.call_deferred)
	var side := VBoxContainer.new()
	_menu_body = side
	side.minimum_size_changed.connect(_fit_menu.call_deferred)
	side.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	center.add_child(side)
	side.add_child(_build_logo())
	side.add_child(_build_weapon_chip())
	side.add_child(_build_modes())
	side.add_child(_build_coop_button())
	side.add_child(_build_mod_chip())
	side.add_child(_build_play())
	column.add_child(_build_dock())
	return column


func _fit_menu() -> void:
	if not is_inside_tree(): return
	if _menu_body == null or _dock == null or _menu_center.size.y <= 0.0:
		return
	var compact := get_viewport_rect().size.y < 600.0
	var children := _menu_body.get_children()
	children[0].custom_minimum_size.y = 60.0 if compact else 88.0
	children[1].custom_minimum_size.y = 66.0 if compact else 74.0
	for button in _mode_buttons:
		button.custom_minimum_size.y = 44.0 if compact else 56.0
	_coop_button.custom_minimum_size.y = 44.0 if compact else 46.0
	children[5].custom_minimum_size.y = 64.0 if compact else 88.0
	children[5].add_theme_font_size_override("font_size", 44 if compact else 54)
	_menu_body.add_theme_constant_override("separation", 6 if compact else 8)
	_avatar.custom_minimum_size = Vector2.ONE * (60.0 if compact else 76.0)
	_gear.custom_minimum_size = Vector2.ONE * (52.0 if compact else 64.0)
	_nick_label.add_theme_font_size_override("font_size", 22 if compact else 26)
	_level_label.add_theme_font_size_override("font_size", 16 if compact else 18)
	for button in _dock.get_child(0).get_children():
		button.custom_minimum_size.y = 72.0 if compact else 88.0
	var target: Control = _chips_row if compact else _chips_box
	if _asc_chip.get_parent() != target:
		_asc_chip.reparent(target)
	_asc_chip.text = Ascension.button_text().replace("ВОЗВЫШЕНИЕ:", "ВОЗВ.:") if compact else Ascension.button_text()
	_mod_chip.text = RunMods.button_text().replace("МОДИФИКАТОР:", "МОД.:") if compact else RunMods.button_text()
	var minimum := _menu_body.get_combined_minimum_size()
	var factor := minf(1.0, minf(_menu_center.size.x / minimum.x, _menu_center.size.y / minimum.y))
	_menu_body.size = minimum
	_menu_body.scale = Vector2.ONE * factor
	_menu_body.position = (_menu_center.size - minimum * factor) * 0.5
	var side_width := maxf(110.0, (_menu_center.size.x - minimum.x * factor) * 0.5 - 12.0)
	_season_pill.offset_right = 4.0 + minf(280.0, side_width)
	_season_pill.text = ("ПРОПУСК · !" if BattlePass.has_unclaimed() else "ПРОПУСК") if compact else str(_season_pill.get_meta("full_caption", _season_pill.text))
	UiStyle.fit_button_font(_season_pill, 16, _season_pill.size.x - 20.0)


## Плашка «Заведи аккаунт» под верхней панелью: не перекрывает экран и не спорит с клавиатурой, как всплывающее окно.
## Тап — открыть окно аккаунта, крестик — убрать до следующего раза.
func show_account_banner(text: String, on_dismiss: Callable = Callable(), action: String = "ЗАВЕСТИ") -> void:
	if is_instance_valid(_account_banner):
		return
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.box(Color("#34312e"), Color("#ff8200"), 3, 16))
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -minf(COLUMN_WIDTH, get_viewport_rect().size.x - 24.0) * 0.5
	bar.offset_right = -bar.offset_left
	bar.offset_top = 112.0 if Orient.portrait else 96.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var label := UiStyle.label(text, 19, UiStyle.TEXT, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(maxf(bar.offset_right * 2.0 - 230.0, 160.0), 0)
	row.add_child(label)
	var go := UiStyle.button(action, UiStyle.HOT, 20, Vector2(132, 52))
	go.pressed.connect(func() -> void:
		bar.queue_free()
		_account.open())
	row.add_child(go)
	var shut := UiStyle.button("X", UiStyle.PANEL_LIGHT, 20, Vector2(52, 52))
	shut.pressed.connect(func() -> void:
		bar.queue_free()
		if on_dismiss.is_valid():
			on_dismiss.call())
	row.add_child(shut)
	bar.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			bar.queue_free()
			_account.open())
	add_child(bar)
	move_child(bar, _settings.get_index())
	_account_banner = bar
	bar.modulate.a = 0.0
	bar.position.y -= 40.0
	var tween := bar.create_tween().set_parallel(true)
	tween.tween_property(bar, "modulate:a", 1.0, 0.35)
	tween.tween_property(bar, "position:y", bar.position.y + 40.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	_nick_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_gear = gear
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
	var accent := UiStyle.CARD_TEAL if kind == "gems" else UiStyle.CARD_BORDER
	var style := UiStyle.box(Color(UiStyle.PANEL, 0.94), accent, 2, 10)
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
	var label := UiStyle.label("0", 24, UiStyle.TEXT, 4)
	box.add_child(label)
	var plus := MenuWidgets.PlusBadge.new()
	plus.custom_minimum_size = Vector2(28, 28)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(plus)
	row.add_child(capsule)
	return label


# --- Логотип и быстрые действия ----------------------------------------------------------------

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
		var edge := 4.0 + column * (px + 8.0)
		button.offset_right = -edge
		button.offset_left = -edge - px
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


## Кнопка тестера появляется и пропадает вместе с тегом DeV или Insider: тег приходит с сервера уже после того, как меню построено.
func _sync_tester_button() -> void:
	if _stage == null:
		return
	var need := SaveService.get_insider() in [0, 1]
	if need and not is_instance_valid(_tester_button):
		_tester_button = _build_tester_button()
		_stage.add_child(_tester_button)
	elif not need and is_instance_valid(_tester_button):
		_tester_button.queue_free()
		_tester_button = null


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
	holder.custom_minimum_size = Vector2(0, 150 if Orient.portrait else 88)
	var logo := LogoText.new()
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.font = load(LOGO_FONT) if ResourceLoader.exists(LOGO_FONT) else ThemeDB.fallback_font
	holder.add_child(logo)
	return holder


## Компактные быстрые действия вокруг центрального выбора боя.
func _build_utility_area() -> Control:
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.custom_minimum_size = Vector2(0, 146 if Orient.portrait else 260)
	_season_pill = Button.new()
	_season_pill.text = "СЕЗОН · РЕЛЬСОТРОН"
	_season_pill.focus_mode = Control.FOCUS_NONE
	_season_pill.add_theme_font_size_override("font_size", 16)
	_season_pill.add_theme_color_override("font_color", Color("#ffb347"))
	for state in ["normal", "hover", "pressed"]:
		_season_pill.add_theme_stylebox_override(state, UiStyle.box(Color(0.1, 0.11, 0.1, 0.92), Color("#d9962b"), 2, 6))
	_season_pill.set_anchors_preset(Control.PRESET_CENTER_TOP if Orient.portrait else Control.PRESET_TOP_LEFT)
	_season_pill.offset_left = -140.0 if Orient.portrait else 4.0
	_season_pill.offset_right = 140.0 if Orient.portrait else 284.0
	_season_pill.offset_top = 4.0
	_season_pill.offset_bottom = 40.0
	_season_pill.pressed.connect(func() -> void: _pass.open())
	stage.add_child(_season_pill)
	var actions := [
		["gift", "res://assets/ui/hub/gift_box.png", "ПОДАРОК", false, 0, func() -> void: _daily.open()],
		["chest", "res://assets/ui/chests_v2/free.png", "БЕСПЛАТНО", false, 1, func() -> void: _chests.open()],
		["vip", "res://assets/ui/hub/vip.png", "VIP", true, 0, func() -> void: _vip.open()],
		["news", "res://assets/ui/hub/news.png", "НОВОСТИ", true, 1, func() -> void: _changelog.open()],
	]
	for spec: Array in actions:
		stage.add_child(_make_side_button(spec[0], spec[1], spec[2], spec[3], 54.0, spec[5], spec[4], 76.0))
	for key in _side_buttons:
		(_side_buttons[key]["caption"] as Label).visible = true
	_stage = stage
	_sync_tester_button()
	return stage


# --- Ник, ИГРАТЬ, режимы -------------------------------------------------------------------------

func _build_play() -> Control:
	var play := Button.new()
	play.text = "В БОЙ"
	play.custom_minimum_size = Vector2(0, 136 if Orient.portrait else 88)
	play.focus_mode = Control.FOCUS_NONE
	play.add_theme_font_size_override("font_size", 60 if Orient.portrait else 54)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		play.add_theme_color_override(state, UiStyle.PANEL)
	play.add_theme_constant_override("outline_size", 0)
	var amber := Color("#d8a157")
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var down := state in ["pressed", "hover_pressed"]
		var bg := amber.darkened(0.08) if down else (amber.lightened(0.08) if state == "hover" else amber)
		var style := UiStyle.box(bg, Color("#80623c"), 2, 10)
		style.border_width_bottom = 2 if down else 5
		play.add_theme_stylebox_override(state, style)
	play.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	play.pressed.connect(_on_play)
	UiStyle.press_feedback(play)
	return play


func _build_modes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var titles := ["ВЫЖИВАНИЕ", "ЛЕДЯНОЙ РЕЙД", "КАМПАНИЯ"]
	for i in 3:
		var button := UiStyle.button(titles[i], UiStyle.PANEL, 22 if Orient.portrait else 20, Vector2(0, 68 if Orient.portrait else 56))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_on_mode_pressed.bind(i))
		row.add_child(button)
		_mode_buttons.append(button)
	_select_mode(Mode.SURVIVAL)
	_mode_buttons[2].text = "КАМПАНИЯ %d/6" % SaveService.story_shards()
	return row


## Отдельное окно коопа на двоих («Выживание»): тренировка, комната, приглашения друзей.
func _build_coop_button() -> Control:
	var button := UiStyle.button("КООП · ОТРЯД НА ДВОИХ", Color("#00a5b8"), 22 if Orient.portrait else 20, Vector2(0, 58 if Orient.portrait else 46))
	button.name = "CoopButton"
	_coop_button = button
	button.pressed.connect(func() -> void: open_coop())
	return button


func open_coop(join_code: String = "", invite_code: String = "") -> void:
	if not await WebResourcePacks.ensure(WebResourcePacks.all_battle_groups()): return
	if not is_inside_tree(): return
	if get_node_or_null("CoopScreen") != null:
		return
	var coop := CoopScreen.new()
	coop.name = "CoopScreen"
	coop.join_code = join_code
	coop.invite_code = invite_code
	add_child(coop)
	coop.closed.connect(func() -> void: _refresh())


## Приглашение друга в кооп: большая карточка по центру на 30 секунд. «ПРИНЯТЬ» открывает комнату друга.
func _show_coop_invite(invite: Dictionary) -> void:
	var from_code := str(invite.get("from_code", ""))
	if get_node_or_null("CoopScreen") != null:
		return   # уже в окне коопа: не мешаем бою и лобби
	if CoopMute.blocks(from_code):
		return   # заглушено: тихо пропускаем
	var news := get_node_or_null("WhatsNew")
	if news != null:
		await news.tree_exited   # сначала «Что нового», потом приглашение
		if CoopMute.blocks(from_code):
			return
	var old := get_node_or_null("CoopInviteCard")
	if old != null:
		old.queue_free()
	var card := CoopInviteCard.new(invite)
	card.name = "CoopInviteCard"
	var id := int(invite.get("id", 0))
	card.accepted.connect(func() -> void:
		var room := await Cloud.answer_coop_invite(id, true)
		if is_instance_valid(card):
			card.queue_free()
		if room.length() >= 3 and room.to_upper() == room:
			open_coop(room)
		else:
			var note := UiStyle.label("Приглашение уже недействительно" if room != "offline" else "Нет связи с сервером", 20, UiStyle.TEXT, 5)
			note.set_anchors_preset(Control.PRESET_CENTER_TOP)
			note.offset_top = 20.0
			note.offset_left = -260.0
			note.offset_right = 260.0
			note.z_index = 80
			add_child(note)
			get_tree().create_timer(2.5).timeout.connect(note.queue_free))
	card.declined.connect(func() -> void: Cloud.answer_coop_invite(id, false))
	card.muted.connect(func(kind: String) -> void:
		match kind:
			"hour": CoopMute.mute_all(CoopMute.HOUR)
			"day": CoopMute.mute_all(CoopMute.DAY)
			"all": CoopMute.mute_all(-1)
			"friend": CoopMute.mute_friend(from_code)
		Cloud.answer_coop_invite(id, false))
	add_child(card)


## Один раз после каждой обновы: плашка «Что нового». Не мешает вопросам нового игрока (вход, аккаунт).
func _maybe_whats_new() -> void:
	if get_node_or_null("CoopScreen") != null or not WhatsNewPopup.should_show() or Cloud.waiting_choice or Cloud.session_lost or get_node_or_null("WhatsNew") != null:
		return
	var popup := WhatsNewPopup.new()
	popup.name = "WhatsNew"
	popup.open_changelog.connect(func() -> void: _changelog.open())
	add_child(popup)


func _build_mod_chip() -> Control:
	_mod_chip = UiStyle.button("", UiStyle.PANEL, 18, Vector2(0, 46 if Orient.portrait else 40))
	_mod_chip.clip_text = true
	var style := UiStyle.box(Color(0.16, 0.08, 0.03, 0.85), Color("#ff9a3d"), 3, 16)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		_mod_chip.add_theme_stylebox_override(state, style)
	_mod_chip.add_theme_color_override("font_color", Color("#ffb066"))
	_mod_chip.pressed.connect(_on_mod_pressed)
	_mod_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Рядом — выбор карты Выживания (выбитые из сундуков карты с редкостью, MapCards).
	_map_chip = _mod_chip.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Button
	_map_chip.pressed.connect(_on_map_pressed)
	_chips_row = HBoxContainer.new()
	_chips_row.add_theme_constant_override("separation", 8)
	_chips_row.add_child(_mod_chip)
	_chips_row.add_child(_map_chip)
	# Возвышения (престиж): видно, когда открыта хотя бы первая ступень.
	_asc_chip = _mod_chip.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Button
	_asc_chip.pressed.connect(_on_asc_pressed)
	_chips_box = VBoxContainer.new()
	_chips_box.add_theme_constant_override("separation", 6)
	_chips_box.add_child(_chips_row)
	_chips_box.add_child(_asc_chip)
	_refresh_mod_chip()
	return _chips_box


func _on_mod_pressed() -> void:
	SoundManager.play(&"ui_click", -4.0)
	var on := RunMods.toggle()
	_refresh_mod_chip()
	if _mode_hint == null:
		_mode_hint = HintBubble.new()
		add_child(_mode_hint)
	_mode_hint.show_for(_mod_chip, "Каждый забег выпадет случайное условие: больше риска, больше монет." if on else "Обычный забег без условий.")


func _refresh_mod_chip() -> void:
	_mod_chip.text = RunMods.button_text()
	_mod_chip.visible = _mode == Mode.SURVIVAL
	if _map_chip != null:
		_map_chip.text = MapCards.button_text()
		var id := MapCards.chosen()
		_map_chip.add_theme_color_override("font_color", MapCards.color_of(id) if not id.is_empty() else Color("#ffb066"))
		# Мини-карточка выбранной карты (арт Астры, assets/maps/<id>/card.png) слева от названия.
		_map_chip.icon = MapCards.card_art(id) if not id.is_empty() else null
		_map_chip.expand_icon = true
		_map_chip.add_theme_constant_override("icon_max_width", 22)
		_map_chip.visible = _mode == Mode.SURVIVAL
	if _chips_row != null:
		_chips_row.visible = _mode == Mode.SURVIVAL
	if _asc_chip != null:
		_asc_chip.text = Ascension.button_text()
		var art_path := "res://assets/ui/ascension/tier_%d.png" % Ascension.chosen()
		_asc_chip.icon = load(art_path) as Texture2D if ResourceLoader.exists(art_path) else null
		_asc_chip.expand_icon = true
		_asc_chip.add_theme_constant_override("icon_max_width", 24)
		_asc_chip.add_theme_color_override("font_color", Color("#ff4d6d") if Ascension.chosen() > 0 else Color("#ffb066"))
		_asc_chip.visible = _mode == Mode.SURVIVAL and Ascension.unlocked() > 0
	_fit_menu.call_deferred()


func _on_asc_pressed() -> void:
	SoundManager.play(&"ui_click", -4.0)
	var level := Ascension.cycle()
	_refresh_mod_chip()
	if _mode_hint == null:
		_mode_hint = HintBubble.new()
		add_child(_mode_hint)
	_mode_hint.show_for(_asc_chip, ("ВОЗВЫШЕНИЕ %s\n" % Ascension.title_of(level) if level > 0 else "") + Ascension.describe(level))


func _on_map_pressed() -> void:
	SoundManager.play(&"ui_click", -4.0)
	var id := MapCards.cycle()
	_refresh_mod_chip()
	if _mode_hint == null:
		_mode_hint = HintBubble.new()
		add_child(_mode_hint)
	var text := "Карты с редкостью выпадают из сундуков: своё небо, свои враги и больше монет."
	if not id.is_empty():
		var card := MapCards.info(id)
		text = "%s · %s. Монеты ×%.2f" % [card["title"], card["desc"], float(card["coins"])]
	_mode_hint.show_for(_map_chip, text)


func _on_mode_pressed(mode: int) -> void:
	_select_mode(mode)
	if _mode == Mode.SURVIVAL and not bool(SaveService.data.get("survival_intro_seen", false)):
		SaveService.set_flag("survival_intro_seen", true)
		_mode_intro.open()


func _select_mode(mode: int) -> void:
	_mode = mode
	if _mod_chip != null:
		_mod_chip.visible = mode == Mode.SURVIVAL
	var colors := [Color("#ff9a2e"), Color("#9fc4d8"), Color("#a6b84a")]
	for i in _mode_buttons.size():
		var active := i == mode
		var b := _mode_buttons[i]
		b.set_pressed_no_signal(active)
		var style := UiStyle.box(Color(colors[i]).darkened(0.7) if active else Color(0.11, 0.12, 0.11, 0.8), colors[i] if active else (Color(colors[i], 0.9) if i == 2 else UiStyle.OUTLINE), 4 if active else (3 if i == 2 else 2), 8)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", colors[i] if active or i == 2 else UiStyle.TEXT_DIM)
		b.add_theme_color_override("font_pressed_color", colors[i])
		b.add_theme_color_override("font_hover_pressed_color", colors[i])


# --- Карточка ствола и нижняя панель ----------------------------------------------------------------

func _build_weapon_chip() -> Control:
	var chip := Button.new()
	chip.custom_minimum_size = Vector2(0, 84 if Orient.portrait else 74)
	chip.focus_mode = Control.FOCUS_NONE
	var normal := UiStyle.box(Color(0.12, 0.13, 0.12, 0.9), Color("#d9962b"), 3, 8)
	chip.add_theme_stylebox_override("normal", normal)
	chip.add_theme_stylebox_override("hover", UiStyle.box(Color(0.17, 0.18, 0.17, 0.92), Color("#ffb347"), 4, 8))
	chip.add_theme_stylebox_override("pressed", UiStyle.box(Color(0.16, 0.17, 0.16, 0.95), Color("#ffb347"), 4, 8))
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
	var change := PanelContainer.new()
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := UiStyle.box(Color("#d9962b").darkened(0.55), Color("#d9962b"), 2, 6)
	pill.set_content_margin_all(8)
	change.add_theme_stylebox_override("panel", pill)
	var change_text := UiStyle.label("СМЕНИТЬ", 22, Color("#ffd257"), 5)
	change_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	change.add_child(change_text)
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weapon_holder.add_child(change)
	return chip


func _build_dock() -> Control:
	var dock := PanelContainer.new()
	_dock = dock
	var style := UiStyle.box(Color(0.110, 0.106, 0.099, 0.88), Color("#4a4d44"), 3, 10)
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
		[MenuWidgets.NavButton.Kind.UPGRADES, "ПРОКАЧКА", Color("#d9962b"), func() -> void: _upgrades.open(), "upgrade"],
		[MenuWidgets.NavButton.Kind.FRIENDS, "ДРУЗЬЯ", Color("#d9962b"), func() -> void: _friends.open(), "friends"],
		[MenuWidgets.NavButton.Kind.SKINS, "ОТРЯД", Color("#d9962b"), func() -> void: _shop.open(), "hero"],
		[MenuWidgets.NavButton.Kind.OUTFITS, "СКИНЫ", Color("#d9962b"), func() -> void: _skins.open(), "outfit"],
	]
	for item in items:
		var button := MenuWidgets.NavButton.new(item[0], item[1], item[2], ArenaProp.texture_of("res://assets/ui/hub/%s.png" % item[4]))
		button.pressed.connect(item[3])
		if not Orient.portrait:
			button.custom_minimum_size = Vector2(0, 88)
		row.add_child(button)
		if item[0] == MenuWidgets.NavButton.Kind.UPGRADES:
			_nav_upgrades = button
		elif item[0] == MenuWidgets.NavButton.Kind.FRIENDS:
			_nav_friends = button
			button.badge = Cloud.unread > 0
		elif item[4] == "pass":
			_nav_pass = button
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
		_camp.open()
	elif _mode == Mode.RAID:
		raid_requested.emit(SaveService.get_selected_weapon())
	elif ObjectsIntroPopup.should_show():
		# Перед первыми двумя забегами Выживания — что делают вышки, сейфы, касса, пылесос и прочее.
		_objects_intro.open()
	else:
		start_requested.emit(SaveService.get_selected_weapon())


func _on_skin_changed() -> void:
	_avatar.queue_redraw()
	_refresh()


func _on_weapon_changed(_weapon_id: StringName) -> void:
	_refresh()


func _refresh_wallet() -> void:
	_nuts_label.text = str(SaveService.get_nuts())
	_dust_label.text = str(SaveService.get_star_dust())


func _refresh() -> void:
	_sync_tester_button()
	_avatar.queue_redraw()
	_nick_label.text = SaveService.get_display_nickname()
	_nick_label.add_theme_color_override("font_color", Cosmetics.nick_color(UiStyle.GOLD))
	if _mode_buttons.size() > 2:
		_mode_buttons[2].text = "КАМПАНИЯ %d/6" % SaveService.story_shards()
	_level_label.text = "LVL %d" % SaveService.get_account_level() + (" · VIP %d" % Premium.level() if Premium.level() > 0 else "")
	_xp_bar.value = SaveService.get_level_progress()
	_nuts_label.text = str(SaveService.get_nuts())
	_dust_label.text = str(SaveService.get_star_dust())
	var weapon := SaveService.get_loadout()
	var best := int(SaveService.data["best_wave"])
	_weapon_title.text = weapon.get_title()
	_record_label.text = "Рекорд: волна %d" % best if best > 0 else ""
	_record_label.visible = best > 0
	if _weapon_icon != null:
		_weapon_icon.queue_free()
	_weapon_icon = WeaponIcons.IconRect.new(weapon.icon, weapon.effect_color, Vector2(120, 54) if Orient.portrait else Vector2(96, 46))
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_holder.add_child(_weapon_icon)
	_weapon_holder.move_child(_weapon_icon, 0)
	_set_side_alert("gift", SaveService.can_claim_daily())
	_set_side_alert("chest", Economy.ad_chest_wait() <= 0)
	_set_side_alert("news", ChangelogPopup.has_unseen())
	if _nav_pass != null:
		_nav_pass.badge = BattlePass.has_unclaimed()
		_nav_pass.queue_redraw()
	if not BattlePass.is_claimed("prem", 1):
		_season_pill.text = "СЕЗОН: РЕЛЬСОТРОН В ПРОПУСКЕ"
	elif BattlePass.has_unclaimed():
		_season_pill.text = "ПРОПУСК: ЕСТЬ НАГРАДЫ!"
	else:
		_season_pill.text = "БОЕВОЙ ПРОПУСК"
	# Надпись целиком внутри плашки, по центру: шрифт уменьшается под ширину.
	UiStyle.fit_button_font(_season_pill, 16, 280.0 - 20.0)
	_season_pill.set_meta("full_caption", _season_pill.text)
	_fit_menu.call_deferred()
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
		draw_circle(Vector2(12, 12), 12.0, Color("#23221f"))
		draw_circle(Vector2(12, 12), 9.0, UiStyle.DANGER)


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
			var alpha := lerpf(0.45, 0.12, sin(t * PI)) if t < 0.5 else lerpf(0.12, 0.5, (t - 0.5) * 2.0)
			draw_rect(Rect2(0, h * i / steps, size.x, h / steps + 1.0), Color(0.02, 0.024, 0.02, alpha))


## Логотип «Trash Squad»: ровная жирная надпись, тонкая линия и подпись «Отряд зачистки».
class LogoText:
	extends Control
	var font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var title := "TRASH SQUAD"
		var compact := size.y < 100.0
		var fs := mini(64, int(size.y) - 24) if compact else 84
		while fs > 30 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x * 0.94:
			fs -= 4
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var start := Vector2((size.x - w) * 0.5, size.y - (34.0 if compact else 52.0))
		draw_string_outline(font, start + Vector2(0, 5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(0, 0, 0, 0.55))
		draw_string_outline(font, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color("#0d0f0e"))
		var split := start.x + font.get_string_size("TRASH ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, start, "TRASH ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ece7d3"))
		draw_string(font, Vector2(split, start.y), "SQUAD", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ff9a2e"))
		var cx := size.x * 0.5
		var y := size.y - (24.0 if compact else 34.0)
		draw_line(Vector2(cx - w * 0.5, y), Vector2(cx + w * 0.5, y), Color("#d9962b"), 3.0)
		var sub := "ОТРЯД ЗАЧИСТКИ"
		var sub_size := 16 if compact else 20
		var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		draw_string(font, Vector2(cx - sw * 0.5, size.y - (3.0 if compact else 8.0)), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color("#c9bd96"))
