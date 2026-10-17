class_name CreditsPopup
extends GlassPopup
## Создатели: игра, копирайт и движок, благодарности тестерам (data/brand.json) и полные лицензии.
## Короткий блок — по образцу титров; полный текст ещё и в THIRD_PARTY_LICENSES.txt рядом с ПК-сборкой.


func _init() -> void:
	super("СОЗДАТЕЛИ")
	var brand := ConfigLoader.load_json("res://data/brand.json")
	content.add_child(_label(str(brand.get("game", "")).to_upper(), 44, UiStyle.GOLD))
	content.add_child(_label(str(brand.get("copyright", "")), 24, UiStyle.TEXT))
	content.add_child(_label("Made with Godot Engine\ngodotengine.org", 22, UiStyle.TEXT_DIM))
	content.add_child(_label("Third-party licenses and attributions:\nsee the file THIRD_PARTY_LICENSES.txt included with the game,\nor press LICENSES below.", 20, UiStyle.TEXT_DIM))
	content.add_child(_label("Спасибо тестерам", 28, UiStyle.NEON))
	var names: Array = brand.get("thanks", [])
	var line := ", ".join(PackedStringArray(names))
	if not line.is_empty():
		line += " и всем остальным, кто нашёл баги и не промолчал."
		content.add_child(_label(line, 24, UiStyle.TEXT))
	content.add_child(_label("Вы сделали эту свалку чище. Ненамного.", 20, UiStyle.TEXT_DIM))
	var licenses := LicensesPopup.new()
	add_child(licenses)
	var button := UiStyle.button("LICENSES", UiStyle.PANEL_LIGHT, 22, Vector2(0, 66))
	button.pressed.connect(licenses.open)
	content.add_child(button)


func _label(text: String, size: int, color: Color) -> Label:
	var label := UiStyle.label(text, size, color, 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 0)
	return label
