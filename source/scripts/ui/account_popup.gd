class_name AccountPopup
extends GlassPopup
## Аккаунт по логину и паролю: ничего не теряется при очистке браузера или смене телефона.
## Почта не нужна и письма не рассылаются. Пароль нельзя восстановить, поэтому его стоит записать.

var _status: Label
var _body: VBoxContainer
var intro := ""
var prefill_login := ""


func _init() -> void:
	super("АККАУНТ")
	_status = UiStyle.label("", 20, UiStyle.NEON, 5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(panel_width() - 110.0, 0)
	content.add_child(_status)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	content.add_child(_body)


func _refresh() -> void:
	MenuPopups.clear(_body)
	if Cloud.has_email() and not Cloud.session_lost:
		_render_logged()
	else:
		_render_guest()


func _render_logged() -> void:
	_say("Аккаунт «%s». Прогресс, друзья, чаты и тег привязаны к нему. На новом устройстве войди с этим логином и паролем." % Cloud.email)
	var pass_edit := _edit("Новый пароль", true)
	_body.add_child(pass_edit)
	var change := UiStyle.button("СМЕНИТЬ ПАРОЛЬ", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	change.pressed.connect(func() -> void:
		if pass_edit.text.length() < 6:
			_say("Пароль от 6 знаков.")
			return
		var result := await Cloud.change_password(pass_edit.text)
		if is_instance_valid(change):
			pass_edit.text = ""
			_say("Пароль изменён." if result == "ok" else ("Слишком простой пароль." if result == "weak" else "Нет связи с сервером.")))
	_body.add_child(change)
	var save := UiStyle.button("СОХРАНИТЬ В ОБЛАКО СЕЙЧАС", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	save.pressed.connect(func() -> void:
		var code := await Cloud.upload_save()
		if is_instance_valid(save):
			_say("Сохранено." if not code.is_empty() else "Нет связи с сервером."))
	_body.add_child(save)
	var out := UiStyle.button("ВЫЙТИ ИЗ АККАУНТА", Color("#a3283e"), 22, Vector2(0, 58))
	var armed := [false]
	out.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			out.text = "ТОЧНО? Прогресс останется в облаке"
			get_tree().create_timer(3.5).timeout.connect(func() -> void:
				if is_instance_valid(out):
					armed[0] = false
					out.text = "ВЫЙТИ ИЗ АККАУНТА")
			return
		out.disabled = true
		out.text = "Сохраняю и выхожу..."
		await Cloud.logout())
	_body.add_child(out)
	_body.add_child(MenuPopups.small_hint("После выхода игра станет чистой. Вернёшь всё, войдя этим же логином и паролем."))


func _render_guest() -> void:
	_say(intro if not intro.is_empty() else "Придумай логин и пароль, и прогресс не пропадёт при очистке браузера или смене телефона. Почта не нужна.")
	var login_edit := _edit("Логин (латиница, цифры, _)", false)
	_body.add_child(login_edit)
	if Cloud.session_lost:
		login_edit.text = Cloud.email
	elif not prefill_login.is_empty():
		login_edit.text = prefill_login
	var pass_edit := _edit("Пароль (от 6 знаков)", true)
	_body.add_child(pass_edit)
	var create := UiStyle.button("СОЗДАТЬ АККАУНТ", UiStyle.HOT, 24, Vector2(0, 64))
	create.pressed.connect(func() -> void:
		if Cloud.clean_login(login_edit.text).is_empty():
			_say("Логин: 3–20 знаков, только латиница, цифры и «_».")
			return
		if pass_edit.text.length() < 6:
			_say("Пароль от 6 знаков.")
			return
		create.disabled = true
		_say("Создаю...")
		var result := await Cloud.register_account(login_edit.text, pass_edit.text)
		if not is_instance_valid(create):
			return
		create.disabled = false
		if result == "ok":
			await Cloud.upload_save()
			_refresh()
			_say("Готово! Аккаунт создан, прогресс в облаке. Запиши пароль: восстановить его нельзя.")
		elif result == "taken":
			_say("Такой логин уже занят. Придумай другой, или нажми «ВОЙТИ», если это твой.")
		elif result == "weak":
			_say("Слишком простой пароль. Добавь знаков.")
		elif result == "confirm":
			_say("Сервер просит подтверждение почты: владельцу надо отключить Confirm email в Supabase (Authentication, Providers, Email).")
		elif result == "offline":
			_say("Нет связи с сервером. Попробуй позже.")
		else:
			_say("Не получилось. Проверь логин (латиница, цифры, «_»)%s" % ((". Сервер ответил: " + Cloud.last_error.left(120)) if not Cloud.last_error.is_empty() else "")))
	_body.add_child(create)
	var login := UiStyle.button("ВОЙТИ (на новом устройстве)", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	login.pressed.connect(func() -> void:
		login.disabled = true
		_say("Вхожу...")
		var result := await Cloud.login_account(login_edit.text, pass_edit.text)
		if not is_instance_valid(login):
			return
		login.disabled = false
		if result != "ok":
			_say("Нет связи с сервером." if result == "offline" else "Логин или пароль не подошли.")
			return
		# Сначала читаем облако, и только потом синхронизируем профиль: иначе гостевой ник и статистика
		# с этого устройства затёрли бы ник аккаунта на сервере.
		var cloud := await Cloud.fetch_cloud_save()
		if not bool(cloud["ok"]):
			_refresh()
			_say("Вход выполнен, но облачное сохранение не прочиталось (%s). Ничего не затёрто, попробуй войти ещё раз чуть позже." % Cloud.last_error)
			return
		var saved := str(cloud["text"])
		var theirs := SaveService.parse_backup(saved)
		var richer_cloud := not theirs.is_empty() and SaveService.score_of(theirs) >= SaveService.progress_score()
		var imported := richer_cloud and SaveService.import_code(saved)
		await Cloud.sync_profile()
		if not is_instance_valid(login):
			return
		if imported:
			_refresh()
			Cloud.upload_save()
			_say("Вход выполнен, прогресс, друзья и тег на месте.")
		elif saved.is_empty():
			_refresh()
			Cloud.upload_save()
			_say("Вход выполнен. В облаке этого аккаунта ещё пусто, твой текущий прогресс сохранён туда.")
		else:
			_refresh()
			Cloud.upload_save()
			_say("Вход выполнен. На этом устройстве прогресса больше, чем в облаке, он сохранён в аккаунт."))
	_body.add_child(login)
	_body.add_child(MenuPopups.small_hint("Запиши пароль: мы его не видим и вернуть не сможем. Если забудешь, поможет только DeV (сбросит на временный)."))


func _say(text: String) -> void:
	_status.text = text


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 56)
	edit.max_length = 64
	SearchBar.style(edit, 22)
	SearchBar.attach_touch_input(edit, placeholder)
	return edit
