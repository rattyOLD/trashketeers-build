class_name CoopMute
extends RefCounted
## «Заглушить» приглашения в кооп, как в современных играх: на час, на сутки, насовсем или только от одного друга.
## Хранится в сохранении на этом устройстве. Заглушённые приглашения просто не показываются, отправитель ничего не узнаёт.

const KEY_UNTIL := "coop_mute_until"      # unix-время окончания, -1 = пока не включу обратно, 0 = не заглушено
const KEY_CODES := "coop_muted_codes"     # коды друзей, которых заглушили по одному

const HOUR := 3600
const DAY := 86400


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func until() -> int:
	var value := int(SaveService.data.get(KEY_UNTIL, 0))
	if value > 0 and value <= _now():
		SaveService.data[KEY_UNTIL] = 0   # срок вышел
		SaveService.save_data()
		return 0
	return value


static func muted_codes() -> Array:
	var raw: Variant = SaveService.data.get(KEY_CODES, [])
	return raw as Array if raw is Array else []


## true, если приглашение от этого друга показывать не надо.
static func blocks(friend_code: String) -> bool:
	return until() != 0 or muted_codes().has(friend_code)


static func mute_all(seconds: int) -> void:
	SaveService.data[KEY_UNTIL] = -1 if seconds < 0 else _now() + seconds
	SaveService.save_data()


static func mute_friend(friend_code: String) -> void:
	if friend_code.is_empty():
		return
	var codes := muted_codes()
	if not codes.has(friend_code):
		codes.append(friend_code)
	SaveService.data[KEY_CODES] = codes
	SaveService.save_data()


static func clear() -> void:
	SaveService.data[KEY_UNTIL] = 0
	SaveService.data[KEY_CODES] = []
	SaveService.save_data()


static func is_any_active() -> bool:
	return until() != 0 or not muted_codes().is_empty()


## Короткая строка состояния для окна коопа.
static func status_text() -> String:
	var value := until()
	if value < 0:
		return "Приглашения выключены"
	if value > 0:
		var left := value - _now()
		return "Приглашения выключены ещё на %s" % (("%d мин" % ceili(left / 60.0)) if left < HOUR else ("%d ч" % ceili(left / 3600.0)))
	var count := muted_codes().size()
	return "Приглашения включены" + ((", заглушено друзей: %d" % count) if count > 0 else "")


## Подпись на кнопке в лобби.
static func short_text() -> String:
	var value := until()
	if value < 0:
		return "ТИХО: ВСЕГДА"
	if value > 0:
		return "ТИХО: %d МИН" % ceili((value - _now()) / 60.0)
	return "ТИХО: НЕТ" if muted_codes().is_empty() else "ТИХО: %d ДР." % muted_codes().size()


## Один тап по кнопке в лобби: приглашения включены -> тихо на час -> тихо всегда -> включены (и список заглушённых друзей очищается).
static func cycle() -> void:
	var value := until()
	if value == 0:
		mute_all(HOUR)
	elif value > 0:
		mute_all(-1)
	else:
		clear()
