class_name BossBar
extends Control
## Полоса здоровья босса. Для Хладгора (winged = true) — по паспорту Алтаря: рамка из двух
## неоновых драконьих крыльев, полоса ослепительно-белая; при ярости (< 30% ХП) шкала
## резко вспыхивает и становится ядовито-розовой. Для обычных боссов — строгая рамка.

const BAR_HEIGHT := 34.0
const WING_WIDTH := 70.0
const OUTLINE := Color("#071b25")
const WING_NEON := Color("#00ffff")
const WHITE_BAR := Color("#ffffff")
const FURY_PINK := Color("#ff2ea6")
const PLAIN_BAR := Color("#ffb020")
const FLASH_TIME := 0.5

var winged := false
var title := ""
var value := 1.0
var hp_now := 0.0
var hp_max := 0.0
var posture := -1.0
var broken := false

var _fury := false
var _flash := 0.0
var _time := 0.0
var _font: Font
var _back := UiStyle.box(Color("#140f24"), OUTLINE, 4, 10)
var _fill := UiStyle.box(PLAIN_BAR, OUTLINE, 4, 10)


func _init() -> void:
	custom_minimum_size = Vector2(560, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func configure(boss_title: String, is_winged: bool) -> void:
	title = boss_title.to_upper()
	winged = is_winged
	_fury = false
	value = 1.0
	posture = -1.0
	broken = false
	queue_redraw()


func set_title(boss_title: String) -> void:
	title = boss_title.to_upper()
	queue_redraw()


func set_health(hp: float, max_hp: float) -> void:
	value = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	hp_now = hp
	hp_max = max_hp
	queue_redraw()


## Выдержка босса: -1 — у этого босса шкалы нет (Хладгор), иначе доля 0…1; broken — босс оглушён.
func set_posture(fraction: float, is_broken: bool) -> void:
	if is_equal_approx(fraction, posture) and is_broken == broken:
		return
	posture = fraction
	broken = is_broken
	queue_redraw()


func set_fury() -> void:
	if _fury:
		return
	_fury = true
	_flash = FLASH_TIME


func _process(delta: float) -> void:
	_time += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
	if winged or _flash > 0.0:
		queue_redraw()


func _draw() -> void:
	var bar_rect := Rect2(WING_WIDTH, size.y - BAR_HEIGHT - 4.0, size.x - WING_WIDTH * 2.0, BAR_HEIGHT)
	var title_pos := Vector2(0, bar_rect.position.y - 8.0)
	var title_color := FURY_PINK if _fury else (Color("#bff6ff") if winged else Color("#ffd257"))
	draw_string_outline(_font, title_pos, title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 8, OUTLINE)
	draw_string(_font, title_pos, title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, title_color)

	if winged:
		_draw_wing(bar_rect, -1.0)
		_draw_wing(bar_rect, 1.0)
	draw_style_box(_back, bar_rect.grow(4.0))
	var fill_color := PLAIN_BAR
	if winged:
		fill_color = FURY_PINK if _fury else WHITE_BAR
	elif _fury:
		fill_color = FURY_PINK
	var fill := Rect2(bar_rect.position, Vector2(bar_rect.size.x * value, bar_rect.size.y))
	if fill.size.x >= 8.0:
		_fill.bg_color = fill_color
		_fill.set_content_margin_all(0)
		draw_style_box(_fill, fill)
		draw_rect(Rect2(fill.position + Vector2(6.0, 3.0), Vector2(fill.size.x - 12.0, 4.0)), Color(1, 1, 1, 0.3))
	var label := "%d / %d" % [ceili(hp_now), roundi(hp_max)]
	var text_y := bar_rect.position.y + bar_rect.size.y * 0.5 + 8.0
	draw_string_outline(_font, Vector2(bar_rect.position.x, text_y), label, HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, 22, 6, OUTLINE)
	draw_string(_font, Vector2(bar_rect.position.x, text_y), label, HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, 22, Color.WHITE)
	if posture >= 0.0:
		var pr := Rect2(bar_rect.position + Vector2(bar_rect.size.x * 0.15, bar_rect.size.y + 9.0), Vector2(bar_rect.size.x * 0.7, 9.0))
		draw_rect(pr.grow(3.0), OUTLINE)
		draw_rect(pr, Color("#140f24"))
		var pcolor := Color("#ffe27a") if broken else Color("#5cf3ff").lerp(Color("#ffffff"), posture * 0.6)
		draw_rect(Rect2(pr.position, Vector2(pr.size.x * posture, pr.size.y)), pcolor)
		if broken:
			draw_string_outline(_font, Vector2(0, pr.end.y + 22.0), "ОГЛУШЁН", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, 6, OUTLINE)
			draw_string(_font, Vector2(0, pr.end.y + 22.0), "ОГЛУШЁН", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color("#ffe27a"))
	if _flash > 0.0:
		draw_rect(bar_rect.grow(6.0), Color(1, 1, 1, _flash / FLASH_TIME * 0.9))


func _draw_wing(bar: Rect2, side: float) -> void:
	var anchor := Vector2(bar.position.x if side < 0.0 else bar.end.x, bar.get_center().y)
	var flap := sin(_time * 3.0) * 3.0
	var points := PackedVector2Array([
		anchor,
		anchor + Vector2(side * 22.0, -26.0 - flap),
		anchor + Vector2(side * 62.0, -30.0 - flap * 1.5),
		anchor + Vector2(side * 50.0, -12.0),
		anchor + Vector2(side * 66.0, -6.0 - flap * 0.5),
		anchor + Vector2(side * 44.0, 4.0),
		anchor + Vector2(side * 56.0, 14.0),
		anchor + Vector2(side * 18.0, 12.0),
	])
	var neon := FURY_PINK if _fury else WING_NEON
	draw_colored_polygon(points, Color(neon, 0.18))
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, OUTLINE, 6.0, true)
	draw_polyline(loop, neon, 2.5, true)
	for k in 3:
		draw_line(anchor, points[2 + k * 2], Color(neon, 0.6), 1.5, true)
