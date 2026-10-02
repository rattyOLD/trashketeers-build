class_name RunStats
extends RefCounted
## Бонусы текущего забега. Живут только до конца боя; базовые конфиги не трогают.

const STAT_KEYS: Array[StringName] = [
	&"damage_mult",
	&"fire_rate_mult",
	&"extra_projectiles",
	&"extra_ricochets",
	&"piercing",
	&"range_mult",
	&"move_speed_mult",
	&"max_hp_add",
	&"magnet_mult",
	&"heal_pct",
	&"crit_chance_add",
	&"poison_chance",
	&"poison_power",
	&"explosive_chance",
	&"blast_power",
	&"shock_chance",
	&"shock_jumps",
	&"bleed_chance",
	&"slow_chance",
	&"vampirism",
	&"kill_heal",
	&"regen",
	&"damage_resist",
	&"shield_max",
	&"double_drop",
	&"status_power",
	&"drone_count",
	&"evo_toxic_burst",
	&"evo_vamp_poison",
	&"evo_static_freeze",
	&"dash_haste",
	&"dash_charges",
	&"dash_range",
	&"dash_damage",
	&"dash_poison",
	&"dash_fire",
	&"dash_blast",
	&"dash_refund",
	&"dash_boost",
	&"close_damage",
	&"close_reach",
	&"close_width",
	&"close_finisher",
	&"burn_chance",
	&"burn_vamp",
	&"rail_ramp",
	&"rail_beams",
	&"rail_overdrive",
	&"rail_boom",
	&"rail_rate",
]

## Мгновенные эффекты: применяются игрой в момент выбора и не накапливаются.
const INSTANT_STATS: Array[StringName] = [&"heal_pct"]

## Есть ли в руках ствол ближнего боя (ставит игра): без него карточки «ближнего боя» не выпадают.
var close_context := false
var rail_context := false
var _values: Dictionary = {}
var _stacks: Dictionary = {}


func _init() -> void:
	for key in STAT_KEYS:
		_values[key] = 0.0


## Потолки бонусов забега. Раньше карточки копились без предела: к 70-му уровню урон и скорострельность
## вырастали в сотни раз, и враги переставали быть угрозой. Теперь выше «колена» (70% потолка) бонус
## растёт в три раза медленнее, а сам потолок жёсткий. Тестерские флаги потолки снимают.
const CAPS := {
	&"damage_mult": 3.0, &"fire_rate_mult": 1.5, &"extra_projectiles": 7.0, &"extra_ricochets": 6.0, &"range_mult": 1.0,
	&"crit_chance_add": 0.6, &"move_speed_mult": 0.8, &"max_hp_add": 300.0, &"damage_resist": 0.5, &"regen": 4.0,
	&"vampirism": 0.005, &"kill_heal": 3.0, &"magnet_mult": 3.0, &"dash_haste": 1.0, &"close_damage": 1.5, &"rail_rate": 1.0,
	&"poison_power": 2.0, &"status_power": 1.5, &"blast_power": 2.0, &"double_drop": 0.5, &"drone_count": 4.0,
}
const KNEE := 0.7
const OVER_KNEE_SLOPE := 0.35
var uncapped := false


## Сырое значение после потолка (чистая функция, её проверяет тест).
static func capped(key: StringName, raw: float) -> float:
	if not CAPS.has(key) or raw <= 0.0:
		return raw
	var cap: float = CAPS[key]
	var knee := cap * KNEE
	if raw <= knee:
		return raw
	return minf(cap, knee + (raw - knee) * OVER_KNEE_SLOPE)


func get_stat(key: StringName) -> float:
	var raw: float = _values.get(key, 0.0)
	return raw if uncapped else RunStats.capped(key, raw)


func get_stacks(upgrade_id: StringName) -> int:
	return _stacks.get(upgrade_id, 0)


func can_take(upgrade: UpgradeData) -> bool:
	return upgrade.max_stacks <= 0 or get_stacks(upgrade.id) < upgrade.max_stacks


func apply(upgrade: UpgradeData) -> void:
	_stacks[upgrade.id] = get_stacks(upgrade.id) + 1
	if not INSTANT_STATS.has(upgrade.stat):
		_values[upgrade.stat] = get_stat(upgrade.stat) + upgrade.value


## Прямой бонус без карточки: постоянная прокачка («Сила») и временный «Адреналин».
func add_flat(key: StringName, value: float) -> void:
	_values[key] = get_stat(key) + value


func has_upgrade(upgrade_id: StringName) -> bool:
	return get_stacks(upgrade_id) > 0


func is_available(upgrade: UpgradeData) -> bool:
	if not can_take(upgrade):
		return false
	if upgrade.close_only and not close_context:
		return false
	if upgrade.rail_only and not rail_context:
		return false
	for req in upgrade.requires:
		if not has_upgrade(req):
			return false
	return true


## Три карточки: взвешенно по редкости, без повторов, с разными категориями, если хватает пула.
## luck (0..1) сдвигает шансы к редким; guarantee_rarity — минимум одна карточка не ниже указанной.
## Архетипы билда: чистый урон, стакер эффектов (яды, огонь, замедления, взрывы), мобильность.
## Остальное — «универсал» (здоровье, магнит, дроны): подходит всем билдам и не влияет на уклон.
const ARCHETYPE_BY_STAT := {
	&"damage_mult": &"dps", &"fire_rate_mult": &"dps", &"extra_projectiles": &"dps", &"crit_chance_add": &"dps",
	&"piercing": &"dps", &"extra_ricochets": &"dps", &"range_mult": &"dps", &"close_damage": &"dps", &"close_width": &"dps",
	&"close_reach": &"dps", &"rail_rate": &"dps", &"rail_ramp": &"dps", &"rail_overdrive": &"dps", &"rail_beams": &"dps",
	&"rail_boom": &"dps",
	&"poison_power": &"debuff", &"poison_chance": &"debuff", &"status_power": &"debuff", &"slow_chance": &"debuff",
	&"shock_chance": &"debuff", &"shock_jumps": &"debuff", &"explosive_chance": &"debuff", &"blast_power": &"debuff",
	&"burn_chance": &"debuff", &"burn_vamp": &"debuff", &"bleed_chance": &"debuff", &"vampirism": &"debuff", &"kill_heal": &"debuff",
	&"close_finisher": &"debuff", &"evo_vamp_poison": &"debuff", &"evo_toxic_burst": &"debuff", &"evo_static_freeze": &"debuff",
	&"dash_poison": &"debuff", &"dash_fire": &"debuff", &"dash_blast": &"debuff",
	&"move_speed_mult": &"mobility", &"dash_haste": &"mobility", &"dash_charges": &"mobility", &"dash_refund": &"mobility",
	&"dash_range": &"mobility", &"dash_damage": &"mobility", &"dash_boost": &"mobility",
}
## Насколько сильно выдача тянется к уже выбранному направлению (доля 1.0 = ×(1 + BIAS)).
const ARCHETYPE_BIAS := 1.8


static func archetype_of(upgrade: UpgradeData) -> StringName:
	return ARCHETYPE_BY_STAT.get(upgrade.stat, &"utility")


## Очки по архетипам из уже взятых улучшений (стаки), только «направляющие» архетипы.
func archetype_shares(pool: Array[UpgradeData]) -> Dictionary:
	var points := {}
	var total := 0.0
	for upgrade in pool:
		var stacks := get_stacks(upgrade.id)
		var kind := archetype_of(upgrade)
		if stacks <= 0 or kind == &"utility":
			continue
		points[kind] = float(points.get(kind, 0.0)) + stacks
		total += stacks
	if total <= 0.0:
		return {}
	for kind in points:
		points[kind] = float(points[kind]) / total
	return points


## avoid — id улучшений, только что показанных: при реролле их вес резко падает, чтобы выпало другое.
func roll_choices(pool: Array[UpgradeData], count: int, luck: float = 0.0, guarantee_rarity: int = 0, avoid: Array[StringName] = []) -> Array[UpgradeData]:
	var candidates: Array[UpgradeData] = []
	for upgrade in pool:
		if is_available(upgrade):
			candidates.append(upgrade)
	var shares := archetype_shares(pool)
	var picked: Array[UpgradeData] = []
	var categories := {}
	while picked.size() < count and not candidates.is_empty():
		var fresh: Array[UpgradeData] = []
		for u in candidates:
			if not categories.has(u.category):
				fresh.append(u)
		var source: Array[UpgradeData] = fresh if not fresh.is_empty() and picked.size() < 3 else candidates
		var need_rarity := guarantee_rarity > 0 and picked.size() == count - 1 and not _has_rarity(picked, guarantee_rarity)
		var total := 0.0
		var weights: Array[float] = []
		for u in source:
			var w := u.pick_weight(luck)
			if not shares.is_empty():
				w *= 1.0 + ARCHETYPE_BIAS * float(shares.get(archetype_of(u), 0.0))
			if avoid.has(u.id):
				w *= 0.08
			if need_rarity and u.rarity_rank < guarantee_rarity:
				w = 0.0
			weights.append(w)
			total += w
		if total <= 0.0:
			for i in weights.size():
				weights[i] = 1.0
			total = float(weights.size())
		var roll := randf() * total
		var chosen := source[source.size() - 1]
		for i in source.size():
			roll -= weights[i]
			if roll <= 0.0:
				chosen = source[i]
				break
		picked.append(chosen)
		categories[chosen.category] = true
		candidates.erase(chosen)
	return picked


func _has_rarity(list: Array[UpgradeData], rank: int) -> bool:
	for u in list:
		if u.rarity_rank >= rank:
			return true
	return false
