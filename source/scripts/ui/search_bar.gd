class_name SearchBar
extends HBoxContainer
## Поле поиска: на телефоне по тапу открывает системную клавиатуру (через диалог браузера),
## на ПК обычный ввод. Сигнал changed шлёт нормализованный запрос в нижнем регистре.

signal changed(query: String)

const PROMPT_COOLDOWN_MS := 1200

static var _last_prompt := 0

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
	field.add_theme_color_override("font_color", Color("#0c1d29"))
	field.add_theme_color_override("font_placeholder_color", Color("#8a82a0"))
	field.add_theme_color_override("caret_color", Color("#ff8a3d"))
	field.add_theme_stylebox_override("normal", UiStyle.box(Color("#ffffff"), UiStyle.OUTLINE, 4, 16))
	field.add_theme_stylebox_override("focus", UiStyle.box(Color("#ffffff"), Color("#ff8a3d"), 4, 16))


## В веб-сборке на сенсорных экранах экранная клавиатура из Godot не открывается (iOS), поэтому по тапу
## вызывается нативный диалог ввода браузера; результат записывается в поле как обычный ввод.
static func attach_touch_input(field: LineEdit, title: String) -> void:
	if not OS.has_feature("web") or not Platform.is_touch():
		return
	field.add_child(NativeField.new(field, title))


## Тёмное поле в неоновой рамке (строка чата): светлый текст, розовый курсор.
static func style_dark(field: LineEdit) -> void:
	field.set_meta("dark", true)
	field.add_theme_color_override("font_color", Color("#f2ecff"))
	field.add_theme_color_override("font_placeholder_color", Color("#8fa8b3"))
	field.add_theme_stylebox_override("normal", UiStyle.box(Color("#162c36"), Color(UiStyle.NEON, 0.55), 3, 30))
	field.add_theme_stylebox_override("focus", UiStyle.box(Color("#1a3642"), UiStyle.NEON, 3, 30))


static func restore_colors(field: LineEdit) -> void:
	if field.has_meta("dark"):
		field.add_theme_color_override("font_color", Color("#f2ecff"))
		field.add_theme_color_override("font_placeholder_color", Color("#8fa8b3"))
		field.add_theme_color_override("caret_color", Color("#ff8a3d"))
		return
	field.add_theme_color_override("font_color", Color("#0c1d29"))
	field.add_theme_color_override("font_placeholder_color", Color("#8a82a0"))
	field.add_theme_color_override("caret_color", Color("#ff8a3d"))
