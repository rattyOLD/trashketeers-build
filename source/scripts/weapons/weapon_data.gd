class_name WeaponData
extends RefCounted
## Read-only конфиг оружия. Базовые экземпляры создаёт только WeaponDB.
## Прокачка в забеге никогда не меняет базовый конфиг: with_run_stats() возвращает копию.
## Производные значения (радианы, модуляция, масштаб спрайта) считаются один раз при загрузке.

const DEFAULTS := {
	"display_name": "",
	"short_name": "",
	"enemy_only": false,
	"unlock_blueprint": "",
	"fire_sound": "",
	"damage": 10.0,
	"fire_rate": 0.25,
	"bullet_speed": 600.0,
	"bullet_sprite": "",
	"bullet_scale": 1.0,
	"piercing": false,
	"ricochet_count": 0,
	"ricochet_range": 260.0,
	"homing": 0.0,
	"homing_time": 0.8,
	"spin": 0.0,
	"effect_color": "#FFFFFF",
	"tint_bullet": false,
	"bullet_lifetime": 1.5,
	"bullet_radius": 6.0,
	"projectiles_per_shot": 1,
	"spread_deg": 0.0,
	"range": 420.0,
	"trail_points": 5,
	"icon": "blaster",
	"rarity": "common",
	"crit_chance": 0.08,
	"crit_mult": 2.0,
	"knockback": 1.0,
	"explosion_radius": 0.0,
	"explosion_damage": 0.0,
	"recoil": 1.0,
	"loot_weight": 1.0,
	"burn": 0.0,
	"finisher_radius": 0.0,
	"finisher_chance": 0.12,
	"pierce_ramp": 0.0,
	"dash_charge": false,
	"trait": "",
	"kind": "gun",
	"melee_class": "",
	"weight": 2,
	"arc_deg": 100.0,
	"reach": 110.0,
	"windup": 0.2,
	"swing": 0.14,
	"recovery": 0.2,
	"lunge": 40.0,
	"stagger": 6.0,
	"combo_hits": 3,
	"heavy_mult": 2.2,
	"block": 0.0,
}

const RARITIES := ["common", "rare", "epic", "legendary"]
const MELEE_DAMAGE_BOOST := 1.6
const MELEE_REACH_BOOST := 1.15
const RARITY_COLORS := {
	"common": Color("#c3cad6"),
	"rare": Color("#3da5ff"),
	"epic": Color("#c15cff"),
	"legendary": Color("#ffc93c"),
}
const RARITY_NAMES := {
	"common": "Обычное",
	"rare": "Редкое",
	"epic": "Эпическое",
	"legendary": "Легендарное",
}
const TRAITS := {
	"close": "В упор: урон до ×1.9, издалека до ×0.55. Лезь в толпу",
	"focus": "Прицел: стоя на месте 1 с — выстрел ×2, в движении ×0.75. Играй от позиции",
	"ice_wave": "Каждый 3-й удар обрушивает ледяной разлом перед тобой: урон по площади и замедление",
	"junk_grow": "Собирает мусор: клинок растёт на 10% за каждые 10 убийств (до +100%)",
	"dash_cut": "Срез: рывок режет всех на пути уроном катаны, раненых — всегда критом; трое за рывок — раж (+30% к скорости ударов на 5 с)",
	"gravity": "Удар стягивает врагов в точку, следующий удар взрывает их",
	"echo": "Каждый удар повторяет второй клинок: ещё 60% урона через 0.09 с",
	"quake": "Финишер комбо бьёт ударной волной по площади",
	"spin": "Раскрутка: темп растёт с 0.6 до 1.7 выстр/с за ~2 с стрельбы",
}
const MAX_TIER := 5
## Что даёт каждый тир помимо цифр (T1 — база). Для окна оружия: игрок видит, зачем сливать копии.
const TIER_PERKS := {
	"common": [
		"База: тусклая жёлтая пуля",
		"Пуля крупнее, сыплет искры",
		"Двойной трассер, пыль от гильз",
		"Поджигает цель: горение 30% урона пули в секунду",
		"Золотая пуля, горение 50% урона пули в секунду",
	],
	"rare": [
		"База: чистая голубая пуля",
		"Тонкая белая сердцевина, блики на хвосте",
		"Пуля летит быстрее (+8%), вспышка-звезда",
		"Скорость пули +16%, кольцо на дульном срезе",
		"Скорость пули +24%, лазерная нить и эхо-кольцо",
	],
	"epic": [
		"База: фиолетовый сгусток плазмы",
		"По краю пробегают мини-разряды",
		"Рикошет +1: пуля перескакивает на соседа",
		"Плазменный луч, дуговые молнии по хвосту",
		"Рикошет +2, массивный луч, вспышка на крите",
	],
}
const TIER_PERKS_MELEE := {
	"common": [
		"База: серый серп-шлейф",
		"Серп шире, лёгкий след пыли",
		"Двойной серп, искры металла",
		"Красноватый жар кромки",
		"Золотая кромка, яркие искры",
	],
	"rare": [
		"База: голубой чистый серп",
		"Белая кромка по дуге",
		"Остаточное изображение клинка",
		"Кольцо ударной волны в конце дуги",
		"Лазерный серп, вспышка и осколки",
	],
	"epic": [
		"База: фиолетовый серп с свечением",
		"Рябь воздуха за клинком",
		"Электрические разряды по кромке",
		"Дуга оставляет трещину на полу",
		"Плазменная дуга, молнии по всей длине",
	],
}


## Описание тира с учётом ствола: у взрывных эпиков вместо рикошета растёт радиус взрыва.
func tier_perk_for(tier_value: int) -> String:
	if rarity == "epic" and not is_melee() and explosion_radius > 0.0:
		match tier_value:
			3:
				return "Взрыв шире на 16%, плазма трещит по краю"
			4:
				return "Взрыв шире на 24%, плазменная вспышка"
			5:
				return "Взрыв шире на 32%, двойное кольцо и вспышка на крите"
	return tier_perk(rarity, tier_value, is_melee())


static func tier_perk(rarity: String, tier: int, melee: bool) -> String:
	var table: Dictionary = TIER_PERKS_MELEE if melee else TIER_PERKS
	if not table.has(rarity):
		return ""
	return str((table[rarity] as Array)[clampi(tier, 1, MAX_TIER) - 1])
## Шаги тира: [урон, скорострельность, шанс крита]. Потолок растёт с качеством; у легендарных тиров нет вообще.
const TIER_STEPS := {
	"common": [0.12, 0.03, 0.01],
	"rare": [0.16, 0.04, 0.015],
	"epic": [0.20, 0.045, 0.02],
}
const TIER_PALETTE := {
	"common": Color("#ffe36e"),
	"rare": Color("#5ce1ff"),
	"epic": Color("#b96bff"),
}
const TIER_VISUAL_BLEND := 0.13
const TIER_SCALE_STEP := 0.07
const TIER_RADIUS_STEP := 0.05
const TRACER_SPRITE := "builtin:tracer"

const EXTRA_PROJECTILE_SPREAD_DEG := 9.0
## Бюджет снарядов: больше этого числа пуль в секунду игра не рождает. Излишек скорострельности
## и мультишота автоматически превращается в урон (DPS сохраняется, нагрузка на телефон — нет).
const BULLET_BUDGET_PER_SEC := 70.0
const MAX_PROJECTILES_PER_SHOT := 14
## Оружие «ближнего боя»: дальность до этого значения. Для него работают улучшения «Ближний контакт».
const CLOSE_RANGE := 360.0

var id: StringName
var display_name: String
var short_name: String
var enemy_only: bool
var unlock_blueprint: StringName
var fire_sound: StringName
var damage: float
var fire_interval: float
var bullet_speed: float
## Лист пули грузится при первом выстреле (WeaponVfx.apply ставит только ключ): иначе при запуске
## в видеопамять попадали листы всех легендарок и редкостей сразу (~9 МБ).
var bullet_texture: Texture2D:
	get:
		if bullet_texture == null and not bullet_vfx_key.is_empty():
			bullet_texture = WeaponVfx.resolve_bullet(bullet_vfx_key)
		return bullet_texture
var bullet_vfx_key := ""
var sprite_scale: Vector2
var bullet_modulate: Color
var piercing: bool
var ricochet_count: int
var ricochet_range: float
## Самонаведение вражеского снаряда: поворот к Еноту, рад/с, первые homing_time секунд.
var homing: float
var homing_time: float
## Вращение спрайта снаряда (рад/с) вместо поворота по направлению полёта.
var spin: float
var effect_color: Color
var bullet_lifetime: float
var bullet_radius: float
var projectiles_per_shot: int
var spread_rad: float
var max_distance: float
var trail_points: int
var icon: StringName
var rarity: String
var crit_chance: float
var crit_mult: float
var knockback: float
var explosion_radius: float
var explosion_damage: float
var recoil: float
var loot_weight: float
## Доля урона пули в секунду горения (0 — ствол не поджигает сам).
var burn: float
## Взрыв в конце полёта (огнемёт): радиус и шанс на каждую пулю.
var finisher_radius: float
var finisher_chance: float
## Рельсотрон: +доля урона за каждого уже пробитого врага; навык героя заряжает следующий выстрел.
var pierce_ramp: float
var dash_charge: bool
var trait_id: StringName
var tier := 1
## Графика по качеству/тиру (см. WeaponVfx): "" — процедурная, редкость или fx_<оружие> — спрайты.
var vfx_id := ""
var vfx_bullet := false
## Ближний бой: kind == "melee" — вместо пуль сектор удара (см. MeleeFighter).
var kind := "gun"
var melee_class := ""
var weight := 2
var arc_rad := 1.7
var melee_reach := 110.0
var windup := 0.2
var swing := 0.14
var recovery := 0.2
var lunge := 40.0
var stagger := 6.0
var combo_hits := 3
var heavy_mult := 2.2
var block := 0.0


## resolve_texture: Callable(path: String) -> Texture2D | null. Кэш текстур живёт в WeaponDB.
static func from_dict(raw: Dictionary, resolve_texture: Callable) -> WeaponData:
	var raw_id := ConfigLoader.require_id(raw, "weapon_id", "WeaponData")
	if raw_id.is_empty():
		return null

	var label := "WeaponData[%s]" % raw_id
	var d := ConfigLoader.sanitize(raw, DEFAULTS, label, PackedStringArray(["weapon_id"]))
	var w := WeaponData.new()
	w.id = StringName(raw_id)
	w.display_name = d["display_name"] if not String(d["display_name"]).is_empty() else raw_id
	w.short_name = d["short_name"] if not String(d["short_name"]).is_empty() else w.display_name
	w.enemy_only = d["enemy_only"]
	w.unlock_blueprint = StringName(d["unlock_blueprint"])
	w.fire_sound = StringName(d["fire_sound"])
	w.damage = maxf(d["damage"], 0.0)
	w.fire_interval = maxf(d["fire_rate"], 0.02)
	w.bullet_speed = maxf(d["bullet_speed"], 1.0)
	w.piercing = d["piercing"]
	w.ricochet_count = maxi(int(d["ricochet_count"]), 0)
	w.ricochet_range = maxf(d["ricochet_range"], 0.0)
	w.homing = maxf(d["homing"], 0.0)
	w.homing_time = maxf(d["homing_time"], 0.0)
	w.spin = float(d["spin"])
	w.bullet_lifetime = maxf(d["bullet_lifetime"], 0.05)
	w.bullet_radius = maxf(d["bullet_radius"], 1.0)
	w.projectiles_per_shot = maxi(int(d["projectiles_per_shot"]), 1)
	w.spread_rad = deg_to_rad(clampf(d["spread_deg"], 0.0, 360.0))
	w.max_distance = maxf(d["range"], 1.0)
	w.trail_points = clampi(int(d["trail_points"]), 0, 12)
	w.effect_color = ConfigLoader.parse_color(d["effect_color"], label)
	w.icon = StringName(d["icon"])
	w.rarity = d["rarity"] if RARITIES.has(d["rarity"]) else "common"
	w.crit_chance = clampf(d["crit_chance"], 0.0, 1.0)
	w.crit_mult = maxf(d["crit_mult"], 1.0)
	w.knockback = maxf(d["knockback"], 0.0)
	w.explosion_radius = maxf(d["explosion_radius"], 0.0)
	w.explosion_damage = maxf(d["explosion_damage"], 0.0)
	w.recoil = maxf(d["recoil"], 0.0)
	w.loot_weight = maxf(d["loot_weight"], 0.0)
	w.burn = maxf(d["burn"], 0.0)
	w.finisher_radius = maxf(d["finisher_radius"], 0.0)
	w.finisher_chance = clampf(d["finisher_chance"], 0.0, 1.0)
	w.pierce_ramp = maxf(d["pierce_ramp"], 0.0)
	w.dash_charge = d["dash_charge"]
	w.trait_id = StringName(d["trait"])
	w.kind = d["kind"]
	if w.kind == "melee":
		# Ближний бой рискованнее огнестрела (надо подойти вплотную и прицелиться пальцем) — бьёт заметно сильнее.
		w.damage *= MELEE_DAMAGE_BOOST
		w.melee_class = d["melee_class"]
		w.weight = clampi(int(d["weight"]), 1, 5)
		w.arc_rad = deg_to_rad(clampf(d["arc_deg"], 20.0, 360.0))
		w.melee_reach = maxf(d["reach"], 30.0) * MELEE_REACH_BOOST
		w.windup = maxf(d["windup"], 0.03)
		w.swing = maxf(d["swing"], 0.04)
		w.recovery = maxf(d["recovery"], 0.03)
		w.lunge = maxf(d["lunge"], 0.0)
		w.stagger = maxf(d["stagger"], 0.0)
		w.combo_hits = clampi(int(d["combo_hits"]), 1, 5)
		w.heavy_mult = maxf(d["heavy_mult"], 1.0)
		w.block = clampf(d["block"], 0.0, 0.95)
		w.fire_interval = w.windup + w.swing + w.recovery
		w.projectiles_per_shot = 1
		w.max_distance = w.melee_reach + w.lunge * 0.9 + 26.0
	_apply_visuals(w, d, resolve_texture)
	WeaponVfx.apply(w)
	return w


func get_dps() -> float:
	var expected := damage * (1.0 + crit_chance * (crit_mult - 1.0)) + explosion_damage * 0.6
	return expected * projectiles_per_shot / fire_interval


func get_rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["common"])


func is_melee() -> bool:
	return kind == "melee"


func has_tiers() -> bool:
	return TIER_STEPS.has(rarity)


func get_title() -> String:
	return "%s T%d" % [display_name, tier] if has_tiers() else display_name


## Копия базового конфига на заданном тире (Merge двух одинаковых стволов даёт тир выше).
## Легендарное оружие возвращается как есть: тиров у него нет, его сила заложена в базовые статы и механику.
## Цвет пули, шлейф, размер и хитбокс сдвигаются к палитре качества: чем выше тир, тем «чище» и крупнее снаряд.
func with_tier(new_tier: int) -> WeaponData:
	var w := duplicate_data()
	if not has_tiers():
		w.tier = 1
		return w
	var steps := clampi(new_tier, 1, MAX_TIER) - 1
	var step: Array = TIER_STEPS[rarity]
	w.tier = steps + 1
	w.damage = damage * (1.0 + float(step[0]) * steps)
	w.explosion_damage = explosion_damage * (1.0 + float(step[0]) * steps)
	w.fire_interval = maxf(fire_interval * (1.0 - float(step[1]) * steps), 0.02)
	w.crit_chance = minf(crit_chance + float(step[2]) * steps, 0.9)
	if is_melee():
		w.melee_reach = melee_reach * (1.0 + 0.04 * steps)
		w.stagger = stagger * (1.0 + 0.05 * steps)
		w.windup = windup * (1.0 - 0.03 * steps)
		w.swing = swing * (1.0 - 0.03 * steps)
		w.recovery = recovery * (1.0 - 0.04 * steps)
		w.fire_interval = w.windup + w.swing + w.recovery
		w.max_distance = w.melee_reach + w.lunge * 0.9 + 26.0
		w.arc_rad = arc_rad * (1.0 + 0.03 * steps)
	elif steps > 0:
		match rarity:
			"common":
				if steps >= 3:
					w.burn = maxf(burn, 0.3 if steps == 3 else 0.5)
			"rare":
				if steps >= 2:
					w.bullet_speed = bullet_speed * (1.0 + 0.08 * (steps - 1))
			"epic":
				if steps >= 2:
					if explosion_radius > 0.0:
						w.explosion_radius = explosion_radius * (1.0 + 0.08 * (steps - 1))
					else:
						w.ricochet_count = ricochet_count + (1 if steps < 4 else 2)
		var palette: Color = TIER_PALETTE[rarity]
		var blend := TIER_VISUAL_BLEND * steps
		w.effect_color = effect_color.lerp(palette, blend)
		if bullet_modulate != Color.WHITE:
			w.bullet_modulate = bullet_modulate.lerp(palette.lightened(0.2), blend)
		w.sprite_scale = sprite_scale * (1.0 + TIER_SCALE_STEP * steps)
		w.trail_points = mini(trail_points + steps, 12)
		w.bullet_radius = bullet_radius * (1.0 + TIER_RADIUS_STEP * steps)
	WeaponVfx.apply(w)
	return w


func duplicate_data() -> WeaponData:
	var copy := WeaponData.new()
	for prop in get_script().get_script_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(prop["name"], get(prop["name"]))
	return copy


func is_close_range() -> bool:
	return max_distance <= CLOSE_RANGE


func with_run_stats(stats: RunStats) -> WeaponData:
	var w := duplicate_data()
	var close := is_close_range()
	var damage_mult := 1.0 + stats.get_stat(&"damage_mult")
	if close:
		damage_mult *= 1.0 + stats.get_stat(&"close_damage")
	w.damage = damage * damage_mult
	w.explosion_damage = explosion_damage * damage_mult
	w.fire_interval = maxf(fire_interval / (1.0 + stats.get_stat(&"fire_rate_mult")), 0.005)
	w.crit_chance = minf(crit_chance + stats.get_stat(&"crit_chance_add"), 0.95)
	w.ricochet_count = ricochet_count + int(stats.get_stat(&"extra_ricochets"))
	w.piercing = piercing or stats.get_stat(&"piercing") > 0.0

	var extra := int(stats.get_stat(&"extra_projectiles"))
	w.projectiles_per_shot = mini(projectiles_per_shot + extra, MAX_PROJECTILES_PER_SHOT)
	if extra > 0 and spread_rad <= 0.0:
		w.spread_rad = deg_to_rad(EXTRA_PROJECTILE_SPREAD_DEG * (w.projectiles_per_shot - 1))

	var reach := 1.0 + stats.get_stat(&"range_mult")
	if close:
		reach *= 1.0 + stats.get_stat(&"close_reach")
		var width := 1.0 + stats.get_stat(&"close_width")
		w.bullet_radius = bullet_radius * width
		w.sprite_scale = sprite_scale * width
		w.spread_rad = spread_rad * (1.0 + 0.5 * stats.get_stat(&"close_width"))
		var finisher := stats.get_stat(&"close_finisher")
		if finisher > 0.0:
			w.finisher_radius = maxf(finisher_radius, 60.0 + 14.0 * finisher)
			w.finisher_chance = clampf(maxf(finisher_chance, 0.0) + 0.05 * finisher, 0.0, 0.5)
	if is_melee():
		w.melee_reach = melee_reach * reach
		w.max_distance = w.melee_reach + lunge * 0.9 + 26.0
	else:
		w.max_distance = max_distance * reach
	w.bullet_speed = bullet_speed * reach
	if w.finisher_radius > 0.0:
		w.explosion_radius = maxf(w.explosion_radius, w.finisher_radius)
		w.explosion_damage = maxf(w.explosion_damage, w.damage * 3.0)

	if pierce_ramp > 0.0:
		w.pierce_ramp = pierce_ramp + stats.get_stat(&"rail_ramp")
		w.fire_interval = maxf(w.fire_interval / (1.0 + stats.get_stat(&"rail_rate")), 0.2)
		var beams := int(stats.get_stat(&"rail_beams"))
		if beams > 0:
			w.projectiles_per_shot = mini(w.projectiles_per_shot + beams, MAX_PROJECTILES_PER_SHOT)
			w.spread_rad = deg_to_rad(7.0 * (w.projectiles_per_shot - 1))
		var boom := stats.get_stat(&"rail_boom")
		if boom > 0.0:
			w.finisher_radius = 100.0 + 22.0 * boom
			w.finisher_chance = 1.0
			w.explosion_radius = w.finisher_radius
			w.explosion_damage = w.damage * (0.8 + 0.4 * boom)

	var per_second := float(w.projectiles_per_shot) / w.fire_interval
	if per_second > BULLET_BUDGET_PER_SEC:
		var squeeze := per_second / BULLET_BUDGET_PER_SEC
		w.fire_interval *= squeeze
		w.damage *= squeeze
		w.explosion_damage *= squeeze
	return w


static func _apply_visuals(w: WeaponData, d: Dictionary, resolve_texture: Callable) -> void:
	var path: String = d["bullet_sprite"]
	var tint: bool = d["tint_bullet"]
	if path == TRACER_SPRITE:
		# Трассер огнестрела: вытянутая капсула с белым ядром, красится в effect_color.
		w.bullet_texture = ConfigLoader.get_tracer_texture()
		w.vfx_bullet = true
		w.sprite_scale = Vector2(maxf(d["bullet_scale"], 0.01), maxf(d["bullet_scale"], 0.01) * clampf(w.bullet_radius / 5.0, 0.6, 2.2))
		w.bullet_modulate = w.effect_color.lightened(0.25)
		return
	var texture: Texture2D = resolve_texture.call(path) if not path.is_empty() else null

	if texture == null:
		# Процедурный диск вместо отсутствующего ассета: подгоняется под хитбокс
		# и всегда красится в effect_color, чтобы пуля оставалась читаемой.
		w.bullet_texture = ConfigLoader.get_fallback_texture()
		w.sprite_scale = Vector2.ONE * (w.bullet_radius * 2.0 / ConfigLoader.FALLBACK_TEXTURE_SIZE) * 1.35
		tint = true
	else:
		w.bullet_texture = texture
		w.sprite_scale = Vector2.ONE * maxf(d["bullet_scale"], 0.01)

	w.bullet_modulate = w.effect_color if tint else Color.WHITE


const MELEE_USAGE := {
	"dagger": ["Сближайся и работай серией: 4 быстрых удара, крит выше обычного", "Не лезь в толпу в лоб: размах короткий"],
	"sword": ["Держи врагов перед собой: средний размах, самое надёжное комбо", "Не растягивай бой: удары ровные, но не взрывные"],
	"katana": ["Выпад с шагом: бей по одиночным целям и добивай", "Не жди, пока обступят: размах узкий"],
	"axe": ["Третий удар бьёт по кругу, лучшее оружие против окружения", "Не спамь по одному врагу: замах медленный"],
	"spear": ["Колет по линии далеко: держи дистанцию", "Не подпускай вплотную: у самой рукояти слабее"],
	"hammer": ["Тяжёлые удары оглушают: бей вожаков и тяжёлых крыс", "Не трать замах на мелочь: он долгий"],
	"shield": ["Бьёт и отталкивает: держи врагов перед собой", "Не поворачивайся спиной: прикрывает только спереди"],
	"club": ["Простая и надёжная: бей и отталкивай", "Не жди чудес против брони: урон средний"],
}
const GUN_MISUSE := {
	"close": "Не стреляй издалека: урон падает до ×0.55",
	"focus": "Не стреляй в бегу: урон ×0.75",
	"spin": "Не жди чуда с первой секунды: ствол сначала раскручивается",
}


## Как пользоваться: пара коротких подсказок по параметрам (для окна оружия).
func usage_text() -> String:
	if is_melee():
		return str((MELEE_USAGE.get(melee_class, MELEE_USAGE["club"]) as Array)[0])
	match str(trait_id):
		"close":
			return "Подходи вплотную: в упор урон до ×1.9. Лезь в самую гущу"
		"focus":
			return "Остановись на секунду и стреляй: стоя ствол бьёт вдвое сильнее"
		"spin":
			return "Зажми и держи: темп растёт примерно 2 секунды, дальше льёт стеной"
	if explosion_radius > 0.0:
		return "Целься в кучу: взрыв накрывает всех рядом с целью"
	if ricochet_count > 0:
		return "Стреляй по группе: пуля перескакивает с врага на врага"
	if piercing:
		return "Стреляй вдоль строя: пуля пробивает всех на линии"
	if projectiles_per_shot > 1:
		return "Бей по ближним: веер дробин бьёт сильнее с малого расстояния"
	if fire_interval < 0.2:
		return "Зажми и води по толпе: быстрая очередь, мало урона на пулю"
	return "Один точный выстрел за раз: держи цель в прицеле"


## Как не использовать: главная ошибка с этим стволом.
func misuse_text() -> String:
	if is_melee():
		return str((MELEE_USAGE.get(melee_class, MELEE_USAGE["club"]) as Array)[1])
	var key := str(trait_id)
	if GUN_MISUSE.has(key):
		return str(GUN_MISUSE[key])
	if explosion_radius > 0.0:
		return "Не трать на одиночных мелких крыс: взрыв раскрывается в куче"
	if fire_interval < 0.2:
		return "Не стреляй по одному далёкому врагу: пули тратятся впустую"
	return "Не трать выстрелы на мелочь, пока рядом тяжёлая цель"


## Короткое описание поведения снаряда по параметрам ствола.
func behavior_text() -> String:
	var parts: PackedStringArray = []
	if kind == "melee":
		parts.append("ближний бой: удар по дуге")
	else:
		if projectiles_per_shot > 1:
			parts.append("%d %s веером" % [projectiles_per_shot, "снаряда" if projectiles_per_shot < 5 else "снарядов"])
		if piercing:
			parts.append("пробивает врагов")
		if ricochet_count > 0:
			parts.append("рикошет ×%d" % ricochet_count)
		if homing > 0.0:
			parts.append("самонаведение")
		if explosion_radius > 0.0:
			parts.append("взрыв при попадании")
		if burn > 0.0:
			parts.append("поджигает")
		if knockback > 220.0:
			parts.append("сильно отбрасывает")
		if parts.is_empty():
			parts.append("точный одиночный выстрел" if fire_interval >= 0.2 else "быстрая очередь")
	var joined := ", ".join(parts)
	return joined.substr(0, 1).to_upper() + joined.substr(1)
