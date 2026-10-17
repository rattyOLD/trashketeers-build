class_name LicensesPopup
extends GlassPopup
## Лицензии: Godot и его компоненты, шрифты (OFL), сторонние звуки и музыка (data/licenses.json).
## Полные тексты длинные, поэтому список собирается при первом открытии.

var _list: VBoxContainer


func _init() -> void:
	super("ЛИЦЕНЗИИ")
	_list = MenuPopups.scroll_list(content)


func _refresh() -> void:
	if _list.get_child_count() > 0:
		return
	var brand := ConfigLoader.load_json("res://data/brand.json")
	_text("%s\n%s" % [brand.get("game", ""), brand.get("copyright", "")], UiStyle.GOLD)
	var data := ConfigLoader.load_json("res://data/licenses.json")
	_section("ЗВУКИ И МУЗЫКА")
	for line: Variant in data.get("assets", []):
		_text(str(line), UiStyle.TEXT)
	_section("ШРИФТЫ")
	for font: Variant in data.get("fonts", []):
		var entry := font as Dictionary
		_text("%s — %s" % [entry.get("name", ""), entry.get("license", "")], UiStyle.NEON)
		_text(str(entry.get("text", "")), UiStyle.TEXT_DIM)
	_section("GODOT ENGINE")
	_text("Игра сделана на движке Godot Engine (godotengine.org).", UiStyle.TEXT)
	_text(Engine.get_license_text(), UiStyle.TEXT_DIM)
	for notice: Variant in data.get("notices", []):
		_text(str(notice), UiStyle.TEXT)
	# MIT и BSD требуют воспроизвести строки копирайта каждого компонента, а не только название лицензии.
	_section("КОМПОНЕНТЫ ДВИЖКА")
	for component: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in component.get("parts", []):
			_text("%s — %s" % [component.get("name", ""), part.get("license", "")], UiStyle.TEXT)
			_text("© " + "\n© ".join(PackedStringArray(part.get("copyright", []))), UiStyle.TEXT_DIM)
	_section("ТЕКСТЫ ЛИЦЕНЗИЙ КОМПОНЕНТОВ")
	var texts := Engine.get_license_info()
	for license_name: String in texts:
		_text(license_name, UiStyle.NEON)
		_text(str(texts[license_name]), UiStyle.TEXT_DIM)


func _section(title: String) -> void:
	var caption := UiStyle.label(title, 26, UiStyle.NEON, 6)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_list.add_child(caption)


func _text(text: String, color: Color) -> void:
	var label := UiStyle.label(text, 17, color, 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_list.add_child(label)
