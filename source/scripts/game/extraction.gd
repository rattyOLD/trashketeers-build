class_name Extraction
extends Node2D
## Короткий финал сюжетной миссии. Печать уже получена: Нэлл подберёт отряд
## даже при ранении; самостоятельная посадка даёт дополнительную награду.
signal completed(boarded: bool)
const LIMIT := 24.0
const BOARD_TIME := 1.8
const BONUS := 75
var active := false
var board_progress := 0.0
var elapsed := 0.0
var game: Game
var _van: Sprite2D
var _marker: Node2D
var _guards: Array[Dictionary] = []
var _packs := 0
var _redraw_cd := 0.0


func start(battle: Game) -> void:
	if active:
		return
	game = battle
	game.player.celebrating = false
	process_mode = Node.PROCESS_MODE_PAUSABLE
	global_position = landing_point(game.map, game.player.global_position)
	active = true
	board_progress = 0.0
	elapsed = 0.0
	_van = Sprite2D.new()
	_van.texture = load("res://assets/district/junkyard/rats_van.png")
	_van.scale = Vector2.ONE * 0.72
	_van.offset = Vector2(-32, -110)
	_van.material = ArtDirection.material("scrap", 0.26)
	add_child(_van)
	_marker = Node2D.new()
	_marker.z_as_relative = false
	_marker.z_index = 24
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	game.story_target = self
	game.hud.show_banner("К МАШИНЕ НЭЛЛ!", Color("#a4d5c8"), 3.0)
	game.hud.radio().push_named("НЭЛЛ", "#a4d5c8", "К метке! Посадка — две секунды. Через 24 секунды подберу сама.", 5.0)
	game.focus_camera(global_position, 1.0)
	game.player.heal(game.player.max_hp * 0.2)


static func landing_point(level: LevelSpawner, from: Vector2) -> Vector2:
	# Только свободная клетка, соединённая с текущим маршрутом.
	for distance in [320.0, 230.0, 150.0]:
		for i in 16:
			var point: Vector2 = from + Vector2.from_angle(i * TAU / 16.0) * float(distance)
			if level.bounds.grow(-100).has_point(point) and level.is_area_clear(point, 80.0) and level._flow.distance_at(level.world_to_cell(point)) >= 0:
				return point
	return from


func _physics_process(delta: float) -> void:
	if not active or get_tree().paused:
		return
	if game.finished:
		cancel()
		return
	if game.player.is_dead:
		finish(false)
		return
	elapsed += delta
	_van.position.x = -110.0 * pow(1.0 - clampf(elapsed / 1.2, 0, 1), 3)
	if _packs < 2 and elapsed >= 2.0 + _packs * 5.0:
		_spawn_pack()
	if elapsed >= 4.0 and game.player.global_position.distance_to(global_position) <= 62.0:
		board_progress = minf(board_progress + delta, BOARD_TIME)
	else:
		board_progress = maxf(board_progress - delta * 0.5, 0.0)
	if board_progress >= BOARD_TIME:
		finish(true)
		return
	if elapsed >= LIMIT:
		finish(false)
		return
	_redraw_cd -= delta
	if _redraw_cd <= 0.0:
		_redraw_cd = 0.1
		queue_redraw()
		_marker.queue_redraw()


func _spawn_pack() -> void:
	_packs += 1
	var data := ContentDB.get_enemy(&"rat_punk")
	if data == null:
		return
	for i in 3:
		var point := game.map.find_spawn_point(game.player.global_position, 360, 510, data.radius)
		if point.distance_to(game.player.global_position) < 180.0:
			continue
		var e := game.enemies.spawn(data, point, 1.0, 0.7)
		if e != null:
			e.boss_minion = true
			_guards.append({"ref": weakref(e), "serial": e.activation_id})


func _release_guards() -> void:
	for entry in _guards:
		var e := (entry["ref"] as WeakRef).get_ref() as Enemy
		if e != null and e.is_alive() and e.activation_id == int(entry["serial"]):
			game.enemies.release(e)
	_guards.clear()


func finish(boarded: bool) -> void:
	if not active:
		return
	active = false
	_release_guards()
	game.story_target = null
	completed.emit(boarded)
	queue_free()


func cancel() -> void:
	active = false
	_release_guards()
	if is_instance_valid(game) and game.story_target == self:
		game.story_target = null
	queue_free()


func _draw() -> void:
	draw_set_transform(Vector2(-23, -10), 0, Vector2(1, 0.45))
	draw_circle(Vector2.ZERO, 105, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)


func _draw_marker() -> void:
	var color := Color("#a4d5c8")
	_marker.draw_circle(Vector2.ZERO, 62, Color(color, 0.08))
	_marker.draw_arc(Vector2.ZERO, 62, 0, TAU, 48, Color("#122527"), 6, true)
	_marker.draw_arc(Vector2.ZERO, 62, 0, TAU, 48, color, 2, true)
	if board_progress > 0.0:
		_marker.draw_arc(Vector2.ZERO, 68, -PI / 2, -PI / 2 + TAU * board_progress / BOARD_TIME, 48, color, 4, true)
	_marker.draw_line(Vector2(-8, 0), Vector2(0, 8), color, 3, true)
	_marker.draw_line(Vector2(0, 8), Vector2(14, -8), color, 3, true)
