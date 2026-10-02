class_name CoopNet
extends Node
## Сетевой узел коопа: комнаты, готовность, старт, тик арен и снимки. Одинаковый узел с именем «CoopNet» создаётся на сервере и
## на клиентах (путь узла должен совпасть, иначе @rpc не найдёт его). Клиент решает только «куда иду» и «готов»;
## всё остальное считает сервер. Код комнаты = дружеский код хозяина (друзья входят по нему из списка друзей).

signal room_state(state: Dictionary)
signal room_error(code: String)
signal snapshot_received(data: Dictionary)
signal run_finished(results: Dictionary)

const SNAPSHOT_EVERY := 2
const MAX_MEMBERS := 2
const CHAPTER := 0

## Минимум игроков для старта. Для автотестов можно поставить 1.
var min_players := 2

# --- состояние сервера ---
var rooms: Dictionary = {}       # code -> {host, members: Array[int], ready: Dictionary, arena: CoopArena, acc: float, ticks: int}
var _peer_room: Dictionary = {}  # peer_id -> code


func _ready() -> void:
	Net.left.connect(_on_peer_left)


# =========================== клиент -> сервер ===========================

func create_room() -> void:
	_create_room.rpc_id(1)


func join_room(code: String) -> void:
	_join_room.rpc_id(1, code)


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
func _create_room() -> void:
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id):
		_error(id, "already_in_room")
		return
	var profile: Dictionary = Net.profiles.get(id, {})
	var code := str(profile.get("friend_code", "")).to_upper()
	if code.is_empty():
		code = "R%05d" % (randi() % 100000)
	if rooms.has(code):
		_error(id, "room_exists")
		return
	rooms[code] = {"host": id, "members": [id], "ready": {}, "arena": null, "acc": 0.0, "ticks": 0}
	_peer_room[id] = code
	_broadcast_state(code)


@rpc("any_peer", "call_remote", "reliable")
func _join_room(code: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var key := code.strip_edges().to_upper()
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
	_broadcast_state(key)


@rpc("any_peer", "call_remote", "reliable")
func _set_ready(value: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	var code: String = _peer_room.get(id, "")
	if code.is_empty() or not rooms.has(code) or rooms[code]["arena"] != null:
		return
	var room: Dictionary = rooms[code]
	(room["ready"] as Dictionary)[id] = value
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
	if members.size() < min_players:
		return
	for member: int in members:
		if not bool((room["ready"] as Dictionary).get(member, false)):
			return
	var arena := CoopArena.new()
	if not arena.setup(CHAPTER):
		for member: int in members:
			_error(member, "arena_failed")
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
	var room: Dictionary = rooms[code]
	(room["members"] as Array).erase(id)
	(room["ready"] as Dictionary).erase(id)
	var arena := room["arena"] as CoopArena
	if arena != null:
		arena.remove_player(id)
	if (room["members"] as Array).is_empty():
		rooms.erase(code)
		return
	if int(room["host"]) == id:
		room["host"] = (room["members"] as Array)[0]
	_broadcast_state(code)


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
			"host": member == int(room["host"]), "insider": int(profile.get("insider", -1))})
	return {"code": code, "members": list, "running": room["arena"] != null, "min": min_players, "max": MAX_MEMBERS}


func _broadcast_state(code: String) -> void:
	var state := _state_of(code)
	for member: int in rooms[code]["members"]:
		_room_state.rpc_id(member, state)


func _error(id: int, code: String) -> void:
	_room_error.rpc_id(id, code)
