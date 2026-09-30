class_name WeaponIcons
extends RefCounted
## Внешний вид оружия: одна функция на всё — ствол в лапах Енота, иконки HUD, карточки Оружейной
## и лут на земле. Координаты в «единицах ствола»: дуло смотрит вправо, ствол вписан примерно
## в x ∈ [-34, 40], y ∈ [-12, 14].
## Нарисованные стволы (data/weapon_sprites.json: пистолет, револьвер, ПП, автомат, дробовик,
## снайперка, миниган, рельса) рисуются текстурой; у каждого свои точки рукояти и дула и длина
## в единицах ствола. Остальные (гранатомёт, огнемёт, бластеры) — процедурные силуэты: контуры
## (Geometry2D.offset_polygon) считаются один раз на тип и кэшируются.

const OUTLINE := Color("#180e22")
const TIER_COLORS := [Color("#b9c2d9"), Color("#5be37d"), Color("#4dc3ff"), Color("#c98bff"), Color("#ffd257")]
const OUTLINE_WIDTH := 2.6
const METAL := Color("#3b3752")
const METAL_LIGHT := Color("#77739a")
const WOOD := Color("#9a6334")
const WOOD_DARK := Color("#6e4322")
const GRIP := Color("#2a2238")

enum Part { METAL, METAL_LIGHT, WOOD, WOOD_DARK, GRIP, ACCENT, ACCENT_DARK }

const SPRITES_PATH := "res://data/weapon_sprites.json"

static var _cache: Dictionary = {}
static var _sprites: Dictionary = {}
static var _sprites_loaded := false


static func _sprite(kind: StringName) -> Dictionary:
	if not _sprites_loaded:
		_sprites_loaded = true
		for raw in ConfigLoader.load_json(SPRITES_PATH).get("sprites", []):
			var path := str(raw.get("texture", ""))
			if not ResourceLoader.exists(path):
				continue
			var tex: Texture2D = load(path)
			var size := tex.get_size()
			var unit := float(raw.get("length", 74.0)) / size.x
			var center := size * 0.5
			var grip: Array = raw.get("grip", [size.x * 0.3, size.y * 0.7])
			var muzzle_px: Array = raw.get("muzzle", [size.x, size.y * 0.4])
			_sprites[StringName(str(raw["icon"]))] = {
				"texture": tex,
				"unit": unit,
				"center": center,
				"grip": (Vector2(float(grip[0]), float(grip[1])) - center) * unit,
				"muzzle": (Vector2(float(muzzle_px[0]), float(muzzle_px[1])) - center) * unit,
			}
	return _sprites.get(kind, {})


## Точка рукояти в единицах ствола — её держит лапа.
static func grip(kind: StringName) -> Vector2:
	var sprite := _sprite(kind)
	if not sprite.is_empty():
		return sprite["grip"]
	return Vector2(-11.0, 5.0)


## Рисует ствол kind с центром в center. flip_y — зеркалить по вертикали (ствол смотрит влево,
## а рукоять должна остаться снизу).
static func draw(canvas: CanvasItem, kind: StringName, center: Vector2, size_scale: float, angle: float, accent: Color, flip_y: bool = false) -> void:
	var sprite := _sprite(kind)
	if not sprite.is_empty():
		var unit: float = sprite["unit"] * size_scale
		canvas.draw_set_transform_matrix(Transform2D(angle, Vector2(unit, unit * (-1.0 if flip_y else 1.0)), 0.0, center))
		canvas.draw_texture(sprite["texture"], -(sprite["center"] as Vector2))
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var entry := _get_entry(kind)
	var xform := Transform2D(angle, Vector2(size_scale, size_scale * (-1.0 if flip_y else 1.0)), 0.0, center)
	canvas.draw_set_transform_matrix(xform)
	for outline_poly in entry["outlines"]:
		canvas.draw_colored_polygon(outline_poly, OUTLINE)
	var parts: Array = entry["parts"]
	for part in parts:
		canvas.draw_colored_polygon(part[0], _part_color(part[1], accent))
	for shine in entry["shines"]:
		canvas.draw_line(shine[0], shine[1], Color(1, 1, 1, 0.35), 1.4)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## Точка дула в единицах ствола — сюда ставится вспышка выстрела.
static func muzzle(kind: StringName) -> Vector2:
	var sprite := _sprite(kind)
	if not sprite.is_empty():
		return sprite["muzzle"]
	return _get_entry(kind)["muzzle"]


static func _part_color(part: int, accent: Color) -> Color:
	match part:
		Part.METAL:
			return METAL
		Part.METAL_LIGHT:
			return METAL_LIGHT
		Part.WOOD:
			return WOOD
		Part.WOOD_DARK:
			return WOOD_DARK
		Part.GRIP:
			return GRIP
		Part.ACCENT:
			return accent
		_:
			return accent.darkened(0.35)


static func _get_entry(kind: StringName) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var parts := _shape(kind)
	var outlines: Array[PackedVector2Array] = []
	for part in parts:
		for grown in Geometry2D.offset_polygon(part[0], OUTLINE_WIDTH, Geometry2D.JOIN_ROUND):
			outlines.append(grown)
	var bounds := Rect2(parts[0][0][0], Vector2.ZERO)
	for part in parts:
		for p in part[0]:
			bounds = bounds.expand(p)
	var entry := {
		"parts": parts,
		"outlines": outlines,
		"shines": [[Vector2(bounds.position.x + 4, bounds.position.y + 2.5), Vector2(bounds.end.x - 6, bounds.position.y + 2.5)]],
		"muzzle": Vector2(bounds.end.x, _muzzle_y(parts)),
	}
	_cache[kind] = entry
	return entry


## y дула — центр самой правой детали.
static func _muzzle_y(parts: Array) -> float:
	var best_x := -INF
	var best_y := 0.0
	for part in parts:
		var poly: PackedVector2Array = part[0]
		var max_x := -INF
		var sum_y := 0.0
		for p in poly:
			max_x = maxf(max_x, p.x)
			sum_y += p.y
		if max_x > best_x:
			best_x = max_x
			best_y = sum_y / poly.size()
	return best_y


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _poly(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		result.append(p)
	return result


static func _circle(center: Vector2, radius: float, segments: int = 12) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in segments:
		result.append(center + Vector2.from_angle(TAU * i / segments) * radius)
	return result


static func _grip(x: float, y: float, length: float = 11.0) -> PackedVector2Array:
	return _poly([Vector2(x, y), Vector2(x + 7, y), Vector2(x + 4, y + length), Vector2(x - 3, y + length)])


## [polygon, Part] в порядке отрисовки (сзади вперёд).
static func _shape(kind: StringName) -> Array:
	match kind:
		&"pistol":
			return [
				[_grip(-9, 0, 12), Part.GRIP],
				[_rect(-11, -2, 15, 3), Part.METAL],
				[_rect(-12, -8, 20, -2), Part.METAL_LIGHT],
				[_rect(-2, -8, 6, -6), Part.ACCENT],
				[_rect(-1, 3, 5, 6), Part.METAL],
			]
		&"smg":
			return [
				[_rect(-26, -5, -14, -2), Part.METAL],
				[_poly([Vector2(0, 2), Vector2(7, 2), Vector2(8, 15), Vector2(1, 15)]), Part.METAL],
				[_grip(-11, 1, 10), Part.GRIP],
				[_rect(-15, -7, 18, 2), Part.METAL_LIGHT],
				[_rect(18, -5, 30, -2), Part.METAL],
				[_rect(-8, -7, 4, -5), Part.ACCENT],
			]
		&"rifle":
			return [
				[_poly([Vector2(-34, -3), Vector2(-18, -6), Vector2(-18, 2), Vector2(-32, 7)]), Part.WOOD],
				[_poly([Vector2(-5, 1), Vector2(3, 1), Vector2(8, 13), Vector2(1, 15)]), Part.METAL],
				[_grip(-15, 1, 10), Part.WOOD_DARK],
				[_rect(-18, -6, 8, 2), Part.METAL],
				[_rect(8, -5, 21, 1), Part.WOOD],
				[_rect(21, -4, 38, -1), Part.METAL_LIGHT],
				[_rect(33, -8, 35, -4), Part.METAL],
				[_rect(-12, -7, -2, -6), Part.ACCENT],
			]
		&"shotgun":
			return [
				[_poly([Vector2(-34, -2), Vector2(-16, -6), Vector2(-16, 2), Vector2(-32, 8)]), Part.WOOD],
				[_grip(-14, 1, 9), Part.WOOD_DARK],
				[_rect(-16, -6, -4, 3), Part.METAL],
				[_rect(-4, -7, 36, -3), Part.METAL_LIGHT],
				[_rect(-4, -3, 36, 1), Part.METAL],
				[_rect(6, 0, 20, 4), Part.WOOD],
				[_rect(-12, -6, -8, -4), Part.ACCENT],
			]
		&"sniper":
			return [
				[_poly([Vector2(-36, -4), Vector2(-20, -5), Vector2(-20, 3), Vector2(-34, 6)]), Part.WOOD_DARK],
				[_grip(-16, 1, 10), Part.GRIP],
				[_rect(-20, -5, 12, 2), Part.METAL],
				[_rect(12, -3.5, 44, -0.5), Part.METAL_LIGHT],
				[_rect(-10, -12, 8, -6), Part.METAL],
				[_rect(6, -11, 10, -7), Part.ACCENT],
				[_poly([Vector2(20, 2), Vector2(22, 2), Vector2(16, 12), Vector2(14, 12)]), Part.METAL],
			]
		&"lmg":
			return [
				[_rect(-32, -5, -18, 3), Part.METAL],
				[_rect(-9, 3, 5, 15), Part.ACCENT_DARK],
				[_grip(-15, 2, 10), Part.GRIP],
				[_rect(-18, -8, 16, 3), Part.METAL],
				[_rect(-16, -10, 6, -8), Part.METAL_LIGHT],
				[_rect(16, -6, 32, 0), Part.METAL_LIGHT],
				[_rect(32, -4.5, 40, -1.5), Part.METAL],
				[_poly([Vector2(24, 0), Vector2(26, 0), Vector2(30, 12), Vector2(28, 12)]), Part.METAL],
			]
		&"launcher":
			return [
				[_grip(-6, 3, 10), Part.GRIP],
				[_rect(-28, -9, 28, 4), Part.METAL_LIGHT],
				[_rect(-20, -9, -14, 4), Part.ACCENT],
				[_rect(12, -9, 18, 4), Part.ACCENT],
				[_rect(28, -11, 34, 6), Part.METAL],
				[_rect(-6, -14, 2, -9), Part.METAL],
			]
		&"flamer":
			return [
				[_rect(-30, -6, -12, 9), Part.ACCENT_DARK],
				[_rect(-28, -4, -14, 0), Part.ACCENT],
				[_grip(-8, 2, 10), Part.GRIP],
				[_rect(-12, -6, 14, 2), Part.METAL],
				[_rect(14, -5, 30, -1), Part.METAL_LIGHT],
				[_rect(30, -7, 34, 1), Part.METAL],
			]
		&"rail":
			return [
				[_grip(-12, 1, 10), Part.GRIP],
				[_rect(-18, -6, 8, 2), Part.METAL],
				[_rect(8, -3.5, 42, -0.5), Part.METAL_LIGHT],
				[_rect(14, -6, 17, 2), Part.ACCENT],
				[_rect(24, -6, 27, 2), Part.ACCENT],
				[_rect(34, -6, 37, 2), Part.ACCENT],
			]
		&"prism":
			return [
				[_grip(-10, 1, 10), Part.GRIP],
				[_rect(-16, -7, 14, 3), Part.METAL],
				[_poly([Vector2(8, -11), Vector2(26, -2), Vector2(8, 7), Vector2(2, -2)]), Part.ACCENT],
				[_poly([Vector2(8, -11), Vector2(26, -2), Vector2(14, -3)]), Part.ACCENT_DARK],
				[_rect(26, -4, 34, 0), Part.METAL_LIGHT],
			]
		_:
			return [
				[_grip(-10, 1, 10), Part.GRIP],
				[_rect(-16, -8, 14, 3), Part.METAL],
				[_circle(Vector2(2, -2.5), 5.5), Part.ACCENT],
				[_rect(14, -6, 26, 1), Part.METAL_LIGHT],
				[_rect(26, -5, 30, 0), Part.ACCENT],
			]


## Иконка для интерфейса: вписывает ствол в размер контрола.
class IconRect:
	extends Control
	var kind: StringName = &"pistol"
	var accent := Color.WHITE
	var icon_scale := 1.0
	var tier := 0

	func _init(weapon_kind: StringName = &"pistol", color: Color = Color.WHITE, min_size: Vector2 = Vector2(96, 48)) -> void:
		kind = weapon_kind
		accent = color
		custom_minimum_size = min_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_weapon(weapon_kind: StringName, color: Color) -> void:
		kind = weapon_kind
		accent = color
		queue_redraw()

	func _draw() -> void:
		var fit := minf(size.x / 84.0, size.y / 32.0) * icon_scale
		WeaponIcons.draw(self, kind, size * 0.5 + Vector2(-2, -1) * fit, fit, 0.0, accent)
		for i in tier:
			var pip := Rect2(Vector2(4.0 + i * 9.0, size.y - 9.0), Vector2(7.0, 5.0))
			draw_rect(pip.grow(1.5), Color(0, 0, 0, 0.7))
			draw_rect(pip, WeaponIcons.TIER_COLORS[clampi(tier - 1, 0, 4)])
