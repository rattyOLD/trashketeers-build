class_name SurvivalRadio
extends Node
## Радио выживания: короткие фоновые сценки персонажей на волнах, у боссов и после мини-боссов.
## Не ставит игру на паузу; реплики берутся из data/story.json (секция radio) без повторов.

const DATA_PATH := "res://data/story.json"
const WAVE_CHANCE := 0.55
const MIN_GAP_MS := 25000

var _line: AmbientLine
var _radio: Dictionary = {}
var _used: Dictionary = {}
var _last_ms := -MIN_GAP_MS
var _run_waves := 0


func setup(owner_game: Node) -> void:
	var root := ConfigLoader.load_json(DATA_PATH)
	_radio = root.get("radio", {})
	if _radio.is_empty():
		return
	_line = AmbientLine.new()
	owner_game.add_child(_line)
	_line.setup(root.get("speakers", {}))


func on_wave(is_boss: bool) -> void:
	if _line == null:
		return
	_run_waves += 1
	if _run_waves == 1:
		_play("first", true)
	elif is_boss:
		_play("boss", true)
	elif randf() < WAVE_CHANCE:
		_play("waves", false)


func on_mini_boss() -> void:
	_play("mini", true)


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
