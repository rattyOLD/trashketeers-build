class_name AmbientLine
extends Node
## Фоновые реплики сюжета и радио выживания. Своей плашки больше нет: реплики идут в квадрат «Рация»
## в шапке боя (HudBarks), игру на паузу не ставят. Очередь нужна, чтобы реплики не наезжали друг на друга.

const MIN_TIME := 3.0
const MAX_TIME := 8.0
const PER_CHAR := 0.05
const CHUNK := 92  # столько букв помещается в квадрат «Рация» без обрезки

signal drained

var _speakers: Dictionary = {}
var _queue: Array = []
var _left := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func setup(speakers: Dictionary) -> void:
	_speakers = speakers
	set_process(false)


func push(lines: Array) -> void:
	for line in lines:
		if not LineVotes.is_hidden(line):
			_enqueue(line)
	set_process(true)


## Реплика с готовым именем (болтовня Нэлл, Короля и т.п., вне списка говорящих).
func push_named(display_name: String, color_hex: String, text: String) -> void:
	_enqueue({"name": display_name, "color": color_hex, "text": text})
	set_process(true)


## Длинную реплику режем по предложениям на куски, которые целиком помещаются в квадрат.
func _enqueue(line: Dictionary) -> void:
	var text := str(line.get("text", ""))
	if text.length() <= CHUNK:
		_queue.append(line)
		return
	var pieces: Array = []
	var current := ""
	for word in text.split(" ", false):
		var candidate: String = word if current.is_empty() else current + " " + word
		if candidate.length() > CHUNK and not current.is_empty():
			pieces.append(current)
			current = word
		elif current.length() > CHUNK * 0.55 and current.right(1) in [".", "!", "?", "…"]:
			pieces.append(current)
			current = word
		else:
			current = candidate
	if not current.is_empty():
		pieces.append(current)
	for piece in pieces:
		var copy := line.duplicate()
		copy["text"] = piece
		_queue.append(copy)


func is_busy() -> bool:
	return _left > 0.0 or not _queue.is_empty()


func clear() -> void:
	_queue.clear()
	_left = 0.0
	set_process(false)


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		return
	if _queue.is_empty():
		set_process(false)
		drained.emit()
		return
	var radio := _radio()
	if radio == null:
		_queue.clear()
		set_process(false)
		return
	var line: Dictionary = _queue.pop_front()
	var who: Dictionary = _speakers.get(str(line.get("who", "")), {})
	if line.has("name"):
		who = {"name": line["name"], "color": line.get("color", "#ffffff")}
	var text := str(line.get("text", ""))
	var hold := clampf(MIN_TIME + float(text.length()) * PER_CHAR, MIN_TIME, MAX_TIME)
	radio.push_named(str(who.get("name", "")).to_upper(), str(who.get("color", "#ffffff")), text, hold)
	_left = hold


func _radio() -> HudBarks:
	var owner_game := get_parent()
	if owner_game == null:
		return null
	var hud: Variant = owner_game.get("hud")
	if hud == null or not hud.has_method("radio"):
		return null
	return hud.call("radio") as HudBarks
