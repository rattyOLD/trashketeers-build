extends Node
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("STORY_RESET FAIL: " + label)

func _find_button(node: Node, prefix: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.begins_with(prefix):
			return child
		var found := _find_button(child, prefix)
		if found != null:
			return found
	return null

func _run() -> void:
	var original := SaveService.data.duplicate(true)
	var badge := Platform.storage_get(SaveService.BADGE_KEY)
	var resume := SaveService.resume_requested
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["story"] = {"m1": {"done": true, "shards": 3, "best": 999}}
	SaveService.data["story_best"] = {"m1": 999}
	SaveService.data["story_log"] = {"m1:intro": true}
	SaveService.data["story_choice"] = {"m1": "informant"}
	SaveService.data["story_resume"] = {"mission": "m2", "saved": int(Time.get_unix_time_from_system())}
	SaveService.data["nuts"] = 12345
	SaveService.data["star_dust"] = 678
	SaveService.data["stats"] = {"story_missions": 7, "kills": 100}
	SaveService.data["perks"] = {"damage": 3}
	SaveService.resume_requested = true
	var before := SaveService.data.duplicate(true)
	for level in ["1", "-1"]:
		Platform.storage_set(SaveService.BADGE_KEY, level)
		_check(not Tester.reset_story(), "non-DeV rejected")
		_check(SaveService.data == before, "rejected reset preserves save")
		var denied := TesterPopup.new()
		add_child(denied)
		denied.open()
		_check(_find_button(denied, "Сбросить сюжетный прогресс") == null, "non-DeV button hidden")
		denied.queue_free()
		await get_tree().process_frame
	Platform.storage_set(SaveService.BADGE_KEY, "0")
	var popup := TesterPopup.new()
	add_child(popup)
	popup.open()
	var button := _find_button(popup, "Сбросить сюжетный прогресс")
	_check(button != null, "DeV button exists")
	if button != null:
		button.pressed.emit()
		_check(SaveService.data == before, "first click only asks for confirmation")
		popup._refresh()
		button = _find_button(popup, "Сбросить сюжетный прогресс")
		button.pressed.emit()
		_check(SaveService.data == before, "refresh disarms confirmation")
		button.pressed.emit()
		for key in ["story", "story_best", "story_log", "story_choice", "story_resume"]:
			_check((SaveService.data[key] as Dictionary).is_empty(), "cleared " + key)
		for key in before:
			if key not in ["story", "story_best", "story_log", "story_choice", "story_resume", "train_again", "saved_at"]:
				_check(SaveService.data[key] == before[key], "preserved " + str(key))
		_check(StoryRun.next_mission_id() == "m1", "restart at mission one")
		_check(not SaveService.resume_requested, "resume request cleared")
		_check(bool(SaveService.data["train_again"]), "training enabled")
		var stored: Dictionary = JSON.parse_string(Platform.storage_get(SaveService.STORAGE_KEY))
		_check((stored["story"] as Dictionary).is_empty(), "reset persisted")
	popup.queue_free()
	SaveService.data = original
	SaveService.resume_requested = resume
	Platform.storage_set(SaveService.BADGE_KEY, badge)
	SaveService.save_data()
	print("STORY_RESET_TEST failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
