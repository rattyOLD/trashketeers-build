class_name Tester
extends RefCounted
## Режим тестера: флаги в SaveService.data["tester"] и мгновенные выдачи для проверки игры.

const FLAGS := {
	"god": "Бессмертие в бою",
	"dmg": "Урон ×10",
	"levels": "Старт с +10 уровней",
	"speed": "Скорость ×1.6 (бег)",
}


static func flag(name: String) -> bool:
	return bool((SaveService.data["tester"] as Dictionary).get(name, false))


static func start_chapter() -> int:
	return clampi(int((SaveService.data["tester"] as Dictionary).get("start_chapter", 0)), 0, ContentDB.get_chapters().size() - 1)


## 1…10 — с какой волны главы начинать бой.
static func start_wave() -> int:
	return clampi(int((SaveService.data["tester"] as Dictionary).get("start_wave", 1)), 1, WaveDirector.WAVES_PER_CHAPTER)


static func set_start(chapter: int, wave: int) -> void:
	var state: Dictionary = SaveService.data["tester"]
	state["start_chapter"] = chapter
	state["start_wave"] = wave
	SaveService.save_data()


static func toggle(name: String) -> void:
	var state: Dictionary = SaveService.data["tester"]
	state[name] = not bool(state.get(name, false))
	SaveService.save_data()


static func give_coins(amount: int) -> void:
	SaveService.add_coins(amount)


static func give_gems(amount: int) -> void:
	SaveService.add_gems(amount)


## tier5 — сразу по одной копии пятого тира, иначе по копии первого.
static func give_all_weapons(tier5: bool) -> int:
	var count := 0
	for weapon in WeaponDB.get_player_weapons():
		SaveService.add_weapon(weapon.id, 5 if tier5 else 1, false)
		count += 1
	SaveService.save_data()
	return count


static func give_all_looks() -> void:
	for hero in CharacterDB.all():
		Economy.give_item("hero:" + String(hero["id"]))
	for skin_id in SaveService.SKINS:
		Economy.give_item("skin:" + String(skin_id))
	SaveService.save_data()


static func max_perks() -> void:
	var perks: Dictionary = SaveService.data["perks"]
	for perk_id in SaveService.PERKS:
		perks[perk_id] = int(SaveService.PERKS[perk_id]["max"])
	SaveService.save_data()


static func give_shards() -> void:
	for rarity in ["epic", "legendary"]:
		for key in Economy.weapons_of(rarity) + Economy.heroes_of(rarity) + Economy.skins_of(rarity):
			Economy.grant_shards(key, Economy.SHARDS_PER_ITEM - 1)
	SaveService.save_data()


static func add_account_levels(levels: int) -> void:
	var target := SaveService.get_account_level() + levels
	SaveService.data["account_xp"] = int(SaveService.XP_PER_LEVEL_BASE * pow(target - 1, 2))
	SaveService.save_data()


static func reset_save() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.save_data()


## Restart the campaign without removing earned account rewards or lifetime statistics.
static func reset_story() -> bool:
	if not SaveService.is_dev():
		return false
	for key in ["story", "story_log", "story_best", "story_choice", "story_resume"]:
		SaveService.data[key] = {}
	SaveService.resume_requested = false
	SaveService.data["train_again"] = true
	SaveService.save_data()
	return true


static func reset_ads() -> void:
	SaveService.data["ads_coins"] = 0
	SaveService.data["ads_gems"] = 0
	SaveService.save_data()


static func reset_chest_timer() -> void:
	SaveService.data["ad_chest_at"] = 0
	SaveService.save_data()


static func reset_daily() -> void:
	SaveService.data["daily_day"] = 0
	SaveService.save_data()


static func advance_daily() -> void:
	var streak := SaveService.get_daily_step() - (1 if SaveService.can_claim_daily() else 0)
	SaveService.data["daily_streak"] = streak + 1
	SaveService.data["daily_day"] = SaveService.today() - 1
	SaveService.save_data()
