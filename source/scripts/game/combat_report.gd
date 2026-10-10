class_name CombatReport
extends RefCounted
## Сумма реально потерянных HP: броня и избыточный урон не увеличивают отчёт.

const KIND_NAMES := {
	&"": "пули", &"projectile": "пули", &"melee": "ближний бой",
	&"blast": "взрывы", &"fire": "огонь", &"poison": "яд",
	&"shock": "электричество", &"bleed": "кровотечение",
	&"ice": "холод", &"dash": "рывок",
	&"acid": "кислота на карте",
}
var enemy_damage := 0.0
var damage_by_kind := {}
var received := 0.0
var last_source: StringName = &""
const RECENT_WINDOW := 4.0
const RECENT_LIMIT := 16
var _clock := 0.0
var _recent: Array[Dictionary] = []


func advance(delta: float) -> void:
	_clock += delta


func record_enemy(amount: float, hp_after: float, kind: StringName) -> void:
	var actual := minf(maxf(amount, 0.0), maxf(hp_after + amount, 0.0))
	if actual <= 0.0:
		return
	# Неизвестные эффекты объединяются, чтобы размер отчёта не рос от модов.
	var key := &"" if kind == &"projectile" else (&"fire" if kind == &"burn" else kind)
	if not KIND_NAMES.has(key):
		key = &"other"
	enemy_damage += actual
	damage_by_kind[key] = float(damage_by_kind.get(key, 0.0)) + actual


func record_received(actual: float, source: StringName) -> void:
	if actual <= 0.0:
		return
	received += actual
	last_source = source
	if _recent.size() >= RECENT_LIMIT:
		_recent.pop_front()
	_recent.append({"at": _clock, "amount": actual, "source": source})


func source_title() -> String:
	return title_for(last_source)


static func title_for(source: StringName) -> String:
	match source:
		&"blast": return "взрыв"
		&"projectile": return "пуля"
		&"acid": return "кислота"
		&"trap": return "магнитная мина"
		&"shock": return "разряд"
		&"collapse": return "обвал"
		&"laser": return "лазер"
		&"?", &"": return "опасность на карте"
	for entry: Dictionary in ConfigLoader.load_json("res://data/enemies.json").get("enemies", []):
		if str(entry.get("enemy_id", "")) == str(source):
			return str(entry.get("display_name", "враг"))
	return "опасность на карте"


func avoidance_tip() -> String:
	match last_source:
		&"blast": return "Выходи за границу круга до заполнения дуги. Рывок поможет покинуть зону."
		&"projectile": return "Смещайся поперёк линии огня; используй укрытия и рывок."
		&"acid": return "Не задерживайся в кислоте: обойди лужу или выйди рывком."
		&"trap": return "Обходи круг магнитной мины, чтобы она не замедляла отход."
		&"shock", &"collapse": return "Покинь подсвеченную зону до удара; держи рывок для отхода."
		&"laser": return "Уйди поперёк луча, пока враг прицеливается."
	return "Держи дистанцию и оставляй свободный путь для рывка из окружения."


func lines(dead: bool) -> String:
	if enemy_damage <= 0.0 and received <= 0.0:
		return ""
	var result := "Урон по врагам: %d" % roundi(enemy_damage)
	var breakdown := damage_breakdown()
	for row: Dictionary in breakdown:
		result += "\n%s: %d · %d%%" % [row["title"], roundi(row["amount"]), roundi(row["amount"] / maxf(enemy_damage, 1.0) * 100.0)]
	result += "\nПотеряно HP: %d" % roundi(received)
	if dead and received > 0.0:
		result += "\nПоследний удар: " + source_title()
		var recent := recent_damage()
		if not recent.is_empty():
			result += "\nПеред гибелью (4 с):"
			for row: Dictionary in recent:
				result += "\n%s · −%d HP" % [row["title"], roundi(row["amount"])]
	return result


func recent_damage() -> Array[Dictionary]:
	var totals := {}
	for hit: Dictionary in _recent:
		if _clock - float(hit["at"]) <= RECENT_WINDOW:
			totals[hit["source"]] = float(totals.get(hit["source"], 0.0)) + float(hit["amount"])
	var rows: Array[Dictionary] = []
	for source: StringName in totals:
		rows.append({"title": title_for(source), "amount": totals[source]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["amount"] > b["amount"])
	if rows.size() > 2:
		rows.resize(2)
	return rows


func damage_breakdown() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for kind: StringName in damage_by_kind:
		rows.append({"title": KIND_NAMES.get(kind, "эффекты"), "amount": float(damage_by_kind[kind])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["amount"] > b["amount"])
	if rows.size() > 3:
		rows.resize(3)
	return rows
