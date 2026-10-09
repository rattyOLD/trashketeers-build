class_name RunStats
extends RefCounted
## Бонусы текущего забега. Живут только до конца боя; базовые конфиги не трогают.

const STAT_KEYS: Array[StringName] = [
	&"dodge_damage", &"dodge_blast", &"dodge_poison", &"dodge_shock", &"dodge_cooldown", &"dodge_distance",
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
	&"melee_wave",
	&"luck",
]

## Мгновенные эффекты: применяются игрой в момент выбора и не накапливаются.
const INSTANT_STATS: Array[StringName] = [&"heal_pct"]

## Есть ли в руках ствол ближнего боя (ставит игра): без него карточки «ближнего боя» не выпадают.
var close_context := false
var rail_context := false
## Убийства за забег: ближним оружием и всем остальным — по ним выдача карточек подстраивается под стиль.
var melee_kills := 0
var ranged_kills := 0
## Есть ли в слотах оружие ближнего боя (до первых убийств выдача ориентируется на него).
var melee_context := false
## Есть ли в слотах стрелковое оружие.
var ranged_context := true
## Фаза забега: 2 — после первого босса Выживания (открываются карточки «ФАЗА 2», враги злее).
var phase := 1
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
	&"vampirism": 0.005, &"kill_heal": 3.0, &"magnet_mult": 3.0, &"close_damage": 1.5, &"rail_rate": 1.0,
	&"poison_power": 2.0, &"status_power": 1.5, &"blast_power": 2.0, &"double_drop": 0.5, &"drone_count": 4.0, &"luck": 1.0,
}
const DASH_CAPS := {&"dodge_damage": 3.0, &"dodge_blast": 2.0, &"dodge_poison": 2.0, &"dodge_shock": 2.0, &"dodge_cooldown": 1.5, &"dodge_distance": 0.2}
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


## «Мощь» билда: урон × скорострельность × число снарядов × живучесть. 1.0 — голый герой.
## По ней выживание подтягивает врагов (см. WaveDirector.adaptive_factor).
func power() -> float:
	var dmg := 1.0 + get_stat(&"damage_mult")
	var rate := 1.0 + get_stat(&"fire_rate_mult")
	var shots := 1.0 + 0.25 * get_stat(&"extra_projectiles")
	var tough := (1.0 + get_stat(&"max_hp_add") / 200.0) / maxf(1.0 - get_stat(&"damage_resist"), 0.3)
	var crit := 1.0 + 0.5 * get_stat(&"crit_chance_add")
	return dmg * rate * shots * tough * crit


func get_stat(key: StringName) -> float:
	var raw: float = _values.get(key, 0.0)
	if DASH_CAPS.has(key):
		return clampf(raw, 0.0, float(DASH_CAPS[key]))
	return raw if uncapped else RunStats.capped(key, raw)


func get_stacks(upgrade_id: StringName) -> int:
	return _stacks.get(upgrade_id, 0)


func can_take(upgrade: UpgradeData) -> bool:
	return upgrade.max_stacks <= 0 or get_stacks(upgrade.id) < upgrade.max_stacks


func apply(upgrade: UpgradeData) -> void:
	if upgrade.category in ["dash", "dash_element"] and not is_available(upgrade):
		return
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
	if upgrade.category == "dash_element":
		for key in [&"dodge_blast", &"dodge_poison", &"dodge_shock"]:
			if key != upgrade.stat and get_stat(key) > 0.0:
				return false
	if upgrade.close_only and not close_context:
		return false
	if upgrade.rail_only and not rail_context:
		return false
	if upgrade.phase2 and phase < 2:
		return false
	if upgrade.style == "melee" and not melee_context:
		return false
	if upgrade.style == "ranged" and not ranged_context:
		return false
	for req in upgrade.requires:
		if not has_upgrade(req):
			return false
	return true


## Карточки, которые работают только на снаряды (у топора и катаны их эффект нулевой).
const PROJECTILE_ONLY: Array[StringName] = [&"extra_projectiles", &"extra_ricochets", &"piercing"]
## Карточки, что раскрывают ближний бой: урон, скорость ударов, криты, дальность взмаха, рывки, бег, лечение.
const MELEE_FRIENDLY: Array[StringName] = [&"damage_mult", &"fire_rate_mult", &"crit_chance_add", &"range_mult",
	&"move_speed_mult", &"dodge_damage", &"dodge_cooldown", &"dodge_distance", &"bleed_chance", &"vampirism", &"kill_heal"]


func note_kill(melee: bool) -> void:
	if melee:
		melee_kills += 1
	else:
		ranged_kills += 1


## Доля ближнего боя в стиле игрока 0..1: по убийствам (после 15), раньше — по слотам.
func melee_share() -> float:
	var total := melee_kills + ranged_kills
	if total < 15:
		return 0.6 if melee_context else 0.0
	return float(melee_kills) / float(total)


## Подкрутка под оружие: чем больше игрок рубит в ближнем бою, тем реже бесполезные «стволы и рикошеты»
## и тем чаще карточки, раскрывающие его оружие (по просьбе тестеров: «карточки под твоё оружие»).
func weapon_affinity(upgrade: UpgradeData) -> float:
	var share := melee_share()
	if share <= 0.0:
		return 1.0
	if PROJECTILE_ONLY.has(upgrade.stat):
		return maxf(1.0 - share, 0.04)
	if MELEE_FRIENDLY.has(upgrade.stat):
		return 1.0 + 1.3 * share
	return 1.0


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
	&"move_speed_mult": &"mobility",
	&"dodge_damage": &"mobility", &"dodge_blast": &"mobility", &"dodge_poison": &"mobility", &"dodge_shock": &"mobility", &"dodge_cooldown": &"mobility", &"dodge_distance": &"mobility",
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
	var filler: Array[UpgradeData] = []
	for upgrade in pool:
		if is_available(upgrade):
			if upgrade.category == "endless":
				filler.append(upgrade)
			else:
				candidates.append(upgrade)
	# «Хлам» (+2% навсегда) — только добивка, когда настоящих улучшений не хватает на выбор:
	# иначе мелкие карточки вылезали в каждом окне и мешали (жалоба тестеров).
	if candidates.size() < count:
		candidates.append_array(filler)
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
			w *= weapon_affinity(u)
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
