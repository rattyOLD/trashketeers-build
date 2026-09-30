class_name LevelUpPanel
extends Control
## Выбор 1 из 3 улучшений. Работает на паузе: HUD имеет PROCESS_MODE_ALWAYS.
## На десктопе карточки выбираются клавишами 1–3.

signal chosen(upgrade: UpgradeData)
signal reroll_requested

var _box: VBoxContainer
var _title: Label
var _cards: VBoxContainer
var _choices: Array[UpgradeData] = []
var _reroll: Button
const ARCHETYPE_NAMES := {&"dps": "БИЛД: УРОН", &"debuff": "БИЛД: ЭФФЕКТЫ", &"mobility": "БИЛД: РЫВОК"}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 18)
	center.add_child(_box)

	_title = UiStyle.label("", 52, UiStyle.GOLD, 12)
	_box.add_child(_title)
	_box.add_child(UiStyle.label("Выбери улучшение", 28, UiStyle.TEXT_DIM, 6))

	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 16)
	_box.add_child(_cards)
	_reroll = UiStyle.button("", Color("#7a3bd1"), 28, Vector2(620, 84))
	_reroll.pressed.connect(func() -> void:
		if visible:
			reroll_requested.emit())
	_box.add_child(_reroll)


func open(choices: Array[UpgradeData], level: int, stats: RunStats, bonus: bool = false, reroll_text: String = "", reroll_ok: bool = false) -> void:
	_choices = choices
	_title.text = "НАГРАДА БОССА!" if bonus else "УРОВЕНЬ %d!" % level
	_title.add_theme_color_override("font_color", Color("#ff7ae0") if bonus else UiStyle.GOLD)
	for child in _cards.get_children():
		child.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i, stats))
	_reroll.visible = not reroll_text.is_empty()
	_reroll.text = reroll_text
	_reroll.modulate = Color.WHITE if reroll_ok else Color(1, 1, 1, 0.5)
	visible = true
	UiStyle.pop_in(_box)


func _make_card(upgrade: UpgradeData, index: int, stats: RunStats) -> Button:
	var accent := upgrade.rarity_color() if upgrade.category != "evolution" else Color("#ff5cf0")
	var card := UiStyle.button("", UiStyle.PANEL_LIGHT, 28, Vector2(620, 150))
	var border := 6 if upgrade.rarity_rank > 0 else 4
	card.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.PANEL_LIGHT.darkened(0.15), accent, border, 22))
	card.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.PANEL_LIGHT.lightened(0.08), accent.lightened(0.25), border, 22))
	card.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.PANEL_LIGHT.lightened(0.15), Color.WHITE, border, 22))
	card.pressed.connect(_pick.bind(index))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 18
	column.offset_right = -18
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var stacks := stats.get_stacks(upgrade.id)
	var tag := "%s  •  %s" % [upgrade.rarity_title() if upgrade.category != "evolution" else "ЭВОЛЮЦИЯ", upgrade.category_title() if upgrade.category != "evolution" else "СИНЕРГИЯ"]
	var archetype: String = ARCHETYPE_NAMES.get(RunStats.archetype_of(upgrade), "")
	if not archetype.is_empty():
		tag += "  •  " + archetype
	var tag_label := UiStyle.label(tag, 20, accent, 5)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(tag_label)
	var suffix := "" if upgrade.max_stacks <= 1 else "   %d/%d" % [stacks + 1, upgrade.max_stacks]
	var title := UiStyle.label("%d. %s%s" % [index + 1, upgrade.title, suffix], 34, upgrade.color, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)
	var desc := UiStyle.label(upgrade.description, 24, UiStyle.TEXT, 6)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	column.add_child(desc)
	return card


func _pick(index: int) -> void:
	if not visible or index >= _choices.size():
		return
	visible = false
	chosen.emit(_choices[index])


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_R and _reroll.visible:
		reroll_requested.emit()
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_3:
		_pick(key - KEY_1)
		get_viewport().set_input_as_handled()
