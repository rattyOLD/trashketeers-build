class_name BadgeWelcomePopup
extends GlassPopup
## Приветствие при получении тега: событие с шуткой, а не тихая плашка.

const DEV_LINES: Array[String] = [
	"Ключи от свалки у тебя. Мусоровоз слушается только тебя, а жалобы теперь читаешь ты.",
	"Добро пожаловать за кулисы. Здесь пахнет мусором и властью.",
	"Теперь ты DeV: видишь жалобы, банишь болтунов и можешь перевыпустить любую ссылку. Не зазнавайся.",
]
const INSIDER_LINES: Array[String] = [
	"Ты теперь свой на свалке. Крысы уже в курсе и немного завидуют.",
	"Тег Insider выдан. Особых прав нет, зато у тебя красивая розовая плашка.",
	"Ты в числе первых, кто лезет в мусорный бак раньше остальных. Респект.",
	"Теперь ты инсайдер. Пиши баги, жми кнопки, не ешь найденное.",
]

var level := 1


func _init(tag_level: int) -> void:
	super("ДОБРО ПОЖАЛОВАТЬ" if tag_level == 0 else "ТЫ В ИГРЕ ПО-ВЗРОСЛОМУ")
	level = tag_level


func _refresh() -> void:
	var keep := content.get_child(0)
	for child in content.get_children():
		if child != keep:
			content.remove_child(child)
			child.queue_free()
	var color := UiStyle.GOLD if level == 0 else UiStyle.HOT
	var badge := UiStyle.label(Insider.badge_of(level), 72, color, 10)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(badge)
	var pool := DEV_LINES if level == 0 else INSIDER_LINES
	var text := UiStyle.label(pool[randi() % pool.size()], 26, UiStyle.TEXT, 6)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size = Vector2(panel_width() - 120.0, 0)
	content.add_child(text)
	var ok := UiStyle.button("ЕСТЬ", color, 32, Vector2(0, 76))
	ok.pressed.connect(close)
	content.add_child(ok)
