class_name ChangelogPopup
extends GlassPopup
## Вкладка «Обновления»: список версий из data/changelog.json. Открытие помечает последнюю версию прочитанной.

const PATH := "res://data/changelog.json"

signal changed

var _list: VBoxContainer


func _init() -> void:
	super("ОБНОВЛЕНИЯ")
	var gift := GiftBox.new("news")
	gift.claimed.connect(func() -> void: changed.emit())
	content.add_child(gift)
	var build_panel := PanelContainer.new()
	build_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.110, 0.106, 0.099, 0.85), UiStyle.NEON, 3, 16))
	build_panel.add_child(UiStyle.label("Установлена версия: %s" % Platform.build_label(), 22, UiStyle.NEON, 6))
	content.add_child(build_panel)
	_list = MenuPopups.scroll_list(content)


static func load_entries() -> Array:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).get("entries") is Array:
		return (parsed as Dictionary)["entries"]
	return []


static func latest_version() -> String:
	var entries := load_entries()
	return str((entries[0] as Dictionary).get("version", "")) if not entries.is_empty() else ""


## Ключ прочтения: версия + дата + заголовок. Новая запись в ту же версию тоже зажигает значок «Обновления».
static func latest_key() -> String:
	var entries := load_entries()
	if entries.is_empty():
		return ""
	var e: Dictionary = entries[0]
	return "%s|%s|%s" % [e.get("version", ""), e.get("date", ""), e.get("title", "")]


static func has_unseen() -> bool:
	var latest := latest_key()
	return not latest.is_empty() and str(SaveService.data.get("changelog_seen", "")) != latest


func _refresh() -> void:
	MenuPopups.clear(_list)
	for entry in load_entries():
		_list.add_child(_make_entry(entry as Dictionary))
	SaveService.data["changelog_seen"] = latest_key()
	SaveService.save_data()


func _make_entry(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.OUTLINE, 3, 20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var head := UiStyle.label("%s · %s" % [entry.get("version", ""), entry.get("date", "")], 28, UiStyle.GOLD, 7)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(head)
	var title := UiStyle.label(str(entry.get("title", "")), 24, UiStyle.NEON, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(520, 0)
	column.add_child(title)
	for block in entry.get("blocks", []):
		var caption := UiStyle.label(str((block as Dictionary).get("name", "")), 21, UiStyle.HOT, 5)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(caption)
		for item in (block as Dictionary).get("lines", []):
			var row := UiStyle.label("• " + str(item), 19, UiStyle.TEXT, 4)
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.custom_minimum_size = Vector2(520, 0)
			column.add_child(row)
	for item in entry.get("items", []):
		var line := UiStyle.label("• " + str(item), 19, UiStyle.TEXT, 4)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(520, 0)
		column.add_child(line)
	return panel
