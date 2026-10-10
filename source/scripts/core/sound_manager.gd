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
const LOOP_CHANNELS := 3
## Сколько запусков должно оставаться в бюджете, чтобы сыграл шаг.
const STEP_BUDGET_RESERVE := 3.0
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
	&"hitmarker": [-12.0, 0.045],
	&"kill_confirm": [-8.0, 0.05],
	&"burp": [-2.0, 0.6],
	&"step_asphalt_0": [-17.0, 0.05],
	&"step_asphalt_1": [-17.0, 0.05],
	&"step_asphalt_2": [-17.0, 0.05],
	&"step_grass_0": [-19.0, 0.05],
	&"step_grass_1": [-19.0, 0.05],
	&"step_grass_2": [-19.0, 0.05],
	&"step_stone_0": [-17.0, 0.05],
	&"step_stone_1": [-17.0, 0.05],
	&"step_stone_2": [-17.0, 0.05],
	&"step_metal_0": [-17.0, 0.05],
	&"step_metal_1": [-17.0, 0.05],
	&"step_metal_2": [-17.0, 0.05],
	&"step_wood_0": [-14.0, 0.05],
	&"step_wood_1": [-14.0, 0.05],
	&"step_wood_2": [-14.0, 0.05],
	&"step_water_0": [-13.0, 0.05],
	&"step_water_1": [-13.0, 0.05],
	&"step_water_2": [-13.0, 0.05],
	&"step_acid_0": [-13.0, 0.05],
	&"step_acid_1": [-13.0, 0.05],
	&"step_acid_2": [-13.0, 0.05],
	&"enter_water": [-6.0, 0.6],
	&"step_ice_0": [-17.0, 0.05],
	&"step_ice_1": [-17.0, 0.05],
	&"step_ice_2": [-17.0, 0.05],
	&"amb_birds": [-16.0, 2.0],
	&"amb_park": [-20.0, 0.5],
	&"enter_acid": [-5.0, 0.6],
	&"amb_acid": [-14.0, 0.5],
	&"amb_water": [-16.0, 0.5],
	&"amb_music": [-8.0, 0.5],
	&"boss_roar": [-3.0, 1.0],
	&"wave_horn": [-8.0, 0.8],
	&"enemy_death_1": [-14.0, 0.06],
	&"enemy_death_2": [-12.0, 0.06],
	&"enemy_death_3": [-13.0, 0.06],
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
const LOOPED_SFX: Array[StringName] = [&"beam_loop", &"amb_hum", &"amb_wind", &"amb_acid", &"amb_water", &"amb_park", &"amb_music"]
## Фон Свалки: два бесконечных слоя + редкие одиночные события со случайной паузой.
const AMBIENT_LOOPS: Array[StringName] = [&"amb_hum", &"amb_wind"]
const AMBIENT_EVENTS := {&"amb_siren": Vector2(22.0, 45.0), &"amb_neon": Vector2(6.0, 14.0)}
const BANK_AMBIENT_LOOPS: Array[StringName] = [&"amb_park"]
const BANK_AMBIENT_EVENTS := {&"amb_birds": Vector2(4.0, 11.0)}
var _ambient_events: Dictionary = AMBIENT_EVENTS

const MUSIC := {
	&"menu": -12.0,
	&"battle": -13.0,
	&"raid": -11.0,
	&"knife": -12.0,
	&"win": -11.0,
	&"boss": -12.0,
}
const LITE_MUSIC: Array[StringName] = [&"battle", &"raid"]

var unlocked := false

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _started_ms: PackedInt64Array = PackedInt64Array()
var _last_played_ms: Dictionary = {}
var _step_variants: Dictionary = {}
var _last_warning_ms := -100000
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_preload_streams()
	_create_players()
	apply_enabled()


func play(id: StringName, volume_offset_db: float = 0.0, randomize_pitch: bool = true) -> void:
	_play(id, volume_offset_db, randf_range(PITCH_MIN, PITCH_MAX) if randomize_pitch else 1.0)


## Звук с заданным питчем: серия подборов гаек «поднимается» по нотам.
## Смерть врага: один из четырёх звуков (писк, хлопок, хруст), чтобы толпа не «пилила» одним сэмплом.
func play_enemy_death() -> void:
	var pick := randi() % 4
	play(&"enemy_death" if pick == 0 else StringName("enemy_death_%d" % pick))


func play_pitched(id: StringName, pitch: float, volume_offset_db: float = 0.0) -> void:
	_play(id, volume_offset_db, pitch)


## Один канал существующего пула сохраняет сигнал опасности под непрерывным огнём.
func play_warning(id: StringName, volume_offset_db: float = 0.0) -> void:
	_play(id, volume_offset_db, 1.0, true)


func _play(id: StringName, volume_offset_db: float, pitch: float, warning: bool = false) -> void:
	if not unlocked or not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	var cfg: Array = SFX[id]
	if warning and now - _last_warning_ms < 500:
		return
	if not warning and now - int(_last_played_ms.get(id, -100000)) < int(cfg[1] * 1000.0):
		return
	_budget = minf(_budget + float(now - _budget_ms) * 0.001 * SFX_BUDGET_PER_SEC, SFX_BUDGET_BURST)
	_budget_ms = now
	if not warning and not PRIORITY_SFX.has(id):
		if _budget < 1.0:
			return
		_budget -= 1.0
	if warning:
		_last_warning_ms = now
	else:
		_last_played_ms[id] = now

	var index := SFX_POOL_SIZE - 1 if warning else _pick_player()
	var player := _players[index]
	player.stream = _streams[id]
	player.volume_db = cfg[0] + volume_offset_db
	player.pitch_scale = pitch
	player.play()
	_started_ms[index] = now


## Шаг по поверхности (surface: asphalt, grass, stone, metal, wood, water, acid): один из трёх вариантов.
## Шаги — фон: играют, только пока в бюджете запусков есть запас, чтобы не отнимать его у выстрелов
## (в вебе каждый запуск — новые аудио-узлы, на iOS их лишние сотни роняли вкладку).
func play_step(surface: StringName, volume_offset_db: float = 0.0) -> void:
	_budget = minf(_budget + float(Time.get_ticks_msec() - _budget_ms) * 0.001 * SFX_BUDGET_PER_SEC, SFX_BUDGET_BURST)
	_budget_ms = Time.get_ticks_msec()
	if _budget < STEP_BUDGET_RESERVE:
		return
	var previous := int(_step_variants.get(surface, -1))
	var variant := (previous + 1 + randi() % 2) % 3 if previous >= 0 else randi() % 3
	_step_variants[surface] = variant
	_play(StringName("step_%s_%d" % [surface, variant]), volume_offset_db, randf_range(0.92, 1.08))


## Громкость петли (фон протоки зависит от расстояния до неё).
func set_loop_volume(channel: int, volume_db: float) -> void:
	if channel >= 0 and channel < _loops.size():
		_loops[channel].volume_db = volume_db


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


## Итог боя: победа — бодрые фанфары, затем весёлая петля на экране итогов; поражение — короткий грустный звук.
func play_result(victory: bool) -> void:
	play(&"victory" if victory else &"defeat", 0.0, false)
	if victory:
		get_tree().create_timer(1.9, true, false, true).timeout.connect(func() -> void:
			if _music_id == &"" or not _music.playing:
				play_music(&"win"))


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


## Фон по стилю локации: Свалка — гул и ветер, сирена и треск неона; Банк — ветер в листве и птицы.
func start_ambient(style: String = "junkyard") -> void:
	_ambient_on = true
	var loops: Array = AMBIENT_LOOPS if style != "bank" else BANK_AMBIENT_LOOPS
	_ambient_events = AMBIENT_EVENTS if style != "bank" else BANK_AMBIENT_EVENTS
	_ambient_timers.clear()
	for i in _ambient.size():
		if i >= loops.size():
			_ambient[i].stop()
			_ambient[i].stream = null
			continue
		var id: StringName = loops[i]
		if not _streams.has(id) or (_ambient[i].playing and _ambient[i].stream == _streams[id]):
			continue
		_ambient[i].stream = _streams[id]
		_ambient[i].volume_db = SFX[id][0]
		if unlocked:
			_ambient[i].play()
	for id in _ambient_events:
		_ambient_timers[id] = randf_range(_ambient_events[id].x * 0.3, _ambient_events[id].y * 0.5)


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
			var range_s: Vector2 = _ambient_events[id]
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


func set_backgrounded(value: bool) -> void:
	_page_hidden = value
	apply_enabled()


func _pick_player() -> int:
	var oldest := 0
	for i in _players.size() - 1:
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
	# Веб на телефоне держит каждый сыгранный трек целиком в памяти (несжатым): длинные петли боя и рейда
	# там заменены укороченными версиями (−30 МБ на iPhone). APK и ПК играют полные треки потоком.
	var lite := Platform.is_web and Platform.is_touch()
	for id in MUSIC:
		var path := MUSIC_DIR + String(id) + ".ogg"
		if lite and LITE_MUSIC.has(id):
			path = MUSIC_DIR + String(id) + "_lite.ogg"
		var stream := _load_stream(path)
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
