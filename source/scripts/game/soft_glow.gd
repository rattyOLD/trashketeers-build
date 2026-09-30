class_name SoftGlow
extends RefCounted
## Мягкие «лежащие на полу» свечения вместо плоских кругов и штриховых обводок: радиальный градиент
## и размытое кольцо строятся один раз, дальше это обычные draw_texture_rect — без аллокаций.
## squash < 1 сплющивает круг в эллипс перспективы пола.

const DISC_SIZE := 128
const RIM_SIZE := 256
const RIM_PEAK := 0.86

## Упрощённые эффекты (настройки): слабые слои свечения пропускаются.
static var lite := false
static var _disc: ImageTexture
static var _rim: ImageTexture


static func _disc_tex() -> ImageTexture:
	if _disc == null:
		var img := Image.create(DISC_SIZE, DISC_SIZE, false, Image.FORMAT_LA8)
		var half := DISC_SIZE * 0.5
		for y in DISC_SIZE:
			for x in DISC_SIZE:
				var r := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
				var a := 1.0 - smoothstep(0.0, 1.0, r)
				a = a * a * (3.0 - 2.0 * a)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_disc = ImageTexture.create_from_image(img)
	return _disc


static func _rim_tex() -> ImageTexture:
	if _rim == null:
		var img := Image.create(RIM_SIZE, RIM_SIZE, false, Image.FORMAT_LA8)
		var half := RIM_SIZE * 0.5
		for y in RIM_SIZE:
			for x in RIM_SIZE:
				var r := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
				var d := (r - RIM_PEAK) / 0.075
				var ring := exp(-d * d)
				var body := (1.0 - smoothstep(0.55, RIM_PEAK, r)) * 0.0 + smoothstep(0.3, RIM_PEAK, r) * 0.1
				var edge := 1.0 - smoothstep(0.96, 1.0, r)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(ring + body, 0.0, 1.0) * edge))
		_rim = ImageTexture.create_from_image(img)
	return _rim


static func pool(item: CanvasItem, at: Vector2, radius: float, squash: float, color: Color) -> void:
	if color.a <= 0.003 or radius <= 0.5 or (lite and color.a < 0.15):
		return
	item.draw_set_transform(at, 0.0, Vector2(1.0, squash))
	item.draw_texture_rect(_disc_tex(), Rect2(-radius, -radius, radius * 2.0, radius * 2.0), false, color)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## radius — внешний край свечения; пик кольца лежит на RIM_PEAK от него.
static func rim(item: CanvasItem, at: Vector2, radius: float, squash: float, color: Color) -> void:
	if color.a <= 0.003 or radius <= 0.5:
		return
	item.draw_set_transform(at, 0.0, Vector2(1.0, squash))
	item.draw_texture_rect(_rim_tex(), Rect2(-radius, -radius, radius * 2.0, radius * 2.0), false, color)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
