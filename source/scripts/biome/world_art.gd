class_name WorldArt
extends RefCounted
## Рисунки объектов нового Выживания (Астра, бриф v29: assets/world/). Ленивые текстуры с кэшем и рисование
## кадра атласа «ногами» на точку узла (низ видимой части рисунка — на y = 0).

const DIR := "res://assets/world/"
static var _tex := {}
static var _feet := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := DIR + name + ".png"
		_tex[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[name]


## Отступ от низа ячейки до низа нарисованного (прозрачные поля снизу), в пикселях рисунка.
static func _foot(name: String, t: Texture2D, cell: Vector2) -> float:
	if not _feet.has(name):
		var pad := 0.0
		var image := t.get_image()
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			var used := image.get_region(Rect2i(Vector2i.ZERO, Vector2i(cell))).get_used_rect()
			pad = cell.y - float(used.end.y)
		_feet[name] = pad
	return _feet[name]


## Рисует кадр frame атласа name (ячейки cell, в ряду columns) с масштабом scale, низом на (0, 0) узла ci.
## centered — для плоских объектов (ринг): центр рисунка на точку узла.
static func draw(ci: CanvasItem, name: String, scale: float, frame: int = 0, cell := Vector2.ZERO, columns: int = 1,
		modulate := Color.WHITE, centered := false) -> bool:
	var t := tex(name)
	if t == null:
		return false
	var c := cell if cell != Vector2.ZERO else t.get_size()
	var src := Rect2(Vector2(frame % columns, frame / columns) * c, c)
	var origin := Vector2(-c.x * 0.5, -c.y * 0.5) if centered else Vector2(-c.x * 0.5, -c.y + _foot(name, t, c))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale)
	ci.draw_texture_rect_region(t, Rect2(origin, c), src, modulate)
	ci.draw_set_transform(Vector2.ZERO)
	return true
