class_name GiftBox
extends Button
## Подарок внутри вкладок: раз в COOLDOWN секунд даёт монеты или, с плавающим шансом, неонит.

signal claimed

const ICON := "res://assets/ui/hub/gift_box.png"
const COOLDOWN := 3 * 3600
const GEM_CHANCE_MIN := 0.02
const GEM_CHANCE_MAX := 0.16
const GEM_PER_DAY := 2

var _key := ""
var _last := ""
var _title: Label
var _sub: Label
var _icon: TextureRect


func _init(key: String) -> void:
	_key = key
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 112)
	pressed.connect(_on_pressed)
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture = ArenaProp.texture_of(ICON)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(88, 88)
	_icon.pivot_offset = Vector2(44, 44)
	box.add_child(_icon)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(texts)
	_title = UiStyle.label("", 26, UiStyle.GOLD, 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_title)
	_sub = UiStyle.label("", 18, UiStyle.TEXT, 4)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_sub)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(refresh)
	add_child(timer)
	refresh()


func _ready_at() -> int:
	var stamps := SaveService.data["gift_at"] as Dictionary
	return int(stamps.get(_key, 0)) + COOLDOWN - Premium.level() * 1200


func _remaining() -> int:
	return _ready_at() - int(Time.get_unix_time_from_system())


func refresh() -> void:
	var wait := _remaining()
	var ready := wait <= 0
	disabled = not ready
	_icon.modulate = Color.WHITE if ready else Color(0.6, 0.6, 0.66)
	var color := Color("#4a3a12") if ready else UiStyle.PANEL
	add_theme_stylebox_override("normal", UiStyle.box(color, UiStyle.GOLD if ready else UiStyle.OUTLINE, 4, 20))
	add_theme_stylebox_override("hover", UiStyle.box(color.lightened(0.1), UiStyle.GOLD, 4, 20))
	add_theme_stylebox_override("pressed", UiStyle.box(color.darkened(0.15), UiStyle.GOLD, 4, 20))
	add_theme_stylebox_override("disabled", UiStyle.box(color, UiStyle.OUTLINE, 3, 20))
	if ready:
		_title.text = "ПОДАРОК ЖДЁТ"
		_sub.text = _last if not _last.is_empty() else "Тапни: монеты, а с удачей - неонит"
	else:
		_title.text = "СЛЕДУЮЩИЙ ПОДАРОК"
		var left := "До подарка: %d:%02d:%02d" % [wait / 3600, (wait % 3600) / 60, wait % 60]
		_sub.text = (_last + "\n" if not _last.is_empty() else "") + left


func _roll() -> Dictionary:
	var today := SaveService.today()
	if int(SaveService.data["gift_gem_day"]) != today:
		SaveService.data["gift_gem_day"] = today
		SaveService.data["gift_gem_n"] = 0
	var chance := randf_range(GEM_CHANCE_MIN, GEM_CHANCE_MAX) * (1.5 if Premium.level() >= 4 else 1.0)
	if int(SaveService.data["gift_gem_n"]) >= GEM_PER_DAY + (1 if Premium.level() >= 5 else 0):
		chance = 0.0
	if randf() < chance:
		SaveService.data["gift_gem_n"] = int(SaveService.data["gift_gem_n"]) + 1
		return {"coins": 0, "gems": 1 + int(randf() < 0.25) + int(randf() < 0.06)}
	var coins := int(round(randf_range(90.0, 320.0) / 10.0)) * 10
	if randf() < 0.08:
		coins *= 3
	return {"coins": coins, "gems": 0}


func _on_pressed() -> void:
	if _remaining() > 0:
		return
	var prize := _roll()
	SaveService.data["gift_at"][_key] = int(Time.get_unix_time_from_system())
	if int(prize["gems"]) > 0:
		SaveService.add_gems(int(prize["gems"]), false)
	SaveService.add_coins(int(prize["coins"]))
	SoundManager.play(&"star_dust")
	_last = "Выпало: %s" % (("%d неонита!" % int(prize["gems"])) if int(prize["gems"]) > 0 else "%d монет" % int(prize["coins"]))
	var tween := create_tween()
	tween.tween_property(_icon, "scale", Vector2(1.3, 1.3), 0.12)
	tween.tween_property(_icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	refresh()
	claimed.emit()
