class_name UpgradeData
extends RefCounted
## Карточка прокачки «1 из 3». stat — ключ из RunStats.STAT_KEYS.
## max_stacks = 0 означает «без лимита» (например, лечение).

const DEFAULTS := {
	"title": "",
	"description": "",
	"stat": "",
	"value": 0.0,
	"max_stacks": 1,
	"color": "#7CFFCB",
	"category": "weapon",
	"rarity": "common",
	"requires": [],
	"weight": 1.0,
	"close_only": false,
	"rail_only": false,
}

const RARITY_RANK := {"common": 0, "rare": 1, "epic": 2}
const RARITY_WEIGHT := [60.0, 28.0, 9.0]
const RARITY_COLORS := [Color("#b9c2d9"), Color("#4dc3ff"), Color("#d05cff")]
const RARITY_TITLES := ["ОБЫЧНОЕ", "РЕДКОЕ", "ЭПИЧЕСКОЕ"]
const CATEGORY_TITLES := {"weapon": "ОРУЖИЕ", "hero": "ПЕРСОНАЖ", "utility": "УТИЛИТА", "evolution": "ЭВОЛЮЦИЯ", "close": "БЛИЖНИЙ БОЙ", "endless": "ХЛАМ", "rail": "РЕЛЬСОТРОН", "dash": "РЫВОК", "dash_element": "СТИХИЯ РЫВКА"}

var id: StringName
var title: String
var description: String
var stat: StringName
var value: float
var max_stacks: int
var color: Color
var category: String
var rarity_rank: int
var requires: Array[StringName] = []
var weight: float
var close_only: bool
var rail_only: bool


static func from_dict(raw: Dictionary) -> UpgradeData:
	var raw_id := ConfigLoader.require_id(raw, "upgrade_id", "UpgradeData")
	if raw_id.is_empty():
		return null

	var label := "UpgradeData[%s]" % raw_id
	var d := ConfigLoader.sanitize(raw, DEFAULTS, label, PackedStringArray(["upgrade_id"]))
	var stat_name := StringName(d["stat"])
	if not RunStats.STAT_KEYS.has(stat_name):
		push_error("%s: неизвестный stat '%s', запись пропущена" % [label, stat_name])
		return null

	var u := UpgradeData.new()
	u.id = StringName(raw_id)
	u.title = d["title"] if not String(d["title"]).is_empty() else raw_id
	u.description = d["description"]
	u.stat = stat_name
	u.value = d["value"]
	u.max_stacks = maxi(int(d["max_stacks"]), 0)
	u.color = ConfigLoader.parse_color(d["color"], label)
	u.category = String(d["category"])
	u.rarity_rank = int(RARITY_RANK.get(String(d["rarity"]), 0))
	u.weight = maxf(float(d["weight"]), 0.0)
	u.close_only = bool(d["close_only"])
	u.rail_only = bool(d["rail_only"])
	for req in d["requires"]:
		u.requires.append(StringName(req))
	return u


func rarity_color() -> Color:
	return RARITY_COLORS[rarity_rank]


func rarity_title() -> String:
	return RARITY_TITLES[rarity_rank]


func category_title() -> String:
	return CATEGORY_TITLES.get(category, "")


## Эволюции всегда выпадают охотнее сразу после открытия: их вес не зависит от редкости.
func pick_weight(luck: float) -> float:
	if category == "evolution":
		return 40.0 * weight
	var base: float = RARITY_WEIGHT[rarity_rank]
	if rarity_rank > 0:
		base *= 1.0 + luck * 2.0
	return base * weight
