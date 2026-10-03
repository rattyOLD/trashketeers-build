extends Node
## Autoload "SoundManager". Единственное место в игре, где существуют аудиоплееры (ТЗ §3):
## игровые объекты только вызывают SoundManager.play(&"id").
##
## - SFX играют через пул из SFX_POOL_SIZE заранее созданных AudioStreamPlayer.
##   Свободный плеер ищется по кругу; если заняты все — перебивается самый старый звук.
## - У каждого SFX есть min_interval: десятки попаданий в одном кадре дают один звук, а не фриз.
## - Питч коротких SFX случайно гуляет в [0.95, 1.05].
## - Ничего не играет до первого касания/клика: мобильные WebView (и Telegram) блокируют
##   аудио без жеста пользователя. Запрошенная до этого музыка запоминается и стартует после тача.
##   Сам AudioContext на iOS разблокирует web/audio_unlock.js в HTML-оболочке (resume() строго
##   внутри touchend + сессия "playback", чтобы звук шёл и при беззвучном режиме айфона).

const SFX_POOL_SIZE := 12
## Общий лимит запусков звуков в секунду для «частых» SFX. В вебе Godot на каждый запуск
## создаёт новые аудио-узлы (источник, 8 узлов шины, AudioWorklet позиции); сотни запусков
## в секунду на iOS копились и роняли страницу через ~40 с боя.
const SFX_BUDGET_PER_SEC := 10.0
const SFX_BUDGET_BURST := 5.0
const PRIORITY_SFX: Array[StringName] = [&"player_hurt", &"explosion", &"level_up", &"boss_spawn", &"victory", &"defeat",
	&"ui_click", &"ui_confirm", &"achievement", &"weapon_pickup", &"crate_break", &"dash", &"shield_up", &"star_dust", &"merge"]
const LOOP_CHANNELS := 2
const PITCH_MIN := 0.95
const PITCH_MAX := 1.05
const MUSIC_FADE := 0.8
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"

## id: [громкость dB, минимальный интервал между повторами, сек]
const SFX := {
	&"shot_laser": [-14.0, 0.08],
	&"shot_shotgun": [-12.0, 0.08],
	&"shot_rail": [-12.0, 0.08],
	&"shot_railgun": [-7.0, 0.3],
	&"enemy_shot": [-18.0, 0.12],
	&"hit": [-17.0, 0.09],
	&"enemy_death": [-12.0, 0.07],
	&"player_hurt": [-6.0, 0.15],
	&"nut_pickup": [-23.0, 0.08],
	&"obstacle_break": [-8.0, 0.08],
	&"level_up": [-6.0, 0.2],
	&"ui_click": [-10.0, 0.05],
	&"ui_confirm": [-8.0, 0.1],
	&"boss_spawn": [-4.0, 0.5],
	&"victory": [-4.0, 1.0],
	&"defeat": [-6.0, 1.0],
	&"dragon_roar": [-3.0, 1.0],
	&"wing_flap": [-12.0, 0.3],
	&"comet_fall": [-12.0, 0.15],
	&"comet_impact": [-12.0, 0.08],
	&"dragon_land": [-2.0, 0.5],
	&"beam_charge": [-8.0, 0.5],
	&"beam_loop": [-10.0, 0.5],
	&"ice_blast": [-8.0, 0.2],
	&"crystal_break": [-8.0, 0.1],
	&"shield_up": [-8.0, 0.2],
	&"star_dust": [-4.0, 0.3],
	&"acid_splash": [-6.0, 0.1],
	&"shot_pistol": [-10.0, 0.07],
	&"shot_smg": [-15.0, 0.08],
	&"shot_rifle": [-12.0, 0.07],
	&"shot_sniper": [-6.0, 0.2],
	&"shot_lmg": [-15.0, 0.08],
	&"shot_double": [-7.0, 0.2],
	&"shot_launcher": [-6.0, 0.2],
	&"explosion": [-4.0, 0.06],
	&"flame": [-13.0, 0.09],
	&"step": [-12.0, 0.08],
	&"dash": [-6.0, 0.1],
	&"k_combo": [-12.0, 0.06],
	&"k_perfect": [-7.0, 0.6],
	&"weapon_pickup": [-6.0, 0.1],
	&"crate_break": [-6.0, 0.08],
	&"merge": [-4.0, 0.3],
	&"achievement": [-4.0, 0.5],
	&"amb_hum": [-22.0, 0.5],
	&"amb_wind": [-19.0, 0.5],
	&"amb_siren": [-17.0, 1.0],
	&"amb_neon": [-17.0, 0.3],
}

## Звуки, которые проигрываются циклично через play_loop (пул SFX их не трогает).
const LOOPED_SFX: Array[StringName] = [&"beam_loop", &"amb_hum", &"amb_wind"]
## Фон Свалки: два бесконечных слоя + редкие одиночные события со случайной паузой.
const AMBIENT_LOOPS: Array[StringName] = [&"amb_hum", &"amb_wind"]
const AMBIENT_EVENTS := {&"amb_siren": Vector2(22.0, 45.0), &"amb_neon": Vector2(6.0, 14.0)}

const MUSIC := {
	&"menu": -12.0,
	&"battle": -13.0,
	&"raid": -11.0,
	&"knife": -12.0,
}

var unlocked := false

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _started_ms: PackedInt64Array = PackedInt64Array()
var _last_played_ms: Dictionary = {}
var _budget := SFX_BUDGET_BURST
var _budget_ms := 0
var _loops: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_id: StringName = &""
var _pending_music: StringName = &""
var _music_tween: Tween
var _page_hidden := false
var _ambient: Array[AudioStreamPlayer] = []
var _ambient_timers: Dictionary = {}
var _ambient_on := false
var _visibility_callback: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_preload_streams()
	_create_players()
	_watch_visibility()
	apply_enabled()


func play(id: StringName, volume_offset_db: float = 0.0, randomize_pitch: bool = true) -> void:
	_play(id, volume_offset_db, randf_range(PITCH_MIN, PITCH_MAX) if randomize_pitch else 1.0)


## Звук с заданным питчем: серия подборов гаек «поднимается» по нотам.
func play_pitched(id: StringName, pitch: float, volume_offset_db: float = 0.0) -> void:
	_play(id, volume_offset_db, pitch)


func _play(id: StringName, volume_offset_db: float, pitch: float) -> void:
	if not unlocked or not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	var cfg: Array = SFX[id]
	if now - int(_last_played_ms.get(id, -100000)) < int(cfg[1] * 1000.0):
		return
	_budget = minf(_budget + float(now - _budget_ms) * 0.001 * SFX_BUDGET_PER_SEC, SFX_BUDGET_BURST)
	_budget_ms = now
	if not PRIORITY_SFX.has(id):
		if _budget < 1.0:
			return
		_budget -= 1.0
	_last_played_ms[id] = now

	var index := _pick_player()
	var player := _players[index]
	player.stream = _streams[id]
	player.volume_db = cfg[0] + volume_offset_db
	player.pitch_scale = pitch
	player.play()
	_started_ms[index] = now


## Возвращает номер канала для stop_loop или -1, если звук не запущен.
func play_loop(id: StringName) -> int:
	if not unlocked or not _streams.has(id):
		return -1
	for i in _loops.size():
		if not _loops[i].playing:
			_loops[i].stream = _streams[id]
			_loops[i].volume_db = SFX[id][0]
			_loops[i].pitch_scale = 1.0
			_loops[i].play()
			return i
	return -1


func stop_loop(channel: int) -> void:
	if channel >= 0 and channel < _loops.size():
		_loops[channel].stop()


func stop_all_loops() -> void:
	for player in _loops:
		player.stop()


func play_music(id: StringName) -> void:
	if not MUSIC.has(id):
		return
	if not unlocked:
		_pending_music = id
		return
	if id == _music_id and _music.playing:
		return
	_music_id = id
	_music.stream = _streams[_music_key(id)]
	_music.volume_db = -40.0
	_music.play()
	_fade_music_to(MUSIC[id])


func stop_music() -> void:
	_pending_music = &""
	_music_id = &""
	if _music.playing:
		_fade_music_to(-40.0, true)


func is_sfx_enabled() -> bool:
	return bool(SaveService.data["sfx_on"]) and get_volume("sfx") > 0.01


func is_music_enabled() -> bool:
	return bool(SaveService.data["music_on"]) and get_volume("music") > 0.01


func set_sfx_enabled(enabled: bool) -> void:
	SaveService.set_flag("sfx_on", enabled)
	apply_enabled()


func set_music_enabled(enabled: bool) -> void:
	SaveService.set_flag("music_on", enabled)
	apply_enabled()


## channel: "music" | "sfx"; value 0..1 (линейная громкость ползунка).
func get_volume(channel: String) -> float:
	return clampf(float(SaveService.data[channel + "_volume"]), 0.0, 1.0)


func set_volume(channel: String, value: float) -> void:
	SaveService.data[channel + "_volume"] = clampf(value, 0.0, 1.0)
	SaveService.data[channel + "_on"] = value > 0.01
	apply_enabled()


func apply_enabled() -> void:
	AudioServer.set_bus_mute(0, _page_hidden)
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	var music := AudioServer.get_bus_index(MUSIC_BUS)
	AudioServer.set_bus_mute(sfx, not is_sfx_enabled())
	AudioServer.set_bus_mute(music, not is_music_enabled())
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(get_volume("sfx"), 0.001)))
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(get_volume("music"), 0.001)))


func start_ambient() -> void:
	_ambient_on = true
	for i in AMBIENT_LOOPS.size():
		var id := AMBIENT_LOOPS[i]
		if not _streams.has(id) or _ambient[i].playing:
			continue
		_ambient[i].stream = _streams[id]
		_ambient[i].volume_db = SFX[id][0]
		if unlocked:
			_ambient[i].play()
	for id in AMBIENT_EVENTS:
		_ambient_timers[id] = randf_range(AMBIENT_EVENTS[id].x * 0.3, AMBIENT_EVENTS[id].y * 0.5)


func stop_ambient() -> void:
	_ambient_on = false
	for player in _ambient:
		player.stop()


func _process(delta: float) -> void:
	if not _ambient_on or not unlocked:
		return
	for i in _ambient.size():
		if not _ambient[i].playing and _ambient[i].stream != null:
			_ambient[i].play()
	for id in _ambient_timers:
		_ambient_timers[id] -= delta
		if _ambient_timers[id] <= 0.0:
			var range_s: Vector2 = AMBIENT_EVENTS[id]
			_ambient_timers[id] = randf_range(range_s.x, range_s.y)
			play(id, randf_range(-4.0, 0.0))


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	var is_gesture: bool = event.is_pressed() and (event is InputEventScreenTouch \
			or event is InputEventMouseButton or event is InputEventKey)
	if not is_gesture:
		return
	unlocked = true
	if _pending_music != &"":
		var id := _pending_music
		_pending_music = &""
		play_music(id)


## В вебе тишина по потере фокуса окна недопустима: игра живёт в iframe (Telegram, просмотрщик),
## и blur приходит, даже когда игрок смотрит на экран. Глушим только по document.hidden
## (свернули Telegram, ушли на другую вкладку). Колбэк через get_interface — без eval,
## который строгий CSP хостинга может запрещать.
func _watch_visibility() -> void:
	if not OS.has_feature("web"):
		return
	var document := JavaScriptBridge.get_interface("document")
	if document == null:
		return
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility_changed)
	document.addEventListener("visibilitychange", _visibility_callback)


func _on_visibility_changed(_args: Array) -> void:
	_page_hidden = bool(JavaScriptBridge.get_interface("document").hidden)
	apply_enabled()


func _notification(what: int) -> void:
	if OS.has_feature("web"):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_page_hidden = true
		apply_enabled()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_page_hidden = false
		apply_enabled()


func _pick_player() -> int:
	var oldest := 0
	for i in _players.size():
		if not _players[i].playing:
			return i
		if _started_ms[i] < _started_ms[oldest]:
			oldest = i
	return oldest


func _fade_music_to(target_db: float, stop_after: bool = false) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target_db, MUSIC_FADE)
	if stop_after:
		_music_tween.tween_callback(_music.stop)


func _music_key(id: StringName) -> StringName:
	return StringName("music_" + String(id))


## Шины SFX/Music объявлены в res://default_bus_layout.tres. Создавать их в рантайме нельзя:
## в веб-режиме Sample (по умолчанию в Godot 4.3+) такие шины не подключаются к Master
## на стороне Web Audio, и игра молчит. Здесь — только страховка для десктопа.
func _ensure_buses() -> void:
	for bus_name in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")


func _preload_streams() -> void:
	for id in SFX:
		var stream := _load_stream(SFX_DIR + String(id) + ".ogg")
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = LOOPED_SFX.has(id)
		_streams[id] = stream
	for id in MUSIC:
		var stream := _load_stream(MUSIC_DIR + String(id) + ".ogg")
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_streams[_music_key(id)] = stream


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("SoundManager: нет файла %s" % path)
		return null
	return load(path) as AudioStream


func _create_players() -> void:
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	_started_ms.resize(SFX_POOL_SIZE)
	for i in LOOP_CHANNELS:
		var loop_player := AudioStreamPlayer.new()
		loop_player.bus = SFX_BUS
		add_child(loop_player)
		_loops.append(loop_player)
	for i in AMBIENT_LOOPS.size():
		var ambient := AudioStreamPlayer.new()
		ambient.bus = SFX_BUS
		add_child(ambient)
		_ambient.append(ambient)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
