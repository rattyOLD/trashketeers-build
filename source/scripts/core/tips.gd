class_name Tips
extends RefCounted
## Подсказки сюжетного режима: при первом подборе оружия или предмета мир встаёт на паузу и показывается карточка
## с шуточным описанием и характеристиками. Каждый предмет показывается один раз; всё отключается в настройках.

const PATH := "res://data/tips.json"
const GENERIC_GUN := "Новая пушка со свалки. Инструкции нет, но кнопка огня, думаю, сама найдётся."
const GENERIC_MELEE := "Оружие для тех, кто любит здороваться вплотную. Подходи и бей."

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		_data = ConfigLoader.load_json(PATH)
	return _data


static func enabled() -> bool:
	return not bool(SaveService.data.get("tips_off", false))


static func set_enabled(on: bool) -> void:
	SaveService.set_flag("tips_off", not on)


static func is_new(key: String) -> bool:
	return enabled() and not (SaveService.data["tips_seen"] as Array).has(key)


static func mark(key: String) -> void:
	var seen: Array = SaveService.data["tips_seen"]
	if not seen.has(key):
		seen.append(key)
		SaveService.save_data()


static func weapon_key(weapon: WeaponData) -> String:
	return "w:%s" % String(weapon.id)


static func weapon_card(weapon: WeaponData) -> Dictionary:
	var jokes: Dictionary = _load().get("weapons", {})
	var joke := str(jokes.get(String(weapon.id), GENERIC_MELEE if weapon.is_melee() else GENERIC_GUN))
	var stats: Array = [["РЕДКОСТЬ", WeaponData.RARITY_NAMES.get(weapon.rarity, "Обычное")]]
	if weapon.is_melee():
		var cycle := maxf(weapon.windup + weapon.swing + weapon.recovery, 0.1)
		stats.append(["УРОН", str(snappedf(weapon.damage, 0.1))])
		stats.append(["УДАРОВ В СЕК", str(snappedf(1.0 / cycle, 0.1))])
		stats.append(["ДОСТАЁТ", "%d" % int(weapon.melee_reach)])
	else:
		var pellets := weapon.projectiles_per_shot
		stats.append(["УРОН", "%s × %d" % [str(snappedf(weapon.damage, 0.1)), pellets] if pellets > 1 else str(snappedf(weapon.damage, 0.1))])
		stats.append(["ВЫСТРЕЛОВ В СЕК", str(snappedf(1.0 / maxf(weapon.fire_interval, 0.01), 0.1))])
		stats.append(["ДАЛЬНОСТЬ", "%d" % int(weapon.max_distance)])
	stats.append(["УРОН В СЕКУНДУ", "%d" % int(weapon.get_dps())])
	var trait_text: String = WeaponData.TRAITS.get(String(weapon.trait_id), "")
	if not trait_text.is_empty():
		stats.append(["ОСОБЕННОСТЬ", trait_text])
	if weapon.explosion_radius > 0.0:
		stats.append(["ВЗРЫВ", "радиус %d" % int(weapon.explosion_radius)])
	return {"title": weapon.get_title(), "color": weapon.get_rarity_color(), "joke": joke, "stats": stats,
		"weapon_icon": weapon.icon, "weapon_color": weapon.effect_color}


static func item_key(id: String) -> String:
	return "i:%s" % id


static func item_card(id: String) -> Dictionary:
	var items: Dictionary = _load().get("items", {})
	if not items.has(id):
		return {}
	var raw: Dictionary = items[id]
	return {"title": str(raw["title"]), "color": Color(str(raw["color"])), "joke": str(raw["joke"]),
		"stats": raw.get("stats", []), "glyph": str(raw.get("icon", ""))}


## Одна строка характеристик для подсказок на слотах.
static func stat_line(weapon: WeaponData) -> String:
	if weapon.is_melee():
		var cycle := maxf(weapon.windup + weapon.swing + weapon.recovery, 0.1)
		return "урон %s · %s ударов/с · достаёт на %d" % [str(snappedf(weapon.damage, 0.1)), str(snappedf(1.0 / cycle, 0.1)), int(weapon.melee_reach)]
	return "урон %s · %s выстр./с · дальность %d" % [str(snappedf(weapon.damage * weapon.projectiles_per_shot, 0.1)), str(snappedf(1.0 / maxf(weapon.fire_interval, 0.01), 0.1)), int(weapon.max_distance)]
