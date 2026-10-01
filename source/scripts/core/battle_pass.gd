class_name BattlePass
extends RefCounted
## Боевой пропуск: 30 уровней за сезон в 30 дней. Очки дают забеги и ежедневный подарок,
## бесплатная ветка награждает монетами, платная - монетами, неонитом и двумя нарядами.

const TIERS := 30
const POINTS_PER_TIER := 100
const SEASON_DAYS := 30
const PRICE := 2.99
const FIRST_PRICE := 1.99
const DAILY_POINTS := 25
const MAX_RUN_POINTS := 80
const QUEST_POINTS := 20
const SKIP_COST := 40
const FREE_ITEMS := {10: "weapon:capgun_v1", 20: "skin:neon", 25: "weapon:harpoon_v1"}
const PREMIUM_ITEMS := {1: "weapon:railgun_v1", 6: "weapon:coil_v1", 12: "weapon:sniper_v1", 18: "skin:gold", 24: "weapon:casino_v1", 30: "skin:star"}
const BONUS_POINTS := 400
const BONUS_GEM_CHANCE_MIN := 0.06
const BONUS_GEM_CHANCE_MAX := 0.22
const BONUS_XP_CHANCE := 0.3


static func _state() -> Dictionary:
	var bp: Dictionary = SaveService.data["bp"]
	var today := SaveService.today()
	if bp.is_empty() or today >= int(bp.get("start", 0)) + SEASON_DAYS:
		bp = {"season": int(bp.get("season", 0)) + 1, "start": today, "points": 0, "claimed": [], "premium": false}
		SaveService.data["bp"] = bp
	return bp


static func season() -> int:
	return int(_state()["season"])


static func days_left() -> int:
	return maxi(int(_state()["start"]) + SEASON_DAYS - SaveService.today(), 0)


static func is_premium() -> bool:
	return bool(_state()["premium"])


static func price() -> float:
	return PRICE if bool(SaveService.data["bp_ever"]) else FIRST_PRICE


static func points() -> int:
	return int(_state()["points"])


static func tier() -> int:
	return mini(points() / POINTS_PER_TIER, TIERS)


static func tier_progress() -> float:
	if tier() >= TIERS:
		return bonus_progress()
	return float(points() % POINTS_PER_TIER) / POINTS_PER_TIER


static func add_points(amount: int) -> void:
	var bp := _state()
	var gained := int(round(amount * (1.0 + Premium.pass_bonus())))
	bp["points"] = int(bp["points"]) + gained


static func run_points(wave: int) -> int:
	return clampi(8 + wave * 3, 8, MAX_RUN_POINTS)


## {coins, gems, item} для клетки; track - "free" или "prem".
static func reward(track: String, level: int) -> Dictionary:
	if track == "free":
		return {"coins": 60 + 10 * level, "gems": {5: 2, 10: 3, 15: 3, 20: 4, 25: 4, 30: 6}.get(level, 0), "item": str(FREE_ITEMS.get(level, ""))}
	var gems := 0
	if level % 5 == 0:
		gems = 20 if level == TIERS else 10
	elif level % 3 == 0:
		gems = 3
	return {"coins": 120 + 25 * level, "gems": gems, "item": str(PREMIUM_ITEMS.get(level, ""))}


static func _key(track: String, level: int) -> String:
	return "%s%d" % [track.left(1), level]


static func is_claimed(track: String, level: int) -> bool:
	return (_state()["claimed"] as Array).has(_key(track, level))


static func can_claim(track: String, level: int) -> bool:
	if level > tier() or is_claimed(track, level):
		return false
	return track == "free" or is_premium()


static func has_unclaimed() -> bool:
	if bonus_ready() > 0:
		return true
	for level in range(1, tier() + 1):
		if can_claim("free", level) or can_claim("prem", level):
			return true
	return false


static func claim(track: String, level: int) -> bool:
	if not can_claim(track, level):
		return false
	var prize := reward(track, level)
	var coins := int(prize["coins"])
	var item := str(prize["item"])
	if not item.is_empty():
		var rarity := Economy.item_rarity(item)
		var repeat_ok := Economy.item_kind(item) == "weapon" and rarity != "legendary"
		if Economy.owns_item(item) and not repeat_ok:
			coins += int(Economy.DUPLICATE_COINS.get(rarity, 1000))
		else:
			Economy.give_item(item)
	SaveService.add_coins_silent(coins)
	SaveService.add_gems(int(prize["gems"]), false)
	(_state()["claimed"] as Array).append(_key(track, level))
	SaveService.save_data()
	return true


## Забирает все доступные награды уровней и бонусы после 30-го. Возвращает {count, coins, gems, xp}.
static func claim_all() -> Dictionary:
	var total := {"count": 0, "coins": 0, "gems": 0, "xp": 0}
	for level in range(1, tier() + 1):
		for track in ["free", "prem"]:
			var prize := reward(track, level)
			if claim(track, level):
				total["count"] += 1
				total["coins"] += int(prize["coins"])
				total["gems"] += int(prize["gems"])
	while bonus_ready() > 0:
		var bonus := claim_bonus()
		total["count"] += 1
		match str(bonus["kind"]):
			"gems":
				total["gems"] += int(bonus["amount"])
			"xp":
				total["xp"] += int(bonus["amount"])
			_:
				total["coins"] += int(bonus["amount"])
	return total


## Ближайший приз-предмет впереди: {level, track, item} или пустой словарь.
static func next_milestone() -> Dictionary:
	for level in range(tier() + 1, TIERS + 1):
		for track in ["prem", "free"]:
			var item := str(reward(track, level)["item"])
			if not item.is_empty():
				return {"level": level, "track": track, "item": item}
	return {}


static func can_skip() -> bool:
	return tier() < TIERS and SaveService.get_gems() >= SKIP_COST


## Пропуск уровня за неонит: очки поднимаются до начала следующего уровня.
static func skip_tier() -> bool:
	if not can_skip() or not SaveService.spend_gems(SKIP_COST, false):
		return false
	_state()["points"] = (tier() + 1) * POINTS_PER_TIER
	SaveService.save_data()
	return true


static func buy_premium() -> void:
	_state()["premium"] = true
	SaveService.data["bp_ever"] = true
	SaveService.save_data()


## После 30 уровня общая для обеих веток награда за каждые BONUS_POINTS очков: монеты, опыт или неонит.
static func bonus_points_into() -> int:
	return maxi(points() - TIERS * POINTS_PER_TIER, 0)


static func bonus_progress() -> float:
	return float(bonus_points_into() % BONUS_POINTS) / BONUS_POINTS


static func bonus_ready() -> int:
	return maxi(bonus_points_into() / BONUS_POINTS - int(_state().get("bonus_claimed", 0)), 0)


## Шанс неонита каждый раз новый, чтобы его нельзя было выфармливать по формуле.
static func claim_bonus() -> Dictionary:
	if bonus_ready() <= 0:
		return {}
	var bp := _state()
	bp["bonus_claimed"] = int(bp.get("bonus_claimed", 0)) + 1
	var roll := randf()
	var gem_chance := randf_range(BONUS_GEM_CHANCE_MIN, BONUS_GEM_CHANCE_MAX)
	var prize: Dictionary
	if roll < gem_chance:
		prize = {"kind": "gems", "amount": randi_range(3, 8)}
		SaveService.add_gems(int(prize["amount"]), false)
	elif roll < gem_chance + BONUS_XP_CHANCE:
		prize = {"kind": "xp", "amount": randi_range(120, 400)}
		SaveService.add_account_xp(int(prize["amount"]))
	else:
		prize = {"kind": "coins", "amount": randi_range(250, 900) / 10 * 10}
		SaveService.add_coins_silent(int(prize["amount"]))
	SaveService.save_data()
	return prize


## Задания сезона: прогресс считается от снимка статистики на момент первого открытия сезона.
const QUESTS := [
	{"id": "runs", "title": "Сыграй 10 забегов", "stat": "runs", "goal": 10, "points": 60},
	{"id": "bosses", "title": "Победи 3 боссов", "stat": "boss_kills", "goal": 3, "points": 80},
	{"id": "kills", "title": "Убей 500 врагов", "stat": "kills", "goal": 500, "points": 60},
]


static func _quest_base(quest: Dictionary) -> int:
	var bp := _state()
	if not bp.has("q0"):
		bp["q0"] = {}
	var base: Dictionary = bp["q0"]
	var stat := str(quest["stat"])
	if not base.has(stat):
		base[stat] = SaveService.get_stat(stat)
		SaveService.save_data()
	return int(base[stat])


static func quest_progress(quest: Dictionary) -> int:
	return clampi(SaveService.get_stat(str(quest["stat"])) - _quest_base(quest), 0, int(quest["goal"]))


static func quest_claimed(quest: Dictionary) -> bool:
	return (_state().get("qclaimed", []) as Array).has(str(quest["id"]))


static func quest_ready(quest: Dictionary) -> bool:
	return not quest_claimed(quest) and quest_progress(quest) >= int(quest["goal"])


static func claim_quest(quest: Dictionary) -> bool:
	if not quest_ready(quest):
		return false
	var bp := _state()
	if not bp.has("qclaimed"):
		bp["qclaimed"] = []
	(bp["qclaimed"] as Array).append(str(quest["id"]))
	add_points(int(quest["points"]))
	SaveService.save_data()
	return true
