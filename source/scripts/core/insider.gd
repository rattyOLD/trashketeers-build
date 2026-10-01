class_name Insider
extends RefCounted
## Теги: 0 — DeV, 1 — Insider, 2 — GOD (единственный, у ИИ-игрока), у остальных тега нет. Выдаёт только сервер.

const GOD := 2
const GOD_COLOR := Color("#ff5a3d")


static func badge_of(number: int) -> String:
	if number == 0:
		return "[DeV]"
	if number == GOD:
		return "[GOD]"
	return "[Insider]" if number > 0 else ""


## Цвет ника по тегу (для списков друзей и топа).
static func color_of(number: int, fallback: Color) -> Color:
	if number == 0:
		return UiStyle.GOLD
	if number == GOD:
		return GOD_COLOR
	if number == 1:
		return UiStyle.HOT.lightened(0.3)
	return fallback
