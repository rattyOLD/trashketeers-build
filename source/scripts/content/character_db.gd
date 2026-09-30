class_name CharacterDB
extends RefCounted
## Герои-налётчики (data/characters.json): один риг енота, но свой окрас меха и глаз,
## пропорции (растяжение костей головы, ушей, хвоста, корпуса, лап) и характеристики.
## Новому зверю со своим артом достаточно своего рига в data/rigs.json — формат тот же.
## coming_soon — герой из концепт-листа ростера: виден в Гардеробе с портретом, но ещё без рига.

const CONFIG_PATH := "res://data/characters.json"
const DEFAULT_ID := "raccoon"

static var _list: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	_load()
	return _list


static func get_character(character_id: String) -> Dictionary:
	_load()
	return _by_id.get(character_id, _by_id.get(DEFAULT_ID, {}))


static func has_character(character_id: String) -> bool:
	_load()
	return _by_id.has(character_id) and not bool(_by_id[character_id].get("coming_soon", false))


## Бонусы характеристик: speed / hp / dash / crit (доли, 0.1 = +10%).
static func get_stat(character_id: String, stat: String) -> float:
	return float((get_character(character_id).get("stats", {}) as Dictionary).get(stat, 0.0))


static func _load() -> void:
	if not _list.is_empty():
		return
	var root := ConfigLoader.load_json(CONFIG_PATH)
	for raw in root.get("characters", []):
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("id"):
			continue
		var entry: Dictionary = raw
		entry["id"] = str(entry["id"])
		entry["price"] = int(entry.get("price", 0))
		entry["currency"] = str(entry.get("currency", "nuts"))
		entry["coming_soon"] = bool(entry.get("coming_soon", false))
		_list.append(entry)
		_by_id[entry["id"]] = entry
	if _list.is_empty():
		var fallback := {"id": DEFAULT_ID, "title": "Енот Бродяга", "description": "", "currency": "nuts", "price": 0,
			"recolor": {}, "proportions": {}, "stats": {}, "traits": ""}
		_list.append(fallback)
		_by_id[DEFAULT_ID] = fallback
