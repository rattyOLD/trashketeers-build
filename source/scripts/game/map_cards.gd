class_name MapCards
extends RefCounted
## Карты Выживания с редкостью («гача карт»): выпадают из сундуков (ключ "map:id"), выбираются перед забегом.
## Карта задаёт настроение неба, «фирменного» врага (доля спавна), крепость врагов и множитель монет.
## Рисунки Астры (бриф v28: assets/maps/<id>/card.png, floor.png) подхватываются по именам, пока — цвета и настроение.

const NONE := ""
const CATALOG := {
	"night_dump": {"title": "Ночная Свалка", "short": "НОЧЬ", "rarity": "rare", "mood": "night", "enemy": &"dash_rat", "share": 0.3,
		"hp": 1.1, "coins": 1.2, "color": "#5b6796", "desc": "Вечная ночь и костры. Шустрые крысы-рывки."},
	"acid_rain": {"title": "Кислотный ливень", "short": "ЛИВЕНЬ", "rarity": "epic", "mood": "storm", "enemy": &"toxic_rat", "share": 0.35,
		"hp": 1.15, "coins": 1.3, "color": "#7dff3a", "desc": "Ливень не стихает. Токсичные крысы повсюду."},
	"neon_market": {"title": "Неоновый рынок", "short": "РЫНОК", "rarity": "epic", "mood": "party", "enemy": &"courier_rat", "share": 0.3,
		"hp": 1.1, "coins": 1.35, "color": "#ff4dd2", "desc": "Розовая дымка и гирлянды. Курьеры с лутом."},
	"gold_vault": {"title": "Золотое хранилище", "short": "ЗОЛОТО", "rarity": "legendary", "mood": "vault", "enemy": &"cash_collector", "share": 0.35,
		"hp": 1.25, "coins": 1.5, "color": "#ffd23f", "desc": "Золото под ногами, инкассаторы на страже. Монеты ×1.5."},
	"pigeon_roofs": {"title": "Голубиные крыши", "short": "КРЫШИ", "rarity": "legendary", "mood": "sunny", "enemy": &"pigeon_bomber", "share": 0.4,
		"hp": 1.2, "coins": 1.45, "color": "#8fd0ff", "desc": "Солнце, трубы и антенны. Голуби-бомбардиры роями."},
}

## Карта текущего забега ("" — обычная).
static var active := NONE


static func keys_of(rarity: String = "") -> Array[String]:
	var out: Array[String] = []
	for id: String in CATALOG:
		if rarity.is_empty() or str(CATALOG[id]["rarity"]) == rarity:
			out.append("map:" + id)
	return out


static func info(id: String) -> Dictionary:
	return CATALOG.get(id, {})


static func owned() -> Array:
	if not SaveService.data.has("maps"):
		SaveService.data["maps"] = []
	return SaveService.data["maps"]


static func owns(id: String) -> bool:
	return owned().has(id)


static func give(id: String) -> void:
	if CATALOG.has(id) and not owned().has(id):
		owned().append(id)
		SaveService.data["map_pick"] = id


## Выбранная перед забегом карта (только из выбитых).
static func chosen() -> String:
	var id := str(SaveService.data.get("map_pick", ""))
	return id if owns(id) else NONE


## Кнопка в меню листает: обычная → выбитые карты по порядку.
static func cycle() -> String:
	var list: Array[String] = [NONE]
	for id: String in CATALOG:
		if owns(id):
			list.append(id)
	var next: String = list[(list.find(chosen()) + 1) % list.size()]
	SaveService.set_value("map_pick", next)
	return next


static func button_text() -> String:
	var id := chosen()
	return "КАРТА: ОБЫЧНАЯ" if id.is_empty() else "КАРТА: %s" % str(CATALOG[id]["short"])


static func resolve() -> void:
	active = chosen()


static func clear() -> void:
	active = NONE


static func coin_mult() -> float:
	return float(info(active).get("coins", 1.0)) if not active.is_empty() else 1.0


static func hp_mult() -> float:
	return float(info(active).get("hp", 1.0)) if not active.is_empty() else 1.0


static func mood() -> String:
	return str(info(active).get("mood", "")) if not active.is_empty() else ""


## Фирменный враг карты и его доля в спавне.
static func featured_enemy() -> StringName:
	return StringName(info(active).get("enemy", &"")) if not active.is_empty() else &""


static func featured_share() -> float:
	return float(info(active).get("share", 0.0)) if not active.is_empty() else 0.0


static func color_of(id: String) -> Color:
	return Color(str(info(id).get("color", "#ffffff")))


static func card_art(id: String) -> Texture2D:
	var path := "res://assets/maps/%s/card.png" % id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
