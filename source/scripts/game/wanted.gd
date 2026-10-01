class_name Wanted
extends Node
## Розыск выживания: убийства греют уровень от 1 до 5 звёзд, Бюро Расчистки шлёт агентов с наградой за каждого.

const THRESHOLDS: Array[int] = [45, 120, 240, 420, 680]
const ELITE_HP := 120.0
const ELITE_POINTS := 8
const BOSS_POINTS := 25
const SPAWN_RING := 520.0
const MARGIN_CELLS := 4
const BASE_INTERVAL := 32.0
const INTERVAL_STEP := 4.5
const MIN_INTERVAL := 11.0
const HP_PER_WAVE := 0.06
const BOUNTY_PER_STAR := 4
const GROUPS: Array = [
	[&"fed_bagel"],
	[&"fed_bagel", &"fed_bagel"],
	[&"fed_agent", &"fed_bagel"],
	[&"fed_agent", &"fed_agent"],
	[&"fed_chief", &"fed_agent"],
]
const AGENTS: Array[StringName] = [&"fed_bagel", &"fed_agent", &"fed_chief"]

signal level_changed(level: int)
signal chief_arrived

var level := 0
var _points := 0
var _timer := BASE_INTERVAL
var _game: Game
var _chief_seen := false


func setup(game: Game) -> void:
	_game = game


func is_agent(data: EnemyData) -> bool:
	return AGENTS.has(data.id)


func on_kill(data: EnemyData) -> int:
	if is_agent(data):
		return BOUNTY_PER_STAR * maxi(level, 1)
	_points += BOSS_POINTS if data.is_boss() else (ELITE_POINTS if data.max_hp >= ELITE_HP else 1)
	var next := level
	while next < THRESHOLDS.size() and _points >= THRESHOLDS[next]:
		next += 1
	if next > level:
		level = next
		_timer = minf(_timer, 4.0)
		level_changed.emit(level)
	return 0


func _physics_process(delta: float) -> void:
	if level <= 0 or _game == null or _game.player == null or _game.player.is_dead:
		return
	var director := _game.director
	if director.phase != WaveDirector.Phase.FIGHT or director.is_boss_wave():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = maxf(BASE_INTERVAL - INTERVAL_STEP * level, MIN_INTERVAL)
	if _game.enemies.get_active_count() > Game.ENEMY_CAPACITY - 12:
		return
	var hp_mult := 1.0 + HP_PER_WAVE * director.wave_number
	for id: StringName in GROUPS[level - 1]:
		var data := ContentDB.get_enemy(id)
		if data != null and _game.enemies.spawn(data, _spawn_point(), hp_mult, 1.0) != null and id == &"fed_chief" and not _chief_seen:
			_chief_seen = true
			chief_arrived.emit()


func _spawn_point() -> Vector2:
	var bounds := _game.map.bounds.grow(-float(MARGIN_CELLS) * LevelSpawner.CELL)
	var player_at := _game.player.global_position
	for i in 8:
		var at := player_at + Vector2.from_angle(randf() * TAU) * SPAWN_RING
		if bounds.has_point(at):
			return at
	return bounds.get_center()
