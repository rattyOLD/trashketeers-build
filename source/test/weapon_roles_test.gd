extends Node2D
var failures := 0
var shots := 0

class Target:
	extends Node2D
	var damage := 0.0
	func take_damage(amount: float, _direction: Vector2, _crit: bool) -> void:
		damage += amount

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("WEAPON_ROLES: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	BulletPool.set_physics_process(false)
	var wc := WeaponController.new()
	add_child(wc)
	wc.set_physics_process(false)
	wc.setup(func(_at: Vector2, _range: float) -> Node2D: return null, WeaponDB.get_weapon(&"trash_shotgun_v1"), RunStats.new())
	wc.fired.connect(func(_w: WeaponData, _at: Vector2, _dir: Vector2) -> void: shots += 1)
	var original := wc.base_weapon.damage
	wc.weapon.projectiles_per_shot = 1
	wc.weapon.spread_rad = 0.0
	wc.weapon.crit_chance = 0.0
	wc.trigger = true
	wc.manual_aim = Vector2.RIGHT
	var damage: Array[float] = []
	for distance in [35.0, 150.0, 280.0]:
		wc._cooldown = 0.0
		wc._physics_process(1.0 / 60.0)
		_check(BulletPool.get_active_count() == 1, "unassisted manual shot spawns a projectile")
		var bullet: Bullet = BulletPool._active.back()
		var target := Target.new()
		add_child(target)
		target.position = Vector2(distance, 0)
		bullet._apply_damage(target)
		damage.append(target.damage)
		var expected := wc.weapon.damage * lerpf(1.9, 0.55, distance / wc.weapon.max_distance)
		_check(is_equal_approx(target.damage, expected), "actual impact distance determines damage")
		target.damage = 0.0
		target.position.x = 35.0
		bullet.damage_scale = 1.25
		bullet._apply_damage(target)
		_check(is_equal_approx(target.damage, wc.weapon.damage * lerpf(1.9,0.55,35.0/wc.weapon.max_distance) * 1.25), "piercing/ricochet hit recomputes distance without stacking falloff")
		target.free()
		BulletPool.release_all()
	_check(damage[0] > damage[1] and damage[1] > damage[2], "closing the distance gives more actual damage")
	_check(wc.base_weapon.damage == original, "base configuration remains immutable")
	var reused := BulletPool.spawn(WeaponDB.get_weapon(&"pistol_v1"), Vector2.ZERO, Vector2.RIGHT)
	_check(not reused.close_origin.is_finite(), "recycled projectile does not retain a shotgun origin")
	BulletPool.release_all()
	for id: StringName in [&"smg_v1", &"golden_smg_v1", &"tommy_v1", &"ak_v1", &"lmg_v1", &"minigun_v1"]:
		_check(WeaponFeel.automatic(WeaponDB.get_weapon(id)), "automatic gun uses its recoil/flash profile: " + String(id))
	# The same impact multiplier must reach the tactical effect subscriber.
	var run := RunStats.new()
	for upgrade in ContentDB.get_upgrades():
		if upgrade.id == &"tactic_arson":
			run.apply(upgrade)
	var tactics := CombatTactics.new()
	tactics.stats = run
	add_child(tactics)
	BulletPool.bullet_hit.connect(tactics._on_hit)
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.activate(ContentDB.get_enemy(&"rat_punk"), Vector2(35,0),100.0)
	enemy.set_physics_process(false)
	wc._cooldown = 0.0
	wc._physics_process(1.0 / 60.0)
	var close_bullet: Bullet = BulletPool._active.back()
	close_bullet._apply_damage(enemy)
	var expected_burn := 5.0 + wc.weapon.damage * lerpf(1.9,0.55,35.0/wc.weapon.max_distance) * 0.12
	_check(enemy.bleed_is_burn and is_equal_approx(enemy.bleed_dps,expected_burn), "fire tactic receives the actual close-range impact multiplier")
	BulletPool.release_all()
	tactics.free()
	enemy.free()
	var spins: Array[float] = []
	for fast in [false, true]:
		var gun := WeaponDB.get_weapon(&"ak_v1").duplicate_data()
		if fast:
			gun.fire_interval *= 0.5
		wc.set_base_weapon(gun)
		var first := shots
		for tick in 60:
			wc._physics_process(1.0 / 60.0)
			BulletPool.release_all()
		spins.append(wc._spin_up)
		var first_second := shots - first
		first = shots
		for tick in 60:
			wc._physics_process(1.0 / 60.0)
			BulletPool.release_all()
		_check(shots - first > first_second, "holding fire increases actual shot frequency")
		_check(is_equal_approx(wc._spin_up, 1.0), "full spin after two seconds")
		wc.trigger = false
		for tick in 75:
			wc._physics_process(1.0 / 60.0)
		_check(is_zero_approx(wc._spin_up), "release cools the gun")
		wc.trigger = true
	_check(is_equal_approx(spins[0], 0.5) and is_equal_approx(spins[1], 0.5), "spin-up time is independent of fire-rate upgrades")
	wc._spin_up = 1.0
	wc.set_slot(1, WeaponDB.get_weapon(&"sniper_v1"))
	wc.switch_slot(1)
	_check(wc._spin_up == 0.0 and wc._still_time == 0.0, "switching starts a new weapon's preparation")
	_check(is_equal_approx(wc._trait_scale(0.0), 0.75), "precision shot starts without a stationary bonus")
	wc.trigger = false
	for tick in 60:
		wc._physics_process(1.0 / 60.0)
	_check(is_equal_approx(wc._trait_scale(0.0), 2.0), "holding position charges precision damage")
	wc.position.x += 10.0
	wc._physics_process(1.0 / 60.0)
	_check(is_equal_approx(wc._trait_scale(0.0), 0.75), "movement removes precision damage")
	wc.queue_free()
	BulletPool.release_all()
	for frame in 4:
		await get_tree().process_frame
	print("WEAPON_ROLES failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)
