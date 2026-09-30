class_name MapEvents
extends Node
## Случайные события арены и «погода» волны. В каждой обычной волне с шансом (растёт, если события
## долго не было) выпадает одно событие с весом по таблице: частые (монетный дождь, утечка), редкие
## (сброс припасов) и очень редкие (джекпот с эпик/легенд-ящиком). Погода — подмена настроения волны
## (гроза, смог, золотой час, розовая дымка) с небольшим игровым бонусом; визуал уже даёт AtmosphereFX.
## Цепные реакции: горящий враг у взрывной бочки и отравленный у токсичной поджигают их сами.
## Всё переиспользует пулы: лужи создаются заранее, монеты идут через PickupManager, ящики — через airdrop.

signal announced(title: String, text: String, color: Color)
signal event_started(kind: int)
signal loot_count(count: int)

enum Kind { COIN_RAIN, LEAK, SUPPLY, JACKPOT, MARAUDER }

## [вид, вес, минимальная волна главы]
const TABLE := [
	[Kind.COIN_RAIN, 30.0, 1],
	[Kind.LEAK, 26.0, 2],
	[Kind.SUPPLY, 14.0, 2],
	[Kind.JACKPOT, 3.5, 3],
	[Kind.MARAUDER, 10.0, 2],
]
const EVENT_CHANCE := 0.5
const DRY_BONUS := 0.18
const DELAY_MIN := 5.0
const DELAY_MAX := 20.0
const WEATHER_CHANCE := 0.3
const LEAK_POOLS := 2
const LEAK_SIZE := 2.0
const LEAK_LIFE := 16.0
const RAIN_TIME := 9.0
const RAIN_STEP := 0.55
const MARAUDER_TIME := 16.0
const CHAIN_INTERVAL := 0.25
const CHAIN_RANGE := 88.0
const CHAIN_COOLDOWN := 0.4
## Настроение → [заголовок, описание, бонус]. bonus: shock / poison / regen / coins
const WEATHER := {
	"storm": ["ГРОЗА", "Молнии цепляют врагов чаще", "shock", 0.12],
	"toxic": ["ЯДОВИТЫЙ СМОГ", "Яд налипает чаще", "poison", 0.1],
	"golden": ["ЗОЛОТОЙ ЧАС", "Монеты ×1.3", "coins", 1.3],
	"night": ["НОЧНАЯ СМЕНА", "Темно, зато монеты ×1.35", "coins", 1.35],
	"pink_haze": ["РОЗОВАЯ ДЫМКА", "Регенерация +1 HP/с", "regen", 1.0],
}
const WEATHER_WEIGHTS := {"storm": 3.0, "toxic": 3.0, "golden": 2.0, "pink_haze": 2.5, "night": 1.5}

var player: Player
var director: WaveDirector
var enemies: EnemyManager
var map: LevelSpawner
var pickups: PickupManager
var fx: FxManager
var status: StatusSystem
var atmosphere: AtmosphereFX
var pools: Array[AcidPool] = []
var coin_mult := 1.0
var weather_name := ""
var marauder: Enemy

var _pending := -1
var _delay := 0.0
var _dry_waves := 0
var _last_kind := -1
var _rain_left := 0.0
var _rain_step := 0.0
var _chain_timer := 0.0
var _chain_cd := 0.0
var _chain_told := false
var _marauder_left := 0.0
var _marauder_ping := 0.0
var _rain_drops := 0
var _loot_timer := 0.0


func setup(target: Player, wave_director: WaveDirector, enemy_manager: EnemyManager, level: LevelSpawner, pickup_manager: PickupManager, effects: FxManager, status_system: StatusSystem, atmo: AtmosphereFX, decals: Node2D) -> void:
	player = target
	director = wave_director
	enemies = enemy_manager
	map = level
	pickups = pickup_manager
	fx = effects
	status = status_system
	atmosphere = atmo
	for i in LEAK_POOLS:
		var pool := AcidPool.new()
		decals.add_child(pool)
		pools.append(pool)


func reset() -> void:
	_pending = -1
	_rain_left = 0.0
	marauder = null
	for pool in pools:
		pool.visible = false
		pool.set_process(false)
		pool.collision_mask = 0
		pool.set_deferred("monitoring", false)
	_apply_weather("")


func on_wave_started(is_boss: bool) -> void:
	_rain_left = 0.0
	_pending = -1
	if is_boss:
		_apply_weather("")
		return
	if randf() < WEATHER_CHANCE:
		_apply_weather(_roll_weather())
	else:
		_apply_weather("")
	var chance := EVENT_CHANCE + DRY_BONUS * _dry_waves
	if randf() < chance:
		var picked := _roll_event()
		if picked >= 0:
			_pending = picked
			_delay = randf_range(DELAY_MIN, DELAY_MAX)
			return
	_dry_waves += 1


func on_wave_cleared() -> void:
	_pending = -1


func _roll_weather() -> String:
	var total := 0.0
	for key in WEATHER_WEIGHTS:
		total += float(WEATHER_WEIGHTS[key])
	var roll := randf() * total
	for key in WEATHER_WEIGHTS:
		roll -= float(WEATHER_WEIGHTS[key])
		if roll <= 0.0:
			return str(key)
	return "storm"


func _apply_weather(mood_name: String) -> void:
	weather_name = mood_name
	coin_mult = 1.0
	status.extra_shock = 0.0
	status.extra_poison = 0.0
	status.extra_regen = 0.0
	if mood_name.is_empty():
		return
	atmosphere.set_mood(mood_name)
	var cfg: Array = WEATHER[mood_name]
	match str(cfg[2]):
		"shock":
			status.extra_shock = float(cfg[3])
		"poison":
			status.extra_poison = float(cfg[3])
		"regen":
			status.extra_regen = float(cfg[3])
		"coins":
			coin_mult = float(cfg[3])
	announced.emit(str(cfg[0]), str(cfg[1]), Color("#7fd6ff"))


func _roll_event() -> int:
	var wave := director.chapter_wave()
	var total := 0.0
	for row in TABLE:
		if wave >= int(row[2]) and int(row[0]) != _last_kind:
			total += float(row[1])
	if total <= 0.0:
		return -1
	var roll := randf() * total
	for row in TABLE:
		if wave < int(row[2]) or int(row[0]) == _last_kind:
			continue
		roll -= float(row[1])
		if roll <= 0.0:
			return int(row[0])
	return -1


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead:
		return
	if _pending >= 0:
		_delay -= delta
		if _delay <= 0.0:
			var kind := _pending
			_pending = -1
			_start(kind)
	if _rain_left > 0.0:
		_rain_left -= delta
		_rain_step -= delta
		if _rain_step <= 0.0:
			_rain_step = RAIN_STEP
			_drop_coins()
	if marauder != null:
		_tick_marauder(delta)
	_loot_timer -= delta
	if _loot_timer <= 0.0:
		_loot_timer = 0.4
		var idle := director.get_enemies_left() <= 0 and director.remaining_to_spawn <= 0
		loot_count.emit(pickups.get_count() if idle else 0)
	_chain_cd -= delta
	_chain_timer -= delta
	if _chain_timer <= 0.0:
		_chain_timer = CHAIN_INTERVAL
		_check_chain()


func _start(kind: int) -> void:
	_last_kind = kind
	_dry_waves = 0
	event_started.emit(kind)
	match kind:
		Kind.COIN_RAIN:
			_rain_left = RAIN_TIME
			_rain_step = 0.0
			_rain_drops = 0
			announced.emit("МОНЕТНЫЙ ДОЖДЬ", "Хватай, пока не разбежались!", Color("#ffd23f"))
		Kind.LEAK:
			_leak()
		Kind.SUPPLY:
			_supply(false)
		Kind.JACKPOT:
			_supply(true)
		Kind.MARAUDER:
			_spawn_marauder()


func _drop_coins() -> void:
	var at := map.find_spawn_point(player.global_position, 90.0, 360.0, 24.0)
	if at == Vector2.INF:
		return
	var amount := 2 + director.chapter_wave() / 4
	_rain_drops += 1
	if _rain_drops % 4 == 0:
		pickups.spawn_xp_gold(at, 3 + director.chapter_wave() / 2)
	else:
		pickups.spawn(at, amount)
	fx.ring(at, Color("#ffd23f"), 34.0)
	fx.burst(at, Color("#ffe27a"), 6, 140.0, 3.0)


func _leak() -> void:
	var placed := 0
	for i in pools.size():
		var at := map.find_spawn_point(player.global_position, 200.0 + 60.0 * i, 460.0, 60.0)
		if at == Vector2.INF:
			continue
		pools[i].activate(at, LEAK_SIZE, LEAK_LIFE)
		fx.ring(at, Color("#7cff3d"), 90.0)
		placed += 1
	if placed > 0:
		SoundManager.play(&"acid_splash", -2.0)
		announced.emit("УТЕЧКА", "Слизь замедляет крыс — заманивай их!", Color("#7cff3d"))
	else:
		_rain_left = RAIN_TIME
		announced.emit("МОНЕТНЫЙ ДОЖДЬ", "Хватай, пока не разбежались!", Color("#ffd23f"))


func _supply(jackpot: bool) -> void:
	var crate := map.airdrop(player.global_position)
	if crate == null:
		_rain_left = RAIN_TIME
		announced.emit("МОНЕТНЫЙ ДОЖДЬ", "Хватай, пока не разбежались!", Color("#ffd23f"))
		return
	if jackpot:
		crate.loot_rarity = "legendary" if randf() < 0.3 else "epic"
		announced.emit("ДЖЕКПОТ!", "Сброс редкого ящика с оружием", Color("#ff7ae0"))
	else:
		announced.emit("ПРИПАСЫ", "Сброс ящика с оружием", Color("#5cf3ff"))


func _check_chain() -> void:
	if _chain_cd > 0.0:
		return
	for object in map.destructibles:
		var chain := object.chain_kind()
		if chain.is_empty() or not object.visible:
			continue
		var origin := object.global_position + Vector2(0, -16)
		var r2 := CHAIN_RANGE * CHAIN_RANGE
		for enemy in enemies.get_active():
			if not enemy.is_alive() or enemy.global_position.distance_squared_to(origin) > r2:
				continue
			var lit := enemy.bleed_left > 0.0 if chain == "explode" else enemy.is_poisoned()
			if lit:
				_chain_cd = CHAIN_COOLDOWN
				object.take_damage(99999.0)
				_chain_popup(origin)
				return


func _chain_popup(at: Vector2) -> void:
	fx.popup(at + Vector2(0, -50), "ЦЕПЬ!", Color("#ff9a3d"), 30.0)
	if not _chain_told:
		_chain_told = true
		announced.emit("ЦЕПНАЯ РЕАКЦИЯ", "Горящие и отравленные враги поджигают бочки", Color("#ff9a3d"))


func _spawn_marauder() -> void:
	var wave := director.chapter_wave()
	var at := map.find_spawn_point(player.global_position, 380.0, 620.0, 40.0)
	var rat: Enemy = null
	if at != Vector2.INF:
		rat = enemies.spawn(ContentDB.get_enemy(&"dash_rat"), at, 3.0 + 0.25 * wave)
	if rat == null:
		_rain_left = RAIN_TIME
		announced.emit("МОНЕТНЫЙ ДОЖДЬ", "Хватай, пока не разбежались!", Color("#ffd23f"))
		return
	rat.fleeing = true
	rat.loot = 25 + 6 * wave
	marauder = rat
	_marauder_left = MARAUDER_TIME
	_marauder_ping = 0.0
	announced.emit("МАРОДЁР!", "Крыса с добычей удирает: успей за %d с" % int(MARAUDER_TIME), Color("#ffd23f"))


func _tick_marauder(delta: float) -> void:
	if marauder.pool_index < 0 or marauder.data == null or not marauder.fleeing:
		marauder = null
		return
	_marauder_left -= delta
	_marauder_ping -= delta
	if _marauder_ping <= 0.0:
		_marauder_ping = 0.9
		fx.ring(marauder.global_position, Color("#ffd23f"), 46.0)
	if _marauder_left <= 0.0:
		fx.burst(marauder.get_aim_point(), Color("#ffe27a"), 14, 260.0, 3.5)
		fx.dust(marauder.global_position, 6, 60.0)
		enemies.release(marauder)
		marauder = null
		announced.emit("МАРОДЁР УДРАЛ", "Добыча уплыла", Color("#c9c4dd"))
