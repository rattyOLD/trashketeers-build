class_name Ascension
extends RefCounted
## Возвышения — престиж в духе «новой игры+»: 10 ступеней сложности Выживания поверх прокачки аккаунта.
## Каждая ступень добавляет испытание к предыдущим (враги крепче, элита с особенностями, дороже лавки…),
## за что монеты забега растут. Ступень N+1 открывается победой над первым боссом на ступени N.

const MAX := 10
const LEVELS := [
	{"title": "Упорство", "desc": "Враги крепче на 20%"},
	{"title": "Элита", "desc": "Часть врагов — элита с особенностью (быстрая, бронированная или взрывная)"},
	{"title": "Жёсткий счёт", "desc": "Враги бьют на 15% больнее, лечение слабее на 25%"},
	{"title": "Тяжёлые ноги", "desc": "Рывок перезаряжается на 30% дольше"},
	{"title": "Боссы в ярости", "desc": "Боссы крепче на 40% и быстрее на 15%"},
	{"title": "Орда", "desc": "Врагов в волнах на 25% больше"},
	{"title": "Инфляция", "desc": "Сейфы и Барыга дороже на 50%"},
	{"title": "Сплошная элита", "desc": "Элиты втрое больше"},
	{"title": "Стальная шкура", "desc": "Враги ещё крепче на 30%"},
	{"title": "Без права на ошибку", "desc": "Нет регенерации, возрождение только одно"},
]
const ELITE_KINDS := ["fast", "armored", "explosive"]
const ELITE_COLORS := {"fast": Color("#6adcff"), "armored": Color("#c9c3d9"), "explosive": Color("#ff7a3d")}

## Ступень текущего забега (0 — без возвышения).
static var active := 0


static func unlocked() -> int:
	return clampi(int(SaveService.data.get("ascension_max", 0)), 0, MAX)


static func chosen() -> int:
	return clampi(int(SaveService.data.get("ascension", 0)), 0, unlocked())


static func cycle() -> int:
	var next := (chosen() + 1) % (unlocked() + 1)
	SaveService.set_value("ascension", next)
	return next


## Победа над первым боссом на ступени level открывает следующую. Возвращает true, если открыта новая.
static func on_boss_beaten(level: int) -> bool:
	if level < unlocked() or unlocked() >= MAX:
		return false
	SaveService.data["ascension_max"] = level + 1
	SaveService.save_data()
	return true


static func resolve() -> void:
	active = chosen()


static func clear() -> void:
	active = 0


static func title_of(level: int) -> String:
	return "НЕТ" if level <= 0 else "%s «%s»" % [roman(level), LEVELS[level - 1]["title"]]


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][clampi(n, 0, 10)]


static func button_text() -> String:
	return "ВОЗВЫШЕНИЕ: %s" % ("НЕТ" if chosen() == 0 else roman(chosen()))


## Все испытания ступени level одним текстом (для подсказки).
static func describe(level: int) -> String:
	if level <= 0:
		return "Обычная сложность. Победи первого босса, чтобы открыть Возвышение I."
	var lines: PackedStringArray = []
	for i in level:
		lines.append("%s. %s" % [roman(i + 1), LEVELS[i]["desc"]])
	return "%s\nМонеты ×%.2f" % ["\n".join(lines), coin_mult_for(level)]


static func coin_mult() -> float:
	return coin_mult_for(active)


static func coin_mult_for(level: int) -> float:
	return 1.0 + 0.12 * level


static func hp_mult() -> float:
	return (1.2 if active >= 1 else 1.0) * (1.3 if active >= 9 else 1.0)


static func damage_mult() -> float:
	return 1.15 if active >= 3 else 1.0


static func heal_mult() -> float:
	return 0.75 if active >= 3 else 1.0


static func dash_mult() -> float:
	return 1.3 if active >= 4 else 1.0


static func boss_hp_mult() -> float:
	return 1.4 if active >= 5 else 1.0


static func boss_speed_mult() -> float:
	return 1.15 if active >= 5 else 1.0


static func count_mult() -> float:
	return 1.25 if active >= 6 else 1.0


static func price_mult() -> float:
	return 1.5 if active >= 7 else 1.0


static func elite_chance() -> float:
	if active >= 8:
		return 0.18
	return 0.06 if active >= 2 else 0.0


static func no_regen() -> bool:
	return active >= 10


static func max_revives() -> int:
	return 1 if active >= 10 else 99
