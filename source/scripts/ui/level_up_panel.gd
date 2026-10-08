class_name LevelUpPanel
extends Control
## Выбор 1 из 3 улучшений. Работает на паузе: HUD имеет PROCESS_MODE_ALWAYS.
## На десктопе карточки выбираются клавишами 1–3.

signal chosen(upgrade: UpgradeData)
signal reroll_requested

var _box: VBoxContainer
## Обёртка окна: её масштабируем, если окно не влезает в видимую область (узкий экран, вырез),
## а у самого окна масштаб занят пружинящим появлением.
var _holder: Control
var _title: Label
var _cards: BoxContainer
var _choices: Array[UpgradeData] = []
var _reroll: Button
var _armed_at := 0
const ARCHETYPE_NAMES := {&"dps": "БИЛД: УРОН", &"debuff": "БИЛД: ЭФФЕКТЫ", &"mobility": "БИЛД: СКОРОСТЬ"}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.074, 0.071, 0.066, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Окно ставим по центру видимой области сами: на части Android (вырез, смена размера окна при
	# переходе во весь экран) контейнер-центровщик оставлял панель съехавшей вправо за край экрана.
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_holder.add_child(_box)
	_box.minimum_size_changed.connect(_center_box.call_deferred)
	resized.connect(_center_box.call_deferred)

	_title = UiStyle.label("", 36, UiStyle.GOLD, 9)
	_box.add_child(_title)
	_box.add_child(UiStyle.label("Выбери улучшение", 20, UiStyle.TEXT_DIM, 5))

	_cards = BoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	_box.add_child(_cards)
	_reroll = UiStyle.button("", Color("#d19250"), 21, Vector2(600, 54))
	# Срабатывает на касании, а не на отпускании: на Android экран может сдвинуться под пальцем
	# (появилась системная панель), и отпускание мимо кнопки терялось — карточку было не выбрать.
	_reroll.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_reroll.pressed.connect(func() -> void:
		if visible and Time.get_ticks_msec() >= _armed_at:
			reroll_requested.emit())
	_box.add_child(_reroll)


func open(choices: Array[UpgradeData], level: int, stats: RunStats, bonus: bool = false, reroll_text: String = "", reroll_ok: bool = false) -> void:
	_choices = choices
	_title.text = "НАГРАДА БОССА!" if bonus else "УРОВЕНЬ %d!" % level
	_title.add_theme_color_override("font_color", Color("#ff7ae0") if bonus else UiStyle.GOLD)
	_cards.vertical = Orient.portrait
	_reroll.custom_minimum_size = Vector2(minf(600.0, _card_width() * 3.0), 64 if Orient.portrait else 54)
	# Старые карточки убираем из дерева сразу: иначе в момент открытия окно меряет ширину по шести карточкам
	# (старые ещё ждут удаления), растягивается вдвое и съезжает.
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i, stats))
	_reroll.visible = not reroll_text.is_empty()
	_reroll.text = reroll_text
	_reroll.modulate = Color.WHITE if reroll_ok else Color(1, 1, 1, 0.5)
	visible = true
	_center_box()
	# Подписи с переносом меряют высоту только после первой раскладки — центрируем ещё раз.
	get_tree().create_timer(0.05, true, false, true).timeout.connect(_center_box)
	get_tree().create_timer(0.3, true, false, true).timeout.connect(_center_box)
	# Короткая пауза, чтобы палец, которым только что стреляли, не выбрал карточку случайно.
	_armed_at = Time.get_ticks_msec() + 350
	UiStyle.pop_in(_box)


func _center_box() -> void:
	if not is_inside_tree():
		return
	# Видимая область — собственный прямоугольник панели (он на весь корень HUD), а не вьюпорт:
	# на iPhone в «альбомной» вкладке и с вырезом они расходились, и окно уезжало влево за край.
	var area := size if size.x > 1.0 else get_viewport_rect().size
	_box.reset_size()
	_box.size = _box.get_combined_minimum_size()
	_box.position = Vector2.ZERO
	_box.pivot_offset = _box.size * 0.5
	var fit := minf(1.0, minf((area.x - 16.0) / maxf(_box.size.x, 1.0), (area.y - 16.0) / maxf(_box.size.y, 1.0)))
	_holder.scale = Vector2.ONE * fit
	_holder.position = (area - _box.size * fit) * 0.5


## Ширина карточки в горизонтали: три карточки и отступы должны влезть в видимую ширину.
func _card_width() -> float:
	var area := (size.x if size.x > 1.0 else get_viewport_rect().size.x) if is_inside_tree() else 1280.0
	return clampf((area - 60.0 - 28.0) / 3.0, 240.0, 340.0)


func _make_card(upgrade: UpgradeData, index: int, stats: RunStats) -> Button:
	var accent := upgrade.rarity_color() if upgrade.category != "evolution" else Color("#ff5cf0")
	var card_w := _card_width()
	var text_width := 540.0 if Orient.portrait else card_w - 40.0
	var card := UiStyle.button("", UiStyle.PANEL_LIGHT, 28, Vector2(600, 122) if Orient.portrait else Vector2(card_w, 280))
	var border := 6 if upgrade.rarity_rank > 0 else 4
	card.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.PANEL_LIGHT.darkened(0.15), accent, border, 22))
	card.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.PANEL_LIGHT.lightened(0.08), accent.lightened(0.25), border, 22))
	card.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.PANEL_LIGHT.lightened(0.15), Color.WHITE, border, 22))
	card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	card.pressed.connect(_pick.bind(index))

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 18
	column.offset_right = -18
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.offset_top = 8
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var stacks := stats.get_stacks(upgrade.id)
	var tag := "%s  •  %s" % [upgrade.rarity_title() if upgrade.category != "evolution" else "ЭВОЛЮЦИЯ", upgrade.category_title() if upgrade.category != "evolution" else "СИНЕРГИЯ"]
	var archetype: String = ARCHETYPE_NAMES.get(RunStats.archetype_of(upgrade), "")
	if not archetype.is_empty():
		tag += "  •  " + archetype
	var tag_label := UiStyle.label(tag, 14, accent, 4)
	tag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_label.custom_minimum_size = Vector2(text_width, 0)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(tag_label)
	var suffix := "" if upgrade.max_stacks <= 1 else "   %d/%d" % [stacks + 1, upgrade.max_stacks]
	var title := UiStyle.label("%d. %s%s" % [index + 1, upgrade.title, suffix], 25, upgrade.color, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(text_width, 0)
	column.add_child(title)
	var desc := UiStyle.label(upgrade.description, 18, UiStyle.TEXT, 5)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(text_width, 0)
	column.add_child(desc)
	if not Orient.portrait:
		var card_ref: WeakRef = weakref(card)
		var column_ref: WeakRef = weakref(column)
		column.minimum_size_changed.connect(func() -> void:
			var target := card_ref.get_ref() as Button
			var contents := column_ref.get_ref() as VBoxContainer
			if is_instance_valid(target) and is_instance_valid(contents):
				target.custom_minimum_size.y = maxf(280.0, contents.get_combined_minimum_size().y + 16.0))
	return card


func _pick(index: int) -> void:
	if not visible or index >= _choices.size() or Time.get_ticks_msec() < _armed_at:
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
