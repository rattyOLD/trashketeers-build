class_name StoryBar
extends HBoxContainer
## Строка состояния сюжета под здоровьем: очки, жизни, зона. Каждая плашка кликабельна (подсказка).

signal chip_tapped(chip: Control, text: String)

var _score: Label
var _lives: Label
var _zone: Label
var _score_chip: PanelContainer
var _lives_chip: PanelContainer
var _zone_chip: PanelContainer
var _foes_chip: PanelContainer
var _foes: Label
var _zone_number := 1
var _zone_name := ""
var _last_lives := -1


func _init() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_chip = _chip("ОЧКИ", Color("#ffd257"))
	_score = _score_chip.get_meta("value")
	_lives_chip = _chip("ЖИЗНИ", Color("#ff5a7a"))
	_lives = _lives_chip.get_meta("value")
	_zone_chip = _chip("ЗОНА", Color("#ffac56"))
	_zone = _zone_chip.get_meta("value")
	_foes_chip = _chip("ВРАГОВ", Color("#ff8a3d"))
	_foes = _foes_chip.get_meta("value")
	_foes_chip.visible = false
	_score_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_chip.size_flags_stretch_ratio = 1.5


func chips() -> Array[Control]:
	return [_score_chip, _lives_chip, _zone_chip]


func update(score: int, lives: int, zone_number: int, zone_count: int, zone_name: String, enemies_left: int = -1) -> void:
	_foes_chip.visible = enemies_left >= 0
	_foes.text = str(maxi(enemies_left, 0))
	_score.text = "%06d" % score
	_lives.text = "×%d" % lives
	_zone.text = "%d/%d" % [zone_number, zone_count]
	_zone_number = zone_number
	_zone_name = zone_name
	if _last_lives >= 0 and lives < _last_lives:
		UiStyle.keep_pivot_centered(_lives_chip)
		var tween := _lives_chip.create_tween()
		_lives_chip.modulate = Color(1.0, 0.4, 0.4)
		tween.tween_property(_lives_chip, "modulate", Color.WHITE, 0.6)
	_last_lives = lives


func hint_for(chip: Control) -> String:
	if chip == _score_chip:
		return "Очки: за врагов, боссов, пленников и зоны без урона. От них зависит ранг S / A / B / C."
	if chip == _lives_chip:
		return "Жизни. Когда кончатся, миссия провалена. После смерти вернёшься на последний чекпоинт."
	if chip == _foes_chip:
		return "Сколько врагов осталось в засаде. Убей всех, и ворота откроются."
	return "Зона %d: «%s». На входе в новую зону лечение и чекпоинт." % [_zone_number, _zone_name]


func _chip(caption: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := UiStyle.box(Color(0.147, 0.141, 0.132, 0.8), Color(color, 0.85), 3, 16)
	style.set_content_margin_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var icon := UiStyle.label(caption, 17, color, 5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var value := UiStyle.label("", 24, UiStyle.TEXT, 6)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)
	chip.set_meta("value", value)
	chip.gui_input.connect(func(event: InputEvent) -> void:
		var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if pressed:
			chip_tapped.emit(chip, hint_for(chip)))
	add_child(chip)
	return chip
