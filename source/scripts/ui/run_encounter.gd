class_name RunEncounter
extends GlassPopup
## Короткий выбор рядом с персонажем/рацией. Закрытие равнозначно безопасному варианту.
signal chosen(risky: bool)
var _resolved := false
var _paused_before := false


func _init(who: String, reward: int) -> void:
	super("НЭЛЛ" if who == "nell" else "ШНЫРЬ")
	process_mode = Node.PROCESS_MODE_ALWAYS
	content.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	var portrait := TextureRect.new()
	portrait.texture = load("res://assets/story/portraits/nell.png" if who == "nell" else "res://assets/story/portraits3/snyr.png")
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(portrait)
	var text := UiStyle.label("Поможешь с ретранслятором? Могу просто прислать припасы. Но удержишь точку — заплачу больше." if who == "nell" else "Есть одна точка, которую надо прикрыть. Можешь взять припасы и уйти. За работу — другая цена.", 20, UiStyle.TEXT, 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x = 10
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	for spec in [["ВЗЯТЬ ПРИПАСЫ · +15 HP И 15 МОНЕТ", false], ["УДЕРЖАТЬ ТОЧКУ · +%d МОНЕТ" % reward, true]]:
		var button := UiStyle.button(spec[0], UiStyle.PANEL_LIGHT, 20, Vector2(0, 48))
		button.pressed.connect(_resolve.bind(bool(spec[1])))
		content.add_child(button)
	var note := UiStyle.label("Поручение: 12 с в круге за 25 с, до конца волны. Враги внутри мешают. Не успеешь — награды не будет.", 16, UiStyle.TEXT_DIM, 2)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	closed.connect(_resolve.bind(false))


func begin() -> void:
	_paused_before = get_tree().paused
	get_tree().paused = true
	open()


func _resolve(risky: bool) -> void:
	if _resolved:
		return
	_resolved = true
	get_tree().paused = _paused_before
	chosen.emit(risky)
	queue_free()
