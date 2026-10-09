class_name Economy
extends RefCounted
## Экономика: сундуки, чертежи, pity, реклама, цены магазина, награды волн и боссов.
## Две валюты: монеты (фарм в забегах) и неонит (редкая: реклама 2 раза в день, боссы, ачивки,
## ежедневная серия). Предметы — стволы, герои, наряды — приходят тремя путями: сундук, покупка
## (стволы и герои — за монеты, дорогое — за неонит) и чертежи (10 штук → предмет).
## Состояние (счётчики, осколки, лимиты рекламы) хранится в SaveService.data, здесь — правила.
##
## Ориентиры (подробно — docs/economy.md): средний забег 5–8 минут ≈ 150–300 монет, полная
## глава с боссом ≈ 500–700; обычный сундук — 1–2 забега, редкий — ~4, эпический — ~12 или
## 45 неонита (неделя бесплатного неонита). Эпик-ствол в магазине — 2–3 дня игры.

const SHARDS_PER_ITEM := 10
const PITY_STEP := 10
const PITY_BONUS := 0.04
const PITY_GUARANTEE := 50
const AD_COINS := 80
const AD_COINS_LIMIT := 5
const AD_GEMS_LIMIT := 2
## Неонит за рекламу: [вес, количество] — чаще 1–2, изредка 5.
const AD_GEMS_TABLE := [[35.0, 1], [30.0, 2], [20.0, 3], [10.0, 4], [5.0, 5]]
const REVIVE_COSTS := [8, 15, 30]
const RARITY_ORDER := ["common", "rare", "epic", "legendary"]
## Монетами покупаются только common/rare/epic; легендарные — исключительно за неонит.
const SHOP_PRICES := {"common": 650, "rare": 1850, "epic": 5000}
## Каждая уже купленная копия удорожает следующую: цена × (1 + STEP × покупок), не больше CAP покупок.
const SHOP_REPEAT_STEP := 0.3
const SHOP_REPEAT_CAP := 8
## Шанс, что подобранный в забеге ствол останется в арсенале навсегда (иначе он «в аренде» на забег).
const KEEP_CHANCE := {"common": 0.5, "rare": 0.3, "epic": 0.12, "legendary": 0.0}
const BOSS_LEGENDARY_CHANCE := 0.15
## Неонит вместо монет для эпических и легендарных стволов (для тех, кто не хочет ждать).
const SHOP_GEM_PRICES := {"epic": 90, "legendary": 220}
## Донатные флагманы дороже обычных легендарок.
const SHOP_GEM_OVERRIDE := {"railgun_v1": 480}
const DUPLICATE_COINS := {"common": 150, "rare": 400, "epic": 1000, "legendary": 2500}
const HERO_RARITY := {"maloy": "rare", "red_panda": "rare", "snow": "rare", "night": "rare", "neon_hopper": "epic", "fluffy_chemist": "epic", "pigeon_mafioso": "epic", "sniper_f": "epic", "medic_f": "epic"}
const SKIN_RARITY := {"punk": "common", "bandit": "common", "neon": "rare", "gold": "epic", "star": "legendary"}
const FIRST_BOSS_GEMS := 15

const CHESTS := {
	"common": {
		"title": "Обычный сундук", "color": Color("#7fd0ff"), "coins": 200, "gems": 0,
		"rolls": 3, "item_chance": 0.06,
		"weapon_rarities": ["common", "common", "rare"], "people": ["skin_common", "skin_rare"],
		"fillers": [[55.0, "coins", 60, 120], [28.0, "xp", 30, 60], [14.0, "shard", 1, 1], [3.0, "gems", 1, 1]],
	},
	"rare": {
		"title": "Редкий сундук", "color": Color("#b36bff"), "coins": 600, "gems": 0,
		"rolls": 4, "item_chance": 0.14,
		"weapon_rarities": ["rare", "rare", "epic"], "people": ["hero_rare", "skin_rare"],
		"fillers": [[45.0, "coins", 150, 280], [25.0, "xp", 80, 140], [22.0, "shard", 1, 2], [8.0, "gems", 1, 3]],
	},
	"epic": {
		"title": "Эпический сундук", "color": Color("#ffb62e"), "coins": 2200, "gems": 35,
		"rolls": 5, "item_chance": 0.3,
		"weapon_rarities": ["epic", "epic", "legendary"], "people": ["hero_epic", "hero_legendary"],
		"fillers": [[35.0, "coins", 350, 650], [20.0, "xp", 180, 300], [30.0, "shard", 2, 3], [15.0, "gems", 2, 5]],
	},
}
const CHEST_ORDER := ["common", "rare", "epic"]
const COSMETIC_RARITIES := {"common": ["common", "common", "rare"], "rare": ["rare", "rare", "epic"], "epic": ["epic", "legendary"]}
## «Сундук дня»: один из трёх со скидкой (меняется каждые сутки), и бесплатный за рекламу раз в несколько часов.
const DAILY_DISCOUNT := 0.3
const AD_CHEST_COOLDOWN := 4 * 3600
const AD_CHEST_TIER := "common"


# --- Форматирование ---------------------------------------------------------------------------------

static func format_gems(amount: int) -> String:
	return "%d %s" % [amount, SaveService.plural(amount, "неонит", "неонита", "неонита")]


static func rarity_color(rarity: String) -> Color:
	return WeaponData.RARITY_COLORS.get(rarity, Color.WHITE)


static func rarity_name(rarity: String) -> String:
	return WeaponData.RARITY_NAMES.get(rarity, rarity)


# --- Каталог предметов (ключи "weapon:id" / "hero:id" / "skin:id") -------------------------------------

static func item_kind(key: String) -> String:
	return key.get_slice(":", 0)


static func item_id(key: String) -> String:
	return key.get_slice(":", 1)


static func item_rarity(key: String) -> String:
	if Cosmetics.is_cosmetic(key):
		return Cosmetics.rarity_of(key)
	match item_kind(key):
		"weapon":
			var w := WeaponDB.get_weapon(StringName(item_id(key)))
			return w.rarity if w != null else "common"
		"hero":
			return HERO_RARITY.get(item_id(key), "rare")
		"skin":
			return SKIN_RARITY.get(item_id(key), "common")
	return "common"


static func item_title(key: String) -> String:
	if Cosmetics.is_cosmetic(key):
		return Cosmetics.title_of(key)
	match item_kind(key):
		"weapon":
			var w := WeaponDB.get_weapon(StringName(item_id(key)))
			return w.display_name if w != null else item_id(key)
		"hero":
			return str(CharacterDB.get_character(item_id(key)).get("title", item_id(key)))
		"skin":
			return str((SaveService.SKINS.get(item_id(key), {}) as Dictionary).get("title", item_id(key)))
	return key


static func item_type_name(key: String) -> String:
	if Cosmetics.is_cosmetic(key):
		return Cosmetics.type_name(key)
	match item_kind(key):
		"weapon":
			return "Ствол"
		"hero":
			return "Герой"
		"skin":
			return "Наряд"
	return "Предмет"


static func blueprint_title(key: String) -> String:
	return "%s «%s»" % [item_type_name(key).to_lower(), item_title(key)]


static func owns_item(key: String) -> bool:
	if Cosmetics.is_cosmetic(key):
		return Cosmetics.owns(key)
	match item_kind(key):
		"weapon":
			return SaveService.owns_weapon(StringName(item_id(key)))
		"hero":
			return SaveService.owns_character(item_id(key))
		"skin":
			return SaveService.owns_skin(item_id(key))
	return false


## Ценный предмет для pity: ствол эпик+ или любой герой.
static func is_valuable(key: String) -> bool:
	if item_kind(key) == "hero":
		return true
	return item_kind(key) == "weapon" and RARITY_ORDER.find(item_rarity(key)) >= 2


static func weapons_of(rarity: String) -> Array[String]:
	var out: Array[String] = []
	for w in WeaponDB.get_player_weapons():
		if w.rarity == rarity and w.loot_weight > 0.0 and String(w.id) != SaveService.START_WEAPON:
			out.append("weapon:" + String(w.id))
	out.sort()
	return out


static func heroes_of(rarity: String) -> Array[String]:
	var out: Array[String] = []
	for id in HERO_RARITY:
		if HERO_RARITY[id] == rarity and CharacterDB.has_character(id):
			out.append("hero:" + id)
	return out


static func skins_of(rarity: String) -> Array[String]:
	var out: Array[String] = []
	for id in SKIN_RARITY:
		if SKIN_RARITY[id] == rarity:
			out.append("skin:" + id)
	return out


## Витрина сундука: 2 ствола + 2 героя/наряда. Обновляется раз в сутки (сид — номер дня).
static func featured(chest_id: String) -> Array[String]:
	var chest: Dictionary = CHESTS[chest_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [chest_id, SaveService.today()])
	var out: Array[String] = []
	var rarities: Array = chest["weapon_rarities"]
	var used := {}
	for i in 2:
		for attempt in 6:
			var pool := weapons_of(str(rarities[rng.randi() % rarities.size()]))
			if pool.is_empty():
				continue
			var key: String = pool[rng.randi() % pool.size()]
			if not used.has(key):
				used[key] = true
				out.append(key)
				break
	for slot in chest["people"]:
		var parts: PackedStringArray = str(slot).split("_")
		var pool: Array[String] = heroes_of(parts[1]) if parts[0] == "hero" else skins_of(parts[1])
		if pool.is_empty():
			pool = skins_of(parts[1])
		if pool.is_empty():
			continue
		var key: String = pool[rng.randi() % pool.size()]
		if used.has(key):
			var alt := skins_of("epic" if parts[1] != "common" else "rare")
			if not alt.is_empty():
				key = alt[rng.randi() % alt.size()]
		used[key] = true
		out.append(key)
	# Косметика: один скин рывка или трассер на витрине (редкость по сундуку, невыбитый — в приоритете).
	var cosm_rarities: Array = COSMETIC_RARITIES.get(chest_id, ["common"])
	var cosm: Array[String] = []
	for kind in Cosmetics.WEARABLE:
		cosm.append_array(Cosmetics.keys_of(kind, str(cosm_rarities[rng.randi() % cosm_rarities.size()])))
	var fresh := cosm.filter(func(k: String) -> bool: return not Cosmetics.owns(k))
	if not fresh.is_empty():
		cosm.assign(fresh)
	if not cosm.is_empty():
		out.append(cosm[rng.randi() % cosm.size()])
	return out


# --- Сундуки ---------------------------------------------------------------------------------------

## Шансы витрины для экрана «Шансы»: героев и наряды берёт 40% попаданий предмета, пока они есть невыбитыми.
static func shelf_odds(chest_id: String) -> Array[Dictionary]:
	var shelf := featured(chest_id)
	var weapons := shelf.filter(func(k: String) -> bool: return item_kind(k) == "weapon")
	var people := shelf.filter(func(k: String) -> bool: return item_kind(k) != "weapon" and not owns_item(k))
	var base := item_chance(chest_id)
	var people_share := 0.0
	if not people.is_empty():
		people_share = 1.0 if weapons.is_empty() else 0.4
	var out: Array[Dictionary] = []
	for key in people:
		out.append({"key": key, "chance": base * people_share / people.size()})
	for key in weapons:
		out.append({"key": key, "chance": base * (1.0 - people_share) / weapons.size()})
	return out


## Остальные награды: [{title, chance}] по весам таблицы.
static func filler_odds(chest_id: String) -> Array[Dictionary]:
	var titles := {"coins": "Монеты", "xp": "Опыт аккаунта", "shard": "Чертежи", "gems": "Неонит"}
	var table: Array = CHESTS[chest_id]["fillers"]
	var total := 0.0
	for row in table:
		total += float(row[0])
	var out: Array[Dictionary] = []
	for row in table:
		var range_text := str(row[2]) if int(row[2]) == int(row[3]) else "%d-%d" % [int(row[2]), int(row[3])]
		out.append({"title": "%s %s" % [titles.get(str(row[1]), str(row[1])), range_text], "chance": float(row[0]) / total})
	return out


static func pity() -> int:
	return int(SaveService.data.get("chest_pity", 0))


## Текущий шанс предмета из витрины с бонусом серии (каждые PITY_STEP открытий без ценного).
static func item_chance(chest_id: String) -> float:
	return minf(float(CHESTS[chest_id]["item_chance"]) + floorf(pity() / float(PITY_STEP)) * PITY_BONUS, 0.95)


static func opens_to_guarantee() -> int:
	return maxi(PITY_GUARANTEE - pity(), 1)


static func daily_chest() -> String:
	var order := ["common", "rare", "common", "epic", "rare", "common", "epic"]
	return str(order[SaveService.today() % order.size()])


static func chest_price(chest_id: String, with_gems: bool) -> int:
	var base := int(CHESTS[chest_id]["gems" if with_gems else "coins"])
	if chest_id == daily_chest():
		return int(round(base * (1.0 - DAILY_DISCOUNT)))
	return base


static func can_afford(chest_id: String, with_gems: bool) -> bool:
	var price := chest_price(chest_id, with_gems)
	if with_gems:
		return price > 0 and SaveService.get_gems() >= price
	return SaveService.get_coins() >= price


static func ad_chest_wait() -> int:
	var ready_at := int(SaveService.data.get("ad_chest_at", 0)) + Premium.chest_cooldown()
	return maxi(ready_at - int(Time.get_unix_time_from_system()), 0)


static func ad_chest_wait_text() -> String:
	var wait := ad_chest_wait()
	return "%d ч %02d мин" % [wait / 3600, (wait % 3600) / 60]


## Открытие: списывает цену, выдаёт награды и возвращает их списком для экрана «ПОЛУЧЕНО».
static func open_chest(chest_id: String, with_gems: bool, free: bool = false) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = []
	if not CHESTS.has(chest_id) or (not free and not can_afford(chest_id, with_gems)):
		return rewards
	var chest: Dictionary = CHESTS[chest_id]
	if not free:
		if with_gems:
			SaveService.spend_gems(chest_price(chest_id, true), false)
		else:
			SaveService.spend_coins_silent(chest_price(chest_id, false))
	var shelf := featured(chest_id)
	var guarantee := pity() + 1 >= PITY_GUARANTEE
	var got_item := guarantee or randf() < item_chance(chest_id)
	if got_item:
		var key := _pick_valuable() if guarantee else _pick_featured(shelf)
		rewards.append(_grant_item(key, guarantee))
		SaveService.data["chest_pity"] = 0 if is_valuable(key) else pity() + 1
	else:
		SaveService.data["chest_pity"] = pity() + 1
		var target := _pick_shard_target(shelf)
		if not target.is_empty():
			rewards.append(grant_shards(target, CHEST_ORDER.find(chest_id) + 1))
	for i in int(chest["rolls"]) - 1:
		rewards.append(_roll_filler(chest["fillers"], shelf))
	SaveService.data["chest_opens"] = int(SaveService.data.get("chest_opens", 0)) + 1
	SaveService.add_stat("chests", 1, false)
	SaveService.save_data()
	return rewards


## Бесплатный сундук после рекламы: не чаще раза в AD_CHEST_COOLDOWN.
static func open_ad_chest() -> Array[Dictionary]:
	if ad_chest_wait() > 0:
		return []
	SaveService.data["ad_chest_at"] = int(Time.get_unix_time_from_system())
	return open_chest(Premium.chest_tier(), false, true)


static func _pick_featured(shelf: Array[String]) -> String:
	var weapons := shelf.filter(func(k: String) -> bool: return item_kind(k) == "weapon")
	var people := shelf.filter(func(k: String) -> bool: return item_kind(k) != "weapon" and not owns_item(k))
	if not people.is_empty() and (weapons.is_empty() or randf() < 0.4):
		return people.pick_random()
	return weapons.pick_random() if not weapons.is_empty() else shelf.pick_random()


## Гарантия 50-го открытия: неполученный герой или эпический/легендарный ствол.
static func _pick_valuable() -> String:
	var pool: Array[String] = []
	for rarity in ["rare", "epic", "legendary"]:
		for key in heroes_of(rarity):
			if not owns_item(key):
				pool.append(key)
	for key in weapons_of("epic") + weapons_of("legendary"):
		if not owns_item(key):
			pool.append(key)
	if pool.is_empty():
		pool = weapons_of("legendary")
	return pool.pick_random()


static func _pick_shard_target(shelf: Array[String]) -> String:
	var pool := shelf.filter(func(k: String) -> bool: return item_kind(k) == "weapon" or not owns_item(k))
	return pool.pick_random() if not pool.is_empty() else ""


static func _roll_filler(table: Array, shelf: Array[String]) -> Dictionary:
	var total := 0.0
	for row in table:
		total += float(row[0])
	var roll := randf() * total
	var pick: Array = table[0]
	for row in table:
		roll -= float(row[0])
		if roll <= 0.0:
			pick = row
			break
	var amount := randi_range(int(pick[2]), int(pick[3]))
	match str(pick[1]):
		"coins":
			SaveService.add_coins_silent(amount)
			return {"type": "coins", "amount": amount, "title": SaveService.format_coins(amount), "rarity": "common"}
		"gems":
			SaveService.add_gems(amount, false)
			return {"type": "gems", "amount": amount, "title": format_gems(amount), "rarity": "epic"}
		"shard":
			var target := _pick_shard_target(shelf)
			if not target.is_empty():
				return grant_shards(target, amount)
	SaveService.add_account_xp(amount)
	return {"type": "xp", "amount": amount, "title": "+%d опыта" % amount, "rarity": "common"}


static func _grant_item(key: String, guaranteed: bool) -> Dictionary:
	var rarity := item_rarity(key)
	var reward := {"type": "item", "key": key, "rarity": rarity, "title": item_title(key), "subtitle": item_type_name(key),
		"guaranteed": guaranteed}
	if item_kind(key) != "weapon" and owns_item(key):
		var coins := int(DUPLICATE_COINS.get(rarity, 150))
		SaveService.add_coins_silent(coins)
		reward["type"] = "dup"
		reward["amount"] = coins
		reward["subtitle"] = "уже есть → %s" % SaveService.format_coins(coins)
		return reward
	give_item(key)
	return reward


static func grant_shards(key: String, count: int) -> Dictionary:
	var shards: Dictionary = SaveService.data["shards"]
	var have := int(shards.get(key, 0)) + count
	var reward := {"type": "shard", "key": key, "amount": count, "rarity": item_rarity(key), "title": "Чертёж ×%d" % count,
		"subtitle": item_title(key)}
	if have >= SHARDS_PER_ITEM:
		have -= SHARDS_PER_ITEM
		give_item(key)
		reward["assembled"] = true
	shards[key] = have
	reward["progress"] = have
	return reward


## Выдать предмет (из сундука, чертежей или магазина).
static func give_item(key: String) -> void:
	if Cosmetics.is_cosmetic(key):
		Cosmetics.give(key)
		return
	match item_kind(key):
		"weapon":
			SaveService.add_weapon(StringName(item_id(key)), 1, false)
		"hero":
			if not SaveService.owns_character(item_id(key)):
				(SaveService.data["characters"] as Array).append(item_id(key))
		"skin":
			if not SaveService.owns_skin(item_id(key)):
				(SaveService.data["skins"] as Array).append(item_id(key))


static func shard_count(key: String) -> int:
	return int((SaveService.data["shards"] as Dictionary).get(key, 0))


# --- Реклама ----------------------------------------------------------------------------------------

static func ads_left(kind: String) -> int:
	SaveService.roll_ad_day()
	if kind == "gems":
		return maxi(AD_GEMS_LIMIT + Premium.ad_bonus() - int(SaveService.data["ads_gems"]), 0)
	return maxi(AD_COINS_LIMIT + Premium.ad_bonus() - int(SaveService.data["ads_coins"]), 0)


## Засчитать досмотренную рекламу: выдаёт награду и возвращает её (0 — лимит исчерпан).
static func claim_ad(kind: String) -> int:
	if ads_left(kind) <= 0:
		return 0
	var amount := AD_COINS
	if kind == "gems":
		var total := 0.0
		for row in AD_GEMS_TABLE:
			total += float(row[0])
		var roll := randf() * total
		for row in AD_GEMS_TABLE:
			roll -= float(row[0])
			if roll <= 0.0:
				amount = int(row[1])
				break
		SaveService.data["ads_gems"] = int(SaveService.data["ads_gems"]) + 1
		SaveService.add_gems(amount, false)
	else:
		SaveService.data["ads_coins"] = int(SaveService.data["ads_coins"]) + 1
		SaveService.add_coins_silent(amount)
	SaveService.save_data()
	return amount


# --- Забег, боссы, возрождение, магазин ----------------------------------------------------------------

## Бонус за очищенную волну: растёт с номером волны главы и кругом.
static func wave_bonus(chapter_wave: int, loop: int) -> int:
	return int(round((3 + 2 * chapter_wave) * (1.0 + 0.5 * loop)))


## Награда босса главы: неонит (первое убийство главы — +FIRST_BOSS_GEMS) и чертежи.
static func boss_reward(chapter_index: int, loop: int) -> Dictionary:
	var gems := (3 if chapter_index % 2 == 0 else 5) + loop
	var firsts: Array = SaveService.data["boss_firsts"]
	if not firsts.has(chapter_index):
		firsts.append(chapter_index)
		gems += FIRST_BOSS_GEMS
	var pool: Array[String] = []
	for key in weapons_of("epic") + weapons_of("legendary"):
		pool.append(key)
	for rarity in ["epic", "legendary"]:
		for key in heroes_of(rarity) + skins_of(rarity):
			if not owns_item(key):
				pool.append(key)
	var blueprints: Array[String] = []
	for i in (1 if chapter_index % 2 == 0 else 2) + mini(loop, 2):
		blueprints.append(pool.pick_random())
	return {"gems": gems, "blueprints": blueprints}


static func revive_cost(used: int) -> int:
	return int(REVIVE_COSTS[mini(used, REVIVE_COSTS.size() - 1)])


static func weapon_buys(weapon: WeaponData) -> int:
	return int((SaveService.data["weapon_buys"] as Dictionary).get(String(weapon.id), 0))


static func is_buyable(weapon: WeaponData) -> bool:
	return weapon.unlock_blueprint == &"" and not weapon.enemy_only


## 0 — за монеты ствол не продаётся (легендарные).
static func shop_price(weapon: WeaponData) -> int:
	var base := int(SHOP_PRICES.get(weapon.rarity, 0))
	if base <= 0:
		return 0
	return int(round(base * (1.0 + SHOP_REPEAT_STEP * mini(weapon_buys(weapon), SHOP_REPEAT_CAP)) / 10.0)) * 10


static func shop_gem_price(weapon: WeaponData) -> int:
	return int(SHOP_GEM_OVERRIDE.get(String(weapon.id), SHOP_GEM_PRICES.get(weapon.rarity, 0)))


static func keep_chance(rarity: String) -> float:
	return float(KEEP_CHANCE.get(rarity, 0.0))


static func buy_weapon(weapon: WeaponData, with_gems: bool) -> bool:
	if not weapon.has_tiers() and SaveService.owns_weapon(weapon.id):
		return false
	if not is_buyable(weapon):
		return false
	if with_gems:
		var gems := shop_gem_price(weapon)
		if gems <= 0 or not SaveService.spend_gems(gems, false):
			return false
	else:
		var price := shop_price(weapon)
		if price <= 0 or not SaveService.spend_coins(price):
			return false
	var buys: Dictionary = SaveService.data["weapon_buys"]
	buys[String(weapon.id)] = weapon_buys(weapon) + 1
	SaveService.add_weapon(weapon.id, 1, false)
	SaveService.save_data()
	return true
