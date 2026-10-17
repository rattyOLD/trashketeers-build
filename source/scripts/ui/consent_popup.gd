class_name ConsentPopup
extends GlassPopup
## Первый запуск: разрешить ли анонимные отчёты об ошибках и производительности.
## Ответ хранит Platform (CONSENT_KEY); поменять можно в настройках.


func _init() -> void:
	super("ОТЧЁТЫ ОБ ОШИБКАХ")
	var text := UiStyle.label("Можно мы будем получать анонимные отчёты о вылетах, ошибках и скорости игры? Они помогают чинить баги. В отчёте — модель устройства, версия игры, журнал ошибок и снимок экрана в момент вылета. Имени, почты и платёжных данных там нет.", 22, UiStyle.TEXT, 4)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(text)
	content.add_child(MenuPopups.small_hint("Решение можно изменить в любой момент: Настройки → Конфиденциальность."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	for allowed: bool in [true, false]:
		var button := UiStyle.button("РАЗРЕШИТЬ" if allowed else "НЕ ОТПРАВЛЯТЬ", UiStyle.NEON if allowed else UiStyle.PANEL_LIGHT, 24, Vector2(0, 76))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			Platform.set_telemetry_consent(allowed)
			close())
		row.add_child(button)
