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
	content.add_child(_line("Арена, волны врагов и ты. Они не кончаются, пока не кончишься ты.", UiStyle.TEXT))
	content.add_child(_line("Каждые 5 волн мини-босс: пощади ради удачи или обери до трусов.", UiStyle.TEXT_DIM))
	content.add_child(_line("Заказ Нэлл с наградой висит слева сверху. Рекорд волны видят друзья.", UiStyle.TEXT_DIM))
	_taunt = _line("", Color("#ff7ae0"))
	content.add_child(_taunt)
	var go := UiStyle.button("ПОНЯТНО", Color("#2fae5f"), 28, Vector2(0, 72))
	go.pressed.connect(close)
	content.add_child(go)


func _refresh() -> void:
	var done := SaveService.get_stat("story_missions")
	if SaveService.story_shards() >= 6:
		_taunt.text = "Король повержен, город спасён. Тебе мало? Ладно, садист. Здесь тебя никто не пожалеет."
	elif done >= 1:
		_taunt.text = "Сюжет не кончен, а ты уже тут? Сбежал, слабак? Нэлл всё запомнила."
	else:
		_taunt.text = "Раньше сюжета влез? Тестер, значит. Иди ищи баги, а не славу, багоёб хренов. Сломаешь что-нибудь, я тебя найду."


func _line(text: String, color: Color) -> Label:
	var label := UiStyle.label(text, 22, color, 5)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(panel_width() - 70.0, 0)
	return label
