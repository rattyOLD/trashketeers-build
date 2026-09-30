class_name Icons
extends RefCounted
## Процедурные иконки валют (кэшируются): не тянем PNG ради 24-пиксельных значков.

const OUTLINE := Color("#180e22")

static var _star_dust: ImageTexture


## Четырёхлучевая искра «Звёздной Пыли».
static func star_dust() -> ImageTexture:
	if _star_dust != null:
		return _star_dust
	var size := 28
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := (Vector2(x + 0.5, y + 0.5) - center).abs()
			var star := pow(p.x / 13.0, 0.5) + pow(p.y / 13.0, 0.5)
			var color := Color(0, 0, 0, 0)
			if star <= 1.18:
				color = OUTLINE
			if star <= 1.0:
				color = Color("#fff4fe").lerp(Color("#c8a8ff"), clampf(star, 0.0, 1.0))
			if p.length() < 2.5:
				color = Color.WHITE
			image.set_pixel(x, y, color)
	_star_dust = ImageTexture.create_from_image(image)
	return _star_dust
