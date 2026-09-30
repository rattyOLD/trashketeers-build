class_name Insider
extends RefCounted
## Коды тестеров без сервера: номер 000 — разработчик, 001+ — инсайдеры. Код = INS-<номер>-<4 знака проверки>.
## Проверка локальная: это защита от опечаток и случайных людей, а не от взлома. Настоящая выдача номеров
## появится вместе с онлайн-аккаунтами.

const SALT := "trashketeers-insider-v1"
const MAX_NUMBER := 999
const REVOKED_PATH := "res://data/insider_revoked.json"

static var _revoked: Array[int] = []
static var _loaded := false


static func check_of(number: int) -> String:
	return ("%s-%03d" % [SALT, number]).sha256_text().left(4).to_upper()


static func code_for(number: int) -> String:
	return "INS-%03d-%s" % [number, check_of(number)]


## Номер по коду или -1, если код не подходит.
static func parse(code: String) -> int:
	var parts := code.strip_edges().to_upper().split("-")
	if parts.size() != 3 or parts[0] != "INS" or not parts[1].is_valid_int():
		return -1
	var number := int(parts[1])
	if number < 0 or number > MAX_NUMBER or parts[2] != check_of(number):
		return -1
	return number


static func badge_of(number: int) -> String:
	if number < 0:
		return ""
	return "[Dev]" if number == 0 else "[Insider]"


## Отозванные номера (утёкшие коды): список в data/insider_revoked.json, номер 0 отозвать нельзя.
static func is_revoked(number: int) -> bool:
	if number <= 0:
		return false
	if not _loaded:
		_loaded = true
		var raw: Variant = ConfigLoader.load_json(REVOKED_PATH).get("revoked", [])
		if raw is Array:
			for n: Variant in raw:
				_revoked.append(int(n))
	return _revoked.has(number)
