class_name SearchBar
extends HBoxContainer
## Поле поиска: на телефоне по тапу открывает системную клавиатуру (через диалог браузера),
## на ПК обычный ввод. Сигнал changed шлёт нормализованный запрос в нижнем регистре.

signal changed(query: String)

var edit: LineEdit


func _init(placeholder: String = "Поиск по названию") -> void:
	add_theme_constant_override("separation", 8)
	edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.clear_button_enabled = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 54)
	SearchBar.style(edit, 22)
	add_child(edit)
	SearchBar.attach_touch_input(edit, placeholder)
	edit.text_changed.connect(func(text: String) -> void: changed.emit(SearchBar.normalize(text)))


static func normalize(text: String) -> String:
	return text.strip_edges().to_lower().replace("ё", "е")


static func matches(query: String, haystack: String) -> bool:
	return query.is_empty() or SearchBar.normalize(haystack).contains(query)


static func style(field: LineEdit, font_size: int) -> void:
	field.add_theme_font_size_override("font_size", font_size)
	field.add_theme_color_override("font_color", Color("#1a1030"))
	field.add_theme_color_override("font_placeholder_color", Color("#8a82a0"))
	field.add_theme_color_override("caret_color", Color("#ff2ea6"))
	field.add_theme_stylebox_override("normal", UiStyle.box(Color("#ffffff"), UiStyle.OUTLINE, 4, 16))
	field.add_theme_stylebox_override("focus", UiStyle.box(Color("#ffffff"), Color("#ff2ea6"), 4, 16))


## В веб-сборке на сенсорных экранах экранная клавиатура из Godot не открывается (iOS), поэтому по тапу
## вызывается нативный диалог ввода браузера; результат записывается в поле как обычный ввод.
static func attach_touch_input(field: LineEdit, title: String) -> void:
	if not OS.has_feature("web") or not DisplayServer.is_touchscreen_available():
		return
	field.focus_entered.connect(func() -> void:
		field.release_focus()
		var typed: Variant = Platform.prompt_text(title, field.text)
		if typed == null:
			return
		field.text = str(typed).substr(0, field.max_length if field.max_length > 0 else 64)
		field.text_changed.emit(field.text)
		field.text_submitted.emit(field.text))
