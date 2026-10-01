class_name RunMods
extends RefCounted
## Модификаторы выживания: меняют числа и флаги, взамен фиксированный множитель монет.

const DEBT_DAMAGE := 0.2
const NONE := &""
const RANDOM := &"random"
const BLAST_RADIUS := 78.0
const BLAST_DAMAGE_BASE := 5.0
const BLAST_DAMAGE_PER_WAVE := 0.6
const ENEMY_SPEED := 2.0
const SHOTGUN_IDS: Array[StringName] = [&"trash_shotgun_v1", &"double_v1"]
const MODS: Array[Dictionary] = [
	{"id": &"no_dash", "title": "Без рывка", "desc": "Рывок отключён", "mult": 1.3},
	{"id": &"fast_enemies", "title": "Двойная скорость врагов", "desc": "Враги бегут вдвое быстрее", "mult": 1.3},
	{"id": &"blast", "title": "Враги взрываются", "desc": "Каждая смерть бьёт по площади", "mult": 1.3},
	{"id": &"shotguns", "title": "Только дробовики", "desc": "Другие стволы не выпадают", "mult": 1.3},
	{"id": &"debt", "title": "Долг коллекторам", "desc": "+20% урона, но 30% монет забега уходит коллекторам", "mult": 0.7},
]

static var active: StringName = NONE


static func order() -> Array[StringName]:
	var list: Array[StringName] = [NONE, RANDOM]
	for mod in MODS:
		list.append(mod["id"])
	return list


static func chosen() -> StringName:
	var id := StringName(str(SaveService.data.get("run_mod", "")))
	return id if order().has(id) else NONE


static func cycle() -> StringName:
	var list := order()
	var next := list[(list.find(chosen()) + 1) % list.size()]
	SaveService.set_value("run_mod", String(next))
	return next


static func resolve() -> void:
	var id := chosen()
	if id == RANDOM:
		id = MODS[randi() % MODS.size()]["id"]
	active = id


static func clear() -> void:
	active = NONE


static func info(id: StringName) -> Dictionary:
	for mod in MODS:
		if mod["id"] == id:
			return mod
	return {}


static func button_text(id: StringName) -> String:
	if id == NONE:
		return "МОДИФИКАТОР: нет"
	if id == RANDOM:
		return "МОДИФИКАТОР: случайный"
	return "%s  ×%.1f" % [str(info(id)["title"]).to_upper(), mult_of(id)]


static func mult_of(id: StringName) -> float:
	var mod := info(id)
	return float(mod.get("mult", 1.0)) if not mod.is_empty() else 1.0


static func has(id: StringName) -> bool:
	return active == id


static func reward(coins: int) -> int:
	return int(round(coins * mult_of(active)))


static func only_shotguns(weapon: WeaponData) -> bool:
	return active != &"shotguns" or SHOTGUN_IDS.has(weapon.id)
