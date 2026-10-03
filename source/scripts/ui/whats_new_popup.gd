class_name WhatsNewPopup
extends Control
## Плашка «Что нового»: один раз после каждой обновы, коротко и только важное. Текст берётся из data/changelog.json
## (поля short и image последней записи). Кнопка ведёт в полный список обновлений.

signal open_changelog
signal closed

const SEEN_KEY := "whatsnew_seen"


## Показывать, если у последней записи есть краткий текст и игрок её ещё не видел.
static func should_show() -> bool:
	var entries := ChangelogPopup.load_entries()
	if entries.is_empty():
		return false
	var latest := entries[0] as Dictionary
	if not (latest.get("short") is Array) or (latest["short"] as Array).is_empty():
		return false
	return str(SaveService.data.get(SEEN_KEY, "")) != str(latest.get("version", ""))


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90


func _ready() -> void:
	var entry := ChangelogPopup.load_entries()[0] as Dictionary
	SaveService.data[SEEN_KEY] = str(entry.get("version", ""))
	SaveService.save_data()
	var dim := ColorRect.new()
	dim.color = Color(0.074, 0.071, 0.066, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Тап мимо окна — закрыть.
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
			_close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var width := minf(GlassPopup.panel_width(), 600.0) - 40.0
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	card.add_theme_stylebox_override("panel", UiStyle.box(Color("#32302d"), UiStyle.GOLD, 5, 28))
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	column.add_child(UiStyle.label("ЧТО НОВОГО · %s" % str(entry.get("version", "")), 24, UiStyle.GOLD, 6))
	var image_path := str(entry.get("image", ""))
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		var picture := TextureRect.new()
		picture.texture = load(image_path) as Texture2D
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(0, 150)
		column.add_child(picture)
	var title := UiStyle.label(str(entry.get("title", "")), 30, UiStyle.NEON, 7)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(width - 50.0, 0)
	column.add_child(title)
	# Список изменений прокручивается: кнопки всегда видны, даже если текст длиннее экрана.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width - 40.0, maxf(get_viewport_rect().size.y - 620.0, 240.0))
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	for line in entry.get("short", []):
		var row := UiStyle.label("• " + str(line), 20, UiStyle.TEXT, 4)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(width - 60.0, 0)
		rows.add_child(row)
	var more := UiStyle.button("ВСЁ ОБ ОБНОВЛЕНИИ", UiStyle.HOT, 24, Vector2(0, 68))
	more.name = "MoreButton"
	more.pressed.connect(func() -> void:
		open_changelog.emit()
		_close())
	column.add_child(more)
	var ok := UiStyle.button("ПОНЯТНО", UiStyle.PANEL_LIGHT, 22, Vector2(0, 56))
	ok.name = "CloseButton"
	ok.pressed.connect(_close)
	column.add_child(ok)
	UiStyle.pop_in(card, 0.5)


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _notification(what: int) -> void:
	# Кнопка «Назад» на Android закрывает окно.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_close()
