class_name WeaponVfx
extends RefCounted
## Каталог графики оружия по качеству и тиру. Листы 4x2: T1..T5 в первой строке и втором слоте второй,
## остальное — попадания/дым/гильза. Легендарки берут свои листы 3x1: снаряд, попадание, дульная вспышка.

const SHEET_DIR := "res://assets/vfx/"
const COLS := 4
const CELL := 128
const SLASH_CELL := 160
const LEGEND_W := 384
const LEGEND_H := 192
const LEGEND_SHEETS := {
	&"flamer_v1": "flamer", &"prism_blaster_v1": "prism", &"magnet_v1": "magnet",
	&"minigun_v1": "minigun", &"toaster_v1": "toaster", &"railgun_v1": "railgun",
}
const LEGEND_BULLET_WIDTH := {
	"flamer": 96.0, "prism": 84.0, "magnet": 70.0, "minigun": 78.0, "toaster": 74.0, "railgun": 170.0,
}
const LEGEND_MUZZLE_WIDTH := {
	"flamer": 110.0, "prism": 90.0, "magnet": 80.0, "minigun": 96.0, "toaster": 84.0, "railgun": 130.0,
}
const BULLET_SCALE := 0.42
const MUZZLE_PIVOT := Vector2(0.3, 0.5)

const LEGEND_SLASH := {&"ice_axe_v1": 0, &"junk_blade_v1": 1, &"graviton_v1": 2, &"pigeon_daggers_v1": 3}
const LEGEND_SLASH_CELL := 224

static var _sheets := {}
static var _atlas := {}


static func legend_key(weapon_id: StringName) -> String:
	return LEGEND_SHEETS.get(weapon_id, "")


static func _sheet(name: String) -> Texture2D:
	if not _sheets.has(name):
		_sheets[name] = load(SHEET_DIR + name + ".png") as Texture2D
	return _sheets[name]


static func _cell(sheet_name: String, index: int, cell: int = CELL) -> Texture2D:
	var key := "%s:%d" % [sheet_name, index]
	if _atlas.has(key):
		return _atlas[key]
	var atlas := AtlasTexture.new()
	atlas.atlas = _sheet(sheet_name)
	atlas.region = Rect2((index % COLS) * cell, (index / COLS) * cell, cell, cell)
	_atlas[key] = atlas
	return atlas


static func _legend_cell(key: String, row: int) -> Texture2D:
	var cache_key := "fx_%s:%d" % [key, row]
	if _atlas.has(cache_key):
		return _atlas[cache_key]
	var atlas := AtlasTexture.new()
	atlas.atlas = _sheet("fx_" + key)
	atlas.region = Rect2(0, row * LEGEND_H, LEGEND_W, LEGEND_H)
	_atlas[cache_key] = atlas
	return atlas


static func bullet(rarity: String, tier: int) -> Texture2D:
	return _cell("bullets_" + rarity, clampi(tier, 1, 5) - 1)


static func muzzle(rarity: String, tier: int) -> Texture2D:
	return _cell("muzzle_" + rarity, clampi(tier, 1, 5) - 1)


static func impact(rarity: String, tier: int) -> Texture2D:
	return _cell("bullets_" + rarity, 5 if tier <= 2 else (6 if tier <= 4 else 7))


static func smoke(rarity: String, tier: int) -> Texture2D:
	return _cell("muzzle_" + rarity, 5 if tier <= 3 else 6)


static func casing(rarity: String) -> Texture2D:
	return _cell("muzzle_" + rarity, 7)


static func slash(rarity: String, tier: int) -> Texture2D:
	return _cell("slash_" + rarity, clampi(tier, 1, 5) - 1, SLASH_CELL)


static func slash_hit(rarity: String, tier: int) -> Texture2D:
	return _cell("slash_" + rarity, 5 if tier <= 2 else (6 if tier <= 4 else 7), SLASH_CELL)


## Проставляет оружию графику снаряда/вспышек. Вызывается при загрузке и при смене тира.
static func apply(w: WeaponData) -> void:
	var key := legend_key(w.id)
	if not key.is_empty():
		w.vfx_id = "fx_" + key
		w.bullet_texture = _legend_cell(key, 0)
		w.sprite_scale = Vector2.ONE * float(LEGEND_BULLET_WIDTH[key]) / LEGEND_W
		w.bullet_modulate = Color.WHITE
		return
	if not w.has_tiers():
		return
	w.vfx_id = w.rarity
	if w.vfx_bullet:
		w.bullet_texture = bullet(w.rarity, w.tier)
		var fat := clampf(w.bullet_radius / 5.0, 0.85, 1.35)
		w.sprite_scale = Vector2(BULLET_SCALE, BULLET_SCALE * fat)
		w.bullet_modulate = Color.WHITE


## Текстура и ширина в мире дульной вспышки оружия (null — оставить процедурную).
static func muzzle_for(w: WeaponData) -> Texture2D:
	if w.vfx_id.begins_with("fx_"):
		return _legend_cell(w.vfx_id.trim_prefix("fx_"), 2)
	if w.vfx_id.is_empty():
		return null
	return muzzle(w.vfx_id, w.tier)


static func muzzle_width(w: WeaponData) -> float:
	if w.vfx_id.begins_with("fx_"):
		return float(LEGEND_MUZZLE_WIDTH[w.vfx_id.trim_prefix("fx_")])
	return 54.0 + 9.0 * (w.tier - 1)


static func impact_for(w: WeaponData) -> Texture2D:
	if w.is_melee():
		return melee_hit_for(w)
	if w.vfx_id.begins_with("fx_"):
		return _legend_cell(w.vfx_id.trim_prefix("fx_"), 1)
	if w.vfx_id.is_empty():
		return null
	return impact(w.vfx_id, w.tier)


static func impact_width(w: WeaponData) -> float:
	if w.is_melee():
		return 64.0 + 8.0 * (w.tier - 1)
	if w.vfx_id.begins_with("fx_"):
		return 92.0
	return 46.0 + 7.0 * (w.tier - 1)


## Дуга взмаха ближнего боя: по качеству и тиру, у легендарок — свой рисунок.
static func slash_for(w: WeaponData) -> Texture2D:
	if LEGEND_SLASH.has(w.id):
		var index: int = LEGEND_SLASH[w.id]
		var key := "legend_melee:%d" % index
		if not _atlas.has(key):
			var atlas := AtlasTexture.new()
			atlas.atlas = _sheet("legend_melee")
			atlas.region = Rect2((index % 2) * LEGEND_SLASH_CELL, (index / 2) * LEGEND_SLASH_CELL, LEGEND_SLASH_CELL, LEGEND_SLASH_CELL)
			_atlas[key] = atlas
		return _atlas[key]
	if w.vfx_id.is_empty():
		return null
	return slash(w.vfx_id, w.tier)


static func melee_hit_for(w: WeaponData) -> Texture2D:
	return slash_hit(w.vfx_id if not w.vfx_id.is_empty() else "epic", w.tier)
