class_name CoopArena
extends RefCounted
## Серверная арена коопа: чистая симуляция боя без графики и без узлов (работает headless на сервере и в тестах).
## Сервер считает всё: движение, автострельбу, урон, волны, сбитых и воскрешение, награды. Клиент шлёт только вектор
## движения и получает снимки состояния. Данные берём из data/enemies.json и data/chapters.json.
## Упрощения этапа 2: все враги ведут себя как «бегущие за ближайшим» (особые поведения и босс добавим позже).

signal wave_started(number: int, title: String)
signal wave_cleared(number: int)
signal player_downed(id: int)
signal player_revived(id: int)
signal finished(won: bool)

enum Phase { INTRO, FIGHT, INTERMISSION, DONE }

const TICK := 1.0 / 30.0
const ARENA := Rect2(-1200.0, -1500.0, 2400.0, 3000.0)
const PLAYER_SPEED := 240.0
const PLAYER_RADIUS := 22.0
const PLAYER_HP := 100.0
const FIRE_INTERVAL := 0.22
const FIRE_RANGE := 650.0
const BULLET_SPEED := 900.0
const BULLET_LIFE := 0.9
const BULLET_DAMAGE := 12.0
const BULLET_RADIUS := 6.0
const CONTACT_COOLDOWN := 0.8
const BLEED_TIME := 25.0
const REVIVE_TIME := 2.5
const REVIVE_RANGE := 90.0
const REVIVE_HP := 50.0
const INTRO_TIME := 1.2
const SPAWN_RING_MIN := 620.0
const SPAWN_RING_MAX := 820.0
const COUNT_PER_EXTRA_PLAYER := 0.6
## Потолки наград за забег на игрока (серверный RPC начисления проверит их ещё раз).
const REWARD_COINS_CAP := 400
const REWARD_XP_CAP := 200

var players: Dictionary = {}     # id -> {x, y, hp, downed, bleed, revive, fire_cd, aim, in_x, in_y, kills, damage, alive}
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var phase: Phase = Phase.INTRO
var wave_index := -1
var tick_count := 0
var time := 0.0
var won := false

var _enemy_defs: Dictionary = {}     # enemy_id -> def
var _type_index: Dictionary = {}     # enemy_id -> int (для снимков)
var _types: Array[String] = []
var _waves: Array = []
var _difficulty: Dictionary = {}
var _next_id := 1
var _phase_time := 0.0
var _spawn_left := 0
var _spawn_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _waves_cleared := 0
var _hp_mult := 1.0
var _dmg_mult := 1.0
var _spd_mult := 1.0


func setup(chapter_index: int, seed_value: int = 0) -> bool:
	var enemies_json := _read_json("res://data/enemies.json")
	var chapters_json := _read_json("res://data/chapters.json")
	if enemies_json.is_empty() or chapters_json.is_empty():
		return false
	for def: Variant in enemies_json.get("enemies", []):
		var d := def as Dictionary
		var id := str(d.get("enemy_id", ""))
		_enemy_defs[id] = d
		_type_index[id] = _types.size()
		_types.append(id)
	var chapters: Array = chapters_json.get("chapters", [])
	if chapter_index < 0 or chapter_index >= chapters.size():
		return false
	_waves = (chapters[chapter_index] as Dictionary).get("waves", [])
	_difficulty = chapters_json.get("difficulty", {})
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_begin_wave(0)
	return true


func type_names() -> Array[String]:
	return _types


func add_player(id: int) -> void:
	var index := players.size()
	players[id] = {"x": -80.0 + 160.0 * float(index), "y": 0.0, "hp": PLAYER_HP, "downed": false, "bleed": 0.0, "revive": 0.0,
		"fire_cd": 0.0, "aim": 0.0, "in_x": 0.0, "in_y": 0.0, "kills": 0, "damage": 0.0, "alive": true}


func remove_player(id: int) -> void:
	players.erase(id)


## Вход игрока: только направление движения. Длину и мусор (NaN, огромные значения) режем здесь, клиенту не верим.
func set_input(id: int, move: Vector2) -> void:
	if not players.has(id) or is_nan(move.x) or is_nan(move.y):
		return
	var clean := move.limit_length(1.0)
	var p: Dictionary = players[id]
	p["in_x"] = clean.x
	p["in_y"] = clean.y


func tick(dt: float = TICK) -> void:
	if phase == Phase.DONE:
		return
	tick_count += 1
	time += dt
	_tick_players(dt)
	_tick_phase(dt)
	_tick_enemies(dt)
	_tick_bullets(dt)
	_check_end()


func snapshot() -> Dictionary:
	var ps: Array = []
	for id: int in players:
		var p: Dictionary = players[id]
		ps.append([id, int(p["x"]), int(p["y"]), int(ceilf(float(p["hp"]))), 1 if bool(p["downed"]) else 0, snappedf(float(p["aim"]), 0.01),
			1 if bool(p["alive"]) else 0, snappedf(float(p["revive"]) / REVIVE_TIME, 0.01)])
	var es: Array = []
	for e in enemies:
		es.append([int(e["id"]), int(e["type"]), int(e["x"]), int(e["y"]), snappedf(float(e["hp"]) / float(e["max"]), 0.01)])
	var bs: Array = []
	for b in bullets:
		bs.append([int(b["x"]), int(b["y"])])
	return {"tick": tick_count, "wave": wave_index + 1, "waves": _waves.size(), "phase": int(phase), "p": ps, "e": es, "b": bs}


## Итоги для начисления наград (их проверит и выдаст серверный RPC в Supabase, не клиент).
func results() -> Dictionary:
	var out: Dictionary = {}
	for id: int in players:
		var p: Dictionary = players[id]
		var coins := mini(int(p["kills"]) + _waves_cleared * 10 + (50 if won else 0), REWARD_COINS_CAP)
		var xp := mini(int(float(p["damage"]) / 40.0) + _waves_cleared * 5, REWARD_XP_CAP)
		out[id] = {"kills": int(p["kills"]), "damage": int(float(p["damage"])), "coins": coins, "xp": xp}
	return {"won": won, "waves_cleared": _waves_cleared, "seconds": int(time), "players": out}


func alive_enemy_count() -> int:
	return enemies.size()


# --- игроки -----------------------------------------------------------------

func _tick_players(dt: float) -> void:
	for id: int in players:
		var p: Dictionary = players[id]
		if not bool(p["alive"]):
			continue
		if bool(p["downed"]):
			p["bleed"] = float(p["bleed"]) + dt
			if float(p["bleed"]) >= BLEED_TIME:
				p["alive"] = false
				p["downed"] = false
				continue
			_tick_revive(id, p, dt)
			continue
		var velocity := Vector2(float(p["in_x"]), float(p["in_y"])) * PLAYER_SPEED
		var pos := Vector2(float(p["x"]), float(p["y"])) + velocity * dt
		pos = pos.clamp(ARENA.position, ARENA.end)
		p["x"] = pos.x
		p["y"] = pos.y
		p["fire_cd"] = maxf(float(p["fire_cd"]) - dt, 0.0)
		if float(p["fire_cd"]) <= 0.0:
			var target := _nearest_enemy(pos, FIRE_RANGE)
			if target >= 0:
				var to := Vector2(float(enemies[target]["x"]), float(enemies[target]["y"])) - pos
				var dir := to.normalized()
				p["aim"] = dir.angle()
				bullets.append({"x": pos.x, "y": pos.y, "vx": dir.x * BULLET_SPEED, "vy": dir.y * BULLET_SPEED, "life": BULLET_LIFE, "owner": id})
				p["fire_cd"] = FIRE_INTERVAL


func _tick_revive(id: int, p: Dictionary, dt: float) -> void:
	var helper := false
	var pos := Vector2(float(p["x"]), float(p["y"]))
	for other_id: int in players:
		if other_id == id:
			continue
		var o: Dictionary = players[other_id]
		if bool(o["alive"]) and not bool(o["downed"]) and Vector2(float(o["x"]), float(o["y"])).distance_to(pos) <= REVIVE_RANGE:
			helper = true
			break
	if helper:
		p["revive"] = float(p["revive"]) + dt
		if float(p["revive"]) >= REVIVE_TIME:
			p["downed"] = false
			p["hp"] = REVIVE_HP
			p["revive"] = 0.0
			p["bleed"] = 0.0
			player_revived.emit(id)
	else:
		p["revive"] = maxf(float(p["revive"]) - dt, 0.0)


func _nearest_enemy(from: Vector2, max_range: float) -> int:
	var best := -1
	var best_d := max_range * max_range
	for i in enemies.size():
		var d := from.distance_squared_to(Vector2(float(enemies[i]["x"]), float(enemies[i]["y"])))
		if d < best_d:
			best_d = d
			best = i
	return best


func _nearest_player(from: Vector2) -> int:
	var best := -1
	var best_d := INF
	for id: int in players:
		var p: Dictionary = players[id]
		if not bool(p["alive"]) or bool(p["downed"]):
			continue
		var d := from.distance_squared_to(Vector2(float(p["x"]), float(p["y"])))
		if d < best_d:
			best_d = d
			best = id
	return best


# --- волны ------------------------------------------------------------------

func _begin_wave(index: int) -> void:
	wave_index = index
	phase = Phase.INTRO
	_phase_time = INTRO_TIME
	var wave := _waves[index] as Dictionary
	var extra := maxi(players.size() - 1, 0)
	_spawn_left = int(round(float(wave.get("count", 10)) * (1.0 + COUNT_PER_EXTRA_PLAYER * float(extra))))
	_spawn_timer = 0.0
	_hp_mult = 1.0 + float(_difficulty.get("hp_per_wave", 0.09)) * float(index)
	_dmg_mult = 1.0 + float(_difficulty.get("damage_per_wave", 0.055)) * float(index)
	_spd_mult = 1.0 + float(_difficulty.get("speed_per_wave", 0.012)) * float(index)
	wave_started.emit(index + 1, str(wave.get("title", "")))


func _tick_phase(dt: float) -> void:
	_phase_time -= dt
	match phase:
		Phase.INTRO:
			if _phase_time <= 0.0:
				phase = Phase.FIGHT
		Phase.FIGHT:
			var wave := _waves[wave_index] as Dictionary
			_spawn_timer -= dt
			var cap := int(wave.get("max_alive", 10)) + 4 * maxi(players.size() - 1, 0)
			if _spawn_left > 0 and _spawn_timer <= 0.0 and enemies.size() < cap:
				var batch := mini(int(wave.get("batch", 2)), _spawn_left)
				for _i in batch:
					_spawn_enemy(wave)
				_spawn_left -= batch
				_spawn_timer = float(wave.get("spawn_interval", 1.0))
			if _spawn_left <= 0 and enemies.is_empty():
				_waves_cleared += 1
				wave_cleared.emit(wave_index + 1)
				if wave_index + 1 >= _waves.size():
					won = true
					phase = Phase.DONE
					finished.emit(true)
				else:
					phase = Phase.INTERMISSION
					_phase_time = float(_difficulty.get("intermission", 3.5))
		Phase.INTERMISSION:
			if _phase_time <= 0.0:
				_begin_wave(wave_index + 1)


func _spawn_enemy(wave: Dictionary) -> void:
	var anchor := _nearest_player(Vector2.ZERO)
	var origin := Vector2.ZERO
	if not players.is_empty():
		var keys := players.keys()
		var pick: int = keys[_rng.randi() % keys.size()]
		var p: Dictionary = players[pick]
		origin = Vector2(float(p["x"]), float(p["y"]))
	if anchor < 0 and players.is_empty():
		return
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(SPAWN_RING_MIN, SPAWN_RING_MAX)
	var pos := (origin + Vector2.from_angle(angle) * dist).clamp(ARENA.position, ARENA.end)
	var id := _pick_type(wave.get("weights", {}))
	var def: Dictionary = _enemy_defs.get(id, {})
	if def.is_empty():
		return
	var hp := float(def.get("max_hp", 20.0)) * _hp_mult
	enemies.append({"id": _next_id, "type": int(_type_index.get(id, 0)), "x": pos.x, "y": pos.y, "hp": hp, "max": hp,
		"spd": float(def.get("move_speed", 110.0)) * _spd_mult, "dmg": float(def.get("contact_damage", 6.0)) * _dmg_mult,
		"r": float(def.get("radius", 20.0)), "cd": 0.0})
	_next_id += 1


func _pick_type(weights: Variant) -> String:
	if not weights is Dictionary or (weights as Dictionary).is_empty():
		return "rat_punk"
	var total := 0.0
	for key: Variant in weights:
		total += float(weights[key])
	var roll := _rng.randf() * total
	for key: Variant in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return str(key)
	return str((weights as Dictionary).keys()[0])


# --- враги и пули -----------------------------------------------------------

func _tick_enemies(dt: float) -> void:
	for e in enemies:
		var pos := Vector2(float(e["x"]), float(e["y"]))
		var target := _nearest_player(pos)
		e["cd"] = maxf(float(e["cd"]) - dt, 0.0)
		if target < 0:
			continue
		var p: Dictionary = players[target]
		var to := Vector2(float(p["x"]), float(p["y"])) - pos
		var dist := to.length()
		var reach := float(e["r"]) + PLAYER_RADIUS
		if dist > reach * 0.8:
			pos += to / maxf(dist, 0.001) * float(e["spd"]) * dt
			e["x"] = pos.x
			e["y"] = pos.y
		if dist <= reach and float(e["cd"]) <= 0.0:
			e["cd"] = CONTACT_COOLDOWN
			_hurt_player(target, float(e["dmg"]))


func _hurt_player(id: int, amount: float) -> void:
	var p: Dictionary = players[id]
	if bool(p["downed"]) or not bool(p["alive"]):
		return
	p["hp"] = maxf(float(p["hp"]) - amount, 0.0)
	if float(p["hp"]) <= 0.0:
		p["downed"] = true
		p["bleed"] = 0.0
		p["revive"] = 0.0
		player_downed.emit(id)


func _tick_bullets(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for b in bullets:
		b["life"] = float(b["life"]) - dt
		if float(b["life"]) <= 0.0:
			continue
		b["x"] = float(b["x"]) + float(b["vx"]) * dt
		b["y"] = float(b["y"]) + float(b["vy"]) * dt
		var hit := false
		var bpos := Vector2(float(b["x"]), float(b["y"]))
		for e in enemies:
			if bpos.distance_to(Vector2(float(e["x"]), float(e["y"]))) <= float(e["r"]) + BULLET_RADIUS:
				e["hp"] = float(e["hp"]) - BULLET_DAMAGE
				var owner_id: int = b["owner"]
				if players.has(owner_id):
					var owner_state: Dictionary = players[owner_id]
					owner_state["damage"] = float(owner_state["damage"]) + BULLET_DAMAGE
					if float(e["hp"]) <= 0.0:
						owner_state["kills"] = int(owner_state["kills"]) + 1
				hit = true
				break
		if not hit:
			keep.append(b)
	bullets = keep
	var alive: Array[Dictionary] = []
	for e in enemies:
		if float(e["hp"]) > 0.0:
			alive.append(e)
	enemies = alive


func _check_end() -> void:
	if phase == Phase.DONE:
		return
	for id: int in players:
		var p: Dictionary = players[id]
		if bool(p["alive"]):
			return
	if players.is_empty():
		return
	phase = Phase.DONE
	won = false
	finished.emit(false)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
