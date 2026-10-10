class_name MapPassage
extends Node2D
## Рисунок прохода и управление дверью. Коллизии и поле пути принадлежат LevelSpawner.
var theme := "junk"
var door: DestructibleObject
var player: Player
var _hold := 0.0
var _floor_mesh: ArrayMesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(theme == "vault")
	_build_floor()


func _build_floor() -> void:
	var mesh := FlatMesh.new()
	var base := Color("#65543f") if theme == "junk" else (Color("#696352") if theme == "vault" else Color("#455258"))
	var edge := Color("#b5874e") if theme != "roof" else Color("#7ca1a3")
	mesh.rect(Rect2(-91, -162, 182, 324), Color("#211f1c"))
	mesh.rect(Rect2(-82, -157, 164, 314), Color(base, 0.92))
	for x in [-85, 85]:
		mesh.line(Vector2(x, -160), Vector2(x, 160), edge, 4)
	for i in 9:
		var y := -144 + i * 36
		mesh.line(Vector2(-80, y), Vector2(80, y), Color("#2d302c"), 3)
		mesh.line(Vector2(-80, y + 3), Vector2(80, y + 3), Color(edge, 0.25), 1)
		for x in [-75, 75]:
			mesh.circle(Vector2(x, y + 12), 2.5, edge, 8)
	if theme == "vault":
		for y in [-108, -36, 36, 108]:
			mesh.line(Vector2(0, y - 30), Vector2(0, y + 30), Color("#b2aa91"), 2)
	else:
		for y in [-148, 132]:
			mesh.rect(Rect2(-79, y, 158, 13), Color("#292a25"))
			for i in 8:
				mesh.polygon(PackedVector2Array([Vector2(-78 + i * 20, y), Vector2(-66 + i * 20, y), Vector2(-58 + i * 20, y + 13), Vector2(-70 + i * 20, y + 13)]), Color(edge, 0.8))
	_floor_mesh = mesh.commit()


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
	if _floor_mesh != null:
		draw_mesh(_floor_mesh, null)
	var open := not is_instance_valid(door) or not door.is_intact()
	var title := "ПРОХОД ОТКРЫТ" if open else ("СЛОМАТЬ ПРОХОД" if theme == "junk" else "СТОЙ У ДВЕРИ · 2 С")
	if theme == "roof":
		title = "УЗКИЙ ПЕРЕХОД"
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var at := Vector2(-width * 0.5, 100)
	draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, UiStyle.OUTLINE)
	draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiStyle.GOLD)
	if _hold > 0 and not open:
		draw_arc(Vector2(0, 64), 75, -PI * 0.5, -PI * 0.5 + TAU * _hold / 2.0, 24, UiStyle.GOLD, 5)
