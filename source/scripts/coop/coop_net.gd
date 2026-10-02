class_name CoopNet
extends Node
## Сетевая обвязка арены коопа. Одинаковый узел с именем «CoopNet» создаётся и на сервере, и на клиентах
## (путь узла должен совпадать, иначе @rpc не найдёт его). Сервер тикает арену 30 раз в секунду и шлёт снимки 15 раз
## в секунду; клиент шлёт только вектор движения.

signal snapshot_received(data: Dictionary)
signal run_finished(results: Dictionary)

const SNAPSHOT_EVERY := 2

var arena: CoopArena
var _acc := 0.0
var _ticks := 0


func start_server_arena(chapter_index: int, peer_ids: Array[int]) -> bool:
	arena = CoopArena.new()
	if not arena.setup(chapter_index):
		arena = null
		return false
	for id in peer_ids:
		arena.add_player(id)
	arena.finished.connect(func(_won: bool) -> void: _announce_finish())
	return true


func _physics_process(delta: float) -> void:
	if arena == null or not multiplayer.is_server():
		return
	_acc += delta
	while _acc >= CoopArena.TICK:
		_acc -= CoopArena.TICK
		arena.tick(CoopArena.TICK)
		_ticks += 1
		if _ticks % SNAPSHOT_EVERY == 0:
			_snapshot.rpc(arena.snapshot())


## Клиент -> сервер: куда идёт игрок. Больше клиент ничего не решает.
func send_move(move: Vector2) -> void:
	if multiplayer.is_server():
		return
	_move_input.rpc_id(1, move)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _move_input(move: Vector2) -> void:
	if arena != null and multiplayer.is_server():
		arena.set_input(multiplayer.get_remote_sender_id(), move)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(data: Dictionary) -> void:
	snapshot_received.emit(data)


func _announce_finish() -> void:
	var results := arena.results()
	_finished.rpc(results)
	run_finished.emit(results)


@rpc("authority", "call_remote", "reliable")
func _finished(results: Dictionary) -> void:
	run_finished.emit(results)
