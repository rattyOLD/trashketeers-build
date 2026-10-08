class_name QuarterSign
extends Node2D
## Табличка квартала на столбике у двора: на Свалке — тёмная доска с неоновой надписью,
## в Банке — кремовая с золотой каймой. Рисуется один раз (без _process), сортируется по Y с миром.

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const FONT_SIZE := 22
const NEON: Array[Color] = [Color("#4dfff0"), Color("#ff5cc8"), Color("#ffb347"), Color("#7cff6b")]

static var _font: Font

var text := ""
var fancy := false
var tint := Color.WHITE


func setup(label: String, bank: bool, index: int) -> void:
	text = label.to_upper()
	fancy = bank
	tint = NEON[index % NEON.size()]
	queue_redraw()


func _draw() -> void:
	if _font == null:
		_font = load(FONT_PATH) as Font
	if _font == null or text.is_empty():
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 28.0
	var plate := Rect2(-w * 0.5, -98.0, w, 38.0)
	# Тень на земле и столбик.
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	var post := Color("#3a2c22") if not fancy else Color("#c9a24a")
	draw_rect(Rect2(-4.0, -62.0, 8.0, 62.0), post)
	draw_rect(Rect2(-4.0, -62.0, 3.0, 62.0), post.lightened(0.25))
	var base := Color("#1b1428") if not fancy else Color("#f6ecd2")
	var edge := tint.darkened(0.2) if not fancy else Color("#c9962e")
	var box := StyleBoxFlat.new()
	box.bg_color = base
	box.border_color = edge
	box.set_border_width_all(3)
	box.set_corner_radius_all(6)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	draw_style_box(box, plate)
	var at := Vector2(plate.position.x + 14.0, plate.position.y + 27.0)
	if fancy:
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color("#5a3a12"))
	else:
		# Неон: мягкое свечение обводкой, поверх — светлая «трубка».
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 8, Color(tint, 0.25))
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, tint.lightened(0.45))
