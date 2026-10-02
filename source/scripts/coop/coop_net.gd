class_name CoopNet
extends Node
## Сетевой узел коопа: комнаты, готовность, старт, тик арен и снимки. Одинаковый узел с именем «CoopNet» создаётся на сервере и
## на клиентах (путь узла должен совпасть, иначе @rpc не найдёт его). Клиент решает только «куда иду» и «готов»;
## всё остальное считает сервер. Код комнаты = дружеский код хозяина (друзья входят по нему из списка друзей).

signal room_state(state: Dictionary)
signal room_error(code: String)
signal snapshot_received(data: Dictionary)
signal run_finished(results: Dictionary)
signal notice(kind: String, who: String)

const SNAPSHOT_EVERY := 2
const MAX_MEMBERS := 2
const CHAPTER := 0
## Версия протокола: клиент старой сборки получает «old_version» вместо тихой поломки.
const PROTOCOL := 1
const OPS_PER_WINDOW := 8
const OPS_WINDOW_SEC := 10.0

## Минимум игроков для старта. Для автотестов можно поставить 1.
var min_players := 2
## Пауза после того, как все нажали «готов» (можно передумать). В автотестах ставят 0.
var countdown := 3.0

# --- состояние сервера ---
var rooms: Dictionary = {}       # code -> {host, members: Array[int], ready: Dictionary, arena: CoopArena, acc: float, ticks: int}
var _peer_room: Dictionary = {}  # peer_id -> code
## Последний отчёт о забеге (для автотестов и отладки на сервере).
var last_report: Dictionary = {}
var _ops: Dictionary = {}        # peer_id -> Array[float] времена последних операций с комнатой


func _ready() -> void:
	Net.left.connect(_on_peer_left)


# =========================== клиент -> сервер ===========================

func create_room() -> void:
	_create_room.rpc_id(1, PROTOCOL)


func join_room(code: String) -> void:
	_join_room.rpc_id(1, code, PROTOCOL)


func set_ready(value: bool) -> void:
	_set_ready.rpc_id(1, value)


func leave_room() -> void:
	_leave_room.rpc_id(1)


## Куда идёт игрок. Больше клиент ничего не решает.
func send_move(move: Vector2) -> void:
	if multiplayer.is_server():
		return
	_move_input.rpc_id(1, move)


@rpc("any_peer", "call_remote", "reliable")
func _create_room(protocol: int = 0) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _limited(id):
		return
	if protocol != PROTOCOL:
		_error(id, "old_version")
		return
	if _peer_room.has(id):
		_error(id, "already_in_room")
		return
	var profile: Dictionary = Net.profiles.get(id, {})
	var code := str(profile.get("friend_code", "")).to_upper()
	if code.is_empty():
		code = "R%05d" % (randi() % 100000)
	if not _valid_code(code):
		_error(id, "bad_code")
		return
	if rooms.has(code):
		_error(id, "room_exists")
		return
	rooms[code] = {"host": id, "members": [id], "ready": {}, "arena": null, "acc": 0.0, "ticks": 0, "countdown": -1.0, "uids": {}}
	_peer_room[id] = code
	_broadcast_state(code)


@rpc("any_peer", "call_remote", "reliable")
func _join_room(code: String, protocol: int = 0) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _limited(id):
		return
	if protocol != PROTOCOL:
		_error(id, "old_version")
		return
	var key := code.strip_edges().to_upper()
	if not _valid_code(key):
		_error(id, "bad_code")
		return
	if _peer_room.has(id):
		_error(id, "already_in_room")
		return
	if not rooms.has(key):
		_error(id, "no_room")
		return
	# Войти можно только к другу: проверка идёт на сервере по токену самого игрока (coop_can_join). Автотесты пропускают.
	if not Net.insecure_test:
		var token := str(Net.tokens.get(id, ""))
		var check := await Cloud.post_with_token("/rest/v1/rpc/coop_can_join", {"p_room": key}, token)
		if not Net.profiles.has(id):
			return   # пока ждали ответ, игрок вышел
		if not bool(check["ok"]):
			_error(id, "check_failed")
			return
		if not bool(check["data"]):
			_error(id, "not_friends")
			return
		if _peer_room.has(id):
			_error(id, "already_in_room")
			return
		if not rooms.has(key):
			_error(id, "no_room")
			return
	var room: Dictionary = rooms[key]
	if room["arena"] != null:
		_error(id, "run_in_progress")
		return
	var members: Array = room["members"]
	if members.size() >= MAX_MEMBERS:
		_error(id, "room_full")
		return
	members.append(id)
	_peer_room[id] = key
	_cancel_countdown(key)
	for other: int in members:
		if other != id:
			_notice.rpc_id(other, "joined", _name_of(id))
	_broadcast_state(key)


@rpc("any_peer", "call_remote", "reliable")
func _set_ready(value: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _limited(id):
		return
	var code: String = _peer_room.get(id, "")
	if code.is_empty() or not rooms.has(code) or rooms[code]["arena"] != null:
		return
	var room: Dictionary = rooms[code]
	(room["ready"] as Dictionary)[id] = value
	if not value:
		_cancel_countdown(code)
	_broadcast_state(code)
	_try_start(code)


@rpc("any_peer", "call_remote", "reliable")
func _leave_room() -> void:
	_remove_peer(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _move_input(move: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	var code: String = _peer_room.get(id, "")
	if code.is_empty() or not rooms.has(code):
		return
	var arena := rooms[code]["arena"] as CoopArena
	if arena != null:
		arena.set_input(id, move)


# =========================== сервер -> клиент ===========================

@rpc("authority", "call_remote", "reliable")
func _room_state(state: Dictionary) -> void:
	room_state.emit(state)


@rpc("authority", "call_remote", "reliable")
func _room_error(code: String) -> void:
	room_error.emit(code)


@rpc("authority", "call_remote", "reliable")
func _notice(kind: String, who: String) -> void:
	notice.emit(kind, who)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(data: Dictionary) -> void:
	snapshot_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _finished(results: Dictionary) -> void:
	run_finished.emit(results)


# =========================== логика сервера ===========================

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for code: String in rooms.keys():
		var room: Dictionary = rooms[code]
		var arena := room["arena"] as CoopArena
		if arena == null:
			if float(room.get("countdown", -1.0)) >= 0.0:
				room["countdown"] = float(room["countdown"]) - delta
				if float(room["countdown"]) <= 0.0:
					_launch(code)
			continue
		room["acc"] = float(room["acc"]) + delta
		while float(room["acc"]) >= CoopArena.TICK:
			room["acc"] = float(room["acc"]) - CoopArena.TICK
			arena.tick(CoopArena.TICK)
			room["ticks"] = int(room["ticks"]) + 1
			if int(room["ticks"]) % SNAPSHOT_EVERY == 0:
				var snap := arena.snapshot()
				for member: int in room["members"]:
					_snapshot.rpc_id(member, snap)


func _try_start(code: String) -> void:
	var room: Dictionary = rooms[code]
	var members: Array = room["members"]
	if members.size() < min_players or float(room.get("countdown", -1.0)) >= 0.0:
		return
	for member: int in members:
		if not bool((room["ready"] as Dictionary).get(member, false)):
			return
	if countdown <= 0.0:
		_launch(code)
		return
	room["countdown"] = countdown
	_broadcast_state(code)


func _cancel_countdown(code: String) -> void:
	if rooms.has(code) and float(rooms[code].get("countdown", -1.0)) >= 0.0:
		rooms[code]["countdown"] = -1.0
		_broadcast_state(code)


func _launch(code: String) -> void:
	var room: Dictionary = rooms[code]
	var members: Array = room["members"]
	room["countdown"] = -1.0
	var arena := CoopArena.new()
	if not arena.setup(CHAPTER):
		for member: int in members:
			_error(member, "arena_failed")
		_broadcast_state(code)
		return
	for member: int in members:
		arena.add_player(member)
	arena.finished.connect(func(_won: bool) -> void: _end_run(code))
	room["arena"] = arena
	room["acc"] = 0.0
	room["ticks"] = 0
	_broadcast_state(code)


func _end_run(code: String) -> void:
	if not rooms.has(code):
		return
	var room: Dictionary = rooms[code]
	var arena := room["arena"] as CoopArena
	if arena == null:
		return
	var results := arena.results()
	results["names"] = _names(room["members"])
	for member: int in room["members"]:
		(room["uids"] as Dictionary)[member] = str((Net.profiles.get(member, {}) as Dictionary).get("id", ""))
	_report_run(results, room["uids"] as Dictionary)
	for member: int in room["members"]:
		_finished.rpc_id(member, results)
	run_finished.emit(results)
	room["arena"] = null
	room["ready"] = {}
	_broadcast_state(code)


func _on_peer_left(id: int) -> void:
	_remove_peer(id)


func _remove_peer(id: int) -> void:
	var code: String = _peer_room.get(id, "")
	_peer_room.erase(id)
	if code.is_empty() or not rooms.has(code):
		return
	_ops.erase(id)
	var room: Dictionary = rooms[code]
	var leaver := _name_of(id)
	(room["members"] as Array).erase(id)
	(room["ready"] as Dictionary).erase(id)
	room["countdown"] = -1.0
	var arena := room["arena"] as CoopArena
	if arena != null:
		(room["uids"] as Dictionary)[id] = str((Net.profiles.get(id, {}) as Dictionary).get("id", ""))   # профиль уходящего нужен для штрафа
		arena.remove_player(id)
	if (room["members"] as Array).is_empty():
		rooms.erase(code)
		return
	for other: int in room["members"]:
		_notice.rpc_id(other, "left", leaver)
	if int(room["host"]) == id:
		room["host"] = (room["members"] as Array)[0]
	_broadcast_state(code)


func _name_of(id: int) -> String:
	return str((Net.profiles.get(id, {}) as Dictionary).get("nickname", "Енот"))


## Код комнаты: только латиница и цифры, 3-12 знаков (тот же шаблон, что в базе).
func _valid_code(code: String) -> bool:
	if code.length() < 3 or code.length() > 12:
		return false
	for i in code.length():
		var c := code.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90)):
			return false
	return true


## Не больше OPS_PER_WINDOW операций с комнатой за OPS_WINDOW_SEC от одного игрока, лишнее молча отбрасывается с ошибкой.
func _limited(id: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var list: Array = _ops.get(id, [])
	while not list.is_empty() and now - float(list[0]) > OPS_WINDOW_SEC:
		list.pop_front()
	if list.size() >= OPS_PER_WINDOW:
		_ops[id] = list
		_error(id, "slow_down")
		return true
	list.append(now)
	_ops[id] = list
	return false


## Тело запроса coop_submit_run. uid_by_peer: peer_id -> id аккаунта (игроки без аккаунта пропускаются).
static func build_report(run_id: String, results: Dictionary, uid_by_peer: Dictionary) -> Dictionary:
	var players: Array = []
	var stats: Dictionary = results.get("players", {})
	for peer: Variant in stats:
		var uid := str(uid_by_peer.get(peer, uid_by_peer.get(int(peer), "")))
		if uid.is_empty() or uid.begins_with(Net.TEST_PREFIX):
			continue
		var p := stats[peer] as Dictionary
		players.append({"uid": uid, "kills": int(p.get("kills", 0)), "damage": int(p.get("damage", 0)), "revives": int(p.get("revives", 0)),
			"downs": int(p.get("downs", 0)), "left": bool(p.get("left", false)), "coins": int(p.get("coins", 0)), "xp": int(p.get("xp", 0))})
	return {"run_id": run_id, "waves": int(results.get("waves_cleared", 0)), "seconds": int(results.get("seconds", 0)), "won": bool(results.get("won", false)), "players": players}


static func new_run_id() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## Сервер записывает итоги забега в базу ключом service_role из окружения (SUPABASE_SERVICE_KEY). Награды и очки считает база.
func _report_run(results: Dictionary, uids: Dictionary) -> void:
	last_report = build_report(new_run_id(), results, uids)
	if Net.insecure_test or (last_report["players"] as Array).is_empty():
		return
	var key := OS.get_environment("SUPABASE_SERVICE_KEY")
	if key.is_empty():
		push_warning("CoopNet: SUPABASE_SERVICE_KEY не задан, итоги забега не записаны")
		return
	_send_report(last_report.duplicate(true), key)


func _send_report(report: Dictionary, key: String) -> void:
	for attempt in 4:
		var reply := await Cloud.post_service("/rest/v1/rpc/coop_submit_run", {"p_run": report}, key)
		var answer := str(reply["data"])
		if bool(reply["ok"]) and answer in ["ok", "dup", "short", "bad"]:
			print("CoopNet: итоги %s -> %s" % [str(report["run_id"]), answer])
			return
		await get_tree().create_timer(2.0 * float(attempt + 1)).timeout
	push_error("CoopNet: итоги забега %s не записаны после 4 попыток" % str(report["run_id"]))


func _names(members: Array) -> Dictionary:
	var out: Dictionary = {}
	for member: int in members:
		var profile: Dictionary = Net.profiles.get(member, {})
		out[member] = str(profile.get("nickname", "Енот"))
	return out


func _state_of(code: String) -> Dictionary:
	var room: Dictionary = rooms[code]
	var list: Array = []
	for member: int in room["members"]:
		var profile: Dictionary = Net.profiles.get(member, {})
		list.append({"id": member, "name": str(profile.get("nickname", "Енот")), "ready": bool((room["ready"] as Dictionary).get(member, false)),
			"host": member == int(room["host"]), "insider": int(profile.get("insider", -1)),
			"c": str(profile.get("c", "")), "s": str(profile.get("s", "classic")), "lv": int(profile.get("lv", 1)), "code": str(profile.get("friend_code", "")), "rating": int(profile.get("rating", 0)), "tier": str(profile.get("tier", ""))})
	return {"code": code, "members": list, "running": room["arena"] != null, "min": min_players, "max": MAX_MEMBERS,
		"countdown": maxf(float(room.get("countdown", -1.0)), -1.0)}


func _broadcast_state(code: String) -> void:
	var state := _state_of(code)
	for member: int in rooms[code]["members"]:
		_room_state.rpc_id(member, state)


func _error(id: int, code: String) -> void:
	_room_error.rpc_id(id, code)
