extends Node
## Заглушка приглашений и плашка «Что нового»: логика и сохранение.

func _ready() -> void:
	var fails := 0
	CoopMute.clear()
	fails += _check(not CoopMute.blocks("ABC"), "по умолчанию не заглушено")
	CoopMute.mute_friend("ABC")
	fails += _check(CoopMute.blocks("ABC") and not CoopMute.blocks("XYZ"), "заглушён только ABC")
	CoopMute.clear()
	CoopMute.mute_all(3600)
	fails += _check(CoopMute.blocks("XYZ") and CoopMute.until() > 0, "заглушено на час")
	SaveService.data[CoopMute.KEY_UNTIL] = int(Time.get_unix_time_from_system()) - 5
	fails += _check(not CoopMute.blocks("XYZ") and CoopMute.until() == 0, "срок вышел")
	CoopMute.mute_all(-1)
	fails += _check(CoopMute.until() == -1 and CoopMute.status_text() == "Приглашения выключены", "навсегда")
	CoopMute.clear()
	fails += _check(not CoopMute.is_any_active(), "сброс")
	CoopMute.clear()
	CoopMute.cycle()
	fails += _check(CoopMute.until() > 0, "цикл: час")
	CoopMute.cycle()
	fails += _check(CoopMute.until() == -1, "цикл: всегда")
	CoopMute.cycle()
	fails += _check(not CoopMute.is_any_active(), "цикл: включено")
	# значения переживают загрузку: ключи должны быть в DEFAULTS
	for key in ["whatsnew_seen", "coop_mute_until", "coop_muted_codes"]:
		fails += _check(SaveService.DEFAULTS.has(key), "DEFAULTS содержит " + key)
	# плашка «Что нового»
	SaveService.data["whatsnew_seen"] = ""
	fails += _check(WhatsNewPopup.should_show(), "плашка показывается до просмотра")
	SaveService.data["whatsnew_seen"] = ChangelogPopup.latest_version()
	fails += _check(not WhatsNewPopup.should_show(), "после просмотра не показывается")
	var latest := ChangelogPopup.load_entries()[0] as Dictionary
	fails += _check(latest.get("short") is Array and (latest["short"] as Array).size() <= 4, "у последней записи есть краткий текст")
	print("MUTE_TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(0 if fails == 0 else 1)


func _check(ok: bool, what: String) -> int:
	if not ok:
		print("FAIL: " + what)
	return 0 if ok else 1
