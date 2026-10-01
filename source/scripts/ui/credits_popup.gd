class_name CreditsPopup
extends GlassPopup
## Создатели: название команды и благодарности тестерам (data/brand.json).


func _init() -> void:
	super("СОЗДАТЕЛИ")
	var brand := ConfigLoader.load_json("res://data/brand.json")
	var studio := str(brand.get("studio", "")).strip_edges()
	if not studio.is_empty():
		content.add_child(_label("Игра сделана командой", 22, UiStyle.TEXT_DIM))
		content.add_child(_label(studio, 40, UiStyle.GOLD))
	content.add_child(_label("Спасибо тестерам", 28, UiStyle.NEON))
	var names: Array = brand.get("thanks", [])
	var line := ", ".join(PackedStringArray(names))
	if not line.is_empty():
		line += " и всем остальным, кто нашёл баги и не промолчал."
		content.add_child(_label(line, 24, UiStyle.TEXT))
	content.add_child(_label("Вы сделали эту свалку чище. Ненамного.", 20, UiStyle.TEXT_DIM))


func _label(text: String, size: int, color: Color) -> Label:
	var label := UiStyle.label(text, size, color, 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(panel_width() - 70.0, 0)
	return label
