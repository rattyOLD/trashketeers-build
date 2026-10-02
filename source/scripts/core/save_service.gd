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
## Тег DeV/Insider пришёл с сервера или снят: меню перерисовывает ник и кнопку тестера.
signal badge_changed

const STORAGE_KEY := "battle_raccoon_save_v1"
const BADGE_KEY := "trk_badge"
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
	"story_log": {},
	"nell_order": {},
	"story_best": {},
	"story_choice": {},
	"story_resume": {},
	"recent_stickers": [],
	"friends": {},
	"invite_used": "",
	"invite_paid": [],
	"raid_wins": 0,
	"dragon_kills": 0,
	"blueprints": [],
	"selected_weapon": START_WEAPON,
	"selected_tier": 1,
	"arsenal": {},
	"perks": {},
	"line_votes": {},
	"acct_hint": false,
	"camp_pack": {},
	"line_votes_on": true,
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
	"eco_fps": false,
	"haptics": true,
	"minimap": true,
	"show_fps": false,
	"min_hud": false,
	"target_nearest": false,
	"tips_off": false,
	"tips_seen": [],
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
	"whatsnew_seen": "",
	"coop_mute_until": 0,
	"coop_muted_codes": [],
	"coop_recent": [],
	"coop_rating": 0,
	"coop_tier": "Ржавый",
	"survival_intro_seen": false,
	"survival_unlock_seen": false,
}

const CLOUD_DEBOUNCE := 2.5
## Ежедневная награда: серия из 7 дней, пропуск дня сбрасывает серию. Дни 4 и 7 — ещё и неонит.
const DAILY_REWARDS := [50, 75, 100, 150, 200, 300, 500]
const DAILY_GEMS := {4: 2, 7: 6}
## Ежедневные задания Сетки: прогресс сбрасывается в новый день (UTC).
const QUESTS := [
	{"id": "raccoon_run", "game": "raccoon", "title": "Сыграй забег в Trash Squad", "goal": 1, "reward": 60},
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
	"power": {"title": "Сила", "description": "+4% урона любым стволом", "step": 0.04, "max": 10, "cost": 120, "icon": "🔫", "theme": "Ржавый ствол — тоже ствол"},
	"stamina": {"title": "Выносливость", "description": "+12 к максимуму здоровья", "step": 12.0, "max": 10, "cost": 100, "icon": "🥫", "theme": "Консервы из мусорки"},
	"armor": {"title": "Броня из жести", "description": "-3% получаемого урона", "step": 0.03, "max": 10, "cost": 140, "icon": "🛡", "theme": "Крышка от бака"},
	"eye": {"title": "Меткий глаз", "description": "+1% шанса крита", "step": 0.01, "max": 10, "cost": 180, "icon": "🎯", "theme": "Очки сварщика"},
	"boots": {"title": "Кроссовки", "description": "+2% скорости бега", "step": 0.02, "max": 8, "cost": 150, "icon": "👟", "theme": "Найдены в контейнере"},
	"magnet": {"title": "Магнит", "description": "+8% радиуса подбора добычи", "step": 0.08, "max": 8, "cost": 130, "icon": "🧲", "theme": "Магнит со свалки"},
	"loot": {"title": "Хапуга", "description": "+4% монет за забег", "step": 0.04, "max": 10, "cost": 220, "icon": "💰", "theme": "Карманы побольше"},
	"vest": {"title": "Бронежилет", "description": "+1 попадание, которое жилет гасит целиком (раз за забег)", "step": 1.0, "max": 3, "cost": 450, "icon": "🦺", "theme": "Жилет с прошлого сезона. Пули ещё в нём", "survival_only": true},
	"drone": {"title": "Дрон-спутник", "description": "Стартовый дрон кружит вокруг и стреляет по крысам", "step": 1.0, "max": 2, "cost": 700, "icon": "🛸", "theme": "Собран из вентилятора и злости", "survival_only": true},
	"logistics": {"title": "Логистика", "description": "+8% опыта в забеге", "step": 0.08, "max": 8, "cost": 170, "icon": "📦", "theme": "Нэлл всё записывает и прокачивает", "survival_only": true},
	"headstart": {"title": "Разгон", "description": "Старт забега с +1 уровнем и выбором усиления", "step": 1.0, "max": 2, "cost": 650, "icon": "🚀", "theme": "Пропусти скучное начало", "survival_only": true},
	"cash": {"title": "Стартовая касса", "description": "+40 орехов в начале забега (на реролл и усиления)", "step": 40.0, "max": 5, "cost": 140, "icon": "💵", "theme": "Заначка в носке", "survival_only": true},
	"radar": {"title": "Чуткий радар", "description": "Миникарта подсвечивает элитных врагов и редкие ящики", "step": 1.0, "max": 2, "cost": 500, "icon": "📡", "theme": "Антенна из зонтика", "survival_only": true},
	"reroll": {"title": "Реролл", "description": "+1 бесплатный реролл улучшений за забег", "step": 1.0, "max": 3, "cost": 600, "icon": "🎲", "theme": "Крысиные кости"},
}
## Удалённые перки: уровни возвращаются монетами при загрузке сохранения.
const REMOVED_PERKS := {"rate": 160, "dasher": 200, "patch": 260, "haggle": 300}
const HERO_MAX_LEVEL := 8
const HERO_HP_PER_LEVEL := 0.04
const HERO_DAMAGE_PER_LEVEL := 0.03
const PERK_COST_GROWTH := 1.25
## Общий множитель награды за забег: экономика была слишком скупой.
const RUN_PAYOUT := 1.4
const SLOT3_PRICE := 250

## stats — ключи в data["stats"] (суммируются), goal — порог; один заказ на день для сюжета и выживания.
const NELL_ORDERS_PER_DAY := 8
const NELL_ORDERS := [
	{"id": "kills", "title": "Убей 120 врагов", "stats": ["kills"], "goal": 120, "nuts": 350, "dust": 2},
	{"id": "kills_big", "title": "Убей 300 врагов", "stats": ["kills"], "goal": 300, "nuts": 700, "dust": 4},
	{"id": "dash", "title": "Сделай 60 рывков", "stats": ["dashes"], "goal": 60, "nuts": 300, "dust": 2},
	{"id": "crit", "title": "Нанеси 80 критов", "stats": ["crits"], "goal": 80, "nuts": 350, "dust": 2},
	{"id": "boss", "title": "Победи босса", "stats": ["boss_kills", "story_missions"], "goal": 1, "nuts": 800, "dust": 5},
	{"id": "crates", "title": "Разбей 5 ящиков с оружием", "stats": ["crates"], "goal": 5, "nuts": 400, "dust": 2},
]
const ACHIEVEMENTS := [
	{"id": "first_blood", "title": "Первая кровь", "description": "Победить первую крысу. Она была чьей-то мамой, но это не точно", "stat": "kills", "goal": 1, "nuts": 20, "dust": 0},
	{"id": "exterminator", "title": "Дератизатор", "description": "Победить 300 крыс. Профсоюз уже в курсе", "stat": "kills", "goal": 300, "nuts": 150, "dust": 0},
	{"id": "rat_plague", "title": "Чума для чумы", "description": "Победить 2000 крыс. Чума завидует", "stat": "kills", "goal": 2000, "nuts": 600, "dust": 5},
	{"id": "wave_5", "title": "Пять волн", "description": "Дойти до 5-й волны и не расплакаться", "stat": "best_wave", "goal": 5, "nuts": 80, "dust": 0},
	{"id": "wave_10", "title": "Ветеран свалки", "description": "Дойти до 10-й волны. Свалка тебя уважает, но не любит", "stat": "best_wave", "goal": 10, "nuts": 250, "dust": 5},
	{"id": "king_slayer", "title": "Цареубийца", "description": "Победить Короля Хлама. Корона теперь дешевле", "stat": "boss_kills", "goal": 1, "nuts": 200, "dust": 0},
	{"id": "dasher", "title": "Шустрый", "description": "Сделать 100 рывков. Ноги жалуются, енот нет", "stat": "dashes", "goal": 100, "nuts": 60, "dust": 0},
	{"id": "crate_hunter", "title": "Охотник за ящиками", "description": "Разбить 15 ящиков с оружием. Подарки есть подарки", "stat": "crates", "goal": 15, "nuts": 120, "dust": 0},
	{"id": "merger", "title": "Кузнец", "description": "Сделать первый Merge оружия. Два плохих ствола лучше одного", "stat": "merges", "goal": 1, "nuts": 100, "dust": 0},
	{"id": "rich", "title": "Мешок монет", "description": "Собрать 1000 монет. Карманы довольны", "stat": "nuts_total", "goal": 1000, "nuts": 0, "dust": 5},
	{"id": "dragon_raid", "title": "Тёплый приём", "description": "Победить Хладгора. Он замёрз, ты нет", "stat": "raid_wins", "goal": 1, "nuts": 150, "dust": 5},
	{"id": "raid_flawless", "title": "Без единой снежинки", "description": "Победить Хладгора, ни разу не замёрзнув. Ты точно енот?", "stat": "raid_flawless", "goal": 1, "nuts": 300, "dust": 10, "hidden": true},
	{"id": "crit_master", "title": "В яблочко", "description": "Нанести 500 критов. Крысы называют это «ой»", "stat": "crits", "goal": 500, "nuts": 120, "dust": 0},
	{"id": "toxic_mask", "title": "Противогаз", "description": "Победить 100 Токсичных крыс. Дышать теперь можно", "stat": "k_toxic_rat", "goal": 100, "nuts": 180, "dust": 0},
	{"id": "mad_calm", "title": "Успокоительное", "description": "Победить 100 Бешеных крыс. Таблетки не понадобились", "stat": "k_dash_rat", "goal": 100, "nuts": 180, "dust": 0},
	{"id": "punk_dead", "title": "Панк-рок жив, но не они", "description": "Победить 500 Скрэппи. Панк-рок слегка притих", "stat": "k_rat_punk", "goal": 500, "nuts": 260, "dust": 0},
	{"id": "sniper_hunt", "title": "Сам себе снайпер", "description": "Победить 60 Свиней-снайперов. Они целились, ты нет", "stat": "k_pig_sniper", "goal": 60, "nuts": 240, "dust": 2},
	{"id": "no_repair", "title": "Ремонту не подлежит", "description": "Победить 80 Свиней-механиков. Гарантия аннулирована", "stat": "k_pig_mechanic", "goal": 80, "nuts": 240, "dust": 2},
	{"id": "hangover", "title": "Похмелье Барона", "description": "Победить Пивного Барона. Бар закрыт, пиво разлито", "stat": "k_beer_baron", "goal": 1, "nuts": 300, "dust": 3},
	{"id": "nationalize", "title": "Национализация", "description": "Победить Свинью-Магната. Рынок в панике", "stat": "k_pig_magnate", "goal": 1, "nuts": 400, "dust": 4},
	{"id": "marauder_catch", "title": "Ловец мародёров", "description": "Поймать 25 мародёров. Свалка вернула своё", "stat": "marauders", "goal": 25, "nuts": 220, "dust": 2},
	{"id": "regular", "title": "Завсегдатай свалки", "description": "Сыграть 25 забегов. Это уже диагноз", "stat": "runs", "goal": 25, "nuts": 300, "dust": 3},
	{"id": "perk_junkie", "title": "Билд на ходу", "description": "Выбрать 100 улучшений. Ты любишь выбирать", "stat": "picks", "goal": 100, "nuts": 200, "dust": 0},
	{"id": "chest_lord", "title": "Владыка сундуков", "description": "Открыть 20 сундуков. Азарт, как он есть", "stat": "chests", "goal": 20, "nuts": 250, "dust": 3},
	{"id": "blacksmith_pro", "title": "Мастер горна", "description": "Сделать 10 Merge. Кузнец гордится", "stat": "merges", "goal": 10, "nuts": 300, "dust": 3},
	{"id": "dash_king", "title": "Молния помоек", "description": "Сделать 1000 рывков. Енот уже не бегает, он телепортируется", "stat": "dashes", "goal": 1000, "nuts": 350, "dust": 3},
	{"id": "rescuer", "title": "Спасатель", "description": "Освободить 10 пленников. Они сказали «спасибо». Некоторые", "stat": "story_rescued", "goal": 10, "nuts": 200, "dust": 2},
	{"id": "liberator", "title": "Освободитель", "description": "Освободить 40 пленников. Клетки в панике", "stat": "story_rescued", "goal": 40, "nuts": 700, "dust": 6},
	{"id": "all_free", "title": "Никто не забыт", "description": "Освободить всех пленников миссии. Никто не забыт, даже крысы", "stat": "story_all_rescued", "goal": 1, "nuts": 250, "dust": 3},
	{"id": "untouchable", "title": "Неприкасаемый", "description": "Пройти миссию без единого урона. Нэлл не поверила, посмотрела запись", "stat": "story_flawless", "goal": 1, "nuts": 600, "dust": 8, "hidden": true},
	{"id": "exterminator_pro", "title": "Санэпидемстанция", "description": "Победить 10000 врагов. Это уже геноцид, но мультяшный", "stat": "kills", "goal": 10000, "nuts": 1500, "dust": 15},
	{"id": "wave_20", "title": "Двадцать волн", "description": "Дойти до 20-й волны. Ты точно не бот?", "stat": "best_wave", "goal": 20, "nuts": 500, "dust": 8},
	{"id": "wave_30", "title": "Хозяин биома", "description": "Дойти до 30-й волны. Хозяин биома, поздравляю", "stat": "best_wave", "goal": 30, "nuts": 900, "dust": 12},
	{"id": "tycoon", "title": "Мусорный магнат", "description": "Собрать 10000 монет. Свалка теперь на тебя работает", "stat": "nuts_total", "goal": 10000, "nuts": 0, "dust": 10},
	{"id": "crit_god", "title": "Только крит", "description": "Нанести 5000 критов. Крысы называют тебя «ой на ножках»", "stat": "crits", "goal": 5000, "nuts": 600, "dust": 6},
	{"id": "dirty_martyr", "title": "Мученик помойки", "rank": "Мученик", "description": "Умереть 10 раз. Помойка помнит каждое падение", "stat": "deaths", "goal": 10, "nuts": 100, "dust": 1},
	{"id": "dirty_undying", "title": "Почти бессмертный", "rank": "Бессмертный", "description": "Умереть 50 раз. Бессмертный, просто очень неудачливый", "stat": "deaths", "goal": 50, "nuts": 400, "dust": 4},
	{"id": "dirty_racket", "title": "Рэкет по понятиям", "rank": "Рэкетир", "description": "Ограбить 10 боссов. Нэлл ведёт учёт, процент её", "stat": "robbed", "goal": 10, "nuts": 250, "dust": 3},
	{"id": "dirty_kind", "title": "Добрый енот", "rank": "Добряк", "description": "Пощадить 10 боссов. Они тебя запомнят, но не добрым словом", "stat": "spared", "goal": 10, "nuts": 250, "dust": 3},
	{"id": "dirty_pigeon", "title": "Голубятник", "rank": "Голубятник", "description": "Сбить 50 Голубей-бомбардиров. Статуи города благодарны", "stat": "k_pigeon_bomber", "goal": 50, "nuts": 220, "dust": 2},
	{"id": "dirty_sanitar", "title": "Санитар свалки", "rank": "Санитар", "description": "Победить 150 Мусорных комков. Теперь они меньше, но их больше", "stat": "k_trash_blob", "goal": 150, "nuts": 220, "dust": 2},
	{"id": "dirty_tax", "title": "Налоговая проверка", "rank": "Налоговая", "description": "Победить 30 Инкассаторов. Декларацию сдавать некому", "stat": "k_cash_collector", "goal": 30, "nuts": 260, "dust": 3},
	{"id": "dirty_pirate", "title": "Гроза морей", "rank": "Гроза морей", "description": "Победить 5 Пиратов Мусорных Морей. Море мусора, а гроза ты", "stat": "k_sea_pirate", "goal": 5, "nuts": 260, "dust": 3},
	{"id": "dirty_masochist", "title": "Любитель острых ощущений", "rank": "Мазохист", "description": "Сыграть 10 забегов с модификатором. Тебе мало, да?", "stat": "mod_runs", "goal": 10, "nuts": 300, "dust": 4},
	{"id": "dirty_wanted", "title": "Враг Бюро", "rank": "Враг Бюро", "description": "Дойти до пяти звёзд розыска 3 раза. Шеф уже выучил твой адрес", "stat": "wanted_max", "goal": 3, "nuts": 400, "dust": 5},
	{"id": "dirty_scars", "title": "Карта сокровищ", "rank": "Шрамированный", "description": "Потерять 10 жизней в сюжете. Живого места нет, зато характер", "stat": "scars", "goal": 10, "nuts": 250, "dust": 3},
	{"id": "dirty_bossdown", "title": "Боссодав", "rank": "Боссодав", "description": "Победить 25 боссов. Они уже собираются в профсоюз", "stat": "boss_kills", "goal": 25, "nuts": 500, "dust": 6},
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


func _refund_removed_perks() -> void:
	var perks: Dictionary = data["perks"]
	for perk_id in REMOVED_PERKS:
		if not perks.has(perk_id):
			continue
		for i in int(perks[perk_id]):
			data["nuts"] = int(data["nuts"]) + int(round(float(REMOVED_PERKS[perk_id]) * pow(PERK_COST_GROWTH, i) / 5.0) * 5.0)
		perks.erase(perk_id)


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
	_refund_retired_weapons()
	_sanitize_arsenal()
	_refund_removed_perks()
	KnifeProgress.sanitize(data)
	data["nickname"] = clean_nickname(str(data["nickname"]))
	if str(data["nickname"]).length() < 2:
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


func camp_has(item_id: String) -> bool:
	return bool((data["camp_pack"] as Dictionary).get(item_id, false))


func camp_buy(item_id: String, cost: int) -> bool:
	if camp_has(item_id) or get_nuts() < cost:
		return false
	data["nuts"] = get_nuts() - cost
	(data["camp_pack"] as Dictionary)[item_id] = true
	save_data()
	return true


func camp_refund(item_id: String, cost: int) -> void:
	if not camp_has(item_id):
		return
	(data["camp_pack"] as Dictionary).erase(item_id)
	data["nuts"] = get_nuts() + cost
	save_data()


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


## Лимит кадров: 30, 60 или 120. Старая «Экономия заряда» = 30.
func get_fps_cap() -> int:
	var cap := int(data.get("fps_cap", 0))
	if cap == 0:
		return 30 if bool(data.get("eco_fps", false)) else 60
	return cap if cap in [30, 60, 120] else 60


func set_fps_cap(cap: int) -> void:
	data["fps_cap"] = cap if cap in [30, 60, 120] else 60
	save_data()
	apply_quality()


func set_quality(q: int) -> void:
	data["quality"] = clampi(q, 0, 2)
	save_data()
	apply_quality()


func apply_quality() -> void:
	var caps := [1.5, 2.0, 2.5] if Platform.is_touch() else [1.25, 2.0, 3.0]
	Platform.set_render_cap(caps[get_quality()])
	Engine.max_fps = get_fps_cap()


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


# --- Друзья: визитки без сервера ---------------------------------------------------------------------

const INVITE_PREFIX := "INV-"
const INVITE_COINS := 300
const INVITE_GEMS := 15
const INVITE_PAID_MAX := 10
const FRIENDS_MAX := 50


func story_done_ids() -> Array:
	var ids: Array = []
	for mission_id in (data["story"] as Dictionary):
		if story_done(str(mission_id)):
			ids.append(str(mission_id))
	ids.sort()
	return ids


func invite_code() -> String:
	return INVITE_PREFIX + get_player_id()


func card_info() -> Dictionary:
	return {
		"id": get_player_id(), "fc": Cloud.friend_code, "n": get_nickname(), "c": get_character_id(), "s": get_selected_skin(),
		"lv": get_account_level(), "w": get_stat("best_wave"), "sh": story_shards(), "m": story_done_ids(),
		"bk": int(data["boss_kills"]), "ins": get_insider(), "inv": str(data["invite_used"]), "sc": data["story_best"],
	}


func backup_code() -> String:
	save_data()
	var raw := JSON.stringify(data).to_utf8_buffer()
	return "TRS1.%d.%s" % [raw.size(), Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))]


## Разбор кода сохранения без применения: пустой словарь, если код испорчен.
static func parse_backup(code: String) -> Dictionary:
	var parts := code.strip_edges().split(".")
	if parts.size() != 3 or parts[0] != "TRS1" or not parts[1].is_valid_int():
		return {}
	var size := int(parts[1])
	if size <= 0 or size > 600000:
		return {}
	var packed := Marshalls.base64_to_raw(parts[2])
	if packed.is_empty():
		return {}
	var raw := packed.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8()) if not raw.is_empty() else null
	return parsed as Dictionary if parsed is Dictionary else {}


## Условная «продвинутость» сохранения: чем больше, тем богаче прогресс. Нужна, чтобы пустое устройство не затёрло облако.
static func score_of(d: Dictionary) -> int:
	var stats: Variant = d.get("stats", {})
	var nuts_total := int((stats as Dictionary).get("nuts_total", 0)) if stats is Dictionary else 0
	# Сюжет весит больше всего: пройденная миссия и найденные осколки не должны проиграть «пустому» устройству.
	var story_points := 0
	var story: Variant = d.get("story", {})
	if story is Dictionary:
		for entry in (story as Dictionary).values():
			if entry is Dictionary:
				story_points += (2000 if bool((entry as Dictionary).get("done", false)) else 0) + int((entry as Dictionary).get("shards", 0)) * 200
	var choices: Variant = d.get("story_choice", {})
	if choices is Dictionary:
		story_points += (choices as Dictionary).size() * 100
	return int(d.get("account_xp", 0)) + int(d.get("runs", 0)) * 100 + int(d.get("best_wave", 0)) * 50 + int(d.get("boss_kills", 0)) * 300 + nuts_total / 10 + story_points


func progress_score() -> int:
	return score_of(data)


func restore_backup(code: String) -> bool:
	var parts := code.strip_edges().split(".")
	if parts.size() != 3 or parts[0] != "TRS1" or not parts[1].is_valid_int():
		return false
	var size := int(parts[1])
	if size <= 0 or size > 600000:
		return false
	var packed := Marshalls.base64_to_raw(parts[2])
	if packed.is_empty():
		return false
	var raw := packed.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return false
	var text := raw.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("nickname"):
		return false
	_apply_text(text)
	data["saved_at"] = int(Time.get_unix_time_from_system())
	Platform.storage_set(STORAGE_KEY, JSON.stringify(data))
	changed.emit()
	reloaded.emit()
	return true


## Публичная статистика для профиля друзей на сервере.
func public_stats() -> Dictionary:
	return {
		"lv": get_account_level(), "c": get_character_id(), "s": get_selected_skin(), "sh": story_shards(), "m": story_done_ids(),
		"bk": int(data["boss_kills"]), "w": get_stat("best_wave"), "k": get_stat("kills"), "r": int(data["runs"]), "t": float(data["best_time"]),
	}


func card_code() -> String:
	var raw := JSON.stringify(card_info()).to_utf8_buffer()
	return "TRF1.%d.%s" % [raw.size(), Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))]


## Ссылка на игру, по которой друг добавляется автоматически: визитка зашита в параметр адреса.
func card_link() -> String:
	var base := Platform.page_url()
	if base.is_empty():
		return ""
	return "%s?card=%s" % [base, card_code().uri_encode()]


## Короткая ссылка для друзей (по серверному ID) или, пока ID нет, ссылка с зашитой визиткой.
func card_qr_text() -> String:
	var base := Platform.page_url()
	if base.is_empty():
		return ""
	if Cloud.has_code():
		return "%s?f=%s" % [base, Cloud.friend_code]
	return card_link()


func get_friends() -> Array:
	var list: Array = (data["friends"] as Dictionary).values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("added", 0)) > int(b.get("added", 0)))
	return list


func remove_friend(friend_id: String) -> void:
	(data["friends"] as Dictionary).erase(friend_id)
	save_data()


## "ok", "bonus" (друг пришёл по твоему приглашению, награда выдана), "self", "bad".
static func clean_scores(raw: Variant) -> Dictionary:
	var result := {}
	if typeof(raw) == TYPE_DICTIONARY:
		for key in raw:
			result[str(key).substr(0, 12)] = clampi(int(raw[key]), 0, 99999999)
	return result


func add_friend(code: String) -> String:
	var parts := code.strip_edges().split(".")
	if parts.size() != 3 or parts[0] != "TRF1" or not parts[1].is_valid_int():
		return "bad"
	var packed := Marshalls.base64_to_raw(parts[2])
	if packed.is_empty() or int(parts[1]) <= 0 or int(parts[1]) > 4096:
		return "bad"
	var raw := packed.decompress(int(parts[1]), FileAccess.COMPRESSION_DEFLATE)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8()) if not raw.is_empty() else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return "bad"
	var card: Dictionary = parsed
	var friend_id := str(card.get("id", "")).substr(0, 24)
	if friend_id.is_empty():
		return "bad"
	if friend_id == get_player_id():
		return "self"
	var friends: Dictionary = data["friends"]
	if not friends.has(friend_id) and friends.size() >= FRIENDS_MAX:
		return "bad"
	var clean := {
		"id": friend_id, "n": str(card.get("n", "Енот")).substr(0, 16), "c": str(card.get("c", "")), "s": str(card.get("s", "classic")),
		"lv": int(card.get("lv", 1)), "w": int(card.get("w", 0)), "sh": int(card.get("sh", 0)), "bk": int(card.get("bk", 0)),
		"ins": int(card.get("ins", -1)), "sc": clean_scores(card.get("sc", {})), "m": card.get("m", []) if typeof(card.get("m", [])) == TYPE_ARRAY else [],
		"added": int((friends.get(friend_id, {}) as Dictionary).get("added", Time.get_unix_time_from_system())),
	}
	friends[friend_id] = clean
	var result := "ok"
	var paid: Array = data["invite_paid"]
	if str(card.get("inv", "")) == invite_code() and not paid.has(friend_id) and paid.size() < INVITE_PAID_MAX:
		paid.append(friend_id)
		add_coins(INVITE_COINS)
		add_gems(INVITE_GEMS, false)
		result = "bonus"
	save_data()
	return result


## "ok", "used" (приглашение уже принято), "self", "bad".
func use_invite(code: String) -> String:
	var clean := code.strip_edges().to_upper()
	if not clean.begins_with(INVITE_PREFIX) or clean.length() <= INVITE_PREFIX.length() or clean.length() > 32:
		return "bad"
	if not str(data["invite_used"]).is_empty():
		return "used"
	if clean == invite_code():
		return "self"
	data["invite_used"] = clean
	add_coins(INVITE_COINS)
	add_gems(INVITE_GEMS, false)
	save_data()
	return "ok"


# --- Ник ------------------------------------------------------------------------------------------

func get_nickname() -> String:
	return data["nickname"]


## Уровень тега: 0 — DeV, 1 — Insider, -1 — Tester. Хранится только то, что подтвердил сервер.
func get_insider() -> int:
	var raw := Platform.storage_get(BADGE_KEY)
	return int(raw) if raw in ["0", "1"] else -1


func is_dev() -> bool:
	return get_insider() == 0


func set_badge_level(level: int) -> void:
	var before := get_insider()
	if level in [0, 1]:
		Platform.storage_set(BADGE_KEY, str(level))
	else:
		Platform.storage_set(BADGE_KEY, "")
	if get_insider() != before:
		badge_changed.emit()


func get_badge() -> String:
	return Insider.badge_of(get_insider())


## Ник с плашкой статуса — для меню и таблички над Енотом.
func unlocked_ranks() -> Array[String]:
	var list: Array[String] = []
	for achievement in ACHIEVEMENTS:
		if achievement.has("rank") and is_achieved(achievement["id"]):
			list.append(str(achievement["id"]))
	for key in Cosmetics.owned():
		if Cosmetics.kind_of(str(key)) == "title":
			list.append(str(key))
	return list


func rank_text(id: String) -> String:
	if Cosmetics.is_cosmetic(id):
		return Cosmetics.title_of(id) if Cosmetics.owns(id) else ""
	if not is_achieved(id):
		return ""
	for achievement in ACHIEVEMENTS:
		if achievement["id"] == id:
			return str(achievement.get("rank", ""))
	return ""


func cycle_rank() -> void:
	var order: Array[String] = ["-"]
	order.append_array(unlocked_ranks())
	var current := str(data.get("rank_id", ""))
	data["rank_id"] = order[(order.find(current) + 1) % order.size()]
	save_data()


func get_rank() -> String:
	var id := str(data.get("rank_id", ""))
	return "" if id.is_empty() or id == "-" else rank_text(id)


func get_display_nickname() -> String:
	var badge := get_badge()
	var shown := get_nickname() if badge.is_empty() else "%s %s" % [badge, get_nickname()]
	var rank := get_rank()
	return shown if rank.is_empty() else "%s · %s" % [shown, rank]


## Всё сохранение одной строкой: копируется в буфер и переносится на другое устройство.
func export_code() -> String:
	return backup_code()


func import_code(code: String) -> bool:
	return restore_backup(code)


## ID игрока: номер инсайдера, Telegram-аккаунт, если запущено в Telegram, иначе постоянный локальный номер.
func get_player_id() -> String:
	if is_dev():
		return "000"
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


## Ник: только буквы, цифры, «_», «-» и «.», без пробелов, не длиннее NICKNAME_MAX.
static func clean_nickname(nick: String) -> String:
	var out := ""
	for i in nick.length():
		var ch := nick.substr(i, 1)
		var code := ch.unicode_at(0)
		var is_letter := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 0x410 and code <= 0x44F) or code == 0x401 or code == 0x451 or code == 0x406 or code == 0x456 or code == 0x404 or code == 0x454 or code == 0x407 or code == 0x457
		if is_letter or ch == "_" or ch == "-" or ch == ".":
			out += ch
		if out.length() >= NICKNAME_MAX:
			break
	return out


func set_nickname(nick: String) -> void:
	var clean := clean_nickname(nick)
	data["nickname"] = clean if clean.length() >= 2 else random_nickname()
	save_data()


static func random_nickname() -> String:
	return ("%s%s%d" % [NICK_PREFIXES.pick_random(), NICK_ROOTS.pick_random(), randi_range(1, 99)]).left(NICKNAME_MAX)


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


## Скины временно убраны из игры (раздел «Скоро»): всегда «Классика», купленные и выбранные не применяются.
func get_selected_skin() -> String:
	return "classic"


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


## Оружие, снятое с выдачи: копии конвертируются в орехи (цена качества за каждую копию, T2 = 2 копии и т.д.).
const RETIRED_WEAPONS := {"rail_needle_v1": "epic"}


func _refund_retired_weapons() -> void:
	var raw: Variant = data.get("arsenal", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for key in RETIRED_WEAPONS:
		if not (raw as Dictionary).has(key):
			continue
		var copies := 0
		var counts: Variant = (raw as Dictionary)[key]
		if typeof(counts) == TYPE_ARRAY:
			for i in (counts as Array).size():
				copies += int(counts[i]) * (1 << i)
		data["nuts"] = int(data["nuts"]) + copies * int(Economy.DUPLICATE_COINS.get(RETIRED_WEAPONS[key], 150))
		(raw as Dictionary).erase(key)
		if str(data.get("selected_weapon", "")) == key:
			data["selected_weapon"] = START_WEAPON


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
			if achievement.has("rank"):
				data["rank_id"] = achievement["id"]
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
	var boost_coins := 0.0 if int(data.get("boost_coins", 0)) <= 0 else Cosmetics.BOOST_COINS_BONUS
	var nuts := int(round(maxi(int(summary.get("nuts", 0)), 0) * RUN_PAYOUT * (1.0 + get_perk_bonus("loot") + CharacterDB.get_stat(get_character_id(), "coins") + Premium.coin_bonus() + boost_coins)))
	var wave := int(summary.get("wave", 0))
	data["nuts"] = get_nuts() + nuts
	add_account_xp(int(round((int(summary.get("kills", 0)) + wave * 5) * (1.0 + Premium.xp_bonus()))))
	BattlePass.add_points(BattlePass.run_points(wave))
	Cosmetics.consume_boosts()
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
	stats["time_played"] = int(stats.get("time_played", 0)) + int(float(summary.get("time", 0.0)))
	var hero_key := "hero_" + get_character_id()
	stats[hero_key] = int(stats.get(hero_key, 0)) + 1
	quest_add("raccoon_run", 1)
	quest_add("rats", int(summary.get("kills", 0)))
	check_achievements()
	save_data()
	Cloud.queue_upload()
	return {"record": is_record, "loot": summary.get("loot", [])}


## Босс побеждён — счётчик живой, чтобы ачивка открылась сразу.
## Заказ Нэлл на сегодня: один в день для всех режимов, счёт от суммы счётчиков на начало дня.
func _order_total(spec: Dictionary) -> int:
	var total := 0
	for stat in spec["stats"]:
		total += get_stat(str(stat))
	return total


func nell_order() -> Dictionary:
	var order: Dictionary = data.get("nell_daily", {})
	if int(order.get("day", -1)) != today():
		var index := absi((today() + get_player_id().hash()) % NELL_ORDERS.size())
		order = {"day": today(), "idx": index, "base": _order_total(NELL_ORDERS[index]), "done": false}
		data["nell_daily"] = order
	var spec: Dictionary = NELL_ORDERS[clampi(int(order["idx"]), 0, NELL_ORDERS.size() - 1)]
	var progress := clampi(_order_total(spec) - int(order["base"]), 0, int(spec["goal"]))
	return {"title": spec["title"], "goal": spec["goal"], "progress": progress, "done": bool(order["done"]), "nuts": spec["nuts"], "dust": spec["dust"]}


## Возвращает заказ, если он только что выполнен (награда выдаётся здесь), иначе пустой словарь.
func nell_order_tick() -> Dictionary:
	var info := nell_order()
	if bool(info["done"]) or int(info["progress"]) < int(info["goal"]):
		return {}
	var daily: Dictionary = data["nell_daily"]
	add_coins(int(info["nuts"]))
	add_gems(int(info["dust"]), false)
	# Выполненный заказ сразу заменяется новым (не больше NELL_ORDERS_PER_DAY в день, чтобы не раздувать награды).
	var finished := int(daily.get("n", 0)) + 1
	daily["n"] = finished
	if finished < NELL_ORDERS_PER_DAY:
		var next_index := (int(daily["idx"]) + 1) % NELL_ORDERS.size()
		daily["idx"] = next_index
		daily["base"] = _order_total(NELL_ORDERS[next_index])
		daily["done"] = false
	else:
		daily["done"] = true
	save_data()
	return info


## Строка для экрана поражения: друг, которого только что обогнали, или ближайший, до кого не дотянул.
func friend_wave_line(wave: int, previous_best: int) -> String:
	var passed: Dictionary = {}
	var ahead: Dictionary = {}
	for friend: Dictionary in get_friends():
		var w := int(friend.get("w", 0))
		if w <= 0:
			continue
		if w <= wave:
			var fresh := w > previous_best
			var better := passed.is_empty() or (fresh and not bool(passed["fresh"])) or (fresh == bool(passed["fresh"]) and w > int(passed["w"]))
			if better:
				passed = {"n": str(friend.get("n", "Друг")), "w": w, "fresh": fresh}
		elif ahead.is_empty() or w < int(ahead["w"]):
			ahead = {"n": str(friend.get("n", "Друг")), "w": w}
	if not passed.is_empty() and bool(passed["fresh"]):
		return "Только что обошёл друга %s: у него %d волн, у тебя %d. Передавай привет." % [passed["n"], passed["w"], wave]
	if not ahead.is_empty():
		return "До рекорда друга %s не хватило %d волн (у него %d)." % [ahead["n"], int(ahead["w"]) - wave, ahead["w"]]
	if not passed.is_empty():
		return "Друг %s с рекордом %d волн остался позади. Все остальные тоже." % [passed["n"], passed["w"]]
	return ""


func friend_best(mission_id: String) -> Dictionary:
	var best := {}
	for friend in (data["friends"] as Dictionary).values():
		var scores: Dictionary = (friend as Dictionary).get("sc", {})
		var value := int(scores.get(mission_id, 0))
		if value > int(best.get("score", 0)):
			best = {"name": str(friend.get("n", "Друг")), "score": value}
	return best


func record_story_best(mission_id: String, score: int) -> void:
	var best: Dictionary = data["story_best"]
	best[mission_id] = maxi(score, int(best.get(mission_id, 0)))


## Чекпоинт сюжетной миссии: продолжить после вылета, сворачивания или выхода. Живёт неделю.
const STORY_RESUME_MAX_AGE := 7 * 24 * 3600
var resume_requested := false


func story_resume(mission_id: String) -> Dictionary:
	var d: Dictionary = data.get("story_resume", {})
	if str(d.get("mission", "")) != mission_id:
		return {}
	if int(Time.get_unix_time_from_system()) - int(d.get("saved", 0)) > STORY_RESUME_MAX_AGE:
		return {}
	return d


func set_story_resume(d: Dictionary) -> void:
	data["story_resume"] = d
	save_data()


func clear_story_resume() -> void:
	if not (data.get("story_resume", {}) as Dictionary).is_empty():
		data["story_resume"] = {}
		save_data()


func story_choice(mission_id: String) -> String:
	return str((data["story_choice"] as Dictionary).get(mission_id, ""))


func set_story_choice(mission_id: String, value: String) -> void:
	(data["story_choice"] as Dictionary)[mission_id] = value
	save_data()


func log_dialog(mission_id: String, key: String) -> void:
	var log: Dictionary = data["story_log"]
	var id := "%s:%s" % [mission_id, key]
	if not log.has(id):
		log[id] = true
		save_data()


func has_dialog(mission_id: String, key: String) -> bool:
	return (data["story_log"] as Dictionary).has("%s:%s" % [mission_id, key])


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
	record_story_best(mission_id, best)
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
