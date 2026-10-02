class_name CoopInviteCard
extends Control
## Большая карточка «тебя зовут в кооп» по центру экрана: имя друга, таймер до исчезновения, крупные ПРИНЯТЬ и ОТКАЗАТЬ.

signal accepted
signal declined
signal muted(kind: String)   # "hour" | "day" | "friend" | "all"

const LIFETIME := 30.0

var _name := "Друг"
var _character := ""
var _skin := "classic"
var _level := 1
var _bar: ColorRect
var _bar_back: Control
var _left := LIFETIME
var _done := false

const LINES: Array[String] = [
	"зовёт тебя вонять вдвоём",
	"нашёл свалку и хочет делить её с тобой",
	"говорит, что один он не вывозит. Врёт, но зайди",
	"ждёт тебя в комнате. Пиво уже налито",
]


func _init(invite: Dictionary = {}) -> void:
	_name = str(invite.get("from_name", "Друг"))
	_character = str(invite.get("from_c", ""))
	_skin = str(invite.get("from_s", "classic"))
	_level = int(invite.get("from_lv", 1))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 95


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.08, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var width := minf(GlassPopup.panel_width(), 520.0) - 60.0
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	card.add_theme_stylebox_override("panel", UiStyle.box(Color("#162c36"), UiStyle.NEON, 6, 30))
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(UiStyle.label("ПРИГЛАШЕНИЕ В КООП", 26, UiStyle.GOLD, 6))
	var avatar := FriendsPopup.AvatarView.new()
	avatar.character_id = _character
	avatar.skin_id = _skin
	avatar.custom_minimum_size = Vector2(130, 130)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(avatar)
	var who := UiStyle.label(_name, 32, UiStyle.NEON, 7)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.custom_minimum_size = Vector2(width - 60.0, 0)
	column.add_child(who)
	var line := UiStyle.label(LINES[randi() % LINES.size()], 22, UiStyle.TEXT, 4)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(width - 60.0, 0)
	column.add_child(line)
	column.add_child(UiStyle.label("УР. %d  ·  «Выживание» на двоих" % _level, 18, UiStyle.TEXT_DIM, 4))
	_bar_back = Control.new()
	_bar_back.custom_minimum_size = Vector2(0, 10)
	var back := ColorRect.new()
	back.color = Color("#1b3d50")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_back.add_child(back)
	_bar = ColorRect.new()
	_bar.color = UiStyle.NEON
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_back.add_child(_bar)
	column.add_child(_bar_back)
	var accept := UiStyle.button("ПРИНЯТЬ", Color("#7ed321"), 30, Vector2(0, 76))
	accept.name = "AcceptInvite"
	accept.pressed.connect(func() -> void:
		if _done:
			return
		_done = true
		accepted.emit())
	column.add_child(accept)
	var decline := UiStyle.button("НЕ СЕЙЧАС", UiStyle.PANEL_LIGHT, 20, Vector2(0, 50))
	decline.name = "DeclineInvite"
	decline.pressed.connect(func() -> void:
		if _done:
			return
		_done = true
		declined.emit()
		queue_free())
	column.add_child(decline)
	var mute := UiStyle.button("ЗАГЛУШИТЬ ПРИГЛАШЕНИЯ", Color("#2b4f5e"), 16, Vector2(0, 42))
	mute.name = "MuteInvite"
	column.add_child(mute)
	var options := VBoxContainer.new()
	options.visible = false
	options.add_theme_constant_override("separation", 8)
	column.add_child(options)
	var choices := [["НА 1 ЧАС", "hour"], ["НА СУТКИ", "day"], ["ТОЛЬКО ОТ ЭТОГО ДРУГА", "friend"], ["ВСЕ ПРИГЛАШЕНИЯ, ПОКА НЕ ВКЛЮЧУ", "all"]]
	for choice: Array in choices:
		var option := UiStyle.button(str(choice[0]), UiStyle.PANEL_LIGHT, 18, Vector2(0, 50))
		option.name = "Mute_" + str(choice[1])
		option.pressed.connect(func() -> void:
			if _done:
				return
			_done = true
			muted.emit(str(choice[1]))
			queue_free())
		options.add_child(option)
	mute.pressed.connect(func() -> void:
		options.visible = not options.visible
		_left = maxf(_left, 12.0))
	UiStyle.pop_in(card, 0.45)


func _process(delta: float) -> void:
	if _done or _bar == null:
		return
	_left -= delta
	_bar.anchor_right = clampf(_left / LIFETIME, 0.0, 1.0)
	if _left <= 0.0:
		_done = true
		queue_free()
