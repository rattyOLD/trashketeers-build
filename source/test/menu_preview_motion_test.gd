extends Node

var failures := 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		if failures < 12:
			push_error("MENU_PREVIEW_MOTION FAIL: " + label)


func _ready() -> void:
	var configs: Array = ConfigLoader.load_json("res://data/characters.json").get("characters", [])
	for character: Dictionary in configs:
		if not character.has("sprite") or str(character["sprite"].get("clips", "")).is_empty():
			continue
		var id := str(character["id"])
		for fps in [30, 60]:
			var preview := MenuWidgets.RaccoonPreview.new({}, 2.5, character)
			preview.size = Vector2(400, 300)
			preview.set_process(false)
			add_child(preview)
			preview._cheer_timer = 100.0
			preview._volley_timer = 100.0
			var dt: float = 1.0 / fps
			for tick in fps * 4:
				if tick % fps == 0:
					preview.fire_burst()
				preview._process(dt)
				_check(preview.raccoon._facing == 1.0, id + " facing stays steady")
				_check(preview.raccoon._clip_cur == "idle" and preview.raccoon._clip_idx == 0, id + " burst keeps neutral body")
				_check(preview.raccoon._body_kick.length() < 4.0, id + " recoil remains bounded")
			preview._aim_hold = 0.0
			preview._shots_left = 0
			preview.raccoon._shoot_t = 0.0
			preview._cheer_timer = 100.0
			if preview.raccoon.play_fidget():
				preview.fire_burst()
				_check(preview._shots_left == 0, id + " firing waits for gesture")
				var frames := {}
				for tick in fps * 2:
					preview._process(dt)
					if preview.raccoon._clip_cur == "fidget":
						frames[preview.raccoon._clip_idx] = true
						_check(preview._shots_left == 0, id + " no volley during gesture")
				_check(frames.size() >= 8, id + " gesture plays all frames")
				_check(preview.raccoon._fidget_t <= 0.0 and preview.raccoon._clip_cur == "idle", id + " gesture returns to neutral stance")
				_check(preview._shots_left == 0 and preview._aim_hold <= 0.0, id + " delayed volley completes")
			preview.free()
		var battle_actor := RaccoonVisual.new()
		add_child(battle_actor)
		battle_actor.apply_look(character, {})
		battle_actor.kick(Vector2.RIGHT, 1.0)
		battle_actor.update_motion(Vector2.ZERO, Vector2.RIGHT, 1.0 / 60.0)
		_check(battle_actor._clip_cur == "shoot", id + " battle retains shoot animation")
		battle_actor.free()
	print("MENU_PREVIEW_MOTION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
