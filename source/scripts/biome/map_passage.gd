class_name MapPassage
extends Node2D
## Рисунок прохода и управление дверью. Коллизии и поле пути принадлежат LevelSpawner.
var theme := "junk"
var door: DestructibleObject
var player: Player
var _hold := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(theme == "vault")


func on_opened(_object: DestructibleObject) -> void:
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if theme != "vault" or not is_instance_valid(door) or not door.is_intact():
		set_process(false)
		queue_redraw()
		return
	if not is_instance_valid(player):
		return
	var near := player.global_position.distance_squared_to(global_position + Vector2(0, 64)) < 90.0 * 90.0
	_hold = clampf(_hold + (delta if near else -delta * 2.0), 0.0, 2.0)
	if _hold >= 2.0:
		door.take_damage(door.hp)
	queue_redraw()


func _draw() -> void:
	var floor_color := Color("#574b39") if theme == "junk" else (Color("#4d4540") if theme == "vault" else Color("#55545e"))
	draw_rect(Rect2(-85, -160, 170, 320), Color(floor_color, 0.7))
	for i in 9:
		draw_line(Vector2(-85, -150 + i * 36), Vector2(85, -150 + i * 36), Color("#28231f"), 4)
	var open := not is_instance_valid(door) or not door.is_intact()
	var title := "ПРОХОД ОТКРЫТ" if open else ("СЛОМАТЬ ПРОХОД" if theme == "junk" else "СТОЙ У ДВЕРИ · 2 С")
	if theme == "roof":
		title = "УЗКИЙ ПЕРЕХОД"
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var at := Vector2(-width * 0.5, 155)
	draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, UiStyle.OUTLINE)
	draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiStyle.GOLD)
	if _hold > 0 and not open:
		draw_arc(Vector2(0, 64), 75, -PI * 0.5, -PI * 0.5 + TAU * _hold / 2.0, 24, UiStyle.GOLD, 5)
