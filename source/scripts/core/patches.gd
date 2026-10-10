class_name Patches
extends RefCounted
## Нашивки на куртку (мета-прокачка в духе рун 20 Minutes Till Dawn, своими образами): покупаются и качаются
## за монеты (3 уровня), но в забег идут только надетые — слотов 4, открыты 2, ещё 2 покупаются.
## Выбор четырёх из двенадцати — это решение под стиль игры, а не «плюс ко всему». Часть нашивок — с ценой
## (Череп: урон за счёт здоровья). Действуют там же, где постоянная прокачка (Выживание).
## Арт Астры (бриф v32, ui/patches/<id>.png) подхватывается по имени; пока — вышитый кружок с буквой кодом.

const MAX_LEVEL := 3
const SLOTS := 4
const FREE_SLOTS := 2
## Нашивки дают большой буст — дорогое занятие на долгую игру.
const SLOT_PRICES := [0, 0, 25000, 60000]
## id: название, описание (%s — значение уровня), эффекты [[стат, за уровень]], цена 1-го уровня, цвет, значок.
const CATALOG := {
	"fist": {"title": "Кулак", "desc": "+%s%% урона", "fx": [[&"damage_mult", 0.08]], "price": 3000, "color": "#ff4d6d"},
	"bullet": {"title": "Пуля", "desc": "+%s%% скорострельности", "fx": [[&"fire_rate_mult", 0.06]], "price": 3000, "color": "#ffb02e"},
	"boot": {"title": "Сапог", "desc": "+%s%% скорости бега", "fx": [[&"move_speed_mult", 0.05]], "price": 2500, "color": "#6adcff"},
	"heart": {"title": "Сердце", "desc": "+%s к здоровью", "fx": [[&"max_hp_add", 15.0]], "price": 2500, "color": "#7dff9a"},
	"magnet": {"title": "Магнит", "desc": "+%s%% радиуса подбора", "fx": [[&"magnet_mult", 0.2]], "price": 2000, "color": "#b96bff"},
	"clover": {"title": "Клевер", "desc": "+%s%% Удачи", "fx": [[&"luck", 0.05]], "price": 3500, "color": "#7dff3a"},
	"rat": {"title": "Крыса", "desc": "+%s%% шанс двойной добычи", "fx": [[&"double_drop", 0.05]], "price": 3500, "color": "#c9c3d9"},
	"bolt": {"title": "Молния", "desc": "+%s%% шанс разряда", "fx": [[&"shock_chance", 0.06]], "price": 4000, "color": "#6adcff"},
	"gear": {"title": "Шестерня", "desc": "+%s%% силы эффектов", "fx": [[&"status_power", 0.1]], "price": 4000, "color": "#ff8a3d"},
	"mug": {"title": "Кружка", "desc": "+%s здоровья в секунду", "fx": [[&"regen", 0.4]], "price": 3000, "color": "#ffd23f"},
	"star": {"title": "Звезда Семёрки", "desc": "+%s%% шанса крита", "fx": [[&"crit_chance_add", 0.04]], "price": 5000, "color": "#ffd23f"},
	"skull": {"title": "Череп", "desc": "+%s%% урона, но -%s к здоровью", "fx": [[&"damage_mult", 0.2], [&"max_hp_add", -10.0]], "price": 5000, "color": "#ff3b3b"},
}
const ORDER := ["fist", "bullet", "boot", "heart", "magnet", "clover", "rat", "bolt", "gear", "mug", "star", "skull"]


static func level(id: String) -> int:
	return clampi(int((SaveService.data.get("patches", {}) as Dictionary).get(id, 0)), 0, MAX_LEVEL)


static func price(id: String) -> int:
	# Следующий уровень: 1×, 3×, 8× базовой цены (полная нашивка — 12× базовой).
	return int(CATALOG[id]["price"]) * [1, 3, 8][clampi(level(id), 0, MAX_LEVEL - 1)]


static func buy(id: String) -> bool:
	if not unlocked(id) or not CATALOG.has(id) or level(id) >= MAX_LEVEL or not SaveService.spend_coins(price(id)):
		return false
	var owned: Dictionary = SaveService.data.get("patches", {})
	owned[id] = level(id) + 1
	SaveService.data["patches"] = owned
	SaveService.save_data()
	return true


static func open_slots() -> int:
	return clampi(int(SaveService.data.get("patch_slots_open", FREE_SLOTS)), FREE_SLOTS, SLOTS)


static func slot_price() -> int:
	return SLOT_PRICES[open_slots()] if open_slots() < SLOTS else 0


static func buy_slot() -> bool:
	if open_slots() >= SLOTS or not SaveService.spend_coins(slot_price()):
		return false
	SaveService.data["patch_slots_open"] = open_slots() + 1
	SaveService.save_data()
	return true


static func worn() -> Array[String]:
	var out: Array[String] = []
	for id in SaveService.data.get("patch_worn", []):
		if CATALOG.has(str(id)) and level(str(id)) > 0 and not out.has(str(id)) and out.size() < open_slots():
			out.append(str(id))
	return out


static func is_worn(id: String) -> bool:
	return worn().has(id)


## Надеть/снять. Нет свободного слота — false.
static func toggle(id: String) -> bool:
	var list := worn()
	if list.has(id):
		list.erase(id)
	elif level(id) > 0 and list.size() < open_slots():
		list.append(id)
	else:
		return false
	SaveService.data["patch_worn"] = list
	SaveService.save_data()
	return true


## Текст эффекта на уровне lvl (для карточки и подсказки).
static func describe(id: String, lvl: int) -> String:
	var info: Dictionary = CATALOG[id]
	var values: Array = []
	for fx: Array in info["fx"]:
		var v: float = absf(float(fx[1])) * maxi(lvl, 1)
		values.append(str(int(round(v * 100.0))) if v < 1.0 and fx[0] != &"regen" else (str(snappedf(v, 0.1)) if fx[0] == &"regen" else str(int(v))))
	return str(info["desc"]) % values


## Бонусы надетых нашивок в статы забега.
static func apply(stats: RunStats) -> void:
	for id in worn():
		stats.equip_patch(id)
		for fx: Array in CATALOG[id]["fx"]:
			stats.add_flat(fx[0], float(fx[1]) * level(id))


static var _art: Dictionary = {}


static func art(id: String) -> Texture2D:
	if not _art.has(id):
		var path := "res://assets/ui/patches/%s.png" % id
		# draw_texture_rect хранит RID, а не ресурс: текстура должна жить до отрисовки кадра.
		_art[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _art[id] as Texture2D


## Постоянные покупки сохраняются; новые нашивки открываются заказами Нэлл.
const RUN_LEVELS := 5
const STARTER := ["fist", "bullet", "boot", "heart"]
const ORDER_UNLOCKS := ["magnet", "clover", "rat", "bolt", "gear", "mug", "star", "skull"]
const RUN_FX := {
	"fist": [[&"damage_mult", 0.06]],
	"bullet": [[&"fire_rate_mult", 0.04]],
	"boot": [[&"move_speed_mult", 0.035]],
	"heart": [[&"max_hp_add", 6.0]],
	"magnet": [[&"magnet_mult", 0.12]],
	"clover": [[&"luck", 0.025]],
	"rat": [[&"double_drop", 0.025]],
	"bolt": [[&"shock_chance", 0.03]],
	"gear": [[&"status_power", 0.06]],
	"mug": [[&"regen", 0.2]],
	"star": [[&"crit_chance_add", 0.02]],
	"skull": [[&"damage_mult", 0.12], [&"max_hp_add", -5.0]],
}
const SETS := [
	{"ids": ["fist", "bullet"], "title": "Залп", "desc": "+10% урона", "stat": &"damage_mult", "value": 0.1},
	{"ids": ["boot", "bolt"], "title": "Налёт", "desc": "+15% к восстановлению рывка", "stat": &"dodge_cooldown", "value": 0.15},
	{"ids": ["heart", "mug"], "title": "Живучесть", "desc": "+15 здоровья", "stat": &"max_hp_add", "value": 15.0},
	{"ids": ["magnet", "rat"], "title": "Сборщик", "desc": "+5% двойной добычи", "stat": &"double_drop", "value": 0.05},
]


static func unlocked(id: String) -> bool:
	if not CATALOG.has(id):
		return false
	if STARTER.has(id) or level(id) > 0:
		return true
	return ORDER_UNLOCKS.find(id) < clampi(int(SaveService.data.get("nell_orders_completed", 0)), 0, ORDER_UNLOCKS.size())


static func next_unlock() -> String:
	for id: String in ORDER_UNLOCKS:
		if not unlocked(id):
			return id
	return ""


static func cards() -> Array[UpgradeData]:
	var out: Array[UpgradeData] = []
	for id: String in ORDER:
		if not unlocked(id):
			continue
		var u := UpgradeData.new()
		u.id = StringName("patch_" + id)
		u.title = str(CATALOG[id]["title"])
		u.category = "patch"
		u.stat = RUN_FX[id][0][0]
		u.value = float(RUN_FX[id][0][1])
		u.max_stacks = RUN_LEVELS
		u.color = Color(str(CATALOG[id]["color"]))
		u.weight = 0.65
		u.rarity_rank = 0
		u.description = run_description(id)
		u.icon = art(id)
		out.append(u)
	return out


static func run_description(id: String) -> String:
	var values: Array = []
	for fx: Array in RUN_FX[id]:
		var v: float = absf(float(fx[1]))
		values.append(str(snappedf(v, 0.1)) if fx[0] == &"regen" else str(snappedf(v * (100.0 if v < 1.0 else 1.0), 0.1)))
	var text := str(CATALOG[id]["desc"]) % values
	for combo: Dictionary in SETS:
		if combo["ids"].has(id):
			var partner: String = combo["ids"][1] if combo["ids"][0] == id else combo["ids"][0]
			text += "\nС «%s»: %s." % [CATALOG[partner]["title"], combo["desc"]]
	return text
