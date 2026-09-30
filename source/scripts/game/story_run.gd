class_name StoryRun
extends Node
## Сюжетная миссия поверх главы боя: диалоги по ходу волн, ключ от мини-босса, оружие из ящика,
## осколок от босса и завершение миссии. Данные и тексты — data/story.json.
## Зоны миссии = отрезки волн главы; диалоги показываются по очереди и не перекрывают друг друга.

const DATA_PATH := "res://data/story.json"
const OPEN_DELAY := 0.9

var game: Game
var mission: Dictionary = {}
var speakers: Dictionary = {}
var has_key := false
var finished_mission := false
var _queue: Array = []
var _box: DialogBox
var _seen := {}
var _after_queue: Callable = Callable()


func setup(owner_game: Game, mission_id: String) -> bool:
	game = owner_game
	var root := ConfigLoader.load_json(DATA_PATH)
	speakers = root.get("speakers", {})
	for entry in root.get("missions", []):
		if str(entry.get("id", "")) == mission_id:
			mission = entry
	return not mission.is_empty()


func title() -> String:
	return "%s · %s" % [mission.get("title", ""), mission.get("subtitle", "")]


func on_start() -> void:
	game.hud.show_banner(title(), UiStyle.GOLD, 2.2)
	_say("intro", OPEN_DELAY + 0.8)


func on_wave_started(chapter_wave: int, is_boss: bool) -> void:
	var zones: Dictionary = mission.get("zones", {})
	var zone_text := str(zones.get(str(chapter_wave), ""))
	if not zone_text.is_empty():
		game.hud.show_banner(zone_text, Color("#5ff2ff"), 2.4)
	match chapter_wave:
		3:
			_say("gate", OPEN_DELAY)
		4:
			_say("toxic", OPEN_DELAY)
		6:
			_open_crate()
	if is_boss and chapter_wave >= 10:
		pass


func on_boss_spawned(is_mini: bool) -> void:
	_say("baron_pre" if is_mini else "king_pre", OPEN_DELAY)


func on_miniboss_killed() -> void:
	has_key = true
	game.hud.toast("ПОЛУЧЕНО: ПИВНАЯ ПРОБКА-КЛЮЧ", "Она открывает Ящик на следующем участке", Color("#ffb020"))
	_say("baron_post", 1.0)


func on_boss_phase(phase: int) -> void:
	var lines: Array = (mission.get("phase_lines", {}) as Dictionary).get("king", [])
	if phase >= 2 and lines.size() > 1:
		game.hud.toast("КОРОЛЬ ХЛАМА", str(lines[1]), Color("#ff5a5a"))


func on_boss_break() -> void:
	var lines: Array = (mission.get("phase_lines", {}) as Dictionary).get("king", [])
	if not lines.is_empty():
		game.hud.toast("КОРОЛЬ ХЛАМА", str(lines[0]), Color("#ff5a5a"))


## Босс главы повержен, арена пуста: финальная сцена, затем итог миссии.
func finish() -> void:
	if finished_mission:
		return
	finished_mission = true
	var shards := int(mission.get("shards", 1))
	SaveService.story_complete(str(mission.get("id", "")), shards)
	game.hud.show_banner("ОСКОЛОК %d/6 ПОЛУЧЕН!" % shards, UiStyle.GOLD, 2.8)
	_after_queue = game.story_finished
	_say("king_dead", 1.6)


func _open_crate() -> void:
	if not has_key:
		return
	game.open_story_crate()
	_say("crate", OPEN_DELAY + 0.6)


func _say(key: String, delay: float) -> void:
	if _seen.has(key):
		return
	var dialogs: Dictionary = mission.get("dialogs", {})
	if not dialogs.has(key):
		return
	_seen[key] = true
	_queue.append(dialogs[key])
	get_tree().create_timer(delay, true, false, true).timeout.connect(_pump)


func _pump() -> void:
	if _box != null or _queue.is_empty():
		if _box == null and _queue.is_empty() and _after_queue.is_valid():
			var cb := _after_queue
			_after_queue = Callable()
			cb.call()
		return
	if game.finished or game.player == null or game.player.is_dead:
		_queue.clear()
		return
	var lines: Array = _queue.pop_front()
	_box = DialogBox.new()
	game.add_child(_box)
	_box.finished.connect(_on_box_finished)
	_box.open(lines, speakers)


func _on_box_finished() -> void:
	_box = null
	get_tree().create_timer(0.15, true, false, true).timeout.connect(_pump)
