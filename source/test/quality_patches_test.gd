extends Node

var failures := 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("QUALITY_PATCHES FAIL: " + label)


func _ready() -> void:
	var saved: Dictionary = SaveService.data.duplicate(true)
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	_test_patches()
	_test_orders()
	_test_tasks()
	_test_quality()
	await _test_screen_feedback()
	SaveService.data = saved
	BattleQuality.configure(0, SaveService.is_fx_lite())
	print("QUALITY_PATCHES failures=", failures)
	get_tree().quit(1 if failures else 0)


func _card(id: String) -> UpgradeData:
	for card in Patches.cards():
		if String(card.id) == "patch_" + id:
			return card
	return null


func _test_patches() -> void:
	_check(Patches.cards().size() == 4, "four starter patches")
	_check(not Patches.buy("skull"), "locked purchase rejected")
	SaveService.data["nell_orders_completed"] = 8
	_check(Patches.cards().size() == 12, "orders unlock twelve patches")
	var stats := RunStats.new()
	_check(not stats.is_available(_card("fist")), "no patches outside survival")
	stats.patch_context = true
	for id in ["fist", "bullet", "heart", "mug"]:
		stats.apply(_card(id))
	_check(stats.patch_ids.size() == 4, "four occupied slots")
	_check(not stats.is_available(_card("boot")), "fifth patch unavailable")
	stats.apply(_card("boot"))
	_check(stats.patch_ids.size() == 4 and stats.get_stat(&"move_speed_mult") == 0, "fifth patch cannot bypass capacity")
	_check(is_equal_approx(stats.get_stat(&"damage_mult"), 0.16), "salvo pair bonus")
	_check(is_equal_approx(stats.get_stat(&"max_hp_add"), 21.0), "health pair bonus")
	for i in 4:
		stats.apply(_card("fist"))
	_check(stats.get_stacks(&"patch_fist") == 5, "five card levels")
	_check(is_equal_approx(stats.get_stat(&"damage_mult"), 0.4), "pair bonus applied once")
	stats.apply(_card("fist"))
	_check(stats.get_stacks(&"patch_fist") == 5 and is_equal_approx(stats.get_stat(&"damage_mult"), 0.4), "sixth level rejected")
	_check(stats.patch_set_titles().size() == 2, "two pair names")
	var cards := stats.roll_choices(Patches.cards(), 3, 0.0)
	for card in cards:
		_check(stats.patch_ids.has(String(card.id).trim_prefix("patch_")), "full jacket only rolls upgrades of equipped patches")
	# Старые покупки и экипировка переживают загрузку; дубликаты не занимают места и не удваивают бонусы.
	SaveService.data["patches"] = {"skull": 3}
	SaveService.data["patch_worn"] = ["skull", "skull", "missing"]
	SaveService.data["patch_slots_open"] = 4
	SaveService.data["nell_orders_completed"] = 0
	SaveService._apply_text(JSON.stringify(SaveService.data))
	_check(Patches.level("skull") == 3 and Patches.unlocked("skull"), "legacy patch ownership kept")
	_check(Patches.worn() == ["skull"] and Patches.open_slots() == 4, "legacy slots kept and duplicate removed")
	var legacy := RunStats.new()
	Patches.apply(legacy)
	_check(is_equal_approx(legacy.get_stat(&"damage_mult"), 0.6) and legacy.patch_ids.size() == 1, "legacy bonus kept")
	SaveService.data = SaveService.DEFAULTS.duplicate(true)


func _test_orders() -> void:
	SaveService.nell_order()
	var daily: Dictionary = SaveService.data["nell_daily"]
	var spec: Dictionary = SaveService.NELL_ORDERS[int(daily["idx"])]
	_complete_order_counter(spec)
	var done := SaveService.nell_order_tick()
	_check(not done.is_empty() and done.get("patch_unlock", "") == "Магнит", "first order unlocks magnet")
	_check(int(SaveService.data["nell_orders_completed"]) == 1, "order counted once")
	_check(SaveService.nell_order_tick().is_empty() and int(SaveService.data["nell_orders_completed"]) == 1, "HUD polling cannot repeat reward")
	SaveService._apply_text(JSON.stringify(SaveService.data))
	_check(Patches.unlocked("magnet") and not Patches.unlocked("clover"), "unlock persists after reload")
	_check(SaveService.nell_order_tick().is_empty(), "reload cannot repeat completed order")
	for i in 7:
		var order: Dictionary = SaveService.data["nell_daily"]
		_complete_order_counter(SaveService.NELL_ORDERS[int(order["idx"])])
		_check(not SaveService.nell_order_tick().is_empty(), "following order completes")
		_check(SaveService.nell_order_tick().is_empty(), "each following order counted once")
	_check(int(SaveService.data["nell_orders_completed"]) == 8 and Patches.cards().size() == 12, "eight orders unlock all patches")
	_check(bool(SaveService.nell_order()["done"]), "daily order limit preserved")


func _complete_order_counter(spec: Dictionary) -> void:
	var key := str(spec["stats"][0])
	if key == "boss_kills":
		SaveService.data[key] = int(SaveService.data[key]) + int(spec["goal"])
	else:
		SaveService.add_stat(key, int(spec["goal"]), false)


func _test_tasks() -> void:
	var task := WaveTask.new()
	task.start({"enemy": "courier_rat", "title": "Перехвати курьеров", "count": 3, "reward": 20})
	_check(not task.kill(&"rat_punk", false), "other enemies do not count")
	_check(not task.kill(&"courier_rat", true) and task.progress == 0, "boss minions do not count")
	for i in 2:
		_check(not task.kill(&"courier_rat", false), "task waits for target")
	_check(task.kill(&"courier_rat", false) and task.completed, "third kill completes")
	_check(not task.kill(&"courier_rat", false) and task.progress == 3, "reward issued once")
	task.start({})
	_check(task.rows().is_empty() and not task.kill(&"courier_rat", false), "new wave clears task")
	var task_count := 0
	for chapter: Dictionary in ContentDB.get_chapters():
		for wave: Dictionary in chapter["waves"]:
			if not (wave["task"] as Dictionary).is_empty():
				task_count += 1
				var spec: Dictionary = wave["task"]
				var kill_spec: Dictionary = spec if str(spec.get("kind", "kill")) == "kill" else spec.get("fallback", {})
				if not kill_spec.is_empty():
					_check(ContentDB.get_enemy(StringName(kill_spec["enemy"])) != null, "task enemy exists")
					_check((wave["weights"] as Dictionary).has(kill_spec["enemy"]), "task enemy spawns in wave")
				_check(str(spec.get("kind", "kill")) in ["kill", "collect", "tower", "break"], "supported task kind")
				_check(str(wave.get("boss", "")).is_empty() and str(wave.get("miniboss", "")).is_empty(), "no reward task during boss wave")
	_check(task_count == 24, "four tasks in each of six chapters survive loading")


func _test_quality() -> void:
	SaveService.data["quality"] = 2
	WaveDirector.alive_scale = 1.0
	var battle := BattleBase.new()
	add_child(battle)
	battle._perf_age = 100.0
	# Возобновление не включает время паузы в длительность кадра.
	battle._perf_last_usec = Time.get_ticks_usec() - 60000000
	battle._notification(Node.NOTIFICATION_PAUSED)
	battle._notification(Node.NOTIFICATION_UNPAUSED)
	battle._process(0.016)
	battle._process(0.016)
	_check(battle._perf_frames.is_empty() and battle._perf_age == 100.0, "paused minute is not a slow frame")
	for stage in 4:
		battle._adapt_quality(5.1)
		_check(battle._adapt_level == stage + 1, "slow frames reduce visual quality")
		_check(WaveDirector.alive_scale == 1.0, "adaptation preserves enemy count")
		_check(BattleQuality.particles(100) < 100 and BattleQuality.light_limit <= 12, "particle and light budgets reduced")
	var enemy := Enemy.new()
	_check(enemy._warning.z_index > BiomeLayers.Z_FX and not enemy._warning.z_as_relative, "warning remains above crowd and flashes")
	enemy.free()
	battle.free()
	SaveService.data["quality"] = 0
	var lite := BattleBase.new()
	add_child(lite)
	lite._perf_age = 100.0
	lite._adapt_quality(5.1)
	_check(lite._fx_scale < 0.5, "adaptation never increases lite effects")
	lite.free()
	_check(BattleQuality.level == 0, "next screen restores visual budget")
	# Поздняя просадка не меняет разрешение ни на одной настройке качества.
	var was_native := Platform.is_native_app
	var saved_scale := Platform.native_render_scale
	Platform.is_native_app = true
	for quality in [0, 1, 2]:
		SaveService.data["quality"] = quality
		Platform.native_render_scale = 1.0
		var sustained := BattleBase.new()
		add_child(sustained)
		sustained._perf_age = 600.0
		for stage in 4:
			sustained._adapt_quality(5.1)
		_check(sustained._adapt_level == 4, "late sustained overload exhausts decorative budget")
		_check(Platform.native_render_scale == 1.0, "late overload keeps chosen canvas resolution")
		sustained.free()
	Platform.is_native_app = was_native
	Platform.native_render_scale = saved_scale


func _test_screen_feedback() -> void:
	SaveService.data["quality"] = 1
	SaveService.data["reduced_flashes"] = false
	var arena := Node2D.new()
	add_child(arena)
	var atmosphere := AtmosphereFX.new()
	arena.add_child(atmosphere)
	atmosphere.build(arena)
	atmosphere.hit_pulse(10.0)
	atmosphere._process(0.01)
	_check(atmosphere._aberration <= 1.0, "damage feedback has a fixed pixel limit")
	atmosphere.flash(Color.WHITE, 0.4, 0.5)
	await get_tree().process_frame
	var previous := atmosphere._flash_tween
	atmosphere.flash(Color.RED, 0.2, 0.25)
	_check(not previous.is_running(), "new flash cancels competing fade")
	get_tree().paused = true
	_check(not atmosphere._flash.visible and atmosphere._aberration == 0.0, "upgrade pause clears transient distortion")
	_check(float((atmosphere._grade.material as ShaderMaterial).get_shader_parameter("aberration")) == 0.0, "paused frame has no color separation")
	get_tree().paused = false
	SaveService.data["reduced_flashes"] = true
	atmosphere.hit_pulse()
	atmosphere.flash(Color.WHITE, 0.6, 0.3)
	_check(not atmosphere._flash.visible and atmosphere._aberration == 0.0, "comfort setting also suppresses atmospheric flashes")
	arena.free()
