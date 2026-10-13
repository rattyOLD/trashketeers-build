extends Node2D
## Настоящие выстрелы: независимое восстановление, доставание и пауза.
var failures := 0
var shots: Array[StringName] = []
var wc: WeaponController

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("WEAPON_SWITCH: " + label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _advance(seconds: float) -> void:
	for step in roundi(seconds * 100.0):
		wc._physics_process(0.01)
		BulletPool.release_all()

func _run() -> void:
	BulletPool.set_physics_process(false)
	wc = WeaponController.new()
	wc.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(wc)
	wc.set_physics_process(false)
	var slow := WeaponDB.get_weapon(&"sniper_v1").duplicate_data()
	slow.fire_interval = 1.0
	var fast := WeaponDB.get_weapon(&"smg_v1").duplicate_data()
	fast.fire_interval = 0.1
	wc.setup(func(_at: Vector2, _range: float) -> Node2D: return null, slow, RunStats.new())
	wc.slot_count = 3
	wc.set_slot(1, fast)
	wc.set_slot(2, WeaponDB.get_weapon(&"pistol_v1"))
	wc.fired.connect(func(w: WeaponData, _at: Vector2, _dir: Vector2) -> void: shots.append(w.id))
	wc.trigger = true
	wc.manual_aim = Vector2.RIGHT
	_advance(0.01)
	_check(shots == [slow.id], "initial gun fires immediately")
	_advance(0.1)
	wc.switch_slot(1)
	_advance(0.21)
	_check(shots.size() == 1, "drawing the backup cannot fire early")
	_advance(0.02)
	_check(shots == [slow.id, fast.id], "ready backup does not wait for the sniper")
	wc.switch_slot(0)
	_advance(0.23)
	_check(shots.size() == 2, "returning to sniper preserves its own recovery")
	_advance(0.46)
	_check(shots.size() == 3 and shots.back() == slow.id, "sniper fires once its background recovery finishes")
	# Repeated rapid switches cannot erase the last shot's recovery.
	for attempt in 10:
		wc.switch_slot(1)
		_advance(0.01)
		wc.switch_slot(0)
		_advance(0.01)
	_advance(0.23)
	_check(shots.size() == 3, "rapid switching never shortcuts the slow gun")
	_advance(0.6)
	_check(shots.size() == 4, "normal fire resumes without releasing the trigger")
	# A stats refresh must not cap a spin-adjusted timer to the base interval.
	wc.trigger = false
	wc.set_slot(2, WeaponDB.get_weapon(&"ak_v1"))
	wc.switch_slot(2)
	wc._cooldown = wc.weapon.fire_interval * 1.7
	var before := wc._cooldown
	wc.apply_run_stats(RunStats.new())
	_check(is_equal_approx(wc._cooldown, before), "stats refresh preserves recovery already in progress")
	wc.switch_slot(0)
	var stowed := wc._slot_cooldowns[2]
	_advance(0.05)
	_check(is_equal_approx(wc._slot_cooldowns[2], maxf(stowed - 0.05, 0.0)), "third slot also recovers in the background")
	before = wc._cooldown
	var equip_before := wc._equip_left
	_check(not wc.switch_slot(0) and not wc.switch_slot(-1) and not wc.switch_slot(3), "invalid/current selection does nothing")
	_check(wc._cooldown == before and wc._equip_left == equip_before, "ignored selections do not restart recovery or drawing")
	# Physics must stop on the actual tree pause, including stowed timers.
	wc.set_physics_process(true)
	get_tree().paused = true
	var paused_timers := wc._slot_cooldowns.duplicate()
	await get_tree().create_timer(0.15, true).timeout
	_check(wc._cooldown == before and wc._equip_left == equip_before and wc._slot_cooldowns == paused_timers, "upgrade pause freezes all weapon clocks")
	get_tree().paused = false
	await get_tree().create_timer(0.1).timeout
	_check(wc._equip_left < equip_before, "weapon clocks resume after pause")
	wc.queue_free()
	BulletPool.release_all()
	for frame in 4:
		await get_tree().process_frame
	print("WEAPON_SWITCH failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)
