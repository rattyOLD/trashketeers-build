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


static func has_unseen() -> bool:
	var latest := latest_version()
	return not latest.is_empty() and str(SaveService.data.get("changelog_seen", "")) != latest


func _refresh() -> void:
	MenuPopups.clear(_list)
	for entry in load_entries():
		_list.add_child(_make_entry(entry as Dictionary))
	SaveService.data["changelog_seen"] = latest_version()
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
	for item in entry.get("items", []):
		var line := UiStyle.label("• " + str(item), 19, UiStyle.TEXT, 4)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(520, 0)
		column.add_child(line)
	return panel
