class_name BossBar
extends Control
## Полоса здоровья босса. Для Хладгора (winged = true) — по паспорту Алтаря: рамка из двух
## неоновых драконьих крыльев, полоса ослепительно-белая; при ярости (< 30% ХП) шкала
## резко вспыхивает и становится ядовито-розовой. Для обычных боссов — строгая рамка.

const BAR_HEIGHT := 34.0
const WING_WIDTH := 70.0
const OUTLINE := Color("#22211f")
const WING_NEON := Color("#ff8200")
const WHITE_BAR := Color("#ffffff")
const FURY_PINK := Color("#ff8a3d")
const PLAIN_BAR := Color("#ffb020")
const FLASH_TIME := 0.5

var winged := false
var title := ""
var value := 1.0
var hp_now := 0.0
var hp_max := 0.0
var posture := -1.0
var broken := false
## Телефонная шапка: всё (шкала оглушения, «ОГЛУШЁН») — внутри своего прямоугольника, ниже ничего не торчит.
var compact := false

var _fury := false
var _flash := 0.0
var _time := 0.0
var _font: Font
var _back := UiStyle.box(Color("#21201e"), OUTLINE, 4, 10)
var _fill := UiStyle.box(PLAIN_BAR, OUTLINE, 4, 10)
## Рамка с черепом и табличка имени (набор интерфейса Астры, assets/ui/kit/); нет файлов — рисуем как раньше.
var _frame_tex: Texture2D = load(FRAME_PATH) if ResourceLoader.exists(FRAME_PATH) else null
var _plate_tex: Texture2D = load(PLATE_PATH) if ResourceLoader.exists(PLATE_PATH) else null
const FRAME_PATH := "res://assets/ui/kit/boss_bar_frame.png"
const PLATE_PATH := "res://assets/ui/kit/boss_name_plate.png"
## Внутреннее окно рамки (в пикселях файла 640×80) и череп по центру верхней планки.
const FRAME_INNER := Rect2(44, 31, 552, 28)
const FRAME_SKULL := Vector2(268, 372)
const PLATE_BAND := Rect2(0, 4, 640, 32)
const PLATE_CAP := 40.0
## Толщина планок рамки относительно файла: в исходнике они втрое выше шкалы.
const BORDER_K := 0.55


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
	if compact:
		var side := WING_WIDTH if winged else 8.0
		var bar_h := 28.0
		bar_rect = Rect2(side, size.y - bar_h - 6.0 - (14.0 if posture >= 0.0 else 0.0), size.x - side * 2.0, bar_h)
	var title_pos := Vector2(0, bar_rect.position.y - 8.0)
	if _frame_tex != null and not winged:
		title_pos.y = bar_rect.position.y - FRAME_INNER.position.y * BORDER_K - 5.0
	var title_color := FURY_PINK if _fury else (Color("#ffd6ac") if winged else Color("#ffd257"))
	var shown_title := (title + " · ОГЛУШЁН") if compact and broken and posture >= 0.0 else title
	if _plate_tex != null and not winged:
		var tw := _font.get_string_size(shown_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 70.0
		_draw_plate(Rect2((size.x - tw) * 0.5, title_pos.y - 27.0, tw, 34.0))
	draw_string_outline(_font, title_pos, shown_title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 8, OUTLINE)
	draw_string(_font, title_pos, shown_title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, title_color)

	if winged:
		_draw_wing(bar_rect, -1.0)
		_draw_wing(bar_rect, 1.0)
	if _frame_tex != null and not winged:
		draw_rect(bar_rect, Color("#21201e"))
	else:
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
	if _frame_tex != null and not winged:
		_draw_frame(bar_rect)
	var label := "%d / %d" % [ceili(hp_now), roundi(hp_max)]
	var text_y := bar_rect.position.y + bar_rect.size.y * 0.5 + 8.0
	draw_string_outline(_font, Vector2(bar_rect.position.x, text_y), label, HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, 22, 6, OUTLINE)
	draw_string(_font, Vector2(bar_rect.position.x, text_y), label, HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, 22, Color.WHITE)
	if posture >= 0.0:
		var pr := Rect2(bar_rect.position + Vector2(bar_rect.size.x * 0.15, bar_rect.size.y + 9.0), Vector2(bar_rect.size.x * 0.7, 9.0))
		if compact:
			pr = Rect2(bar_rect.position + Vector2(bar_rect.size.x * 0.15, bar_rect.size.y + 7.0), Vector2(bar_rect.size.x * 0.7, 6.0))
		draw_rect(pr.grow(3.0), OUTLINE)
		draw_rect(pr, Color("#21201e"))
		var pcolor := Color("#ffe27a") if broken else Color("#ffab53").lerp(Color("#ffffff"), posture * 0.6)
		draw_rect(Rect2(pr.position, Vector2(pr.size.x * posture, pr.size.y)), pcolor)
		if broken and not compact:
			draw_string_outline(_font, Vector2(0, pr.end.y + 22.0), "ОГЛУШЁН", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, 6, OUTLINE)
			draw_string(_font, Vector2(0, pr.end.y + 22.0), "ОГЛУШЁН", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color("#ffe27a"))
	if _flash > 0.0:
		draw_rect(bar_rect.grow(6.0), Color(1, 1, 1, _flash / FLASH_TIME * 0.9))


## Рамка Астры вокруг шкалы: окно рамки точно по шкале, планки и края — в масштабе BORDER_K (тоньше исходника),
## череп и края не растягиваются, ровные куски планок тянутся.
func _draw_frame(bar: Rect2) -> void:
	var kb := BORDER_K
	var rows := [Vector2(0, FRAME_INNER.position.y), Vector2(FRAME_INNER.position.y, FRAME_INNER.end.y), Vector2(FRAME_INNER.end.y, 80.0)]
	var heights := [FRAME_INNER.position.y * kb, bar.size.y, (80.0 - FRAME_INNER.end.y) * kb]
	var cap := FRAME_INNER.position.x
	var left := bar.position.x - cap * kb
	var right := bar.end.x + cap * kb
	var mid := (left + right) * 0.5
	var skull_w := (FRAME_SKULL.y - FRAME_SKULL.x) * kb
	# Колонки: [x на экране, ширина, x в файле, ширина в файле].
	var cols := [
		[left, cap * kb, 0.0, cap],
		[left + cap * kb, mid - skull_w * 0.5 - left - cap * kb, cap, FRAME_SKULL.x - cap],
		[mid - skull_w * 0.5, skull_w, FRAME_SKULL.x, FRAME_SKULL.y - FRAME_SKULL.x],
		[mid + skull_w * 0.5, right - cap * kb - mid - skull_w * 0.5, FRAME_SKULL.y, 640.0 - cap - FRAME_SKULL.y],
		[right - cap * kb, cap * kb, 640.0 - cap, cap],
	]
	var y: float = bar.position.y - heights[0]
	for r in 3:
		for c: Array in cols:
			if r == 1 and (c[2] > cap - 1.0 and c[2] < 640.0 - cap - 1.0):
				continue
			draw_texture_rect_region(_frame_tex, Rect2(c[0], y, c[1], heights[r]), Rect2(c[2], rows[r].x, c[3], rows[r].y - rows[r].x))
		y += heights[r]


## Табличка под имя босса: края без растяжения, середина тянется.
func _draw_plate(r: Rect2) -> void:
	var k := r.size.y / PLATE_BAND.size.y
	var cap := PLATE_CAP * k
	draw_texture_rect_region(_plate_tex, Rect2(r.position, Vector2(cap, r.size.y)), Rect2(0, PLATE_BAND.position.y, PLATE_CAP, PLATE_BAND.size.y))
	draw_texture_rect_region(_plate_tex, Rect2(r.position.x + cap, r.position.y, r.size.x - cap * 2.0, r.size.y), Rect2(PLATE_CAP, PLATE_BAND.position.y, 640.0 - PLATE_CAP * 2.0, PLATE_BAND.size.y))
	draw_texture_rect_region(_plate_tex, Rect2(r.end.x - cap, r.position.y, cap, r.size.y), Rect2(640.0 - PLATE_CAP, PLATE_BAND.position.y, PLATE_CAP, PLATE_BAND.size.y))


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
