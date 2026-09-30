extends Node
## Autoload "SaveService". Единый прогресс всей Игровой Сетки (JSON через Platform):
## общий кошелёк монет (ключ "nuts" оставлен ради старых сохранений), прогресс Енота,
## прогресс «Втык!» (data["knife"], логика — KnifeProgress), ежедневная награда и задания.
## Загруженные данные накладываются на DEFAULTS со строгой проверкой типов,
## поэтому старые сохранения без новых полей и ручные правки не ломают игру.
##
## Синхронизация: локально (localStorage) — сразу; в Telegram CloudStorage — с задержкой
## CLOUD_DEBOUNCE, чтобы серия покупок не превращалась в серию запросов. При запуске берётся
## более свежая из двух копий (по saved_at).
##
## Арсенал: weapon_id → [кол-во T1, T2, T3, T4, T5]. Merge: две копии одного тира → одна тиром выше.
## Прокачка (перки): Сила / Выносливость / Броня, покупаются за монеты, цена растёт геометрически.
## Ачивки: счётчики stats + пороги ACHIEVEMENTS; награда выдаётся один раз при достижении.

signal changed
signal achievement_unlocked(achievement: Dictionary)
## Прогресс заменён более свежей облачной копией — экраны перечитывают данные.
signal reloaded

const STORAGE_KEY := "battle_raccoon_save_v1"
const START_WEAPON := "pistol_v1"
const DEFAULTS := {
	"nuts": 0,
	"gift_at": {},
	"gift_gem_day": 0,
	"gift_gem_n": 0,
	"star_dust": 0,
	"best_time": 0.0,
	"best_wave": 0,
	"runs": 0,
	"boss_kills": 0,
	"story": {},
	"raid_wins": 0,
	"dragon_kills": 0,
	"blueprints": [],
	"selected_weapon": START_WEAPON,
	"selected_tier": 1,
	"arsenal": {},
	"perks": {},
	"slot3": false,
	"hero_levels": {},
	"achievements": [],
	"stats": {},
	"nickname": "",
	"local_id": "",
	"insider_no": -1,
	"weapon_buys": {},
	"sfx_on": true,
	"music_on": true,
	"glow_on": true,
	"fx_lite": false,
	"minimap": true,
	"show_fps": false,
	"grade_on": true,
	"quality": -1,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"account_xp": 0,
	"skins": ["classic"],
	"selected_skin": "classic",
	"characters": ["raccoon"],
	"character": "raccoon",
	"knife": {},
	"daily_day": 0,
	"daily_streak": 0,
	"quest_day": 0,
	"quest_progress": {},
	"quest_claimed": [],
	"ref_claimed": false,
	"invites_sent": 0,
	"saved_at": 0,
	"shards": {},
	"chest_pity": 0,
	"chest_opens": 0,
	"ads_day": 0,
	"ads_coins": 0,
	"ads_gems": 0,
	"boss_firsts": [],
	"controls": {},
	"tester": {},
	"iap_bought": [],
	"vip_level": 0,
	"vip_until": 0,
	"no_ads": false,
	"bp": {},
	"bp_ever": false,
	"death_tips": 0,
	"ad_chest_at": 0,
	"changelog_seen": "",
}

const CLOUD_DEBOUNCE := 2.5
## Ежедневная награда: серия из 7 дней, пропуск дня сбрасывает серию. Дни 4 и 7 — ещё и неонит.
const DAILY_REWARDS := [50, 75, 100, 150, 200, 300, 500]
const DAILY_GEMS := {4: 2, 7: 6}
## Ежедневные задания Сетки: прогресс сбрасывается в новый день (UTC).
const QUESTS := [
	{"id": "raccoon_run", "game": "raccoon", "title": "Сыграй забег в Trashketeers.io", "goal": 1, "reward": 60},
	{"id": "rats", "game": "raccoon", "title": "Победи 50 крыс", "goal": 50, "reward": 70},
	{"id": "knife_levels", "game": "knife", "title": "Пройди 3 уровня во «Втык!»", "goal": 3, "reward": 80},
	{"id": "knife_perfect", "game": "knife", "title": "Сделай 10 идеальных втыков", "goal": 10, "reward": 70},
]

## Скины (наряды): цена в монетах (nuts) или неоните (ключ star_dust). look — не наклейки поверх
## спрайта, а перекраска нарисованных регионов (одежда / шарф / кожа ремней / металл / радужка)
## градиентной картой с сохранением светотени + слой аксессуаров, нарисованный в развёртке спрайта
## (двигается вместе с костями головы и корпуса). Формат региона:
## [тень, середина, свет, сила, яркость_min, яркость_max].
const SKINS := {
	"classic": {"title": "Классика", "description": "Походный шарф и ремни налётчика", "currency": "nuts", "price": 0,
		"effect": "", "look": {}},
	"punk": {"title": "Панк", "description": "Кожанка, розовый ирокез, шипастый ошейник", "currency": "nuts", "price": 900,
		"effect": "", "look": {
			"recolor": {
				"clothes": ["#060609", "#24232f", "#9aa0b8", 1.0, 0.08, 0.41],
				"scarf": ["#3d0428", "#d8217f", "#ff9ad0", 1.0, 0.15, 0.49],
				"leather": ["#09080c", "#26222e", "#77708a", 1.0, 0.13, 0.43],
				"metal": ["#3a3f4e", "#b7bfd2", "#ffffff", 1.0, 0.27, 0.72],
			},
			"overlay": "punk"}},
	"bandit": {"title": "Бандит", "description": "Кепка, красная бандана в горошек", "currency": "nuts", "price": 1400,
		"effect": "", "look": {
			"recolor": {
				"clothes": ["#07090f", "#1d2536", "#5d6c8c", 1.0, 0.08, 0.41],
				"scarf": ["#3a0406", "#c81d25", "#ff8a80", 1.0, 0.15, 0.49],
				"leather": ["#140a05", "#3c2414", "#8a5a38", 1.0, 0.13, 0.43],
				"metal": ["#4a3510", "#c9a24a", "#fff0b8", 1.0, 0.27, 0.72],
			},
			"overlay": "bandit"}},
	"neon": {"title": "Кибер-Неон", "description": "Неоновый визор, светящаяся экипировка", "currency": "nuts", "price": 2600,
		"effect": "aura", "look": {
			"recolor": {
				"clothes": ["#050814", "#16213d", "#4f6fa6", 1.0, 0.08, 0.41],
				"scarf": ["#00323c", "#00d2ea", "#c8fdff", 1.0, 0.15, 0.49],
				"leather": ["#0b0d16", "#1f2436", "#5b6584", 1.0, 0.13, 0.43],
				"metal": ["#4d0634", "#ff2ea6", "#ffd6f0", 1.0, 0.27, 0.72],
				"iris": ["#002a36", "#00e5ff", "#e8ffff", 1.0, 0.06, 0.83],
			},
			"overlay": "neon"}},
	"gold": {"title": "Золотой Босс", "description": "Корона, золотая цепь, королевский шарф", "currency": "nuts", "price": 5500,
		"effect": "sparkle", "look": {
			"recolor": {
				"clothes": ["#120407", "#3d1219", "#8a4450", 1.0, 0.08, 0.41],
				"scarf": ["#1b0730", "#6d2bb0", "#dcb0ff", 1.0, 0.15, 0.49],
				"leather": ["#230606", "#7c1d1d", "#d8716a", 1.0, 0.13, 0.43],
				"metal": ["#5a3a05", "#f2b72c", "#fff6cf", 1.0, 0.27, 0.72],
			},
			"overlay": "gold"}},
	"star": {"title": "Космонавт", "description": "Скафандр, стеклянный шлем, звёзды вокруг", "currency": "star_dust", "price": 60,
		"effect": "stars", "look": {
			"recolor": {
				"clothes": ["#5d6376", "#d9dde8", "#ffffff", 1.0, 0.08, 0.41],
				"scarf": ["#4a1800", "#ff7a1a", "#ffd4a8", 1.0, 0.15, 0.49],
				"leather": ["#262a34", "#6c7384", "#c6ccda", 1.0, 0.13, 0.43],
				"metal": ["#123456", "#4aa8ff", "#e2f3ff", 1.0, 0.27, 0.72],
			},
			"overlay": "star"}},
}

const PERKS := {
	"power": {"title": "Сила", "description": "+6% урона любым стволом", "step": 0.06, "max": 10, "cost": 120, "icon": "🔫", "theme": "Ржавый ствол — тоже ствол"},
	"stamina": {"title": "Выносливость", "description": "+12 к максимуму здоровья", "step": 12.0, "max": 10, "cost": 100, "icon": "🥫", "theme": "Консервы из мусорки"},
	"armor": {"title": "Броня из жести", "description": "-3% получаемого урона", "step": 0.03, "max": 10, "cost": 140, "icon": "🛡", "theme": "Крышка от бака"},
	"rate": {"title": "Смазка", "description": "+2% скорострельности", "step": 0.02, "max": 10, "cost": 160, "icon": "🛢", "theme": "Машинное масло с помойки"},
	"eye": {"title": "Меткий глаз", "description": "+1% шанса крита", "step": 0.01, "max": 10, "cost": 180, "icon": "🎯", "theme": "Очки сварщика"},
	"boots": {"title": "Кроссовки", "description": "+2% скорости бега", "step": 0.02, "max": 8, "cost": 150, "icon": "👟", "theme": "Найдены в контейнере"},
	"dasher": {"title": "Проворство", "description": "-4% перезарядки рывка", "step": 0.04, "max": 8, "cost": 200, "icon": "💨", "theme": "Хвост-руль"},
	"magnet": {"title": "Магнит", "description": "+8% радиуса подбора добычи", "step": 0.08, "max": 8, "cost": 130, "icon": "🧲", "theme": "Магнит со свалки"},
	"patch": {"title": "Пластырь", "description": "+0.15 HP/с регенерации", "step": 0.15, "max": 6, "cost": 260, "icon": "🩹", "theme": "Изолента лечит всё"},
	"loot": {"title": "Хапуга", "description": "+4% монет за забег", "step": 0.04, "max": 10, "cost": 220, "icon": "💰", "theme": "Карманы побольше"},
	"reroll": {"title": "Реролл", "description": "+1 бесплатный реролл улучшений за забег", "step": 1.0, "max": 3, "cost": 600, "icon": "🎲", "theme": "Крысиные кости"},
	"haggle": {"title": "Торговец", "description": "-12% цены платного реролла", "step": 0.12, "max": 5, "cost": 300, "icon": "🤝", "theme": "Торг у контейнеров"},
}
const HERO_MAX_LEVEL := 8
const HERO_HP_PER_LEVEL := 0.04
const HERO_DAMAGE_PER_LEVEL := 0.03
const PERK_COST_GROWTH := 1.36
const SLOT3_PRICE := 250

## stat — ключ в data["stats"], goal — порог; награды — монеты и Звёздная Пыль.
const ACHIEVEMENTS := [
	{"id": "first_blood", "title": "Первая кровь", "description": "Победить первую крысу", "stat": "kills", "goal": 1, "nuts": 20, "dust": 0},
	{"id": "exterminator", "title": "Дератизатор", "description": "Победить 300 крыс", "stat": "kills", "goal": 300, "nuts": 150, "dust": 0},
	{"id": "rat_plague", "title": "Чума для чумы", "description": "Победить 2000 крыс", "stat": "kills", "goal": 2000, "nuts": 600, "dust": 5},
	{"id": "wave_5", "title": "Пять волн", "description": "Дойти до 5-й волны", "stat": "best_wave", "goal": 5, "nuts": 80, "dust": 0},
	{"id": "wave_10", "title": "Ветеран свалки", "description": "Дойти до 10-й волны", "stat": "best_wave", "goal": 10, "nuts": 250, "dust": 5},
	{"id": "king_slayer", "title": "Цареубийца", "description": "Победить Короля Хлама", "stat": "boss_kills", "goal": 1, "nuts": 200, "dust": 0},
	{"id": "dasher", "title": "Шустрый", "description": "Сделать 100 рывков", "stat": "dashes", "goal": 100, "nuts": 60, "dust": 0},
	{"id": "crate_hunter", "title": "Охотник за ящиками", "description": "Разбить 15 ящиков с оружием", "stat": "crates", "goal": 15, "nuts": 120, "dust": 0},
	{"id": "merger", "title": "Кузнец", "description": "Сделать первый Merge оружия", "stat": "merges", "goal": 1, "nuts": 100, "dust": 0},
	{"id": "rich", "title": "Мешок монет", "description": "Собрать 1000 монет за всё время", "stat": "nuts_total", "goal": 1000, "nuts": 0, "dust": 5},
	{"id": "dragon_raid", "title": "Тёплый приём", "description": "Победить Хладгора в Ледяном налёте", "stat": "raid_wins", "goal": 1, "nuts": 150, "dust": 5},
	{"id": "raid_flawless", "title": "Без единой снежинки", "description": "Победить Хладгора, ни разу не замёрзнув", "stat": "raid_flawless", "goal": 1, "nuts": 300, "dust": 10, "hidden": true},
	{"id": "crit_master", "title": "В яблочко", "description": "Нанести 500 критических попаданий", "stat": "crits", "goal": 500, "nuts": 120, "dust": 0},
	{"id": "toxic_mask", "title": "Противогаз", "description": "Победить 100 Токсичных крыс", "stat": "k_toxic_rat", "goal": 100, "nuts": 180, "dust": 0},
	{"id": "mad_calm", "title": "Успокоительное", "description": "Победить 100 Бешеных крыс", "stat": "k_dash_rat", "goal": 100, "nuts": 180, "dust": 0},
	{"id": "punk_dead", "title": "Панк-рок жив, но не они", "description": "Победить 500 Скрэппи", "stat": "k_rat_punk", "goal": 500, "nuts": 260, "dust": 0},
	{"id": "sniper_hunt", "title": "Сам себе снайпер", "description": "Победить 60 Свиней-снайперов", "stat": "k_pig_sniper", "goal": 60, "nuts": 240, "dust": 2},
	{"id": "no_repair", "title": "Ремонту не подлежит", "description": "Победить 80 Свиней-механиков", "stat": "k_pig_mechanic", "goal": 80, "nuts": 240, "dust": 2},
	{"id": "hangover", "title": "Похмелье Барона", "description": "Победить Пивного Барона", "stat": "k_beer_baron", "goal": 1, "nuts": 300, "dust": 3},
	{"id": "nationalize", "title": "Национализация", "description": "Победить Свинью-Магната", "stat": "k_pig_magnate", "goal": 1, "nuts": 400, "dust": 4},
	{"id": "marauder_catch", "title": "Ловец мародёров", "description": "Поймать 25 мародёров с добычей", "stat": "marauders", "goal": 25, "nuts": 220, "dust": 2},
	{"id": "regular", "title": "Завсегдатай свалки", "description": "Сыграть 25 забегов", "stat": "runs", "goal": 25, "nuts": 300, "dust": 3},
	{"id": "perk_junkie", "title": "Билд на ходу", "description": "Выбрать 100 улучшений в боях", "stat": "picks", "goal": 100, "nuts": 200, "dust": 0},
	{"id": "chest_lord", "title": "Владыка сундуков", "description": "Открыть 20 сундуков", "stat": "chests", "goal": 20, "nuts": 250, "dust": 3},
	{"id": "blacksmith_pro", "title": "Мастер горна", "description": "Сделать 10 Merge оружия", "stat": "merges", "goal": 10, "nuts": 300, "dust": 3},
	{"id": "dash_king", "title": "Молния помоек", "description": "Сделать 1000 рывков", "stat": "dashes", "goal": 1000, "nuts": 350, "dust": 3},
	{"id": "exterminator_pro", "title": "Санэпидемстанция", "description": "Победить 10000 врагов", "stat": "kills", "goal": 10000, "nuts": 1500, "dust": 15},
	{"id": "wave_20", "title": "Двадцать волн", "description": "Дойти до 20-й волны", "stat": "best_wave", "goal": 20, "nuts": 500, "dust": 8},
	{"id": "wave_30", "title": "Хозяин биома", "description": "Дойти до 30-й волны", "stat": "best_wave", "goal": 30, "nuts": 900, "dust": 12},
	{"id": "tycoon", "title": "Мусорный магнат", "description": "Собрать 10000 монет за всё время", "stat": "nuts_total", "goal": 10000, "nuts": 0, "dust": 10},
	{"id": "crit_god", "title": "Только крит", "description": "Нанести 5000 критических попаданий", "stat": "crits", "goal": 5000, "nuts": 600, "dust": 6},
]

const XP_PER_LEVEL_BASE := 20.0
const RAID_WIN_XP := 60
const RAID_DUST_KILL := 6
const RAID_DUST_SURVIVE := 3
const RAID_BLUEPRINT := &"prism_blaster_blueprint"
const NICKNAME_MAX := 16
const NICK_PREFIXES := ["Мусорный", "Неоновый", "Ржавый", "Кибер", "Дикий", "Бешеный", "Ночной", "Хромой"]
const NICK_ROOTS := ["Енот", "Бандит", "Мститель", "Шериф", "Барон", "Панда", "Ворюга", "Гопник"]

var data: Dictionary = DEFAULTS.duplicate(true)
var _cloud_timer := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_data()
	Platform.cloud_loaded.connect(_on_cloud_loaded, CONNECT_ONE_SHOT)
	Platform.cloud_load(STORAGE_KEY)


func _process(delta: float) -> void:
	if _cloud_timer < 0.0:
		return
	_cloud_timer -= delta
	if _cloud_timer < 0.0:
		Platform.cloud_save(STORAGE_KEY, JSON.stringify(data))


func load_data() -> void:
	_apply_text(Platform.storage_get(STORAGE_KEY))
	changed.emit()


func _apply_text(text: String) -> void:
	data = DEFAULTS.duplicate(true)
	if not text.is_empty():
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			for key in DEFAULTS:
				if parsed.has(key) and ConfigLoader.type_matches(parsed[key], DEFAULTS[key]):
					data[key] = parsed[key]
		else:
			push_warning("SaveService: сохранение повреждено, начат новый прогресс")
	for key in ["nuts", "star_dust", "runs", "boss_kills", "raid_wins", "dragon_kills", "account_xp", "best_wave", "selected_tier",
			"daily_day", "daily_streak", "quest_day", "invites_sent", "saved_at", "chest_pity", "chest_opens", "ads_day",
			"ads_coins", "ads_gems", "gift_gem_day", "gift_gem_n", "vip_level", "vip_until", "insider_no"]:
		data[key] = int(data[key])
	_sanitize_arsenal()
	KnifeProgress.sanitize(data)
	if data["nickname"] == "":
		data["nickname"] = random_nickname()


func save_data() -> void:
	data["saved_at"] = int(Time.get_unix_time_from_system())
	Platform.storage_set(STORAGE_KEY, JSON.stringify(data))
	_cloud_timer = CLOUD_DEBOUNCE
	changed.emit()


## Облачная копия новее локальной (другое устройство) — берём её целиком.
func _on_cloud_loaded(text: String) -> void:
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if int(parsed.get("saved_at", 0)) <= int(data["saved_at"]):
		return
	_apply_text(text)
	Platform.storage_set(STORAGE_KEY, JSON.stringify(data))
	changed.emit()
	reloaded.emit()


# --- Общий кошелёк --------------------------------------------------------------------------------

func get_coins() -> int:
	return data["nuts"]


func add_coins(amount: int) -> void:
	data["nuts"] = get_coins() + amount
	save_data()


## Списывает монеты; false — не хватает.
func spend_coins(amount: int) -> bool:
	if get_coins() < amount:
		return false
	data["nuts"] = get_coins() - amount
	save_data()
	return true


## «150 монет», «1 монета», «3 монеты».
static func format_coins(amount: int) -> String:
	return "%d %s" % [amount, plural(amount, "монета", "монеты", "монет")]


static func plural(n: int, one: String, few: String, many: String) -> String:
	var mod100 := absi(n) % 100
	var mod10 := absi(n) % 10
	if mod100 >= 11 and mod100 <= 14:
		return many
	if mod10 == 1:
		return one
	if mod10 >= 2 and mod10 <= 4:
		return few
	return many


func get_nuts() -> int:
	return data["nuts"]


func get_star_dust() -> int:
	return data["star_dust"]


## Неонит — редкая валюта (ключ сохранения star_dust остался от «Звёздной Пыли»).
func get_gems() -> int:
	return int(data["star_dust"])


func add_gems(amount: int, save: bool = true) -> void:
	data["star_dust"] = get_gems() + maxi(amount, 0)
	if save:
		save_data()


func spend_gems(amount: int, save: bool = true) -> bool:
	if get_gems() < amount:
		return false
	data["star_dust"] = get_gems() - amount
	if save:
		save_data()
	return true


func add_coins_silent(amount: int) -> void:
	data["nuts"] = get_coins() + amount


func spend_coins_silent(amount: int) -> void:
	data["nuts"] = maxi(get_coins() - amount, 0)


## Новый день — лимиты рекламы обнуляются.
func roll_ad_day() -> void:
	if int(data["ads_day"]) != today():
		data["ads_day"] = today()
		data["ads_coins"] = 0
		data["ads_gems"] = 0


func add_nuts(amount: int) -> void:
	data["nuts"] = get_nuts() + amount
	save_data()


## Качество графики: 0 — «Эконом» (без света пропов, свечения и цветокоррекции, холст до 1.5×),
## 1 — «Баланс» (свет и цветокоррекция, холст до 2×), 2 — «Красиво» (+ неоновое свечение,
## родное разрешение). -1 — авто: телефон/планшет → 0, компьютер → 1.
func get_quality() -> int:
	var q := int(data.get("quality", -1))
	if q < 0:
		return 0 if Platform.is_touch() else 1
	return clampi(q, 0, 2)


func set_quality(q: int) -> void:
	data["quality"] = clampi(q, 0, 2)
	save_data()
	apply_quality()


func apply_quality() -> void:
	var caps := [1.25, 1.75, 2.5] if Platform.is_touch() else [1.25, 2.0, 3.0]
	Platform.set_render_cap(caps[get_quality()])


func is_minimap_enabled() -> bool:
	return bool(data.get("minimap", true))


func is_fx_lite() -> bool:
	return get_quality() == 0 or bool(data.get("fx_lite", false))


func is_glow_enabled() -> bool:
	return get_quality() >= 2


func is_grade_enabled() -> bool:
	return get_quality() >= 1


func are_prop_lights_enabled() -> bool:
	return get_quality() >= 1


func set_flag(key: String, enabled: bool) -> void:
	data[key] = enabled
	save_data()


func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save_data()


# --- Ежедневная награда ---------------------------------------------------------------------------

static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func can_claim_daily() -> bool:
	return today() > int(data["daily_day"])


## Номер дня серии, который будет выдан (1..7).
func get_daily_step() -> int:
	var streak := int(data["daily_streak"])
	if today() - int(data["daily_day"]) > 1:
		streak = 0
	if not can_claim_daily():
		return clampi(streak, 1, DAILY_REWARDS.size())
	return streak % DAILY_REWARDS.size() + 1


func get_daily_reward() -> int:
	return int(DAILY_REWARDS[get_daily_step() - 1]) * Premium.daily_mult()


## Возвращает выданную сумму (0 — сегодня уже забрано).
func claim_daily() -> int:
	if not can_claim_daily():
		return 0
	var step := get_daily_step()
	var mult := Premium.daily_mult()
	var reward := int(DAILY_REWARDS[step - 1]) * mult
	data["daily_streak"] = step
	data["daily_day"] = today()
	data["nuts"] = get_coins() + reward
	data["star_dust"] = get_gems() + int(DAILY_GEMS.get(step, 0)) * mult
	BattlePass.add_points(BattlePass.DAILY_POINTS)
	save_data()
	return reward


# --- Ежедневные задания ----------------------------------------------------------------------------

func _roll_quests() -> void:
	if int(data["quest_day"]) != today():
		data["quest_day"] = today()
		data["quest_progress"] = {}
		data["quest_claimed"] = []


func quest_add(quest_id: String, amount: int = 1) -> void:
	_roll_quests()
	var progress: Dictionary = data["quest_progress"]
	progress[quest_id] = int(progress.get(quest_id, 0)) + amount


func get_quest_progress(quest: Dictionary) -> int:
	_roll_quests()
	return mini(int((data["quest_progress"] as Dictionary).get(quest["id"], 0)), int(quest["goal"]))


func is_quest_claimed(quest: Dictionary) -> bool:
	_roll_quests()
	return (data["quest_claimed"] as Array).has(quest["id"])


func claim_quest(quest: Dictionary) -> bool:
	if is_quest_claimed(quest) or get_quest_progress(quest) < int(quest["goal"]):
		return false
	(data["quest_claimed"] as Array).append(quest["id"])
	data["nuts"] = get_coins() + int(quest["reward"])
	BattlePass.add_points(BattlePass.QUEST_POINTS)
	save_data()
	return true


func count_ready_quests() -> int:
	var ready := 0
	for quest in QUESTS:
		if not is_quest_claimed(quest) and get_quest_progress(quest) >= int(quest["goal"]):
			ready += 1
	return ready


# --- Друзья ----------------------------------------------------------------------------------------

## Бонус новичку, пришедшему по чужой ссылке (startapp=ref_<id>). Возвращает сумму или 0.
func claim_welcome_bonus() -> int:
	if bool(data["ref_claimed"]):
		return 0
	var param := Platform.start_param()
	if not param.begins_with("ref_") or param == "ref_" + Platform.user_id():
		return 0
	var bonus := int(ConfigLoader.load_json("res://data/platform.json").get("welcome_bonus", 100))
	data["ref_claimed"] = true
	data["nuts"] = get_coins() + bonus
	save_data()
	return bonus


func mark_invite_sent() -> void:
	data["invites_sent"] = int(data["invites_sent"]) + 1
	save_data()


# --- Ник ------------------------------------------------------------------------------------------

func get_nickname() -> String:
	return data["nickname"]


## Номер инсайдера (0 — разработчик) или -1.
func get_insider() -> int:
	return int(data["insider_no"])


func get_badge() -> String:
	return Insider.badge_of(get_insider())


## Ник с плашкой статуса — для меню и таблички над Енотом.
func get_display_nickname() -> String:
	var badge := get_badge()
	return get_nickname() if badge.is_empty() else "%s %s" % [badge, get_nickname()]


func activate_insider(code: String) -> bool:
	var number := Insider.parse(code)
	if number < 0:
		return false
	data["insider_no"] = number
	save_data()
	return true


## Всё сохранение одной строкой: копируется в буфер и переносится на другое устройство.
func export_code() -> String:
	var raw := JSON.stringify(data).to_utf8_buffer()
	return "TRS1.%d.%s" % [raw.size(), Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))]


func import_code(code: String) -> bool:
	var parts := code.strip_edges().split(".")
	if parts.size() != 3 or parts[0] != "TRS1" or not parts[1].is_valid_int():
		return false
	var packed := Marshalls.base64_to_raw(parts[2])
	if packed.is_empty():
		return false
	var raw := packed.decompress(int(parts[1]), FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return false
	var text := raw.get_string_from_utf8()
	if typeof(JSON.parse_string(text)) != TYPE_DICTIONARY:
		return false
	_apply_text(text)
	save_data()
	reloaded.emit()
	return true


## ID игрока: номер инсайдера, Telegram-аккаунт, если запущено в Telegram, иначе постоянный локальный номер.
func get_player_id() -> String:
	if get_insider() >= 0:
		return "%03d" % get_insider()
	var uid := Platform.user_id()
	if not uid.is_empty():
		return uid
	if str(data.get("local_id", "")).is_empty():
		data["local_id"] = str(10000000 + randi() % 90000000)
		save_data()
	return str(data["local_id"])


## Сколько разных глав пройдено (побеждён их босс).
func get_biomes_cleared() -> int:
	var seen := {}
	for chapter_index in data["boss_firsts"]:
		seen[int(chapter_index)] = true
	return seen.size()


func set_nickname(nick: String) -> void:
	var clean := nick.strip_edges().left(NICKNAME_MAX)
	data["nickname"] = clean if not clean.is_empty() else random_nickname()
	save_data()


static func random_nickname() -> String:
	return "%s%s%d" % [NICK_PREFIXES.pick_random(), NICK_ROOTS.pick_random(), randi_range(1, 99)]


# --- Уровень аккаунта ----------------------------------------------------------------------------

## Уровень аккаунта: каждый следующий требует больше опыта (квадратичная кривая).
func get_account_level() -> int:
	return 1 + int(floor(sqrt(float(data["account_xp"]) / XP_PER_LEVEL_BASE)))


## Доля прогресса к следующему уровню, 0..1.
func get_level_progress() -> float:
	var level := get_account_level()
	var from := XP_PER_LEVEL_BASE * pow(level - 1, 2)
	var to := XP_PER_LEVEL_BASE * pow(level, 2)
	return clampf((float(data["account_xp"]) - from) / (to - from), 0.0, 1.0)


func add_account_xp(amount: int) -> void:
	data["account_xp"] = int(data["account_xp"]) + maxi(amount, 0)


# --- Скины ----------------------------------------------------------------------------------------

func owns_skin(skin_id: String) -> bool:
	return (data["skins"] as Array).has(skin_id)


func get_selected_skin() -> String:
	var skin: String = data["selected_skin"]
	return skin if SKINS.has(skin) and owns_skin(skin) else "classic"


func get_skin() -> Dictionary:
	return SKINS[get_selected_skin()]


func select_skin(skin_id: String) -> void:
	if owns_skin(skin_id):
		data["selected_skin"] = skin_id
		save_data()


## Покупка скина. Возвращает false, если не хватает валюты или скин уже куплен.
func buy_skin(skin_id: String) -> bool:
	if not SKINS.has(skin_id) or owns_skin(skin_id):
		return false
	var skin: Dictionary = SKINS[skin_id]
	var currency: String = skin["currency"]
	if int(data[currency]) < int(skin["price"]):
		return false
	data[currency] = int(data[currency]) - int(skin["price"])
	(data["skins"] as Array).append(skin_id)
	data["selected_skin"] = skin_id
	save_data()
	return true


# --- Герои ----------------------------------------------------------------------------------------

func owns_character(character_id: String) -> bool:
	return (data["characters"] as Array).has(character_id)


func get_character_id() -> String:
	var id := str(data["character"])
	return id if CharacterDB.has_character(id) and owns_character(id) else CharacterDB.DEFAULT_ID


func get_character() -> Dictionary:
	return CharacterDB.get_character(get_character_id())


func get_hero_level(character_id: String) -> int:
	return clampi(int((data["hero_levels"] as Dictionary).get(character_id, 1)), 1, HERO_MAX_LEVEL)


func hero_upgrade_cost(character_id: String) -> int:
	var level := get_hero_level(character_id)
	if level >= HERO_MAX_LEVEL:
		return 0
	return int(round(500.0 * pow(1.6, level - 1) / 50.0)) * 50


func upgrade_hero(character_id: String) -> bool:
	if not owns_character(character_id) or get_hero_level(character_id) >= HERO_MAX_LEVEL:
		return false
	var cost := hero_upgrade_cost(character_id)
	if get_coins() < cost:
		return false
	data["nuts"] = get_coins() - cost
	(data["hero_levels"] as Dictionary)[character_id] = get_hero_level(character_id) + 1
	save_data()
	return true


func select_character(character_id: String) -> void:
	if owns_character(character_id):
		data["character"] = character_id
		save_data()


func buy_character(character_id: String) -> bool:
	if not CharacterDB.has_character(character_id) or owns_character(character_id):
		return false
	var entry := CharacterDB.get_character(character_id)
	var currency: String = entry["currency"]
	if int(data[currency]) < int(entry["price"]):
		return false
	data[currency] = int(data[currency]) - int(entry["price"])
	(data["characters"] as Array).append(character_id)
	data["character"] = character_id
	save_data()
	return true


# --- Арсенал и Merge -------------------------------------------------------------------------------

func has_blueprint(blueprint_id: StringName) -> bool:
	return (data["blueprints"] as Array).has(String(blueprint_id))


func get_tier_counts(weapon_id: StringName) -> Array:
	var arsenal: Dictionary = data["arsenal"]
	return arsenal.get(String(weapon_id), [0, 0, 0, 0, 0])


func get_copies(weapon_id: StringName, tier: int) -> int:
	return int(get_tier_counts(weapon_id)[clampi(tier, 1, WeaponData.MAX_TIER) - 1])


func owns_weapon(weapon_id: StringName) -> bool:
	for count in get_tier_counts(weapon_id):
		if int(count) > 0:
			return true
	return false


func best_tier(weapon_id: StringName) -> int:
	var counts := get_tier_counts(weapon_id)
	for t in range(WeaponData.MAX_TIER, 0, -1):
		if int(counts[t - 1]) > 0:
			return t
	return 0


func is_weapon_unlocked(weapon: WeaponData) -> bool:
	return owns_weapon(weapon.id)


func add_weapon(weapon_id: StringName, tier: int = 1, save: bool = true) -> void:
	if not WeaponDB.has_weapon(weapon_id):
		return
	var arsenal: Dictionary = data["arsenal"]
	var counts: Array = arsenal.get(String(weapon_id), [0, 0, 0, 0, 0]).duplicate()
	var index := clampi(tier, 1, WeaponData.MAX_TIER) - 1
	if not WeaponDB.get_weapon(weapon_id).has_tiers():
		counts = [1, 0, 0, 0, 0]
		index = 0
	else:
		counts[index] = int(counts[index]) + 1
	arsenal[String(weapon_id)] = counts
	if save:
		save_data()


func can_merge(weapon_id: StringName, tier: int) -> bool:
	if WeaponDB.has_weapon(weapon_id) and not WeaponDB.get_weapon(weapon_id).has_tiers():
		return false
	return tier < WeaponData.MAX_TIER and get_copies(weapon_id, tier) >= 2


## Две копии тира tier → одна тира tier + 1. Если слита последняя копия экипированного тира,
## экипировка переезжает на лучший оставшийся.
func merge(weapon_id: StringName, tier: int) -> bool:
	if not can_merge(weapon_id, tier):
		return false
	var arsenal: Dictionary = data["arsenal"]
	var counts: Array = arsenal[String(weapon_id)].duplicate()
	counts[tier - 1] = int(counts[tier - 1]) - 2
	counts[tier] = int(counts[tier]) + 1
	arsenal[String(weapon_id)] = counts
	if get_selected_weapon() == weapon_id and get_copies(weapon_id, get_selected_tier()) == 0:
		data["selected_tier"] = best_tier(weapon_id)
	add_stat("merges", 1, false)
	save_data()
	return true


func get_selected_weapon() -> StringName:
	return StringName(data["selected_weapon"])


func get_selected_tier() -> int:
	return clampi(int(data["selected_tier"]), 1, WeaponData.MAX_TIER)


func set_selected_weapon(weapon_id: StringName, tier: int = 0) -> void:
	if not owns_weapon(weapon_id):
		return
	data["selected_weapon"] = String(weapon_id)
	var wanted := tier if tier > 0 else best_tier(weapon_id)
	data["selected_tier"] = wanted if get_copies(weapon_id, wanted) > 0 else best_tier(weapon_id)
	save_data()


## Стартовый ствол забега на выбранном тире (или пистолет, если выбор недоступен).
func get_loadout() -> WeaponData:
	var id := get_selected_weapon()
	if WeaponDB.has_weapon(id) and owns_weapon(id):
		var tier := get_selected_tier()
		if get_copies(id, tier) <= 0:
			tier = best_tier(id)
		return WeaponDB.get_weapon(id).with_tier(tier)
	return WeaponDB.get_weapon(StringName(START_WEAPON)).with_tier(1)


func _sanitize_arsenal() -> void:
	var clean := {}
	var raw: Dictionary = data["arsenal"]
	for key in raw:
		var counts = raw[key]
		if typeof(counts) != TYPE_ARRAY or not WeaponDB.has_weapon(StringName(key)):
			continue
		var fixed := [0, 0, 0, 0, 0]
		for i in mini((counts as Array).size(), WeaponData.MAX_TIER):
			if ConfigLoader.type_matches(counts[i], 0):
				fixed[i] = maxi(int(counts[i]), 0)
		if not WeaponDB.get_weapon(StringName(key)).has_tiers():
			var owned_copies := 0
			for c in fixed:
				owned_copies += int(c)
			fixed = [1 if owned_copies > 0 else 0, 0, 0, 0, 0]
		clean[String(key)] = fixed
	data["arsenal"] = clean
	if not owns_weapon(StringName(START_WEAPON)):
		add_weapon(StringName(START_WEAPON), 1, false)
	if has_blueprint(RAID_BLUEPRINT) and not owns_weapon(&"prism_blaster_v1"):
		add_weapon(&"prism_blaster_v1", 1, false)
	if not owns_weapon(get_selected_weapon()):
		data["selected_weapon"] = START_WEAPON
		data["selected_tier"] = 1


# --- Прокачка -------------------------------------------------------------------------------------

func get_perk_level(perk_id: String) -> int:
	return int((data["perks"] as Dictionary).get(perk_id, 0))


func get_perk_cost(perk_id: String) -> int:
	var perk: Dictionary = PERKS[perk_id]
	var raw := float(perk["cost"]) * pow(PERK_COST_GROWTH, get_perk_level(perk_id))
	return int(round(raw / 5.0) * 5.0)


func is_perk_maxed(perk_id: String) -> bool:
	return get_perk_level(perk_id) >= int(PERKS[perk_id]["max"])


func buy_perk(perk_id: String) -> bool:
	if not PERKS.has(perk_id) or is_perk_maxed(perk_id):
		return false
	var cost := get_perk_cost(perk_id)
	if get_nuts() < cost:
		return false
	data["nuts"] = get_nuts() - cost
	(data["perks"] as Dictionary)[perk_id] = get_perk_level(perk_id) + 1
	save_data()
	return true


func has_slot3() -> bool:
	return bool(data["slot3"])


func buy_slot3() -> bool:
	if has_slot3() or not spend_gems(SLOT3_PRICE, false):
		return false
	data["slot3"] = true
	save_data()
	return true


func get_perk_bonus(perk_id: String) -> float:
	return float(PERKS[perk_id]["step"]) * get_perk_level(perk_id)


# --- Статистика и ачивки ---------------------------------------------------------------------------

func get_stat(key: String) -> int:
	match key:
		"best_wave", "boss_kills", "raid_wins", "runs":
			return int(data[key])
	return int((data["stats"] as Dictionary).get(key, 0))


## Прибавляет счётчик и проверяет ачивки. Возвращает только что открытые.
func add_stat(key: String, amount: int = 1, save: bool = true) -> Array:
	var stats: Dictionary = data["stats"]
	stats[key] = int(stats.get(key, 0)) + amount
	var unlocked := check_achievements()
	if save:
		save_data()
	return unlocked


func is_achieved(achievement_id: String) -> bool:
	return (data["achievements"] as Array).has(achievement_id)


func check_achievements() -> Array:
	var unlocked := []
	for achievement in ACHIEVEMENTS:
		if is_achieved(achievement["id"]):
			continue
		if get_stat(achievement["stat"]) >= int(achievement["goal"]):
			(data["achievements"] as Array).append(achievement["id"])
			data["nuts"] = get_nuts() + int(achievement["nuts"])
			data["star_dust"] = get_star_dust() + int(achievement["dust"])
			unlocked.append(achievement)
			achievement_unlocked.emit(achievement)
	return unlocked


func get_achievement_progress(achievement: Dictionary) -> float:
	return clampf(float(get_stat(achievement["stat"])) / float(achievement["goal"]), 0.0, 1.0)


# --- Итоги забегов ---------------------------------------------------------------------------------

## Итоги забега Свалки. Счётчики боя (kills, crits, dashes, crates, boss_kills) уже
## накоплены вживую через add_stat() — ачивки открываются прямо в бою; здесь только монеты,
## рекорд волны, опыт аккаунта и трофейные стволы (сразу попадают в арсенал).
## summary: nuts, time, wave, kills, loot (Array [[id, tier], ...]). Возвращает {"record", "loot"}.
func record_run(summary: Dictionary) -> Dictionary:
	var nuts := int(round(maxi(int(summary.get("nuts", 0)), 0) * (1.0 + get_perk_bonus("loot") + CharacterDB.get_stat(get_character_id(), "coins") + Premium.coin_bonus())))
	var wave := int(summary.get("wave", 0))
	data["nuts"] = get_nuts() + nuts
	add_account_xp(int(round((int(summary.get("kills", 0)) + wave * 5) * (1.0 + Premium.xp_bonus()))))
	BattlePass.add_points(BattlePass.run_points(wave))
	data["runs"] = int(data["runs"]) + 1
	var is_record := wave > int(data["best_wave"])
	if is_record:
		data["best_wave"] = wave
	data["best_time"] = maxf(float(data["best_time"]), float(summary.get("time", 0.0)))
	for pair in summary.get("loot", []):
		add_weapon(StringName(pair[0]), int(pair[1]), false)
	data["star_dust"] = get_gems() + maxi(int(summary.get("gems", 0)), 0)
	for key in summary.get("blueprints", []):
		Economy.grant_shards(str(key), 1)
	var stats: Dictionary = data["stats"]
	stats["nuts_total"] = int(stats.get("nuts_total", 0)) + nuts
	quest_add("raccoon_run", 1)
	quest_add("rats", int(summary.get("kills", 0)))
	check_achievements()
	save_data()
	return {"record": is_record, "loot": summary.get("loot", [])}


## Босс побеждён — счётчик живой, чтобы ачивка открылась сразу.
func story_done(mission_id: String) -> bool:
	return bool((data["story"] as Dictionary).get(mission_id, {}).get("done", false))


func story_shards() -> int:
	var total := 0
	for entry in (data["story"] as Dictionary).values():
		if typeof(entry) == TYPE_DICTIONARY and bool(entry.get("done", false)):
			total += int(entry.get("shards", 0))
	return total


func story_complete(mission_id: String, shards: int, score: int = 0) -> void:
	var story: Dictionary = data["story"]
	var best := maxi(score, int((story.get(mission_id, {}) as Dictionary).get("best", 0)))
	story[mission_id] = {"done": true, "shards": shards, "best": best}
	save_data()


func add_boss_kill() -> void:
	data["boss_kills"] = int(data["boss_kills"]) + 1
	check_achievements()


## Начисляет награду Налёта. Возвращает {"star_dust": int, "blueprint_new": bool}.
func record_raid_victory(dragon_killed: bool) -> Dictionary:
	var dust := RAID_DUST_KILL if dragon_killed else RAID_DUST_SURVIVE
	data["star_dust"] = get_star_dust() + dust
	data["raid_wins"] = int(data["raid_wins"]) + 1
	if dragon_killed:
		data["dragon_kills"] = int(data["dragon_kills"]) + 1
	add_account_xp(RAID_WIN_XP)
	var blueprint_new := not has_blueprint(RAID_BLUEPRINT)
	if blueprint_new:
		(data["blueprints"] as Array).append(String(RAID_BLUEPRINT))
		add_weapon(&"prism_blaster_v1", 1, false)
	check_achievements()
	save_data()
	return {"star_dust": dust, "blueprint_new": blueprint_new}
