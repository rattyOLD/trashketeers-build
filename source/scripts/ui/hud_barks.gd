class_name HudBarks
extends Control
## Панелька реплик персонажей во время боя. Только читать, ответить нельзя.
## Фразы лежат в data/chatter.json и к сюжету не относятся: просто болтовня Рико и Нэлл.

const PATH := "res://data/chatter.json"
const SHOW_TIME := 7.0
const MAX_LINES := 3
const COOLDOWN := 9.0
const IDLE_MIN := 26.0
const IDLE_MAX := 42.0

var _list: VBoxContainer
var _panel: PanelContainer
var _speakers: Dictionary = {}
var _events: Dictionary = {}
var _lines: Array = []
var _cool := 3.0
var _idle := 12.0
var _hide_in := 0.0
var _last: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.03, 0.1, 0.72), Color(UiStyle.NEON, 0.6), 3, 14))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_list)
	_load()
	set_process(true)


func _load() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_speakers = (parsed as Dictionary).get("speakers", {})
		_events = (parsed as Dictionary).get("events", {})


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	_idle -= delta
	if _idle <= 0.0:
		_idle = _rng.randf_range(IDLE_MIN, IDLE_MAX)
		say("idle")
	if _hide_in > 0.0:
		_hide_in -= delta
		if _hide_in <= 0.0:
			_lines.clear()
			_refresh()


## Сказать фразу под событие. Если рано (кулдаун), молча пропускаем.
func say(event: String, force: bool = false) -> void:
	if not force and _cool > 0.0:
		return
	var pool: Array = _events.get(event, [])
	if pool.is_empty():
		return
	var pick := _rng.randi() % pool.size()
	if pool.size() > 1 and int(_last.get(event, -1)) == pick:
		pick = (pick + 1) % pool.size()
	_last[event] = pick
	var line: Array = pool[pick]
	_push(str(line[0]), str(line[1]))
	_cool = COOLDOWN
	_idle = _rng.randf_range(IDLE_MIN, IDLE_MAX)


## Показать готовую реплику (для превью и тестов).
func push_line(who: String, text: String) -> void:
	_push(who, text)


func _push(who: String, text: String) -> void:
	_lines.append([who, text])
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_hide_in = SHOW_TIME
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_panel.visible = not _lines.is_empty()
	for entry: Array in _lines:
		var info: Dictionary = _speakers.get(entry[0], {})
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.fit_content = true
		row.scroll_active = false
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_size_override("normal_font_size", 20)
		row.add_theme_font_size_override("bold_font_size", 20)
		row.text = "[b][color=%s]%s:[/color][/b] %s" % [str(info.get("color", "#ffffff")), str(info.get("name", "")), entry[1]]
		_list.add_child(row)
