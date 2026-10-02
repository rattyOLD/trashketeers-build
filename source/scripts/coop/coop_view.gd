class_name CoopView
extends Control
## Клиентская отрисовка коопа. Получает снимки состояния (от сервера или от локальной арены тренировки), плавно
## двигает фигуры к новым позициям и рисует бой. Ввод: перетаскивание пальцем/мышью как виртуальный джойстик либо WASD/стрелки.
## Заглушки на кружках: настоящий арт придёт из блока M брифа Астры (кольца, сбитый герой, метки).

const WORLD_SCALE := 1.0
const STICK_RADIUS := 90.0
const SMOOTH := 22.0
const PLAYER_COLORS: Array[Color] = [Color("#00e5ff"), Color("#ff8a3d")]
const HP_MAX := 100.0

var my_id := 0
var names: Dictionary = {}      # peer_id -> имя
var move := Vector2.ZERO        # текущий вектор движения (джойстик или клавиатура)
var snap: Dictionary = {}

var _font: Font
var _players: Dictionary = {}   # id -> {pos: Vector2, hp, downed, alive, revive, aim, slot}
var _enemies: Dictionary = {}   # id -> {pos, target, type, frac}
var _bullets: Array = []
var _types: Array[String] = []
var _cam := Vector2.ZERO
var _dragging := false
var _origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _slots: Dictionary = {}     # id -> цвет по порядку появления
var _time := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = load("res://assets/fonts/RussoOne-Regular.ttf") as Font


func set_types(list: Array[String]) -> void:
	_types = list


func apply_snapshot(data: Dictionary) -> void:
	snap = data
	for item: Variant in data.get("p", []):
		var row := item as Array
		var id := int(row[0])
		if not _slots.has(id):
			_slots[id] = _slots.size() % PLAYER_COLORS.size()
		var target := Vector2(float(row[1]), float(row[2]))
		var state: Dictionary = _players.get(id, {"pos": target})
		state["target"] = target
		state["hp"] = float(row[3])
		state["downed"] = int(row[4]) == 1
		state["aim"] = float(row[5])
		state["alive"] = int(row[6]) == 1
		state["revive"] = float(row[7])
		_players[id] = state
	var seen: Dictionary = {}
	for item: Variant in data.get("e", []):
		var row := item as Array
		var id := int(row[0])
		seen[id] = true
		var target := Vector2(float(row[2]), float(row[3]))
		var state: Dictionary = _enemies.get(id, {"pos": target})
		state["target"] = target
		state["type"] = int(row[1])
		state["frac"] = float(row[4])
		_enemies[id] = state
	for id: int in _enemies.keys():
		if not seen.has(id):
			_enemies.erase(id)
	_bullets = data.get("b", [])


func _process(delta: float) -> void:
	_time += delta
	var blend := 1.0 - exp(-SMOOTH * delta)
	for id: int in _players:
		var state: Dictionary = _players[id]
		if state.has("target"):
			state["pos"] = (state["pos"] as Vector2).lerp(state["target"] as Vector2, blend)
	for id: int in _enemies:
		var state: Dictionary = _enemies[id]
		state["pos"] = (state["pos"] as Vector2).lerp(state["target"] as Vector2, blend)
	if _players.has(my_id):
		_cam = _cam.lerp((_players[my_id] as Dictionary)["pos"] as Vector2, 1.0 - exp(-10.0 * delta))
	var keys := Vector2(
		(1.0 if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT) else 0.0),
		(1.0 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) else 0.0))
	move = _stick if _stick.length() > 0.05 else keys.limit_length(1.0)
	queue_redraw()


## Касание приходит и как касание, и как эмулированная мышь: обрабатываем только мышь, иначе джойстик дёргался бы дважды.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		_dragging = button.pressed
		_origin = button.position
		if not button.pressed:
			_stick = Vector2.ZERO
	elif event is InputEventMouseMotion and _dragging:
		_stick = ((event as InputEventMouseMotion).position - _origin) / STICK_RADIUS
		_stick = _stick.limit_length(1.0)


func _to_screen(world: Vector2) -> Vector2:
	return size * 0.5 + (world - _cam) * WORLD_SCALE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#11222a"))
	_draw_floor()
	for id: int in _enemies:
		var e: Dictionary = _enemies[id]
		var at := _to_screen(e["pos"] as Vector2)
		if not Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(at):
			continue
		var hue := fmod(float(int(e["type"])) * 0.137, 1.0)
		var color := Color.from_hsv(hue, 0.6, 0.95)
		var radius := 17.0 * WORLD_SCALE * 1.3
		draw_circle(at, radius + 2.0, Color("#071b25"))
		draw_circle(at, radius, color)
		if float(e["frac"]) < 0.999:
			draw_rect(Rect2(at + Vector2(-radius, -radius - 8.0), Vector2(radius * 2.0, 4.0)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(at + Vector2(-radius, -radius - 8.0), Vector2(radius * 2.0 * float(e["frac"]), 4.0)), Color("#ff4d6d"))
	for item: Variant in _bullets:
		var row := item as Array
		draw_circle(_to_screen(Vector2(float(row[0]), float(row[1]))), 4.0, Color("#ffe066"))
	for id: int in _players:
		_draw_player(id, _players[id] as Dictionary)
	_draw_hud()


func _draw_floor() -> void:
	var step := 200.0
	var top_left := _cam - size * 0.5 / WORLD_SCALE
	var bottom_right := _cam + size * 0.5 / WORLD_SCALE
	var x := floorf(top_left.x / step) * step
	while x < bottom_right.x:
		draw_line(_to_screen(Vector2(x, top_left.y)), _to_screen(Vector2(x, bottom_right.y)), Color(1, 1, 1, 0.05), 2.0)
		x += step
	var y := floorf(top_left.y / step) * step
	while y < bottom_right.y:
		draw_line(_to_screen(Vector2(top_left.x, y)), _to_screen(Vector2(bottom_right.x, y)), Color(1, 1, 1, 0.05), 2.0)
		y += step
	var arena := Rect2(CoopArena.ARENA.position, CoopArena.ARENA.size)
	draw_rect(Rect2(_to_screen(arena.position), arena.size * WORLD_SCALE), Color("#ff8a3d"), false, 4.0)


func _draw_player(id: int, state: Dictionary) -> void:
	var at := _to_screen(state["pos"] as Vector2)
	var color := PLAYER_COLORS[int(_slots.get(id, 0))]
	var radius := 22.0 * WORLD_SCALE * 1.2
	if not bool(state["alive"]):
		draw_circle(at, radius, Color(0.3, 0.3, 0.3, 0.5))
		return
	if bool(state["downed"]):
		draw_circle(at, radius + 4.0, Color("#071b25"))
		draw_circle(at, radius, Color(0.45, 0.45, 0.5))
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_arc(at, radius + 10.0, 0.0, TAU, 32, Color(1, 0.2, 0.3, 0.4 + 0.5 * pulse), 3.0)
		var progress := clampf(float(state["revive"]), 0.0, 1.0)
		if progress > 0.0:
			draw_arc(at, radius + 18.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, color, 5.0)
		_text(at + Vector2(0, -radius - 28.0), "ПОДНИМИ!", 16, Color("#ffd257"))
	else:
		draw_circle(at, radius + 3.0, Color("#071b25"))
		draw_circle(at, radius, color)
		var aim := float(state["aim"])
		draw_line(at, at + Vector2.from_angle(aim) * (radius + 10.0), Color.WHITE, 3.0)
		var frac := clampf(float(state["hp"]) / HP_MAX, 0.0, 1.0)
		draw_rect(Rect2(at + Vector2(-radius, radius + 6.0), Vector2(radius * 2.0, 5.0)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(at + Vector2(-radius, radius + 6.0), Vector2(radius * 2.0 * frac, 5.0)), Color("#35c46a") if frac > 0.3 else Color("#ff4d6d"))
	_text(at + Vector2(0, -radius - 8.0), str(names.get(id, "Енот")), 16, color)
	if id != my_id and not Rect2(Vector2.ZERO, size).has_point(at):
		_draw_arrow(at, color)


## Напарник за краем экрана: стрелка у края в его цвете.
func _draw_arrow(world_screen_pos: Vector2, color: Color) -> void:
	var center := size * 0.5
	var dir := (world_screen_pos - center).normalized()
	var edge := center + dir * (minf(size.x, size.y) * 0.5 - 40.0)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([edge + dir * 18.0, edge - dir * 10.0 + side * 12.0, edge - dir * 10.0 - side * 12.0]), color)


func _draw_hud() -> void:
	var wave := int(snap.get("wave", 0))
	var waves := int(snap.get("waves", 0))
	var enemies := (snap.get("e", []) as Array).size()
	_text(Vector2(size.x * 0.5, 42.0), "ВОЛНА %d / %d" % [wave, waves], 28, Color.WHITE)
	_text(Vector2(size.x * 0.5, 72.0), "Врагов: %d" % enemies, 18, Color("#cdf0ff"))
	if int(snap.get("phase", 0)) == CoopArena.Phase.INTERMISSION:
		_text(size * 0.5 + Vector2(0, -120.0), "ВОЛНА ОЧИЩЕНА", 40, Color("#ffd257"))
	elif int(snap.get("phase", 0)) == CoopArena.Phase.INTRO:
		_text(size * 0.5 + Vector2(0, -120.0), "ВОЛНА %d" % wave, 40, Color("#00e5ff"))
	if _players.has(my_id):
		var me: Dictionary = _players[my_id]
		var frac := clampf(float(me["hp"]) / HP_MAX, 0.0, 1.0)
		var bar := Rect2(Vector2(24.0, size.y - 52.0), Vector2(260.0, 22.0))
		draw_rect(bar.grow(3.0), Color("#071b25"))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("#35c46a") if frac > 0.3 else Color("#ff4d6d"))
		if bool(me["downed"]):
			_text(size * 0.5 + Vector2(0, 60.0), "ТЕБЯ СБИЛИ. ЖДИ НАПАРНИКА", 26, Color("#ff4d6d"))
		elif not bool(me["alive"]):
			_text(size * 0.5 + Vector2(0, 60.0), "ТЫ ВЫБЫЛ", 26, Color("#ff4d6d"))
	if _dragging:
		draw_arc(_origin, STICK_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 3.0)
		draw_circle(_origin + _stick * STICK_RADIUS, 26.0, Color(1, 1, 1, 0.35))


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := at - Vector2(width * 0.5, 0.0)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color("#071b25"))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
