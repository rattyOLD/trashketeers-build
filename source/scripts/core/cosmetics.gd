class_name Cosmetics
extends RefCounted
## Косметика: титулы, рамки аватара, цвета ника, бустеры, скины рывка и трассеры пуль.
## Ключи "title:id", "frame:id", "color:id", "boost:id", "dash:id", "shot:id". Выпадают из сундуков
## (витрина) и за рекламу (меню «Скины»); рисунки Астры (бриф v28) подхватываются по именам, пока — цвета.

const KINDS: Array[String] = ["title", "frame", "color", "boost", "dash", "shot"]
## Скины рывка и трассеры: надеваются в меню «Скины», без них — стандартный голубой рывок и цвет оружия.
const WEARABLE: Array[String] = ["dash", "shot"]
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
	"dash:ember": {"name": "Рывок «Угли»", "rarity": "common", "color": "#ff8a3d", "bits": "#ffd27a"},
	"dash:toxic": {"name": "Рывок «Кислота»", "rarity": "common", "color": "#7dff3a", "bits": "#d6ff7a"},
	"dash:neon": {"name": "Рывок «Неон»", "rarity": "rare", "color": "#ff4dd2", "bits": "#6adcff"},
	"dash:void": {"name": "Рывок «Пустота»", "rarity": "epic", "color": "#7a3dff", "bits": "#e0d0ff"},
	"dash:gold": {"name": "Золотой рывок", "rarity": "legendary", "color": "#ffd23f", "bits": "#fff6c0"},
	"dash:cat": {"name": "Кошачий след", "rarity": "legendary", "color": "#ff8fc8", "bits": "#ffffff"},
	"shot:plasma": {"name": "Трассер «Плазма»", "rarity": "common", "color": "#6adcff"},
	"shot:candy": {"name": "Трассер «Карамель»", "rarity": "rare", "color": "#ff9ad5"},
	"shot:venom": {"name": "Трассер «Яд»", "rarity": "rare", "color": "#9dff4a"},
	"shot:inferno": {"name": "Трассер «Пекло»", "rarity": "epic", "color": "#ff5a1f"},
	"shot:rainbow": {"name": "Трассер «Радуга»", "rarity": "legendary", "color": "#ffffff", "rainbow": true},
	"shot:crown": {"name": "Трассер «Корона»", "rarity": "legendary", "color": "#ffd23f"},
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
		"dash":
			return "Скин рывка"
		"shot":
			return "Трассер"
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
		"dash", "shot":
			if not owned().has(key):
				owned().append(key)
			SaveService.data[kind_of(key) + "_skin"] = key


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


## Все ключи косметики вида kind (для меню «Скины» и витрины сундуков).
static func keys_of(kind: String, rarity: String = "") -> Array[String]:
	var out: Array[String] = []
	for key: String in CATALOG:
		if kind_of(key) == kind and (rarity.is_empty() or rarity_of(key) == rarity):
			out.append(key)
	return out


## Надетый скин вида "dash"/"shot" или "" — стандартный.
static func worn(kind: String) -> String:
	var key := str(SaveService.data.get(kind + "_skin", ""))
	return key if owned().has(key) else ""


static func wear(key: String, kind: String) -> void:
	SaveService.data[kind + "_skin"] = key
	SaveService.save_data()


## Цвет послеобраза рывка (fallback — стандартный голубой) и цвет искр.
static func dash_colors() -> Array[Color]:
	var key := worn("dash")
	if key.is_empty():
		return [Color(0.45, 0.85, 1.0), Color(0, 0, 0, 0)]
	var item: Dictionary = CATALOG[key]
	return [Color(str(item["color"])), Color(str(item.get("bits", item["color"])))]


## Цвет трассеров игрока: прозрачный — без скина; rainbow — переливается (BulletPool крутит оттенок).
static func shot_color() -> Color:
	var key := worn("shot")
	return Color(str(CATALOG[key]["color"])) if not key.is_empty() else Color(0, 0, 0, 0)


static func shot_rainbow() -> bool:
	var key := worn("shot")
	return not key.is_empty() and bool(CATALOG[key].get("rainbow", false))


## Случайный невыбитый скин рывка или трассер (за рекламу): обычный 70%, редкий 25%, эпик 5%.
static func roll_ad_skin() -> String:
	var r := randf()
	var rarity := "common" if r < 0.7 else ("rare" if r < 0.95 else "epic")
	for attempt in 3:
		var pool: Array[String] = []
		for kind in WEARABLE:
			for key in keys_of(kind, rarity):
				if not owned().has(key):
					pool.append(key)
		if not pool.is_empty():
			return pool.pick_random()
		rarity = "rare" if rarity == "common" else ("epic" if rarity == "rare" else "common")
	return ""


## Иконка Астры для витрины и меню (бриф v28: assets/ui/cosmetics/<вид>_<id>.png); null — рисуем кодом.
static func icon_of(key: String) -> Texture2D:
	var path := "res://assets/ui/cosmetics/%s_%s.png" % [kind_of(key), key.get_slice(":", 1)]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Рисунок части надетого скина (Астра, бриф v28): assets/cosmetics/<вид>/<id>/<part>.png; null — нет скина или файла.
static var _skin_tex := {}


static func skin_texture(kind: String, part: String) -> Texture2D:
	var key := worn(kind)
	if key.is_empty():
		return null
	var path := "res://assets/cosmetics/%s/%s/%s.png" % [kind, key.get_slice(":", 1), part]
	if not _skin_tex.has(path):
		_skin_tex[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _skin_tex[path]
