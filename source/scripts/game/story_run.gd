class_name StoryRun
extends Node
## Сюжетная миссия в духе Heavy Barrel / Contra: линейный проход по арене снизу вверх,
## засады по ходу пути (триггер по прогрессу), красный барьер «зачисти зону», ключ от мини-босса,
## ящик с оружием и босс в конце. Без таймерных волн. Данные и тексты — data/story.json.

const DATA_PATH := "res://data/story.json"
const OPEN_DELAY := 0.8
const TRIGGER_LEAD := 0.05
const BARRIER_LEAD := 0.03
const PACK_SPREAD := 110.0
const ZONE_HEAL := 0.3
const CLEAR_HEAL := 0.1
const HP_PER_PROGRESS := 1.7
const DMG_PER_PROGRESS := 0.5

var game: Game
var mission: Dictionary = {}
var speakers: Dictionary = {}
var has_key := false
var finished_mission := false
var progress := 0.0
var zone_index := -1
var locked := false
var barrier_y := 0.0
var waypoint: Node2D

var _encounters: Array = []
var _next := 0
var _active: Dictionary = {}
var _tracked: Array = []
var _pending_waves: Array = []
var _wave_clock := 0.0
var _boss_alive := false
var _queue: Array = []
var _box: DialogBox
var _seen := {}
var _after_queue: Callable = Callable()
var _barrier: Barrier
var _start_y := 0.0
var _end_y := 0.0


func setup(owner_game: Game, mission_id: String) -> bool:
	game = owner_game
	var root := ConfigLoader.load_json(DATA_PATH)
	speakers = root.get("speakers", {})
	for entry in root.get("missions", []):
		if str(entry.get("id", "")) == mission_id:
			mission = entry
	_encounters = mission.get("encounters", [])
	_start_y = game.map.player_start.y
	_end_y = game.map.boss_point.y
	waypoint = Node2D.new()
	game.layers.fx.add_child(waypoint)
	_barrier = Barrier.new()
	_barrier.bounds = game.map.bounds
	_barrier.visible = false
	game.layers.fx.add_child(_barrier)
	return not mission.is_empty()


func title() -> String:
	return "%s · %s" % [mission.get("title", ""), mission.get("subtitle", "")]


func hud_text() -> String:
	var zones: Array = mission.get("zones", [])
	var number := clampi(zone_index + 1, 1, maxi(zones.size(), 1))
	return "ЗОНА %d · ПУТЬ %d%%" % [number, int(progress * 100.0)]


func on_start() -> void:
	game.hud.show_banner(title(), UiStyle.GOLD, 2.2)
	_update_progress()
	_check_zone()


func _y_of(p: float) -> float:
	return lerpf(_start_y, _end_y, p)


func _update_progress() -> void:
	progress = clampf((_start_y - game.player.global_position.y) / maxf(_start_y - _end_y, 1.0), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if game == null or game.player == null or game.player.is_dead or finished_mission:
		return
	game.director.elapsed += delta
	_update_progress()
	_check_zone()
	_tick_pending_waves(delta)
	if locked:
		_hold_player()
		_check_clear()
		waypoint.global_position = game.player.global_position
	elif _next < _encounters.size():
		var enc: Dictionary = _encounters[_next]
		if progress >= float(enc["at"]) - TRIGGER_LEAD:
			_begin(enc)
	_update_waypoint()


func _check_zone() -> void:
	var zones: Array = mission.get("zones", [])
	var index := zone_index
	for i in zones.size():
		if progress >= float(zones[i]["from"]):
			index = i
	if index == zone_index:
		return
	zone_index = index
	var zone: Dictionary = zones[index]
	game.hud.show_banner(str(zone["name"]), Color("#5ff2ff"), 2.4)
	if index > 0:
		game.player.heal(game.player.max_hp * ZONE_HEAL)
		game.fx.ring(game.player.global_position, Color("#7cff6b"), 160.0)
	if zone.has("say"):
		_say(str(zone["say"]), OPEN_DELAY + (0.8 if index == 0 else 0.0))
	if bool(zone.get("crate", false)) and has_key:
		_open_crate()


func _update_waypoint() -> void:
	if locked or game.director.boss != null:
		game.story_target = null
		return
	waypoint.global_position = game.player.global_position + Vector2(0, -1100)
	game.story_target = waypoint


func _begin(enc: Dictionary) -> void:
	_next += 1
	_active = enc
	_tracked.clear()
	_pending_waves.clear()
	_wave_clock = 0.0
	if enc.has("say"):
		_say(str(enc["say"]), OPEN_DELAY)
	if enc.has("boss"):
		_spawn_boss(enc)
	else:
		for wave in enc.get("waves", []):
			_pending_waves.append(wave)
		game.hud.show_banner("ЗАСАДА!", UiStyle.DANGER, 1.2)
		SoundManager.play(&"boss_spawn", -6.0, false)
		game.add_shake(0.3)
	locked = bool(enc.get("lock", false))
	if locked:
		barrier_y = _y_of(float(enc["at"]) + BARRIER_LEAD)
		_barrier.y = barrier_y
		_barrier.visible = true
		_barrier.queue_redraw()


func _tick_pending_waves(delta: float) -> void:
	if _pending_waves.is_empty():
		return
	_wave_clock += delta
	while not _pending_waves.is_empty() and _wave_clock >= float((_pending_waves[0] as Dictionary).get("delay", 0.0)):
		_spawn_wave(_pending_waves.pop_front(), _active.get("wave_index", 0))
		_active["wave_index"] = int(_active.get("wave_index", 0)) + 1


func _spawn_wave(wave: Dictionary, index: int) -> void:
	var batch: Array[EnemyData] = []
	var clearance := 20.0
	for id in (wave.get("enemies", {}) as Dictionary):
		var data := ContentDB.get_enemy(StringName(id))
		if data == null:
			continue
		for i in int(wave["enemies"][id]):
			batch.append(data)
			clearance = maxf(clearance, data.radius * 1.4 + 6.0)
	if batch.is_empty():
		return
	var player_pos := game.player.global_position
	var top := _y_of(float(_active.get("at", progress)) + BARRIER_LEAD) - 380.0
	var center := Vector2(player_pos.x + randf_range(-220.0, 220.0), top)
	if index % 2 == 1:
		center = player_pos + Vector2(550.0 * (1.0 if randf() < 0.5 else -1.0), -120.0)
	var anchor := game.map.find_spawn_point(center, 0.0, 260.0, clearance)
	if anchor == Vector2.INF:
		anchor = game.map.find_spawn_point(player_pos, 520.0, 760.0, clearance)
	if anchor == Vector2.INF:
		return
	var hp_mult := 1.0 + HP_PER_PROGRESS * progress
	var dmg_mult := 1.0 + DMG_PER_PROGRESS * progress
	for i in batch.size():
		var at := anchor
		if i > 0:
			at = game.map.find_spawn_point(anchor, 30.0, PACK_SPREAD, clearance)
			if at == Vector2.INF:
				continue
		var enemy := game.enemies.spawn(batch[i], at, hp_mult, dmg_mult)
		if enemy != null:
			_tracked.append(enemy)


func _spawn_boss(enc: Dictionary) -> void:
	var data := ContentDB.get_enemy(StringName(str(enc["boss"])))
	if data == null:
		return
	var mini := bool(enc.get("mini", false))
	var at := game.map.boss_point
	if mini:
		at = game.map.find_spawn_point(Vector2(game.player.global_position.x, _y_of(float(enc["at"]) + BARRIER_LEAD) - 420.0), 0.0, 260.0, data.radius)
		if at == Vector2.INF:
			at = game.map.boss_point
	var boss := game.enemies.spawn(data, at, float(enc.get("hp", 1.0)) * 0.9, 1.0 + DMG_PER_PROGRESS * progress)
	if boss == null:
		return
	game.director.story_mini = mini
	game.director.boss = boss
	_boss_alive = true
	_tracked.append(boss)
	game.announce_boss(boss)


func _hold_player() -> void:
	var p := game.player
	if p.global_position.y < barrier_y:
		p.global_position.y = barrier_y
		if p.velocity.y < 0.0:
			p.velocity.y = 0.0


func _check_clear() -> void:
	if not _pending_waves.is_empty():
		return
	for enemy in _tracked:
		if is_instance_valid(enemy) and enemy.pool_index >= 0 and enemy.is_alive():
			return
	_tracked.clear()
	if _boss_alive:
		return
	locked = false
	_barrier.visible = false
	game.player.heal(game.player.max_hp * CLEAR_HEAL)
	game.hud.show_banner("ПУТЬ СВОБОДЕН — ВПЕРЁД!", Color("#7cff6b"), 1.4)
	SoundManager.play(&"shield_up", -4.0, false)
	game.pickups.spawn_xp_gold(game.player.global_position + Vector2(0, -60), 4)


func on_boss_spawned(is_mini: bool) -> void:
	_say("baron_pre" if is_mini else "king_pre", OPEN_DELAY)


func on_miniboss_killed() -> void:
	has_key = true
	_boss_alive = false
	game.hud.toast("ПОЛУЧЕНО: ПИВНАЯ ПРОБКА-КЛЮЧ", "Она откроет Ящик с оружием в Зоне 3", Color("#ffb020"))
	_say("baron_post", 1.0)


func on_king_killed() -> void:
	_boss_alive = false
	locked = false
	_barrier.visible = false
	get_tree().create_timer(2.2, true, false, true).timeout.connect(finish)


func on_boss_phase(phase: int) -> void:
	var lines: Array = (mission.get("phase_lines", {}) as Dictionary).get("king", [])
	if phase >= 2 and lines.size() > 1:
		game.hud.toast("КОРОЛЬ ХЛАМА", str(lines[1]), Color("#ff5a5a"))


func on_boss_break() -> void:
	var lines: Array = (mission.get("phase_lines", {}) as Dictionary).get("king", [])
	if not lines.is_empty():
		game.hud.toast("КОРОЛЬ ХЛАМА", str(lines[0]), Color("#ff5a5a"))


## Босс главы повержен: финальная сцена, затем итог миссии.
func finish() -> void:
	if finished_mission:
		return
	finished_mission = true
	var shards := int(mission.get("shards", 1))
	SaveService.story_complete(str(mission.get("id", "")), shards)
	game.story_target = null
	game.hud.show_banner("ОСКОЛОК %d/6 ПОЛУЧЕН!" % shards, UiStyle.GOLD, 2.8)
	_after_queue = game.story_finished
	_say("king_dead", 1.6)


func _open_crate() -> void:
	game.open_story_crate()
	_say("crate", OPEN_DELAY + 0.6)


func _say(key: String, delay: float) -> void:
	if _seen.has(key):
		return
	var dialogs: Dictionary = mission.get("dialogs", {})
	if not dialogs.has(key):
		return
	_seen[key] = true
	_queue.append(dialogs[key])
	get_tree().create_timer(delay, true, false, true).timeout.connect(_pump)


func _pump() -> void:
	if _box != null:
		return
	if _queue.is_empty():
		if _after_queue.is_valid():
			var cb := _after_queue
			_after_queue = Callable()
			cb.call()
		return
	if game.finished or game.player == null or game.player.is_dead:
		_queue.clear()
		return
	var lines: Array = _queue.pop_front()
	_box = DialogBox.new()
	game.add_child(_box)
	_box.finished.connect(_on_box_finished)
	_box.open(lines, speakers)


func _on_box_finished() -> void:
	_box = null
	get_tree().create_timer(0.15, true, false, true).timeout.connect(_pump)


## Красный лазерный барьер поперёк прохода: Енот не пройдёт, пока засада не зачищена.
class Barrier:
	extends Node2D

	var bounds := Rect2()
	var y := 0.0
	var _time := 0.0

	func _init() -> void:
		z_index = 4

	func _process(delta: float) -> void:
		if visible:
			_time += delta
			queue_redraw()

	func _draw() -> void:
		var left := bounds.position.x + 64.0
		var right := bounds.end.x - 64.0
		var pulse := 0.6 + 0.4 * sin(_time * 7.0)
		draw_line(Vector2(left, y), Vector2(right, y), Color(1.0, 0.1, 0.25, 0.25 * pulse), 26.0)
		draw_line(Vector2(left, y), Vector2(right, y), Color(1.0, 0.25, 0.35, 0.85), 6.0)
		draw_line(Vector2(left, y), Vector2(right, y), Color(1.0, 0.9, 0.9, 0.9), 2.0)
		var step := 96.0
		var x := left
		while x < right:
			draw_circle(Vector2(x, y), 8.0, Color(1.0, 0.85, 0.3, 0.9))
			x += step
