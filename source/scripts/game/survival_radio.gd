class_name SurvivalRadio
extends Node
## Радио выживания: короткие фоновые сценки персонажей на волнах, у боссов и после мини-боссов.
## Не ставит игру на паузу; реплики берутся из data/story.json (секция radio) без повторов.

const DATA_PATH := "res://data/story.json"
const WAVE_CHANCE := 0.55
const MIN_GAP_MS := 25000
const STREAK_GOAL := 40
const LOW_HP := 0.25
const LOW_GAP_MS := 45000
const MAX_LOW := 3

var _line: AmbientLine
var _radio: Dictionary = {}
var _used: Dictionary = {}
var _last_ms := -MIN_GAP_MS
var _run_waves := 0
var _player: Player
var _hp_ratio := 1.0
var _low_ms := -60000
var _low_count := 0
var _streak := 0
var _streak_goal := STREAK_GOAL


func setup(owner_game: Node, player: Player) -> void:
	var root := ConfigLoader.load_json(DATA_PATH)
	_radio = root.get("radio", {})
	if _radio.is_empty():
		return
	_line = AmbientLine.new()
	owner_game.add_child(_line)
	_line.setup(root.get("speakers", {}))
	_player = player
	player.health_changed.connect(_on_health)
	player.damaged.connect(func(_amount: float) -> void: _streak = 0)


func on_wave(is_boss: bool) -> void:
	if _line == null:
		return
	_run_waves += 1
	if _run_waves == 1:
		_play("first", true)
		_king_record()
	elif is_boss:
		_play("boss", true)
	elif randf() < WAVE_CHANCE:
		_play("waves", false)


func on_mini_boss(weapon_id: String) -> void:
	var paid: Array = _radio.get("paid_weapons", [])
	_play("mini_paid" if paid.has(weapon_id) else "mini", true)


func _play(key: String, force: bool) -> void:
	if _line == null or _line.is_busy():
		return
	if not force and Time.get_ticks_msec() - _last_ms < MIN_GAP_MS:
		return
	var pool: Array = _radio.get(key, [])
	if pool.is_empty():
		return
	var used: Array = _used.get(key, [])
	if used.size() >= pool.size():
		used.clear()
	var choices: Array = []
	for i in pool.size():
		if not used.has(i):
			choices.append(i)
	var index: int = choices.pick_random()
	used.append(index)
	_used[key] = used
	_last_ms = Time.get_ticks_msec()
	_line.push(pool[index])


func on_kill() -> void:
	_streak += 1
	if _streak >= _streak_goal:
		_streak = 0
		_streak_goal += STREAK_GOAL
		_play("streak", true)


func _on_health(hp: float, max_hp: float) -> void:
	var ratio := hp / maxf(max_hp, 1.0)
	var crossed := ratio < LOW_HP and _hp_ratio >= LOW_HP and hp > 0.0
	_hp_ratio = ratio
	if crossed and _low_count < MAX_LOW and Time.get_ticks_msec() - _low_ms >= LOW_GAP_MS:
		_low_ms = Time.get_ticks_msec()
		_low_count += 1
		_play("low_hp", true)


func _king_record() -> void:
	var best := SaveService.get_stat("best_wave")
	var week := floori(float(SaveService.today()) / 7.0)
	if best < 3 or int(SaveService.data.get("king_radio_week", -1)) == week:
		return
	var pool: Array = _radio.get("king_record", [])
	if pool.is_empty():
		return
	SaveService.set_value("king_radio_week", week)
	var scene: Array = (pool.pick_random() as Array).duplicate(true)
	for line: Dictionary in scene:
		line["text"] = str(line["text"]).replace("{n2}", str(best + 3)).replace("{n}", str(best))
	_line.push(scene)
