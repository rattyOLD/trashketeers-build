class_name Cosmetics
extends RefCounted
## Косметика сезона: титулы, рамки аватара, цвета ника и бустеры. Ключи "title:id", "frame:id", "color:id", "boost:id".

const KINDS: Array[String] = ["title", "frame", "color", "boost"]
const BOOST_COINS_BONUS := 0.25
const BOOST_PASS_BONUS := 0.5
const BOOST_RUNS := 3
const CATALOG := {
	"title:tax_evader": {"name": "Неплательщик", "rarity": "common"},
	"title:rat_dentist": {"name": "Крысиный дантист", "rarity": "rare"},
	"title:lord_dump": {"name": "Лорд Помойки", "rarity": "rare"},
	"title:pigeon_dad": {"name": "Голубиный папа", "rarity": "epic"},
	"title:beer_prophet": {"name": "Пивной пророк", "rarity": "epic"},
	"title:cashier": {"name": "Кассир Апокалипсиса", "rarity": "legendary"},
	"frame:tin": {"name": "Рамка из банок", "rarity": "common", "color": "#9aa7b5"},
	"frame:caps": {"name": "Рамка из крышек", "rarity": "rare", "color": "#d9923a"},
	"frame:beer": {"name": "Пенная рамка", "rarity": "rare", "color": "#ffd23f"},
	"frame:neon": {"name": "Неоновая рамка", "rarity": "epic", "color": "#ff4dd2"},
	"frame:rail": {"name": "Рельсовая рамка", "rarity": "legendary", "color": "#4df3ff"},
	"color:toxic": {"name": "Токсичный ник", "rarity": "common", "color": "#b6ff00"},
	"color:hot": {"name": "Горячий ник", "rarity": "rare", "color": "#ff4d9d"},
	"color:ice": {"name": "Ледяной ник", "rarity": "rare", "color": "#7df9ff"},
	"color:gold": {"name": "Золотой ник", "rarity": "epic", "color": "#ffd23f"},
	"color:magma": {"name": "Магмовый ник", "rarity": "legendary", "color": "#ff6a3d"},
	"boost:coins": {"name": "Монетный заряд", "rarity": "common", "text": "+25% монет на 3 забега"},
	"boost:pass": {"name": "Пивной заряд", "rarity": "rare", "text": "+50% очков пропуска на 3 забега"},
}


static func kind_of(key: String) -> String:
	return key.get_slice(":", 0)


static func is_cosmetic(key: String) -> bool:
	return KINDS.has(kind_of(key))


static func title_of(key: String) -> String:
	return str((CATALOG.get(key, {}) as Dictionary).get("name", key))


static func rarity_of(key: String) -> String:
	return str((CATALOG.get(key, {}) as Dictionary).get("rarity", "common"))


static func color_of(key: String) -> Color:
	return Color(str((CATALOG.get(key, {}) as Dictionary).get("color", "#ffffff")))


static func text_of(key: String) -> String:
	return str((CATALOG.get(key, {}) as Dictionary).get("text", ""))


static func type_name(key: String) -> String:
	match kind_of(key):
		"title":
			return "Титул"
		"frame":
			return "Рамка"
		"color":
			return "Цвет ника"
	return "Бустер"


static func owned() -> Array:
	if not SaveService.data.has("cosmetics"):
		SaveService.data["cosmetics"] = []
	return SaveService.data["cosmetics"]


static func owns(key: String) -> bool:
	return kind_of(key) != "boost" and owned().has(key)


static func give(key: String) -> void:
	match kind_of(key):
		"boost":
			var field := "boost_coins" if key == "boost:coins" else "boost_pass"
			SaveService.data[field] = int(SaveService.data.get(field, 0)) + BOOST_RUNS
		"title":
			if not owned().has(key):
				owned().append(key)
		"frame":
			if not owned().has(key):
				owned().append(key)
			SaveService.data["frame"] = key
		"color":
			if not owned().has(key):
				owned().append(key)
			SaveService.data["nick_color"] = key


static func frame_color() -> Color:
	var key := str(SaveService.data.get("frame", ""))
	return color_of(key) if owned().has(key) else Color.TRANSPARENT


## Нарисованная рамка аватара (Астра) для надетой рамки; null — нет рамки или арта.
static func frame_art() -> Texture2D:
	var key := str(SaveService.data.get("frame", ""))
	if not owned().has(key):
		return null
	var path := "res://assets/ui/frames/%s.png" % key.get_slice(":", 1)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func nick_color(fallback: Color) -> Color:
	var key := str(SaveService.data.get("nick_color", ""))
	return color_of(key) if owned().has(key) else fallback


## Расход бустеров после забега: возвращает множители {coins, pass}.
static func consume_boosts() -> Dictionary:
	var result := {"coins": 0.0, "pass": 0.0}
	for pair in [["boost_coins", "coins", BOOST_COINS_BONUS], ["boost_pass", "pass", BOOST_PASS_BONUS]]:
		var left := int(SaveService.data.get(pair[0], 0))
		if left > 0:
			result[pair[1]] = float(pair[2])
			SaveService.data[pair[0]] = left - 1
	return result
