extends Node
## Сетевой фасад для коопа. Геймплей работает с этим классом, а не с пирами: транспорт (ENet на нативных платформах,
## WebSocket в вебе) выбирается здесь, логика синхронизации у них общая. Сервер авторитетный: клиенты шлют ввод,
## сервер считает бой и награды. Подробности: проект AppRaccoon, claude/netcode_design.md и claude/coop_plan.md.

signal joined(peer_id: int, profile: Dictionary)
signal left(peer_id: int)
signal failed(reason: String)
signal server_said(text: String)

const PORT_UDP := 7777
const PORT_WS := 7778
const MAX_CLIENTS := 8
const AUTH_TIMEOUT := 5.0
const TEST_PREFIX := "test:"

## Только для автотестов (запуск с аргументом --net-test): токены вида «test:Ник» принимаются без Supabase.
var insecure_test := false
var profiles: Dictionary = {}   # peer_id -> {id, nickname, insider}
var _wired := false


func _ready() -> void:
	insecure_test = "--net-test" in OS.get_cmdline_user_args()


func use_websocket() -> bool:
	return Platform.is_web or "--ws" in OS.get_cmdline_user_args()


func is_active() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func start_server(port_udp: int = PORT_UDP, port_ws: int = PORT_WS) -> bool:
	var peer: MultiplayerPeer
	if use_websocket():
		if Platform.is_web:
			failed.emit("server_in_web")
			return false
		var ws := WebSocketMultiplayerPeer.new()
		if ws.create_server(port_ws) != OK:
			failed.emit("ws_server")
			return false
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		if enet.create_server(port_udp, MAX_CLIENTS) != OK:
			failed.emit("enet_server")
			return false
		peer = enet
	_attach(peer)
	return true


## host: «play.example.com» (для WebSocket добавляется wss://), или «127.0.0.1» для локального ENet.
func connect_to(host: String, port_udp: int = PORT_UDP, port_ws: int = PORT_WS) -> bool:
	var peer: MultiplayerPeer
	if use_websocket():
		var ws := WebSocketMultiplayerPeer.new()
		var url := host if host.begins_with("ws") else "wss://%s" % host
		if host.begins_with("localhost") or host.begins_with("127."):
			url = "ws://%s:%d" % [host, port_ws]
		if ws.create_client(url) != OK:
			failed.emit("ws_client")
			return false
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		if enet.create_client(host, port_udp) != OK:
			failed.emit("enet_client")
			return false
		peer = enet
	_attach(peer)
	return true


func disconnect_all() -> void:
	if is_active():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	profiles.clear()


func say_to_all(text: String) -> void:
	if multiplayer.is_server():
		_server_say.rpc(text)


@rpc("authority", "call_remote", "reliable")
func _server_say(text: String) -> void:
	server_said.emit(text)


func _attach(peer: MultiplayerPeer) -> void:
	var api := multiplayer as SceneMultiplayer
	if not _wired:
		_wired = true
		api.auth_callback = _on_auth
		api.auth_timeout = AUTH_TIMEOUT
		api.peer_authenticating.connect(_on_authenticating)
		api.peer_authentication_failed.connect(func(id: int) -> void: failed.emit("auth %d" % id))
		api.peer_connected.connect(func(id: int) -> void:
			if multiplayer.is_server():
				joined.emit(id, profiles.get(id, {})))
		api.peer_disconnected.connect(func(id: int) -> void:
			profiles.erase(id)
			left.emit(id))
		api.connection_failed.connect(func() -> void: failed.emit("connection_failed"))
		api.server_disconnected.connect(func() -> void: failed.emit("server_disconnected"))
	multiplayer.multiplayer_peer = peer


## Клиент: на этапе авторизации отправляет свой токен. Пир считается подключённым только после complete_auth с обеих сторон.
func _on_authenticating(id: int) -> void:
	if multiplayer.is_server():
		return
	var token := Cloud.access_token()
	if token.is_empty() and insecure_test:
		token = TEST_PREFIX + ("player%d" % (randi() % 1000))
	(multiplayer as SceneMultiplayer).send_auth(id, token.to_utf8_buffer())


func _on_auth(id: int, data: PackedByteArray) -> void:
	var api := multiplayer as SceneMultiplayer
	if not multiplayer.is_server():
		api.complete_auth(id)   # ответ сервера получен: сервер проверил нас
		return
	var profile := await verify_token(data.get_string_from_utf8())
	if profile.is_empty():
		failed.emit("bad_token %d" % id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	profiles[id] = profile
	api.send_auth(id, PackedByteArray([1]))
	api.complete_auth(id)


## Проверка токена на сервере: /auth/v1/user отдаёт владельца токена, и только потом читаем его профиль.
## Ник и тег берутся отсюда, а не от клиента.
func verify_token(jwt: String) -> Dictionary:
	if jwt.is_empty():
		return {}
	if jwt.begins_with(TEST_PREFIX):
		return {"id": jwt, "nickname": jwt.trim_prefix(TEST_PREFIX), "insider": -1} if insecure_test else {}
	var user := await Cloud.fetch_with_token("/auth/v1/user", jwt)
	var uid := str(user.get("id", ""))
	if uid.is_empty():
		return {}
	var rows := await Cloud.fetch_with_token("/rest/v1/profiles?id=eq.%s&select=id,nickname,insider" % uid, jwt)
	var row: Variant = rows.get("row", {})
	return row as Dictionary if row is Dictionary else {}
