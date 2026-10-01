class_name ModeIntroPopup
extends GlassPopup
## Первое знакомство с режимом выживания: что это, чем отличается от сюжета, что дают волны.

const PICTURES: Array[String] = [
	"res://assets/enemies/pig_default.png",
	"res://assets/enemies/pig_heavy.png",
	"res://assets/enemies/pig_royal.png",
]

var _taunt: Label


func _init() -> void:
	super("ВЫЖИВАНИЕ")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	for path in PICTURES:
		var rect := TextureRect.new()
		rect.texture = load(path) as Texture2D
		rect.custom_minimum_size = Vector2(110, 110)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(rect)
	content.add_child(_line("Тут нет миссий и босса в конце. Есть арена, волны врагов и ты. Стреляешь куда держишь палец, враги не заканчиваются, пока не закончишься ты.", UiStyle.TEXT))
	content.add_child(_line("Каждая волна злее прошлой. Каждые 5 волн приходит мини-босс: добей и выбери, пощадить его ради удачи или обобрать до трусов.", UiStyle.TEXT_DIM))
	content.add_child(_line("Между волнами можно выдохнуть секунды две. Нэлл каждый день даёт заказ с наградой, он висит слева сверху.", UiStyle.TEXT_DIM))
	content.add_child(_line("Рекорд волны сохраняется. Друзья его видят. Радуйся тихо.", UiStyle.GOLD))
	_taunt = _line("", Color("#ff7ae0"))
	content.add_child(_taunt)
	var go := UiStyle.button("ПОНЯТНО", Color("#2fae5f"), 28, Vector2(0, 72))
	go.pressed.connect(close)
	content.add_child(go)


func _refresh() -> void:
	var done := SaveService.get_stat("story_missions")
	if SaveService.story_shards() >= 6:
		_taunt.text = "Сюжет пройден, Король повержен, город спасён. А тебе мало? Ладно, садист. Здесь тебя никто не пожалеет, и я в первую очередь."
	elif done >= 1:
		_taunt.text = "Сюжет ещё не закончен, а ты уже здесь? Убежал от сюжета, потому что слабак? Нэлл всё запомнила, а Король Хлама уже смеётся."
	else:
		_taunt.text = "Ты открыл это раньше сюжета. Тестер, да? Тогда ладно."


func _line(text: String, color: Color) -> Label:
	var label := UiStyle.label(text, 22, color, 5)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(panel_width() - 70.0, 0)
	return label
