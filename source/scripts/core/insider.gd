class_name Insider
extends RefCounted
## Коды тестеров без сервера: номер 000 — разработчик, 001+ — инсайдеры. Код = INS-<номер>-<4 знака проверки>.
## Проверка локальная: это защита от опечаток и случайных людей, а не от взлома. Настоящая выдача номеров
## появится вместе с онлайн-аккаунтами.

const SALT := "trashketeers-insider-v1"
const MAX_NUMBER := 999


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
