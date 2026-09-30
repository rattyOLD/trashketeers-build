class_name LastEnemyMarker
extends Node2D
## Подсветка последних врагов волны: когда их осталось меньше LIMIT и новых не будет, каждого
## окутывает мягкое бирюзовое свечение (ореол за телом + «лужа» под ногами), а тех, кто за
## экраном, показывает аккуратная стрелка у края. Один узел рисует всех сразу — без нод на врага.

const LIMIT := 5
const COLOR := Color("#5cf3ff")
const EDGE_MARGIN := 58.0
const FADE_SPEED := 2.5
## Враги от этого радиуса получают подпись «ПОСЛЕДНИЙ» — крупных проще потерять из виду.
const LABEL_RADIUS := 20.0
const LABEL_COLOR := Color(0.85, 1.0, 1.0)

var _director: WaveDirector
var _enemies: EnemyManager
var _camera: Camera2D
var _shown: Array[Enemy] = []
var _fade := 0.0
var _clock := 0.0
## Секунды с момента, когда осталось меньше LIMIT врагов; замирает на зачистке, сбрасывается новой волной.
var hunt_time := 0.0
var _hunting := false


func setup(director: WaveDirector, enemies: EnemyManager, camera: Camera2D) -> void:
	_director = director
	_enemies = enemies
	_camera = camera
	z_index = 3


func reset_hunt() -> void:
	hunt_time = 0.0
	_hunting = false


func _process(delta: float) -> void:
	_clock += delta
	_shown.clear()
	var left := _director.get_enemies_left()
	var active := _director.remaining_to_spawn <= 0 and left < LIMIT
	if active and left > 0:
		_hunting = true
	if _hunting and left > 0:
		hunt_time += delta
	if active:
		for enemy in _enemies.get_active():
			if enemy.is_alive() and not enemy.data.is_boss():
				_shown.append(enemy)
	var target := 1.0 if not _shown.is_empty() else 0.0
	_fade = move_toward(_fade, target, delta * FADE_SPEED)
	if _fade > 0.0:
		queue_redraw()
	elif visible:
		queue_redraw()
	visible = _fade > 0.0


func _draw() -> void:
	if _fade <= 0.0 or _camera == null:
		return
	var pulse := 0.5 + 0.5 * sin(_clock * 3.2)
	var center := _camera.get_screen_center_position()
	var view := get_viewport_rect().size / _camera.zoom
	var half := view * 0.5
	for enemy in _shown:
		var body := enemy.global_position
		var r := enemy.data.radius
		var offset := body - center
		if absf(offset.x) < half.x + r and absf(offset.y) < half.y + r:
			var a := _fade * (0.8 + 0.2 * pulse)
			SoftGlow.pool(self, body, r * 2.3, 1.0, Color(COLOR, 0.13 * a))
			SoftGlow.pool(self, body, r * 1.5, 1.0, Color(COLOR, 0.12 * a))
			SoftGlow.pool(self, body + Vector2(0, r * 0.8), r * 2.0, 0.42, Color(COLOR, 0.32 * a))
			SoftGlow.rim(self, body + Vector2(0, r * 0.8), r * (1.5 + 0.12 * pulse), 0.42, Color(COLOR, 0.45 * a))
			if r >= LABEL_RADIUS:
				_draw_label(body + Vector2(0, -r * 1.7 - 6.0 - 2.0 * pulse), a)
		else:
			_draw_arrow(center, half, offset, pulse)


func _draw_arrow(center: Vector2, half: Vector2, offset: Vector2, pulse: float) -> void:
	var limit := half - Vector2.ONE * EDGE_MARGIN
	var scale_to_edge := minf(limit.x / maxf(absf(offset.x), 0.001), limit.y / maxf(absf(offset.y), 0.001))
	var at := center + offset * scale_to_edge
	var dir := offset.normalized()
	var side := Vector2(-dir.y, dir.x)
	var s := 1.0 + 0.08 * pulse
	var alpha := _fade * (0.7 + 0.25 * pulse)
	SoftGlow.pool(self, at, 34.0 * s, 1.0, Color(COLOR, 0.22 * alpha))
	var tip := at + dir * 15.0 * s
	var wing_a := at - dir * 9.0 * s + side * 11.0 * s
	var wing_b := at - dir * 9.0 * s - side * 11.0 * s
	var notch := at - dir * 3.0 * s
	draw_colored_polygon(PackedVector2Array([tip, wing_a, notch, wing_b]), Color(COLOR, 0.55 * alpha))
	draw_polyline(PackedVector2Array([tip, wing_a, notch, wing_b, tip]), Color(0.85, 1.0, 1.0, 0.8 * alpha), 1.8, true)


func _draw_label(at: Vector2, alpha: float) -> void:
	var font := ThemeDB.fallback_font
	var text := "ПОСЛЕДНИЙ"
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x + 16.0
	var box := Rect2(at - Vector2(width * 0.5, 12.0), Vector2(width, 20.0))
	draw_rect(box, Color(0.02, 0.1, 0.14, 0.72 * alpha))
	draw_rect(box, Color(COLOR, 0.8 * alpha), false, 1.5)
	draw_string(font, at + Vector2(-width * 0.5, 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, width, 15, Color(LABEL_COLOR, alpha))
