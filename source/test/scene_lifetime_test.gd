extends Node
var failures := 0
var delivered := 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("SCENE_LIFETIME: " + message)

func _reply() -> Dictionary:
	await get_tree().create_timer(0.08, true, false, true).timeout
	return {"ok": true, "value": 42}

func _deliver(answer: Dictionary) -> void:
	_check(answer == {"ok": true, "value": 42}, "response data is preserved")
	delivered += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 20:
		var button := UiStyle.button("Transient button", UiStyle.PANEL)
		add_child(button)
		button.free()
		var label := UiStyle.label("Transient plate", 20)
		UiStyle.fit_plate_label(label, 20)
		add_child(label)
		label.free()
	for i in 40:
		var closed := Control.new()
		add_child(closed)
		Cloud.request_for(closed, _reply, _deliver)
		closed.queue_free()
	var detached := Control.new()
	add_child(detached)
	Cloud.request_for(detached, _reply, _deliver)
	remove_child(detached)
	var live := Control.new()
	add_child(live)
	Cloud.request_for(live, _reply, _deliver)
	get_tree().paused = true
	await get_tree().create_timer(0.2, true, false, true).timeout
	_check(delivered == 1, "only live receiver gets its response, also while gameplay is paused")
	get_tree().paused = false
	detached.free()
	live.free()
	# Destroy the training target while its delayed line is still scheduled.
	Controls.apply_keys()
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tips_off"] = true
	var game := Game.new()
	game.story_mission = "m1"
	add_child(game)
	game.start()
	var targets := game.find_children("*", "TrainingTarget", true, false)
	_check(not targets.is_empty(), "story creates a training target")
	for target in targets:
		target.queue_free()
	game.queue_free()
	await get_tree().create_timer(3.0, true, false, true).timeout
	for i in 4:
		await get_tree().process_frame
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before, "closed requests and story leave no orphan nodes")
	print("SCENE_LIFETIME failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)
