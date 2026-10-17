## Генерирует THIRD_PARTY_LICENSES.txt из данных движка и source/data/licenses.json.
## OUT=THIRD_PARTY_LICENSES.txt godot --headless --path source --script "$PWD/tools/legal/third_party_licenses.gd"
extends SceneTree
const BAR := "══════════════════════════════════════════════════════════════"
func _init() -> void:
	var o := PackedStringArray()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/licenses.json"))
	var v := Engine.get_version_info()
	o.append("LICENSES / THIRD-PARTY NOTICES")
	o.append("TrashSquad © 2026 Beer Party Studio. All rights reserved.\n")
	o.append("This game is proprietary software.")
	o.append("It uses the Godot Engine and various third-party libraries and assets.")
	o.append("This file contains the required copyright notices and license texts.")
	o.append("This file MUST be distributed together with the game.\n")
	o.append("Godot Engine version used: %s.%s.%s-%s" % [v.major, v.minor, v.patch, v.status])
	_head(o, "1. SOUNDS AND MUSIC")
	var names := {"Звуки: ": "", "Музыка: ": ""}
	for line: Variant in data.get("assets", []):
		var t := str(line)
		for k: String in names:
			t = t.replace(k, "")
		o.append("• " + t.replace(". CC0 1.0.", " — CC0 1.0"))
	o.append("\nAll of the above are licensed under CC0 1.0 (public domain dedication).")
	_head(o, "2. FONTS")
	for font: Variant in data.get("fonts", []):
		var text := str(font.get("text", ""))
		o.append("• %s — %s" % [font.get("name", ""), font.get("license", "")])
		o.append("  " + text.split("\n\n")[0].replace("\n", " ").replace(",  ", ", ") + "\n")
	o.append("Full text of the SIL Open Font License 1.1 is provided in section 6.")
	_head(o, "3. GODOT ENGINE")
	o.append("This game is made with Godot Engine (https://godotengine.org).\n")
	o.append(Engine.get_license_text())
	o.append("Godot Engine logo — Creative Commons Attribution 4.0 International (CC-BY-4.0)")
	o.append("Copyright (c) 2017 Andrea Calabró")
	_head(o, "4. NOTICES")
	for notice: Variant in data.get("notices", []):
		o.append("• " + str(notice))
	_head(o, "5. ENGINE COMPONENTS")
	for component: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in component.get("parts", []):
			o.append("%s — %s" % [component.get("name", ""), part.get("license", "")])
			for line: Variant in part.get("copyright", []):
				o.append("  © " + str(line))
			o.append("")
	_head(o, "6. FULL LICENSE TEXTS")
	var ofl := str((data.get("fonts", [])[0] as Dictionary).get("text", ""))
	o.append("--- OFL-1.1 (SIL Open Font License) ---\n")
	o.append(ofl.substr(ofl.find("SIL OPEN FONT LICENSE")))
	var texts := Engine.get_license_info()
	for license_name: String in texts:
		o.append("\n--- %s ---\n" % license_name)
		o.append(str(texts[license_name]))
	o.append("\n\nEND OF THIRD-PARTY LICENSES")
	o.append("This file is provided to comply with the attribution and notice requirements")
	o.append("of the licenses under which the third-party components are distributed.")
	o.append("The game itself remains proprietary © 2026 Beer Party Studio.")
	var file := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	file.store_string("\n".join(o) + "\n")
	quit()

func _head(o: PackedStringArray, title: String) -> void:
	o.append("\n" + BAR + "\n" + title + "\n" + BAR + "\n")
