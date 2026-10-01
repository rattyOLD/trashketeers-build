class_name AccountPopup
extends GlassPopup
## Аккаунт по почте: привязать почту к профилю или войти на новом устройстве. Коды приходят письмом.

enum Step { START, LINK_CODE, LOGIN_CODE }

var _step := Step.START
var _address := ""
var _status: Label
var _body: VBoxContainer


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
	_step = Step.START
	_render()


func _render() -> void:
	MenuPopups.clear(_body)
	if _step == Step.START:
		_render_start()
	else:
		_render_code()


func _render_start() -> void:
	if Cloud.has_email():
		_say("Почта привязана: %s. Прогресс вернётся на любом устройстве, где войдёшь по ней." % Cloud.email)
	else:
		_say("Привяжи почту, и прогресс не пропадёт, даже если очистишь браузер или сменишь телефон.")
	var edit := _edit("Твоя почта")
	_body.add_child(edit)
	var link := UiStyle.button("ПРИВЯЗАТЬ ПОЧТУ", UiStyle.HOT, 24, Vector2(0, 64))
	link.pressed.connect(func() -> void:
		if not _valid(edit.text):
			_say("Проверь почту: она должна быть вида name@mail.com")
			return
		link.disabled = true
		_say("Отправляю письмо...")
		var result := await Cloud.link_email(edit.text)
		if not is_instance_valid(link):
			return
		link.disabled = false
		if result == "sent":
			_address = edit.text.strip_edges().to_lower()
			_step = Step.LINK_CODE
			_render()
			_say("Письмо отправлено на %s. Введи код из письма. Проверь и «Спам»." % _address)
		elif result == "exists":
			_say("Эта почта уже привязана к профилю. Нажми «ВОЙТИ ПО ПОЧТЕ», чтобы вернуть тот прогресс.")
		elif result == "limit":
			_say("Слишком много писем. Подожди несколько минут и попробуй снова.")
		elif result == "offline":
			_say("Нет связи с сервером. Попробуй позже.")
		else:
			_say("Не получилось отправить письмо. Проверь адрес."))
	_body.add_child(link)
	var login := UiStyle.button("ВОЙТИ ПО ПОЧТЕ (на новом устройстве)", UiStyle.PANEL_LIGHT, 22, Vector2(0, 58))
	login.pressed.connect(func() -> void:
		if not _valid(edit.text):
			_say("Впиши почту выше, потом нажми «Войти».")
			return
		login.disabled = true
		_say("Отправляю письмо...")
		var result := await Cloud.request_login(edit.text)
		if not is_instance_valid(login):
			return
		login.disabled = false
		if result == "sent":
			_address = edit.text.strip_edges().to_lower()
			_step = Step.LOGIN_CODE
			_render()
			_say("Письмо отправлено на %s. Введи код из письма." % _address)
		elif result == "not_found":
			_say("К этой почте ничего не привязано. Привяжи её на старом устройстве или проверь адрес.")
		elif result == "limit":
			_say("Слишком много писем. Подожди несколько минут и попробуй снова.")
		else:
			_say("Нет связи с сервером. Попробуй позже."))
	_body.add_child(login)
	_body.add_child(MenuPopups.small_hint("Почта нужна только для входа. Мы ничего не рассылаем."))


func _render_code() -> void:
	var edit := _edit("Код из письма")
	_body.add_child(edit)
	var ok := UiStyle.button("ПОДТВЕРДИТЬ", UiStyle.HOT, 24, Vector2(0, 64))
	ok.pressed.connect(func() -> void:
		if edit.text.strip_edges().length() < 4:
			return
		ok.disabled = true
		if _step == Step.LINK_CODE:
			var done := await Cloud.confirm_link(_address, edit.text)
			if not is_instance_valid(ok):
				return
			ok.disabled = false
			if done:
				await Cloud.upload_save()
				_step = Step.START
				_render()
				_say("Готово! Почта привязана, прогресс сохранён в облаке.")
			else:
				_say("Код не подошёл. Проверь цифры или запроси новое письмо.")
		else:
			var logged := await Cloud.confirm_login(_address, edit.text)
			if not is_instance_valid(ok):
				return
			ok.disabled = false
			if not logged:
				_say("Код не подошёл. Проверь цифры или запроси новое письмо.")
				return
			await Cloud.sync_profile()
			var saved := await Cloud.my_save()
			_step = Step.START
			_render()
			if not saved.is_empty() and SaveService.import_code(saved):
				_say("Вход выполнен, прогресс возвращён.")
			else:
				_say("Вход выполнен. В облаке пока нет сохранения для этой почты."))
	_body.add_child(ok)
	var back := UiStyle.button("Назад", UiStyle.PANEL_LIGHT, 22, Vector2(0, 54))
	back.pressed.connect(func() -> void:
		_step = Step.START
		_render())
	_body.add_child(back)


func _valid(text: String) -> bool:
	var value := text.strip_edges()
	return value.contains("@") and value.contains(".") and value.length() >= 6 and not value.contains(" ")


func _say(text: String) -> void:
	_status.text = text


func _edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 56)
	edit.max_length = 128
	SearchBar.style(edit, 22)
	SearchBar.attach_touch_input(edit, placeholder)
	return edit
