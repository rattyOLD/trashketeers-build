class_name OrderCard
extends Control
## Карточка ежедневного заказа Нэлл в сюжетном HUD: бумажный ярлык, название и полоса прогресса.

const SIZE := Vector2(360.0, 62.0)
const INK := Color("#5ff2ff")
const DONE := Color("#7cff6b")
const GOAL_H := 26.0

var _title := ""
var _progress := 0
var _goal := 1
var _done := false
var _shown := 0.0
var _flash := 0.0
var _panel: StyleBoxFlat
var _goals: Array = []


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = UiStyle.box(Color(0.04, 0.06, 0.12, 0.62), Color(INK, 0.75), 3, 10)
	visible = false


func set_order(title: String, progress: int, goal: int, done: bool) -> void:
	if title.is_empty():
		visible = false
		return
	visible = true
	if progress > _progress and _title == title:
		_flash = 1.0
	if done and not _done:
		_flash = 1.0
	var changed := title != _title or progress != _progress or goal != _goal or done != _done
	_title = title
	_progress = progress
	_goal = maxi(goal, 1)
	_done = done
	if changed:
		queue_redraw()
		set_process(true)


func set_goals(goals: Array) -> void:
	var same := goals.size() == _goals.size()
	if same:
		for i in goals.size():
			if goals[i] != _goals[i]:
				same = false
				break
	if same:
		return
	_goals = goals.duplicate(true)
	custom_minimum_size = Vector2(SIZE.x, SIZE.y + _goals.size() * GOAL_H)
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if _done else float(_progress) / float(_goal)
	_shown = move_toward(_shown, target, delta * 1.6)
	_flash = maxf(_flash - delta * 2.0, 0.0)
	queue_redraw()
	if is_equal_approx(_shown, target) and _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	var accent := DONE if _done else INK
	_panel.border_color = Color(accent, 0.75 + _flash * 0.25)
	draw_style_box(_panel, Rect2(Vector2.ZERO, SIZE + Vector2(0.0, _goals.size() * GOAL_H)))
	var tag := Rect2(8.0, 8.0, 86.0, 18.0)
	draw_rect(tag, Color(accent, 0.9))
	var font := ThemeDB.fallback_font
	draw_string(font, tag.position + Vector2(0.0, 13.5), "ЗАКАЗ НЭЛЛ", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 13, Color("#06141c"))
	var text := "ГОТОВО" if _done else "%d / %d" % [_progress, _goal]
	draw_string(font, Vector2(SIZE.x - 68.0, 22.0), text, HORIZONTAL_ALIGNMENT_RIGHT, 58.0, 15, accent)
	draw_string(font, Vector2(104.0, 22.0), _title, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 216.0, 13, Color(1, 1, 1, 0.9))
	if not _done:
		var coin := Vector2(SIZE.x - 108.0, 16.0)
		draw_circle(coin, 7.0, Color("#1a1030"))
		draw_circle(coin, 5.6, Color("#ffc233"))
		draw_arc(coin, 3.2, 0.5, 4.0, 10, Color("#b36b00"), 1.5, true)
		var gem := Vector2(SIZE.x - 90.0, 16.0)
		draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -8), gem + Vector2(7, 0), gem + Vector2(0, 8), gem + Vector2(-7, 0)]), Color("#1a1030"))
		draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -6), gem + Vector2(5, 0), gem + Vector2(0, 6), gem + Vector2(-5, 0)]), Color("#b46bff"))
	var bar := Rect2(8.0, 38.0, SIZE.x - 16.0, 14.0)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	var fill := Rect2(bar.position, Vector2(bar.size.x * _shown, bar.size.y))
	draw_rect(fill, Color(accent, 0.85))
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 4.0)), Color(1, 1, 1, 0.25))
	for i in range(1, mini(_goal, 12)):
		var x := bar.position.x + bar.size.x * float(i) / float(_goal)
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.5), 1.0)
	draw_rect(bar, Color(accent, 0.6 + _flash * 0.4), false, 1.5)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(accent, _flash * 0.18))
	var y := SIZE.y - 4.0
	for goal: Dictionary in _goals:
		var done := bool(goal.get("done", false))
		var color := DONE if done else Color("#ffd257")
		var gp := int(goal.get("progress", 0))
		var gg := maxi(int(goal.get("goal", 1)), 1)
		draw_string(font, Vector2(12.0, y + 17.0), str(goal.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, 128.0, 15, Color(1, 1, 1, 0.85))
		var track := Rect2(144.0, y + 7.0, SIZE.x - 144.0 - 70.0, 9.0)
		draw_rect(track, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(float(gp) / float(gg), 0.0, 1.0), track.size.y)), Color(color, 0.85))
		draw_rect(track, Color(color, 0.5), false, 1.0)
		draw_string(font, Vector2(SIZE.x - 62.0, y + 17.0), "%d/%d" % [gp, gg], HORIZONTAL_ALIGNMENT_RIGHT, 52.0, 15, color)
		y += GOAL_H
