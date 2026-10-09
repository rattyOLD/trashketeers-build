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
const SLOT_PRICES := [0, 0, 5000, 12000]
## id: название, описание (%s — значение уровня), эффекты [[стат, за уровень]], цена 1-го уровня, цвет, значок.
const CATALOG := {
	"fist": {"title": "Кулак", "desc": "+%s%% урона", "fx": [[&"damage_mult", 0.08]], "price": 500, "color": "#ff4d6d"},
	"bullet": {"title": "Пуля", "desc": "+%s%% скорострельности", "fx": [[&"fire_rate_mult", 0.06]], "price": 500, "color": "#ffb02e"},
	"boot": {"title": "Сапог", "desc": "+%s%% скорости бега", "fx": [[&"move_speed_mult", 0.05]], "price": 400, "color": "#6adcff"},
	"heart": {"title": "Сердце", "desc": "+%s к здоровью", "fx": [[&"max_hp_add", 15.0]], "price": 400, "color": "#7dff9a"},
	"magnet": {"title": "Магнит", "desc": "+%s%% радиуса подбора", "fx": [[&"magnet_mult", 0.2]], "price": 300, "color": "#b96bff"},
	"clover": {"title": "Клевер", "desc": "+%s%% Удачи", "fx": [[&"luck", 0.05]], "price": 600, "color": "#7dff3a"},
	"rat": {"title": "Крыса", "desc": "+%s%% шанс двойной добычи", "fx": [[&"double_drop", 0.05]], "price": 600, "color": "#c9c3d9"},
	"bolt": {"title": "Молния", "desc": "+%s%% шанс разряда", "fx": [[&"shock_chance", 0.06]], "price": 700, "color": "#6adcff"},
	"gear": {"title": "Шестерня", "desc": "+%s%% силы эффектов", "fx": [[&"status_power", 0.1]], "price": 700, "color": "#ff8a3d"},
	"mug": {"title": "Кружка", "desc": "+%s здоровья в секунду", "fx": [[&"regen", 0.4]], "price": 500, "color": "#ffd23f"},
	"star": {"title": "Звезда Семёрки", "desc": "+%s%% шанса крита", "fx": [[&"crit_chance_add", 0.04]], "price": 900, "color": "#ffd23f"},
	"skull": {"title": "Череп", "desc": "+%s%% урона, но -%s к здоровью", "fx": [[&"damage_mult", 0.2], [&"max_hp_add", -10.0]], "price": 900, "color": "#ff3b3b"},
}
const ORDER := ["fist", "bullet", "boot", "heart", "magnet", "clover", "rat", "bolt", "gear", "mug", "star", "skull"]


static func level(id: String) -> int:
	return clampi(int((SaveService.data.get("patches", {}) as Dictionary).get(id, 0)), 0, MAX_LEVEL)


static func price(id: String) -> int:
	# Следующий уровень: 1×, 3×, 7× базовой цены.
	return int(CATALOG[id]["price"]) * [1, 3, 7][clampi(level(id), 0, MAX_LEVEL - 1)]


static func buy(id: String) -> bool:
	if not CATALOG.has(id) or level(id) >= MAX_LEVEL or not SaveService.spend_coins(price(id)):
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
		if CATALOG.has(str(id)) and level(str(id)) > 0 and out.size() < open_slots():
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
		for fx: Array in CATALOG[id]["fx"]:
			stats.add_flat(fx[0], float(fx[1]) * level(id))


static func art(id: String) -> Texture2D:
	var path := "res://assets/ui/patches/%s.png" % id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
