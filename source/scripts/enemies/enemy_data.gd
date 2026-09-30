class_name EnemyData
extends RefCounted
## Read-only конфиг врага. Создаётся только через ContentDB.
## Оружие хранится как id и резолвится через WeaponDB при спавне,
## чтобы горячая перезагрузка weapons.json сразу влияла на врагов.

enum Behavior { CHASER, RANGED, BOSS, EXPLODER, DASHER, BOMBER, SLAMMER, ASSASSIN, TRAPPER, TRICKSTER }

const BEHAVIORS := {
	"chaser": Behavior.CHASER,
	"ranged": Behavior.RANGED,
	"boss": Behavior.BOSS,
	"exploder": Behavior.EXPLODER,
	"dasher": Behavior.DASHER,
	"bomber": Behavior.BOMBER,
	"slammer": Behavior.SLAMMER,
	"assassin": Behavior.ASSASSIN,
	"trapper": Behavior.TRAPPER,
	"trickster": Behavior.TRICKSTER,
}

const DEFAULTS := {
	"display_name": "",
	"behavior": "chaser",
	"max_hp": 20.0,
	"move_speed": 100.0,
	"contact_damage": 8.0,
	"radius": 20.0,
	"sprite": "",
	"sprite_scale": 1.0,
	"sprite_faces_right": true,
	"weapon_id": "",
	"preferred_distance": 300.0,
	"attack_cooldown": 2.0,
	"xp": 1,
	"nut_drop": 1,
	"nut_drop_chance": 1.0,
	"knockback_resist": 0.0,
	"fx_color": "#FF6A3D",
	"tint": "#FFFFFF",
	"hue_variance": 0.0,
	"size_variance": 0.0,
	"accessories": [],
	"accessory_anchor": [0.0, -60.0],
	"explode_radius": 0.0,
	"explode_damage": 0.0,
	"dash_speed": 0.0,
	"lunge": false,
	"heal_radius": 0.0,
	"heal_pct": 0.06,
	"heal_interval": 2.5,
	"flank_chance": 0.0,
	"rig": "",
	"recolor": {},
	"proportions": {},
	"variants": true,
	"frames": "",
	"accent_variants": [],
	"accessory_scale": 1.0,
	"outline_world": 2.2,
	"rig_variants": [],
	"shield": false,
	"shield_arc": 62.0,
	"shield_block": 0.85,
	"shield_turn": 2.6,
	"flying": false,
	"hover": 0.0,
	"attack_sprite": "",
	"attack_width": 0.0,
	"slam_radius": 0.0,
	"slam_damage": 0.0,
	"slam_windup": 0.6,
	"bomb": {},
	"boss_pattern": "",
	"parts": [],
	"title": "",
	"armor": 0.0,
	"stealth_alpha": 1.0,
	"slam_line": 0,
	"charge_speed": 0.0,
	"alt_weapon_id": "",
	"trap_every": 3,
	"blink_distance": 0.0,
	"muzzles": [],
}

var id: StringName
var display_name: String
var behavior: Behavior
var max_hp: float
var move_speed: float
var contact_damage: float
var radius: float
## Текстуры грузятся при первом обращении: враги, которых нет в текущем забеге, не занимают память
## (на iPhone 11 и слабых Android браузер убивает вкладку по лимиту памяти).
var texture: Texture2D:
	get:
		if _texture == null and _resolver.is_valid():
			_texture = _resolver.call(_texture_path)
			if _texture == null:
				_texture = ConfigLoader.get_fallback_texture()
		return _texture
var _texture: Texture2D
var _texture_path := ""
var _attack_path := ""
var _resolver: Callable
var sprite_scale: Vector2
var sprite_modulate: Color
var faces_right: bool
var weapon_id: StringName
var preferred_distance: float
var attack_cooldown: float
var xp: int
var nut_drop: int
var nut_drop_chance: float
var knockback_resist: float
var fx_color: Color
var tint: Color
var hue_variance: float
var size_variance: float
## Набор аксессуаров, из которых каждой особи выпадает 1–2 (EnemyAccessories.Kind по имени).
var accessories: PackedStringArray
## Точка головы в пикселях текстуры относительно её центра — от неё рисуются аксессуары.
var accessory_anchor: Vector2
var explode_radius: float
var explode_damage: float
var dash_speed: float
var lunge: bool
## Поддержка: раз в heal_interval лечит союзников в радиусе на долю их максимума.
var heal_radius: float
var heal_pct: float
var heal_interval: float
var flank_chance: float
## Риг из data/rigs.json (по умолчанию — имя файла текстуры).
var rig_id: String
## Перекраска регионов типа (формат как у нарядов енота): бомбо- и торпедо-крысы — не просто
## перекрашенные копии, у них свой мех, одежда и свечение.
var recolor: Dictionary
## Пропорции типа: растяжение костей head / ears / tail / torso / legs.
var proportions: Dictionary
## Индивидуальные вариации особей: окрас меха, цвет глаз, пропорции.
var variants: bool
## Покадровый лист из data/frames.json (кадры с концепт-листа) — если задан, вместо рига.
var frames_id: String
## Цвета акцента покадровых особей (ирокез, нашивки): [вес, {регион: градиент}], {} — как на листе.
var accent_variants: Array
## Масштаб процедурных аксессуаров относительно спрайта (кадры крупнее рига в пикселях).
var accessory_scale: float
## Толщина обводки в пикселях мира (у покадровых — пересчёт в пиксели атласа).
var outline_world: float
## Внешности одного типа (разные риги): каждая особь выбирает случайную.
var rig_variants: PackedStringArray
## Щит: пули спереди (в секторе shield_arc° от направления щита) теряют shield_block урона.
## Щит поворачивается к Еноту со скоростью shield_turn рад/с и опущен во время атаки.
var shield: bool
var shield_arc: float
var shield_block: float
var shield_turn: float
## Летающий: зависает на hover px над тенью, не упирается в укрытия.
var flying: bool
var hover: float
## Кадр атаки (выстрел Искруна, удар щитом Слиткобоя) — отдельная картинка с концепт-листа.
var attack_texture: Texture2D:
	get:
		if _attack_texture == null and not _attack_path.is_empty() and _resolver.is_valid():
			_attack_texture = _resolver.call(_attack_path)
		return _attack_texture
var _attack_texture: Texture2D
var attack_width: float
## Удар по площади (Слиткобой): радиус, урон, время замаха.
var slam_radius: float
var slam_damage: float
var slam_windup: float
## Навесной снаряд (Дивидендщик): radius, damage, flight, height, texture, blast, size, color.
var bomb: Dictionary
## Сценарий босса (BossBrain): "overlord" | "magnate".
var boss_pattern: String
## Составные части (базука, стволы меха, пилот): см. EnemyParts.
var parts: Array
## Подзаголовок для полоски босса.
var title: String
## Доля поглощаемого урона бронёй (Сейфолом).
var armor: float
## Прозрачность «в тени» (Искро-Заточка): видна полностью только на замахе и ударе.
var stealth_alpha: float
## Удар-трещина: сколько волн идёт от удара по линии к Еноту.
var slam_line: int
## Разгон-таран слэммера (0 — нет).
var charge_speed: float
## Второе оружие (веер карт у Крупье — основное, фишки — второе).
var alt_weapon_id: StringName
## Каждая N-я атака Магнитчика — магнитная ловушка вместо выстрела.
var trap_every: int
## Уход-телепорт Крупье после попаданий (0 — нет).
var blink_distance: float
## Точки дул без составных частей (мир, относительно ног; x — вперёд по взгляду).
var muzzles: Array[Vector2] = []


static func from_dict(raw: Dictionary, resolve_texture: Callable) -> EnemyData:
	var raw_id := ConfigLoader.require_id(raw, "enemy_id", "EnemyData")
	if raw_id.is_empty():
		return null

	var label := "EnemyData[%s]" % raw_id
	var d := ConfigLoader.sanitize(raw, DEFAULTS, label, PackedStringArray(["enemy_id"]))
	if not BEHAVIORS.has(d["behavior"]):
		push_error("%s: неизвестный behavior '%s', запись пропущена" % [label, d["behavior"]])
		return null

	var e := EnemyData.new()
	e.id = StringName(raw_id)
	e.display_name = d["display_name"] if not String(d["display_name"]).is_empty() else raw_id
	e.behavior = BEHAVIORS[d["behavior"]]
	e.max_hp = maxf(d["max_hp"], 1.0)
	e.move_speed = maxf(d["move_speed"], 0.0)
	e.contact_damage = maxf(d["contact_damage"], 0.0)
	e.radius = maxf(d["radius"], 4.0)
	e.faces_right = d["sprite_faces_right"]
	e.weapon_id = StringName(d["weapon_id"])
	e.preferred_distance = maxf(d["preferred_distance"], 0.0)
	e.attack_cooldown = maxf(d["attack_cooldown"], 0.1)
	e.xp = maxi(int(d["xp"]), 0)
	e.nut_drop = maxi(int(d["nut_drop"]), 0)
	e.nut_drop_chance = clampf(d["nut_drop_chance"], 0.0, 1.0)
	e.knockback_resist = clampf(d["knockback_resist"], 0.0, 1.0)
	e.fx_color = ConfigLoader.parse_color(d["fx_color"], label)
	e.tint = ConfigLoader.parse_color(d["tint"], label)
	e.hue_variance = clampf(d["hue_variance"], 0.0, 0.5)
	e.size_variance = clampf(d["size_variance"], 0.0, 0.4)
	e.accessories = PackedStringArray()
	for item in d["accessories"]:
		e.accessories.append(str(item))
	var anchor: Array = d["accessory_anchor"]
	e.accessory_anchor = Vector2(float(anchor[0]), float(anchor[1])) if anchor.size() >= 2 else Vector2(0, -60)
	e.explode_radius = maxf(d["explode_radius"], 0.0)
	e.explode_damage = maxf(d["explode_damage"], 0.0)
	e.dash_speed = maxf(d["dash_speed"], 0.0)
	e.lunge = d["lunge"]
	e.heal_radius = maxf(d["heal_radius"], 0.0)
	e.heal_pct = clampf(d["heal_pct"], 0.0, 1.0)
	e.heal_interval = maxf(d["heal_interval"], 0.5)
	e.flank_chance = clampf(d["flank_chance"], 0.0, 1.0)
	e.rig_id = str(d["rig"]) if not str(d["rig"]).is_empty() else String(d["sprite"]).get_file().get_basename()
	e.recolor = d["recolor"]
	e.proportions = d["proportions"]
	e.variants = d["variants"]
	e.frames_id = str(d["frames"])
	e.accent_variants = d["accent_variants"]
	e.accessory_scale = maxf(d["accessory_scale"], 0.05)
	e.outline_world = maxf(d["outline_world"], 0.0)
	e.rig_variants = PackedStringArray()
	for v in d["rig_variants"]:
		e.rig_variants.append(str(v))
	e.shield = d["shield"]
	e.shield_arc = deg_to_rad(clampf(d["shield_arc"], 5.0, 180.0))
	e.shield_block = clampf(d["shield_block"], 0.0, 1.0)
	e.shield_turn = maxf(d["shield_turn"], 0.1)
	e.flying = d["flying"]
	e.hover = maxf(d["hover"], 0.0)
	var attack_path := str(d["attack_sprite"])
	e._attack_path = attack_path
	e.attack_width = maxf(d["attack_width"], 0.0)
	e.slam_radius = maxf(d["slam_radius"], 0.0)
	e.slam_damage = maxf(d["slam_damage"], 0.0)
	e.slam_windup = maxf(d["slam_windup"], 0.1)
	e.bomb = d["bomb"]
	e.boss_pattern = str(d["boss_pattern"])
	e.parts = d["parts"]
	e.title = str(d["title"])
	e.armor = clampf(d["armor"], 0.0, 0.9)
	e.stealth_alpha = clampf(d["stealth_alpha"], 0.05, 1.0)
	e.slam_line = maxi(int(d["slam_line"]), 0)
	e.charge_speed = maxf(d["charge_speed"], 0.0)
	e.alt_weapon_id = StringName(d["alt_weapon_id"])
	e.trap_every = maxi(int(d["trap_every"]), 1)
	e.blink_distance = maxf(d["blink_distance"], 0.0)
	for m in d["muzzles"]:
		if m is Array and (m as Array).size() >= 2:
			e.muzzles.append(Vector2(float(m[0]), float(m[1])))

	e._resolver = resolve_texture
	e._texture_path = String(d["sprite"])
	if not e._texture_path.is_empty() and ResourceLoader.exists(e._texture_path, "Texture2D"):
		e.sprite_scale = Vector2.ONE * maxf(d["sprite_scale"], 0.01)
		e.sprite_modulate = e.tint
	else:
		e.sprite_scale = Vector2.ONE * (e.radius * 2.2 / ConfigLoader.FALLBACK_TEXTURE_SIZE)
		e.sprite_modulate = e.fx_color
	return e


func is_boss() -> bool:
	return behavior == Behavior.BOSS
