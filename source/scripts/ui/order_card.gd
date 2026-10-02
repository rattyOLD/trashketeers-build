class_name OrderCard
extends Control
## Карточка ежедневного заказа Нэлл в сюжетном HUD: бумажный ярлык, название и полоса прогресса.

signal pressed

const SIZE := Vector2(350.0, 46.0)
const INK := Color("#5ff2ff")
const DONE := Color("#7cff6b")
const GOAL_H := 30.0

var _title := ""
var _progress := 0
var _goal := 1
var _done := false
var _shown := 0.0
var _flash := 0.0
var _panel: StyleBoxFlat
var _goals: Array = []
## «Минимальный худ»: карточка не показывается вовсе.
var minimal := false
## Показ «выполнено»: плашка горит зелёным, потом гаснет, и появляется следующий заказ.
const CELEBRATE_TIME := 1.6
const FADE_TIME := 0.35
var _celebrate := 0.0
var _pending: Array = []


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_panel = UiStyle.box(Color(0.04, 0.06, 0.12, 0.62), Color(INK, 0.75), 3, 10)
	visible = false


## Заказ только что выполнен: показываем «ГОТОВО», затем плашка гаснет и уступает место новому заказу.
func celebrate(title: String, goal: int) -> void:
	if minimal:
		return
	visible = true
	_celebrate = CELEBRATE_TIME
	_title = title
	_goal = maxi(goal, 1)
	_progress = _goal
	_done = true
	_shown = 1.0
	_flash = 1.0
	modulate.a = 1.0
	set_process(true)
	queue_redraw()


func set_order(title: String, progress: int, goal: int, done: bool) -> void:
	if _celebrate > 0.0:
		_pending = [title, progress, goal, done]
		return
	if title.is_empty() or minimal:
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
	if minimal:
		return
	var same := goals.size() == _goals.size()
	if same:
		for i in goals.size():
			if goals[i] != _goals[i]:
				same = false
				break
	if same:
		return
	_goals = goals.duplicate(true)
	custom_minimum_size = Vector2(SIZE.x, SIZE.y + (GOAL_H if not _goals.is_empty() else 0.0))
	queue_redraw()


func _process(delta: float) -> void:
	if _celebrate > 0.0:
		_celebrate -= delta
		_flash = maxf(_flash, 0.5 if int(_celebrate * 6.0) % 2 == 0 else 0.0)
		modulate.a = clampf(_celebrate / FADE_TIME, 0.0, 1.0)
		queue_redraw()
		if _celebrate <= 0.0:
			var next := _pending
			_pending = []
			_shown = 0.0
			_done = false
			_progress = 0
			if not next.is_empty():
				set_order(str(next[0]), int(next[1]), int(next[2]), bool(next[3]))
			var tween := create_tween()
			tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
		return
	var target := 1.0 if _done else float(_progress) / float(_goal)
	_shown = move_toward(_shown, target, delta * 1.6)
	_flash = maxf(_flash - delta * 2.0, 0.0)
	queue_redraw()
	if is_equal_approx(_shown, target) and _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	var accent := DONE if _done else INK
	_panel.border_color = Color(accent, 0.75 + _flash * 0.25)
	var extra := GOAL_H if not _goals.is_empty() else 0.0
	draw_style_box(_panel, Rect2(Vector2.ZERO, SIZE + Vector2(0.0, extra)))
	var font := ThemeDB.fallback_font
	var tag := Rect2(6.0, 6.0, 56.0, 15.0)
	draw_rect(tag, Color(accent, 0.9))
	draw_string(font, tag.position + Vector2(0.0, 11.5), "ЗАКАЗ", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 12, Color("#06141c"))
	var text := "ГОТОВО" if _done else "%d / %d" % [_progress, _goal]
	draw_string(font, Vector2(SIZE.x - 64.0, 19.0), text, HORIZONTAL_ALIGNMENT_RIGHT, 58.0, 14, accent)
	draw_string(font, Vector2(68.0, 19.0), _title, HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 140.0, 13, Color(1, 1, 1, 0.9))
	var bar := Rect2(6.0, 28.0, SIZE.x - 12.0, 10.0)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	var fill := Rect2(bar.position, Vector2(bar.size.x * _shown, bar.size.y))
	draw_rect(fill, Color(accent, 0.85))
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 3.0)), Color(1, 1, 1, 0.25))
	for i in range(1, mini(_goal, 12)):
		var x := bar.position.x + bar.size.x * float(i) / float(_goal)
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.5), 1.0)
	draw_rect(bar, Color(accent, 0.6 + _flash * 0.4), false, 1.5)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(accent, _flash * 0.18))
	if _goals.is_empty():
		return
	var cell := (SIZE.x - 12.0) / float(_goals.size())
	for i in _goals.size():
		var goal: Dictionary = _goals[i]
		var color := DONE if bool(goal.get("done", false)) else Color("#ffd257")
		var gp := int(goal.get("progress", 0))
		var gg := maxi(int(goal.get("goal", 1)), 1)
		var x := 6.0 + cell * i
		draw_string(font, Vector2(x + 2.0, SIZE.y + 11.0), "%s %d/%d" % [str(goal.get("title", "")), gp, gg], HORIZONTAL_ALIGNMENT_LEFT, cell - 8.0, 12, color)
		var track := Rect2(x + 2.0, SIZE.y + 16.0, cell - 10.0, 5.0)
		draw_rect(track, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(float(gp) / float(gg), 0.0, 1.0), track.size.y)), Color(color, 0.85))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		pressed.emit()
		accept_event()
