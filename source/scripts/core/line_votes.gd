class_name LineVotes
extends RefCounted
## Оценки реплик от тестеров: 👍 оставить / 👎 убрать. Дизлайкнутые реплики больше не показываются этому игроку,
## все оценки уходят в общий отчёт (Platform.send_report, вид "line_vote").

static func enabled() -> bool:
	return SaveService.get_insider() >= 0 and bool(SaveService.data.get("line_votes_on", true))


static func line_id(line: Dictionary) -> String:
	return ("%s|%s" % [line.get("who", ""), line.get("text", "")]).md5_text().substr(0, 10)


static func vote_of(id: String) -> int:
	return int((SaveService.data["line_votes"] as Dictionary).get(id, 0))


static func is_hidden(line: Dictionary) -> bool:
	return enabled() and vote_of(line_id(line)) < 0


static func rated_count() -> int:
	return (SaveService.data["line_votes"] as Dictionary).size()


static func cast(line: Dictionary, value: int) -> void:
	var id := line_id(line)
	(SaveService.data["line_votes"] as Dictionary)[id] = value
	SaveService.save_data()
	var text := str(line.get("text", "")).replace("|", "/")
	Platform.send_report("line_vote", "%s|%d|%s|%s|ins%03d" % [id, value, str(line.get("who", "")), text, SaveService.get_insider()])
