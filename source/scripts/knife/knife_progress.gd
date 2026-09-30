class_name KnifeProgress
extends RefCounted
## Прогресс игры «Втык!» внутри общего сохранения Сетки: SaveService.data["knife"].
## Все функции статические и работают поверх SaveService, чтобы у Сетки был один файл
## сохранения и один кошелёк монет.

const KNIFE_IDS: Array[String] = ["kitchen", "screwdriver", "cleaver", "axe", "fork", "banana", "saber", "crystal"]
const START_KNIFE := "kitchen"
const DEFAULTS := {
	"level": 1,
	"best": 1,
	"owned": ["kitchen"],
	"selected": "kitchen",
	"best_combo": 0,
	"bosses": [],
	"throws": 0,
	"perfects": 0,
}


static func sanitize(save: Dictionary) -> void:
	var raw = save.get("knife", {})
	var clean := DEFAULTS.duplicate(true)
	if typeof(raw) == TYPE_DICTIONARY:
		for key in DEFAULTS:
			if (raw as Dictionary).has(key) and ConfigLoader.type_matches(raw[key], DEFAULTS[key]):
				clean[key] = raw[key]
	for key in ["level", "best", "best_combo", "throws", "perfects"]:
		clean[key] = maxi(int(clean[key]), 0)
	clean["level"] = maxi(int(clean["level"]), 1)
	clean["best"] = maxi(int(clean["best"]), int(clean["level"]))
	var owned: Array = []
	for id in clean["owned"]:
		if KNIFE_IDS.has(str(id)) and not owned.has(str(id)):
			owned.append(str(id))
	if not owned.has(START_KNIFE):
		owned.push_front(START_KNIFE)
	clean["owned"] = owned
	var bosses: Array = []
	for level in clean["bosses"]:
		bosses.append(int(level))
	clean["bosses"] = bosses
	if not owned.has(str(clean["selected"])):
		clean["selected"] = START_KNIFE
	save["knife"] = clean


static func _data() -> Dictionary:
	return SaveService.data["knife"]


static func get_level() -> int:
	return int(_data()["level"])


static func get_best_level() -> int:
	return int(_data()["best"])


static func get_best_combo() -> int:
	return int(_data()["best_combo"])


static func owns(knife_id: String) -> bool:
	return (_data()["owned"] as Array).has(knife_id)


static func get_selected() -> String:
	return str(_data()["selected"])


static func select(knife_id: String) -> void:
	if owns(knife_id):
		_data()["selected"] = knife_id
		SaveService.save_data()


static func unlock(knife_id: String) -> bool:
	if owns(knife_id) or not KNIFE_IDS.has(knife_id):
		return false
	(_data()["owned"] as Array).append(knife_id)
	SaveService.save_data()
	return true


## Покупка за монеты общего кошелька; false — не хватает или уже есть.
static func buy(knife_id: String, price: int) -> bool:
	if owns(knife_id) or SaveService.get_coins() < price:
		return false
	SaveService.data["nuts"] = SaveService.get_coins() - price
	(_data()["owned"] as Array).append(knife_id)
	_data()["selected"] = knife_id
	SaveService.save_data()
	return true


static func buy_with_dust(knife_id: String, price: int) -> bool:
	if owns(knife_id) or SaveService.get_star_dust() < price:
		return false
	SaveService.data["star_dust"] = SaveService.get_star_dust() - price
	(_data()["owned"] as Array).append(knife_id)
	_data()["selected"] = knife_id
	SaveService.save_data()
	return true


static func is_boss_beaten(level: int) -> bool:
	return (_data()["bosses"] as Array).has(level)


## Уровень пройден: следующий становится текущим, монеты — в общий кошелёк.
static func complete_level(level: int, coins: int, was_boss: bool) -> void:
	var data := _data()
	data["level"] = maxi(int(data["level"]), level + 1)
	data["best"] = maxi(int(data["best"]), level + 1)
	if was_boss and not is_boss_beaten(level):
		(data["bosses"] as Array).append(level)
	SaveService.data["nuts"] = SaveService.get_coins() + coins
	var stats: Dictionary = SaveService.data["stats"]
	stats["nuts_total"] = int(stats.get("nuts_total", 0)) + coins
	SaveService.quest_add("knife_levels", 1)
	SaveService.save_data()


## Счётчики бросков копятся в памяти и сохраняются вместе с итогом уровня.
static func add_throw(perfect: bool) -> void:
	var data := _data()
	data["throws"] = int(data["throws"]) + 1
	if perfect:
		data["perfects"] = int(data["perfects"]) + 1
		SaveService.quest_add("knife_perfect", 1)


static func record_combo(combo: int) -> void:
	if combo > get_best_combo():
		_data()["best_combo"] = combo
