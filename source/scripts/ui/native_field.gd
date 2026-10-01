class_name NativeField
extends Node
## Поле ввода браузера поверх LineEdit (веб, сенсорный экран). Игрок тапает прямо в него: клавиатура открывается
## сама, текст видно на месте, работают автозамена, вставка и эмодзи-клавиатура. Текст синхронизируется
## с LineEdit (text_changed / text_submitted срабатывают как обычно). Поле видно, только пока его окно верхнее.

signal focus_changed(focused: bool)

static var _counter := 0

var field: LineEdit
var placeholder := ""
var _id := ""
var _shown := false
var _rect := Rect2()
var _html_text := ""
var _focused := false


func _init(target: LineEdit, hint: String) -> void:
	field = target
	placeholder = hint if not hint.is_empty() else target.placeholder_text
	_counter += 1
	_id = "f%d" % _counter


func _process(_delta: float) -> void:
	var want := is_instance_valid(field) and field.is_visible_in_tree() and GlassPopup.is_on_top(field) and field.size.x > 20.0
	if not want:
		if _shown:
			_hide()
		return
	var rect := field.get_global_rect()
	if not _inside_scroll(rect):
		if _shown:
			_hide()
		return
	if not _shown or not rect.is_equal_approx(_rect):
		_rect = rect
		var font_px := float(field.get_theme_font_size("font_size"))
		Platform.native_input_show(_id, rect, placeholder, field.secret, field.max_length, font_px)
		if not _shown:
			_shown = true
			_html_text = ""
			Platform.native_input_set(_id, field.text)
			_html_text = field.text
			_mute(true)
	if field.text != _html_text:
		Platform.native_input_set(_id, field.text)
		_html_text = field.text
	var state := Platform.native_input_poll(_id)
	if state.is_empty():
		return
	var text := str(state.get("text", ""))
	if text != _html_text:
		_html_text = text
		field.text = text
		field.text_changed.emit(text)
	var focused := bool(state.get("focused", false))
	if focused != _focused:
		_focused = focused
		focus_changed.emit(focused)
		var popup := GlassPopup.owner_of(field)
		if popup != null:
			popup._lift(focused)
	if bool(state.get("enter", false)):
		field.text_submitted.emit(field.text)


## Поле прокручено за край списка: браузерное поле иначе висело бы поверх окна.
func _inside_scroll(rect: Rect2) -> bool:
	var cur := field.get_parent()
	while cur != null:
		if cur is ScrollContainer:
			return (cur as ScrollContainer).get_global_rect().grow(2.0).encloses(rect)
		cur = cur.get_parent()
	return true


## Обновить подсказку и прочие настройки поля на экране.
func refresh() -> void:
	_rect = Rect2()


func _hide() -> void:
	_shown = false
	Platform.native_input_hide(_id)
	_mute(false)
	if _focused:
		_focused = false
		focus_changed.emit(false)
		var popup := GlassPopup.owner_of(field)
		if popup != null:
			popup._lift(false)


## Собственный текст LineEdit прячем, чтобы не было двух надписей: виден только браузерный.
func _mute(on: bool) -> void:
	if not is_instance_valid(field):
		return
	if on:
		field.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		field.add_theme_color_override("font_placeholder_color", Color(0, 0, 0, 0))
		field.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
	else:
		field.remove_theme_color_override("caret_color")
		SearchBar.restore_colors(field)


func _exit_tree() -> void:
	if _shown:
		_hide()
