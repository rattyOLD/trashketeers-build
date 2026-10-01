class_name Insider
extends RefCounted
## Теги: 0 — DeV, 1 — Insider, остальные — Tester. Выдаёт только сервер (claim_badge по секретной ссылке).

static func badge_of(number: int) -> String:
	if number == 0:
		return "[DeV]"
	return "[Insider]" if number > 0 else "[Tester]"
