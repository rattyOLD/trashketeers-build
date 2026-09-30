class_name StoryRun
extends Node
## Сюжетная миссия в духе Heavy Barrel / Contra: линейный проход по арене снизу вверх,
## засады по ходу пути (триггер по прогрессу), красный барьер «зачисти зону», ключ от мини-босса,
## ящик с оружием и босс в конце. Без таймерных волн. Данные и тексты — data/story.json.

const DATA_PATH := "res://data/story.json"
const OPEN_DELAY := 0.8
const TRIGGER_LEAD := 0.085
const EXIT_MARGIN := 0.022
const ROOM_DEPTH := 220.0
const ARENA_ENTRY := 110.0
const PACK_SPREAD := 110.0
const ZONE_HEAL := 0.3
const CLEAR_HEAL := 0.1
const HP_PER_PROGRESS := 1.2
const DMG_PER_PROGRESS := 0.35
const BOSS_POINTS := 5000
const RESCUE_POINTS := 3000
const CLEAN_ZONE_POINTS := 2000
const RESCUE_HEAL := 0.25
const CAPTIVE_LEAD := 0.07
const BARK_CHANCE := 0.5
const BARK_DELAY := 1.1
const LIFE_BONUS := 1500
const SECRET_POINTS := 1000
const RANK_STEPS: Array[int] = [30000, 20000, 11000]
const START_LIVES := 3
const MEDKIT_HEAL := 0.4

var game: Game
var mission: Dictionary = {}
var speakers: Dictionary = {}
var has_key := false
var finished_mission := false
var progress := 0.0
var zone_index := -1
var locked := false
var gate_key := ""
var waypoint: Node2D
var lives := START_LIVES
var score := 0
var barrel: HeavyBarrel
var kills := 0
var lives_lost := 0
var rescued := 0
var checkpoint := Vector2.ZERO

var _encounters: Array = []
var _next := 0
var _next_captive := 0
var _min_trigger := 0.0
var _captives: Array = []
var _enemy_lines: Dictionary = {}
var _zone_hit := false
var _active: Dictionary = {}
var _tracked: Array = []
var _pending_waves: Array = []
var _wave_clock := 0.0
var _boss_alive := false
var _queue: Array = []
var _box: DialogBox
var _tip: TipCard
var secrets: Array[StorySecret] = []
var secrets_found := 0
var _grade_shadow := Vector3(0.1, 0.02, 0.16)
var _grade_light := Vector3(0.06, 0.03, -0.02)
var _tip_queue: Array[Dictionary] = []
var _seen := {}
var _after_queue: Callable = Callable()
var _start_y := 0.0
var _end_y := 0.0


static func map_chapter(base: Dictionary, mission_id: String) -> Dictionary:
	var root: Dictionary = ConfigLoader.load_json(DATA_PATH)
	var chapter := base.duplicate(true)
	for entry in root.get("missions", []):
		if str(entry.get("id", "")) != mission_id:
			continue
		var doors: Array = []
		for enc in entry.get("encounters", []):
			if bool(enc.get("lock", false)) and not (enc.has("boss") and not bool(enc.get("mini", false))):
				doors.append(float(enc["at"]))
		chapter["size"] = entry.get("size", [34, 150])
		chapter["story"] = {"doors": doors, "boss_cells": entry.get("boss_cells", [22, 12])}
	return chapter


func setup(owner_game: Game, mission_id: String) -> bool:
	game = owner_game
	var root := ConfigLoader.load_json(DATA_PATH)
	speakers = root.get("speakers", {})
	for entry in root.get("missions", []):
		if str(entry.get("id", "")) == mission_id:
			mission = entry
	_encounters = mission.get("encounters", [])
	_captives = mission.get("captives", [])
	_enemy_lines = root.get("enemy_lines", {})
	BossBrain.story_phases = true
	barrel = HeavyBarrel.new()
	add_child(barrel)
	barrel.setup(game.player, game.fx, game.atmosphere)
	barrel.assembled.connect(_on_barrel_assembled)
	var meter := HeavyBarrel.Meter.new()
	meter.bind(barrel)
	game.hud.dock_story_meter(meter)
	game.player.damaged.connect(func(_amount: float) -> void: _zone_hit = true)
	_start_y = game.map.player_start.y
	_end_y = game.map.boss_point.y
	waypoint = Node2D.new()
	game.layers.fx.add_child(waypoint)
	game.map.open_story_gate("boss")
	_place_decor()
	var span := maxf(_start_y - _end_y, 1.0)
	for enc in _encounters:
		if enc.has("boss") and not bool(enc.get("mini", false)):
			enc["at"] = 1.0 - (game.map.boss_rect.size.y * 0.5 - ARENA_ENTRY) / span
	return not mission.is_empty()


func title() -> String:
	return "%s · %s" % [mission.get("title", ""), mission.get("subtitle", "")]


func zone_count() -> int:
	return maxi((mission.get("zones", []) as Array).size(), 1)


func zone_number() -> int:
	return clampi(zone_index + 1, 1, zone_count())


func zone_name() -> String:
	var zones: Array = mission.get("zones", [])
	return str(zones[clampi(zone_index, 0, zones.size() - 1)].get("name", "")) if not zones.is_empty() else ""


func encounter_mark(index: int) -> float:
	return float(_encounters[index]["at"]) if index < _encounters.size() else -1.0


func encounter_total() -> int:
	return _encounters.size()


func encounters_done() -> int:
	return _next


func captive_mark(index: int) -> float:
	return float(_captives[index]["at"]) if index < _captives.size() else -1.0


func captive_total() -> int:
	return _captives.size()


func captives_spawned() -> int:
	return _next_captive


func hud_text() -> String:
	var zones: Array = mission.get("zones", [])
	var number := clampi(zone_index + 1, 1, maxi(zones.size(), 1))
	return "ОЧКИ %06d · ЖИЗНИ %d · ЗОНА %d" % [score, lives, number]


func on_kill(data: EnemyData) -> void:
	kills += 1
	score += BOSS_POINTS if data.is_boss() else maxi(int(data.max_hp / 4.0), 10) * 10


func rank() -> String:
	var total := score + lives * LIFE_BONUS
	for i in RANK_STEPS.size():
		if total >= RANK_STEPS[i]:
			return ["S", "A", "B"][i]
	return "C"


func result_lines(victory: bool) -> PackedStringArray:
	var lines := PackedStringArray([title() if not victory else "ОСКОЛОК %d/6 ПОЛУЧЕН" % int(mission.get("shards", 1))])
	var bonus := lives * LIFE_BONUS if victory else 0
	lines.append("Очки: %d" % (score + bonus))
	lines.append("Врагов: %d" % kills)
	lines.append("Спасено: %d" % rescued)
	lines.append("Тайники: %d из %d" % [secrets_found, secrets.size()])
	lines.append("Детали ствола: %d из %d" % [barrel.parts if not barrel.active else HeavyBarrel.TOTAL_PARTS, HeavyBarrel.TOTAL_PARTS])
	lines.append("Жизни: %d из %d" % [lives, START_LIVES])
	lines.append("Время: %s" % BattleBase.format_time(game.director.elapsed))
	if victory:
		lines.append("Ранг: %s" % rank())
	return lines


func game_over() -> void:
	finished_mission = true
	game.story_result(false, result_lines(false))


## Жизнь потрачена: возвращает Рико на чекпоинт; false, когда жизни кончились.
func try_respawn() -> bool:
	if finished_mission:
		return true
	if lives <= 1:
		get_tree().create_timer(1.6, false).timeout.connect(game_over)
		return true
	lives -= 1
	lives_lost += 1
	game.hud.show_banner("ЖИЗНЬ ПОТЕРЯНА · ОСТАЛОСЬ %d" % lives, UiStyle.DANGER, 1.6)
	get_tree().create_timer(1.3, false).timeout.connect(func() -> void: game.story_respawn(checkpoint))
	return true


func on_start() -> void:
	checkpoint = game.player.global_position
	game.hud.show_banner(title(), UiStyle.GOLD, 2.2)
	_update_progress()
	_check_zone()


func _place_decor() -> void:
	_place_secrets()
	var inner_left: float = game.map.bounds.position.x + LevelSpawner.RING_SIDE * LevelSpawner.CELL
	var inner_right: float = game.map.bounds.end.x - LevelSpawner.RING_SIDE * LevelSpawner.CELL
	for entry in mission.get("posters", []):
		var poster := Poster.new()
		poster.title = str(entry["title"])
		poster.text = str(entry["text"])
		var side := float(entry.get("side", 1.0))
		poster.position = Vector2(inner_left + 46.0 if side < 0.0 else inner_right - 46.0, _y_of(float(entry["at"])))
		poster.rotation = randf_range(-0.07, 0.07)
		game.layers.fx.add_child(poster)
	for entry in mission.get("graffiti", []):
		var tag := Graffiti.new()
		tag.text = str(entry["text"])
		tag.color = Color(str(entry.get("color", "#ff2ea6")))
		tag.position = Vector2(randf_range(-260.0, 260.0), _y_of(float(entry["at"])))
		tag.rotation = randf_range(-0.14, 0.14)
		game.layers.decals.add_child(tag)


func _place_secrets() -> void:
	var inner_left: float = game.map.bounds.position.x + LevelSpawner.RING_SIDE * LevelSpawner.CELL
	var inner_right: float = game.map.bounds.end.x - LevelSpawner.RING_SIDE * LevelSpawner.CELL
	for entry: Dictionary in mission.get("secrets", []):
		var secret := StorySecret.new()
		secret.entry = entry
		secret.side = float(entry.get("side", 1.0))
		var inset := StorySecret.SIZE.x * 0.5
		secret.position = Vector2(inner_left + inset if secret.side < 0.0 else inner_right - inset, _y_of(float(entry["at"])))
		secret.broken.connect(_on_secret_broken)
		game.layers.world.add_child(secret)
		secrets.append(secret)


func nearest_secret(from: Vector2, max_distance: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_distance * max_distance
	for secret in secrets:
		if secret.is_targetable():
			var d := from.distance_squared_to(secret.global_position)
			if d < best_d:
				best_d = d
				best = secret
	return best


func _on_secret_broken(secret: StorySecret) -> void:
	secrets_found += 1
	score += SECRET_POINTS
	var at := secret.global_position
	game.fx.dust(at, 14, 120.0)
	game.fx.chunks(at, Color("#6d6a7a"), 14, 320.0, 5.0)
	game.fx.ring(at, Color("#5ff2ff"), 140.0)
	game.add_shake(0.5)
	SoundManager.play(&"crate_break", 0.0, false)
	var kind := str(secret.entry.get("kind", "cache"))
	var front := at + Vector2(-secret.side * 90.0, 0.0)
	game.fx.popup(front + Vector2(0, -80), "ТАЙНИК +%d" % SECRET_POINTS, Color("#5ff2ff"), 32.0)
	match kind:
		"cache":
			game.pickups.spawn_xp_gold(front, 8)
			_drop_medkit(front)
		"weapon":
			game._drop_weapon(game._roll_weapon("rare"), front, true)
			game.pickups.spawn_xp_gold(front, 4)
	game.hud.toast(str(secret.entry.get("title", "ТАЙНИК")), str(secret.entry.get("text", "")), Color("#5ff2ff"))


func _drop_medkit(at: Vector2) -> void:
	var kit := Medkit.new()
	kit.player = game.player
	kit.heal_share = MEDKIT_HEAL
	kit.picked.connect(tip_item.bind("medkit"))
	kit.global_position = at
	game.layers.fx.add_child(kit)


func debug_jump(target: float) -> void:
	game.player.global_position = Vector2(game.player.global_position.x, _y_of(target))
	while _next < _encounters.size() and float(_encounters[_next]["at"]) < target - 0.02:
		_next += 1
	while _next_captive < _captives.size() and float(_captives[_next_captive]["at"]) < target:
		_next_captive += 1
	game.camera.global_position = game.player.global_position
	game.camera.reset_smoothing()


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
	_tick_captives()
	if locked:
		_check_clear()
		waypoint.global_position = game.player.global_position
	elif _next < _encounters.size():
		var enc: Dictionary = _encounters[_next]
		if progress >= _trigger_at(enc):
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
	if zone_index >= 0 and not _zone_hit:
		score += CLEAN_ZONE_POINTS
		game.fx.popup(game.player.global_position + Vector2(0, -110), "БЕЗ УРОНА +%d" % CLEAN_ZONE_POINTS, Color("#7cff6b"), 30.0)
	_zone_hit = false
	zone_index = index
	checkpoint = game.player.global_position
	var zone: Dictionary = zones[index]
	_apply_palette(zone)
	game.hud.show_banner(str(zone["name"]), Color("#5ff2ff"), 2.4)
	if index > 0:
		game.player.heal(game.player.max_hp * ZONE_HEAL)
		game.fx.ring(game.player.global_position, Color("#7cff6b"), 160.0)
	if zone.has("say"):
		_say(str(zone["say"]), OPEN_DELAY + (0.8 if index == 0 else 0.0))
	if bool(zone.get("crate", false)) and has_key:
		_open_crate()


## Палитра зоны: настроение погоды и плавный переход сплит-тонирования теней и света.
func _apply_palette(zone: Dictionary) -> void:
	if zone.has("mood"):
		game.atmosphere.set_mood(str(zone["mood"]))
	if not zone.has("shadow"):
		return
	var to_shadow := _vec3(zone["shadow"])
	var to_light := _vec3(zone["highlight"])
	var from_shadow := _grade_shadow
	var from_light := _grade_light
	_grade_shadow = to_shadow
	_grade_light = to_light
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		game.atmosphere.set_grade(from_shadow.lerp(to_shadow, t), from_light.lerp(to_light, t)), 0.0, 1.0, 2.0)


func _vec3(raw: Array) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _tick_captives() -> void:
	if _next_captive >= _captives.size():
		return
	var entry: Dictionary = _captives[_next_captive]
	if progress < float(entry["at"]) - CAPTIVE_LEAD:
		return
	_next_captive += 1
	var side := float(entry.get("side", 1.0))
	var want := Vector2(game.player.global_position.x + 230.0 * side, _y_of(float(entry["at"])))
	var at := game.map.find_spawn_point(want, 0.0, 240.0, 40.0)
	if at == Vector2.INF:
		return
	var captive := Captive.new()
	captive.player = game.player
	captive.freed.connect(_on_captive_freed.bind(captive))
	captive.global_position = at
	game.layers.fx.add_child(captive)


func _on_captive_freed(captive: Captive) -> void:
	rescued += 1
	score += RESCUE_POINTS
	game.player.heal(game.player.max_hp * RESCUE_HEAL)
	game.fx.popup(captive.global_position + Vector2(0, -80), "СПАСЁН +%d" % RESCUE_POINTS, Color("#ffd257"), 32.0)
	game.fx.ring(captive.global_position, Color("#ffd257"), 120.0)
	game.pickups.spawn_xp_gold(captive.global_position, 5)
	game.hud.toast("ПЛЕННИК ОСВОБОЖДЁН", "Спасено: %d · +%d очков" % [rescued, RESCUE_POINTS], Color("#ffd257"))


func _bark(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or enemy.pool_index < 0 or not enemy.is_alive():
		return
	var lines: Array = _enemy_lines.get(str(enemy.data.id), [])
	if lines.is_empty():
		return
	game.fx.popup(enemy.global_position + Vector2(0, -70), str(lines.pick_random()), Color("#ff9b9b"), 22.0)


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
	if bool(enc.get("arena_part", false)):
		_drop_part(game.map.boss_point + Vector2(0, game.map.boss_rect.size.y * 0.3))
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
		gate_key = "boss" if enc.has("boss") and not bool(enc.get("mini", false)) else LevelSpawner.door_key(float(enc["at"]))
		if gate_key == "boss":
			game.map.close_story_gate(gate_key)


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
	var top := _gate_y(float(_active.get("at", progress))) + ROOM_DEPTH
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
			if randf() < BARK_CHANCE and _enemy_lines.has(str(batch[i].id)):
				get_tree().create_timer(BARK_DELAY, false).timeout.connect(_bark.bind(enemy))


func _spawn_boss(enc: Dictionary) -> void:
	var data := ContentDB.get_enemy(StringName(str(enc["boss"])))
	if data == null:
		return
	var mini := bool(enc.get("mini", false))
	var at := game.map.boss_point
	if mini:
		at = game.map.find_spawn_point(Vector2(game.player.global_position.x, _gate_y(float(enc["at"])) + ROOM_DEPTH + 40.0), 0.0, 260.0, data.radius)
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


func _trigger_at(enc: Dictionary) -> float:
	if enc.has("boss") and not bool(enc.get("mini", false)):
		return float(enc["at"])
	return maxf(float(enc["at"]) - TRIGGER_LEAD, _min_trigger)


func _gate_y(at: float) -> float:
	return _y_of(at + LevelSpawner.DOOR_LEAD) + LevelSpawner.WALL_THICK * LevelSpawner.CELL


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
	game.map.open_story_gate(gate_key)
	_min_trigger = float(_active.get("at", 0.0)) + LevelSpawner.DOOR_LEAD + EXIT_MARGIN
	checkpoint = game.player.global_position
	_give_reward(str(_active.get("reward", "")))
	game.player.heal(game.player.max_hp * CLEAR_HEAL)
	game.hud.show_banner("ПУТЬ СВОБОДЕН — ВПЕРЁД!", Color("#7cff6b"), 1.4)
	SoundManager.play(&"shield_up", -4.0, false)
	game.pickups.spawn_xp_gold(game.player.global_position + Vector2(0, -60), 4)


## Награда за зачищенную засаду: аптечка или ствол (как бонусные капсулы в Contra).
func _drop_part(at: Vector2) -> void:
	var box := HeavyBarrel.Case.new()
	box.player = game.player
	box.picked.connect(_on_part_picked.bind(box))
	box.global_position = at
	game.layers.fx.add_child(box)


func _on_barrel_assembled() -> void:
	game.hud.show_banner("СУПЕР-СТВОЛ СОБРАН!", Color("#ff2ea6"), 2.4)
	game.add_shake(1.0)
	Platform.haptic("heavy")


func _on_part_picked(box: HeavyBarrel.Case) -> void:
	tip_item("barrel_part")
	barrel.collect_part()
	game.fx.popup(box.global_position + Vector2(0, -70), "ДЕТАЛЬ %d/%d" % [barrel.parts, HeavyBarrel.TOTAL_PARTS] if barrel.active == false else "СТВОЛ СОБРАН!", Color("#ff2ea6"), 34.0)
	game.fx.ring(box.global_position, Color("#ffb020"), 140.0)


func _give_reward(reward: String) -> void:
	if bool(_active.get("hb", false)):
		_drop_part(game.player.global_position + Vector2(70, -110))
	if reward.is_empty():
		return
	var at := game.player.global_position + Vector2(0, -90)
	if reward == "medkit":
		_drop_medkit(at)
		game.hud.toast("АПТЕЧКА", "Подбери, чтобы подлечиться", Color("#7cff6b"))
	elif reward.begins_with("weapon:"):
		game._drop_weapon(game._roll_weapon(reward.get_slice(":", 1)), at, true)
		game.hud.toast("ОРУЖИЕ", "Трофей с поля боя: подбери ствол", Color("#ffd257"))


func on_boss_spawned(is_mini: bool) -> void:
	_say("baron_pre" if is_mini else "king_pre", OPEN_DELAY)


func on_miniboss_killed() -> void:
	has_key = true
	_boss_alive = false
	tip_item("beer_key")
	game.hud.toast("ПОЛУЧЕНО: ПИВНАЯ ПРОБКА-КЛЮЧ", "Она откроет Ящик с оружием в Зоне 3", Color("#ffb020"))
	_say("baron_post", 1.0)


func on_king_killed() -> void:
	_boss_alive = false
	locked = false
	game.map.open_story_gate("boss")
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
	SaveService.story_complete(str(mission.get("id", "")), shards, score + lives * LIFE_BONUS)
	game.story_target = null
	game.hud.show_banner("ОСКОЛОК %d/6 ПОЛУЧЕН!" % shards, UiStyle.GOLD, 2.8)
	_after_queue = game.story_finished
	_say("king_dead", 1.6)
	_say("outro", 1.7)


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
	if game._level_up_open or game.get_tree().paused:
		get_tree().create_timer(0.6, true, false, true).timeout.connect(_pump)
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


## Подсказка при первом подборе: оружие или предмет. Показывается один раз, если подсказки не выключены.
func tip_weapon(weapon: WeaponData) -> void:
	_queue_tip(Tips.weapon_key(weapon), Tips.weapon_card(weapon))


func tip_item(id: String) -> void:
	_queue_tip(Tips.item_key(id), Tips.item_card(id))


func _queue_tip(key: String, card: Dictionary) -> void:
	if card.is_empty() or not Tips.is_new(key):
		return
	Tips.mark(key)
	_tip_queue.append(card)
	get_tree().create_timer(0.3, true, false, true).timeout.connect(_pump_tips)


func _pump_tips() -> void:
	if _tip != null or _tip_queue.is_empty():
		return
	if game.finished or game.player == null or game.player.is_dead:
		_tip_queue.clear()
		return
	if _box != null or game._level_up_open or game.get_tree().paused:
		get_tree().create_timer(0.4, true, false, true).timeout.connect(_pump_tips)
		return
	if not Tips.enabled():
		_tip_queue.clear()
		return
	_tip = TipCard.new()
	game.add_child(_tip)
	_tip.finished.connect(_on_tip_finished)
	_tip.open(_tip_queue.pop_front())


func _on_tip_finished() -> void:
	_tip = null
	get_tree().create_timer(0.2, true, false, true).timeout.connect(_pump_tips)


func _on_box_finished() -> void:
	_box = null
	get_tree().create_timer(0.15, true, false, true).timeout.connect(_pump)


## Аптечка: крест на земле, лечит при касании и исчезает.
class Medkit:
	extends Node2D

	signal picked

	var player: Node2D
	var heal_share := 0.4
	var _time := 0.0

	func _init() -> void:
		z_index = 3

	func _physics_process(delta: float) -> void:
		_time += delta
		queue_redraw()
		if player == null:
			return
		if global_position.distance_to(player.global_position) < 56.0:
			(player as Player).heal((player as Player).max_hp * heal_share)
			SoundManager.play(&"level_up", -6.0, false)
			picked.emit()
			queue_free()

	func _draw() -> void:
		var bob := sin(_time * 4.0) * 3.0
		draw_circle(Vector2(0, bob + 8), 26.0, Color(0.0, 0.0, 0.0, 0.25))
		draw_rect(Rect2(-20, bob - 20, 40, 40), Color("#f4f0ff"), true)
		draw_rect(Rect2(-20, bob - 20, 40, 40), Color("#180e22"), false, 4.0)
		draw_rect(Rect2(-5, bob - 15, 10, 30), Color("#ff3b5c"), true)
		draw_rect(Rect2(-15, bob - 5, 30, 10), Color("#ff3b5c"), true)


## Пленник в клетке: касание освобождает его (как заложники в Metal Slug).
class Captive:
	extends Node2D

	signal freed

	var player: Node2D
	var _time := 0.0
	var _tex: Texture2D = load("res://assets/ui/portraits/nell.png")

	func _init() -> void:
		z_index = 3
		add_to_group(&"story_captive")

	func _physics_process(delta: float) -> void:
		_time += delta
		queue_redraw()
		if player != null and global_position.distance_to(player.global_position) < 62.0:
			SoundManager.play(&"level_up", -4.0, false)
			freed.emit()
			queue_free()

	func _draw() -> void:
		var bob := sin(_time * 3.0) * 2.0
		draw_circle(Vector2(0, 30), 34.0, Color(0, 0, 0, 0.25))
		draw_texture_rect(_tex, Rect2(-28, bob - 44, 56, 56), false)
		var bar := Color("#8a8fa8")
		for i in range(-3, 4):
			draw_line(Vector2(i * 10.0, -48), Vector2(i * 10.0, 16), bar, 3.0)
		draw_rect(Rect2(-34, -52, 68, 10), Color("#3a3550"), true)
		draw_rect(Rect2(-34, 10, 68, 8), Color("#3a3550"), true)
		var pulse := 0.6 + 0.4 * sin(_time * 6.0)
		draw_rect(Rect2(-40, -58, 80, 80), Color(1.0, 0.82, 0.3, 0.6 * pulse), false, 3.0)


## Плакат на стене: бумага с булавкой, заголовок и пара строк в тоне свалки.
class Poster:
	extends Node2D

	var title := ""
	var text := ""

	func _init() -> void:
		z_index = 2

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(-56, -74, 112, 148), Color(0, 0, 0, 0.3), true)
		draw_rect(Rect2(-60, -80, 112, 148), Color("#d8caa4"), true)
		draw_rect(Rect2(-60, -80, 112, 148), Color("#6b5a3a"), false, 3.0)
		draw_rect(Rect2(-60, -80, 112, 26), Color("#b3262e"), true)
		draw_multiline_string(font, Vector2(-56, -62), title, HORIZONTAL_ALIGNMENT_CENTER, 104.0, 11, 2, Color("#fff4dc"))
		draw_multiline_string(font, Vector2(-54, -36), text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 11, 6, Color("#2a1f12"))
		draw_circle(Vector2(-4, -80), 5.0, Color("#ff3b5c"))


## Неоновый тег на полу: крупная надпись краской под небольшим углом.
class Graffiti:
	extends Node2D

	var text := ""
	var color := Color("#ff2ea6")

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-250, 14), text, HORIZONTAL_ALIGNMENT_CENTER, 500.0, 54, Color(color, 0.16))
		draw_string(font, Vector2(-252, 10), text, HORIZONTAL_ALIGNMENT_CENTER, 500.0, 54, Color(color, 0.34))
