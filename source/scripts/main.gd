extends Node
## Точка входа: меню ↔ (загрузочный экран) ↔ бой на Свалке / Налёт.
## Сцены собираются кодом; смена экрана — не геймплей, поэтому создание/удаление нод здесь
## не нарушает запрет на instantiate в бою. Переходы из кнопок делаются deferred:
## кнопки живут внутри удаляемого экрана.

const INPUT_BINDINGS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"dash": [KEY_SPACE, KEY_SHIFT],
}
const UI_FONT := "res://assets/fonts/RussoOne-Regular.ttf"

const BATTLE_RESOURCES := [
	"res://assets/enemies/rat_base.png",
	"res://assets/enemies/spark_rat.png",
	"res://assets/biome/ch1_floor.png",
	"res://assets/props/ch1/container.png",
	"res://assets/props/ch1/junk_pile.png",
	"res://assets/audio/music/battle.ogg",
	"res://assets/player/raccoon.png",
	"res://assets/player/raccoon_body.png",
	"res://assets/player/raccoon_arm.png",
]
const RAID_RESOURCES := [
	"res://assets/bosses/ice_dragon_idle.png",
	"res://assets/bosses/ice_dragon_fly.png",
	"res://assets/bosses/ice_dragon_breath.png",
	"res://assets/bosses/ice_dragon_tail.png",
	"res://assets/raid/ice_shield.png",
	"res://assets/raid/ice_puddle.png",
	"res://assets/audio/music/raid.ogg",
	"res://assets/bullets/ice_shard.png",
	"res://assets/player/raccoon.png",
	"res://assets/player/raccoon_body.png",
	"res://assets/player/raccoon_arm.png",
]

var _debug_hash := ""
var _screen: Node
var _pending_login := ""
var _moved_prompted := false
var _resize_serial := 0
var _menu_view := Vector2.ZERO
var _loading: LoadingScreen


func _ready() -> void:
	# Интерполяция физики включена в проекте, но по умолчанию выключена для всего дерева: её
	# включают только узлы, которым нужна плавность (дракон Хладгор).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Шрифт по умолчанию для всего, что рисуется через ThemeDB.fallback_font (цифры урона,
	# подписи в _draw) — тот же, что у контролов (gui/theme/custom_font).
	if ResourceLoader.exists(UI_FONT):
		ThemeDB.fallback_font = load(UI_FONT)
	# Телефоны с экраном 90–120 Гц иначе гонят вдвое больше кадров: греются и начинают
	# троттлить. Игра рассчитана на 60.
	Engine.max_fps = 60
	_handle_unclean_exit()
	Platform.send_report("profile", "nick=%s hero=%s weapon=%s coins=%d dust=%d gems=%d quality=%d lite=%s glow=%s minimap=%s" % [SaveService.get_nickname(), SaveService.get_character_id(), SaveService.get_selected_weapon(), SaveService.get_coins(), SaveService.get_star_dust(), SaveService.get_gems(), SaveService.get_quality(), SaveService.is_fx_lite(), SaveService.is_glow_enabled(), SaveService.is_minimap_enabled()])
	Orient.refresh(get_window())
	get_window().size_changed.connect(_on_window_resized)
	var poll := Timer.new()
	poll.wait_time = 0.7
	poll.timeout.connect(_poll_orientation)
	add_child(poll)
	poll.start()
	SaveService.apply_quality()
	_register_input()
	_show_menu()
	_accept_card_link.call_deferred()
	if OS.has_feature("web"):
		var url_hash := str(JavaScriptBridge.eval("window.location.hash"))
		if url_hash.begins_with("#boss:"):
			_debug_hash = url_hash.substr(6)
			_start_game.call_deferred(SaveService.get_selected_weapon())
		elif url_hash.begins_with("#story"):
			_debug_hash = url_hash.substr(1)
			_start_story.call_deferred(SaveService.get_selected_weapon())
		elif url_hash == "#camp":
			_debug_hash = "camp"
			_show_menu()
		elif url_hash.begins_with("#raid"):
			_debug_hash = url_hash.substr(1)
			_start_raid.call_deferred(SaveService.get_selected_weapon())


func _accept_card_link() -> void:
	for key in ["dev", "insider"]:
		var badge_code := Platform.consume_url_param(key).strip_edges()
		if badge_code.is_empty():
			continue
		var level := await Cloud.claim_badge(badge_code)
		if level >= 0:
			_show_menu()
			if Platform.storage_get("trk_badge_seen") != str(level):
				Platform.storage_set("trk_badge_seen", str(level))
				_show_badge_welcome(level)
		else:
			if SaveService.get_insider() >= 0:
				_toast_note("Твой тег %s уже на месте, эта ссылка своё отработала" % SaveService.get_badge())
			else:
				_toast_note("Ссылка не действует: она уже использована или заменена. Попроси новую")
	var restore := Platform.consume_url_param("restore")
	if not restore.is_empty() and restore.strip_edges().to_upper() == Platform.storage_get(Cloud.RECOVERY_KEY).to_upper():
		restore = ""
	var login := Platform.consume_url_param("login").strip_edges().to_lower()
	if not login.is_empty() and login != Cloud.email:
		_ask_login(login)
		return
	if not restore.is_empty():
		_toast_note("Возвращаю аккаунт...")
		var text := await Cloud.restore_save(restore)
		if text.begins_with("ACCOUNT:"):
			_ask_login(text.trim_prefix("ACCOUNT:"))
			return
		if not text.is_empty() and SaveService.import_code(text):
			Cloud.recovery_code = restore
			Platform.storage_set(Cloud.RECOVERY_KEY, restore)
			_toast_note("Аккаунт вернулся. Прогресс на месте")
			_show_menu()
		else:
			_toast_note("Ссылка-вход не сработала. Проверь, что скопировал её целиком")
		return
	var friend := Platform.consume_url_param("f")
	if not friend.is_empty():
		var result := await Cloud.add_friend(friend.strip_edges().to_upper())
		match result:
			"ok":
				_toast_note("Друг добавлен. Открой «Друзья», чтобы посмотреть")
			"self":
				_toast_note("Это твоя собственная ссылка. С собой дружить можно и без неё")
			"not_found":
				_toast_note("Такого игрока нет. Ссылка устарела или скопирована не целиком")
			"limit":
				_toast_note("Друзей уже максимум")
			_:
				_toast_note("Нет связи с сервером. Открой ссылку ещё раз, когда появится интернет")
		return
	var code := Platform.consume_url_param("card")
	if code.is_empty():
		return
	var card_result: String = SaveService.add_friend(code)
	var note := "Визитка по ссылке не подошла"
	if card_result == "ok" or card_result == "bonus":
		var added := SaveService.get_friends()
		var who := str((added[0] as Dictionary).get("n", "Енот")) if not added.is_empty() else "Енот"
		note = "%s теперь в друзьях" % who if card_result == "ok" else "%s в друзьях: +%d монет и +%d неонита" % [who, SaveService.INVITE_COINS, SaveService.INVITE_GEMS]
	elif card_result == "self":
		note = "Это твоя собственная визитка. С собой дружить можно и без ссылки"
	_toast_note(note)


func _show_badge_welcome(level: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var popup := BadgeWelcomePopup.new(level)
	layer.add_child(popup)
	popup.closed.connect(layer.queue_free)
	popup.open()


func _toast_note(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.06, 0.03, 0.12, 0.95), UiStyle.NEON, 4, 20))
	var label := UiStyle.label(text, 26, UiStyle.TEXT, 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(maxf(get_viewport().get_visible_rect().size.x - 120.0, 240.0), 0.0)
	panel.add_child(label)
	layer.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position.y = 150.0
	var tween := panel.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(layer.queue_free)


func _handle_unclean_exit() -> void:
	var info := Platform.consume_unclean_exit()
	if info.is_empty():
		return
	var quality := SaveService.get_quality()
	if quality > 0:
		SaveService.set_quality(quality - 1)
		SaveService.set_flag("crash_downgraded", true)
	Platform.send_report("unclean_exit", "%s | now quality %d | last: %s | %s" % [info, SaveService.get_quality(), Platform.last_context(), Platform.device_info()])


## Браузер присылает size_changed до того, как холст принял новый размер, поэтому реагируем после паузы.
func _poll_orientation() -> void:
	if not OS.has_feature("web"):
		return
	var w := float(JavaScriptBridge.eval("window.innerWidth"))
	var h := float(JavaScriptBridge.eval("window.innerHeight"))
	if Orient.wants_portrait(w, h) != Orient.portrait:
		_on_window_resized()


func _on_window_resized() -> void:
	_resize_serial += 1
	var serial := _resize_serial
	await get_tree().create_timer(0.35, true, false, true).timeout
	if serial != _resize_serial:
		return
	var view := get_viewport().get_visible_rect().size
	var flipped := Orient.refresh(get_window())
	if (flipped or view != _menu_view) and _screen is MainMenuUI:
		_show_menu()


func _register_input() -> void:
	Controls.apply_keys()


func _show_menu() -> void:
	Orient.refresh(get_window())
	_menu_view = get_viewport().get_visible_rect().size
	var menu := MainMenuUI.new()
	menu.start_requested.connect(_start_game, CONNECT_DEFERRED)
	menu.raid_requested.connect(_start_raid, CONNECT_DEFERRED)
	menu.story_requested.connect(_start_story, CONNECT_DEFERRED)
	_swap_screen(menu)
	_maybe_nag_account(menu)
	_maybe_ask_returning(menu)
	if _debug_hash == "camp":
		SaveService.add_nuts(1000)
		menu._camp.open.call_deferred()
		_debug_hash = ""


## Чистое устройство: до создания гостя спрашиваем «Уже играл?». Закрыл окно — значит новенький, заводим гостя.
func _maybe_ask_returning(menu: MainMenuUI) -> void:
	if not Cloud.session_lost_changed.is_connected(_on_session_lost):
		Cloud.session_lost_changed.connect(_on_session_lost)
	if Cloud.session_lost or Cloud.moved_away:
		_on_session_lost()
		return
	if not _pending_login.is_empty() and not Cloud.has_email():
		var login := _pending_login
		_pending_login = ""
		_ask_login(login)
		return
	if not Cloud.waiting_choice or not _debug_hash.is_empty():
		return
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if not is_instance_valid(menu) or not Cloud.waiting_choice or menu._account.visible:
			return
		menu._account.intro = "Уже играл в Trash Squad? Введи логин и пароль и жми «ВОЙТИ», прогресс вернётся. Новенький? Закрывай окно и беги на помойку, аккаунт заведёшь потом."
		menu._account.closed.connect(func() -> void:
			menu._account.intro = ""
			Cloud.start_guest(), CONNECT_ONE_SHOT)
		menu._account.open())


## Сессия аккаунта слетела (сервер её больше не принимает) или аккаунт переехал на другое устройство:
## просим войти, нового енота не заводим, прогресс на устройстве не трогаем.
func _on_session_lost() -> void:
	if not _screen is MainMenuUI:
		return
	if Cloud.session_lost:
		_ask_login(Cloud.email, "Сервер забыл твою сессию (так бывает после долгого перерыва). Войди логином и паролем, прогресс и друзья на месте.")
	elif Cloud.moved_away and not _moved_prompted:
		_moved_prompted = true
		_ask_login("", "Этот енот переехал на другое устройство (например, в приложение с экрана «Домой») и живёт теперь там. Чтобы играть одним аккаунтом и тут, и там, заведи логин и пароль в приложении и войди ими здесь.")


## Окно входа с подставленным логином: это тот же аккаунт на втором устройстве, ничего не переносится.
func _ask_login(login: String, intro: String = "") -> void:
	if not _screen is MainMenuUI:
		_pending_login = login
		return
	var menu := _screen as MainMenuUI
	menu._account.intro = intro if not intro.is_empty() else "Это твой аккаунт «%s». Введи пароль и жми «ВОЙТИ»: прогресс, друзья и тег подтянутся сами, и браузер с приложением будут одним аккаунтом." % login
	menu._account.prefill_login = login
	if menu._account.visible:
		menu._account._refresh()
		return
	menu._account.closed.connect(func() -> void:
		menu._account.intro = ""
		menu._account.prefill_login = ""
		Cloud.start_guest(), CONNECT_ONE_SHOT)
	menu._account.open()


## После первого забега (и ещё раз после пятого) один раз просим завести аккаунт: иначе прогресс может пропасть.
func _maybe_nag_account(menu: MainMenuUI) -> void:
	if not Platform.is_web or Cloud.has_email() or not _debug_hash.is_empty():
		return
	var runs := SaveService.get_stat("runs")
	var shown := int(Platform.storage_get("trk_acct_nag"))
	if runs < 1 or shown >= 2 or (shown == 1 and runs < 5):
		return
	Platform.storage_set("trk_acct_nag", str(shown + 1))
	menu._account.intro = "Первый забег позади, енот! Заведи логин и пароль, и прогресс не пропадёт, даже если телефон сойдёт с ума или браузер всё забудет."
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(menu):
			menu._account.open()
			menu._account.intro = "")


func _start_game(weapon_id: StringName) -> void:
	Orient.refresh(get_window())
	_with_loading(BATTLE_RESOURCES, func() -> void:
		var game := Game.new()
		game.exit_requested.connect(_show_menu, CONNECT_DEFERRED)
		game.restart_requested.connect(_start_game.bind(weapon_id), CONNECT_DEFERRED)
		_swap_screen(game)
		game.start(weapon_id)
		if not _debug_hash.is_empty():
			game.debug_boss(StringName(_debug_hash))
			_debug_hash = "")


func _start_story(weapon_id: StringName) -> void:
	Orient.refresh(get_window())
	_with_loading(BATTLE_RESOURCES, func() -> void:
		var game := Game.new()
		game.story_mission = "m1"
		game.exit_requested.connect(_show_menu, CONNECT_DEFERRED)
		game.restart_requested.connect(_start_story.bind(weapon_id), CONNECT_DEFERRED)
		_swap_screen(game)
		game.start(weapon_id)
		if _debug_hash == "story:toast":
			game.hud.toast("ПОЛУЧЕНО: ПИВНАЯ ПРОБКА-КЛЮЧ", "Она откроет Ящик с оружием в Зоне 3, стреляй по ящику", Color("#ffb020"))
			game.hud.toast("КОРОЛЬ ХЛАМА", "Мои колонки! Они стоили мне трёх мусоровозов!", Color("#ff5a5a"))
		if _debug_hash == "story:choice":
			game.story._offer_choice("informant")
		if _debug_hash == "story:mini":
			game._show_mini_card("Пивной Барон", "beer_baron", game.player.global_position)
		if _debug_hash == "story:tip":
			game.story.tip_weapon(game._roll_weapon("legendary"))
		if _debug_hash.begins_with("story:jump"):
			game.story.debug_jump(float(_debug_hash.get_slice("=", 1)))
		_debug_hash = "")


func _start_raid(weapon_id: StringName) -> void:
	Orient.refresh(get_window())
	_with_loading(RAID_RESOURCES, func() -> void:
		var raid := Raid.new()
		raid.exit_requested.connect(_show_menu, CONNECT_DEFERRED)
		raid.restart_requested.connect(_start_raid.bind(weapon_id), CONNECT_DEFERRED)
		_swap_screen(raid)
		raid.start(weapon_id)
		if not _debug_hash.is_empty():
			raid.debug_setup(_debug_hash)
			_debug_hash = "")


## Загрузочный экран поверх текущего; новая сцена собирается в пике белой вспышки.
func _with_loading(resources: Array, build: Callable) -> void:
	if _loading != null:
		return
	get_tree().paused = false
	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.transition_point.connect(build, CONNECT_ONE_SHOT)
	_loading.finished.connect(func() -> void: _loading = null, CONNECT_ONE_SHOT)
	_loading.track_resources(PackedStringArray(resources))


func _swap_screen(next: Node) -> void:
	Platform.trail("экран " + next.get_class() + ("/" + str((next.get_script() as Script).get_global_name()) if next.get_script() != null else ""))
	get_tree().paused = false
	if _screen != null:
		# remove_child сразу вызывает _exit_tree старого экрана (бой чистит BulletPool)
		# до того, как новый экран сделает первый кадр.
		remove_child(_screen)
		_screen.queue_free()
	_screen = next
	add_child(next)
	if _loading != null:
		move_child(_loading, get_child_count() - 1)
