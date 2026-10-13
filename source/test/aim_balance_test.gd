extends Node2D
## Реальные коллизии, ручное направление и измерение ролей на одинаковой мишени.
var failures := 0
var candidates: Array = []
var finder_calls := 0
var path_checks := 0
var wc: WeaponController
var report: Array = []

class Target:
	extends StaticBody2D
	var damage := 0.0
	func _init() -> void:
		collision_layer = PhysicsLayers.ENEMY
		collision_mask = 0
		var shape := CircleShape2D.new()
		shape.radius = 12.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
	func is_targetable() -> bool: return true
	func take_damage(amount: float, _direction: Vector2, _crit: bool) -> void: damage += amount

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("AIM_BALANCE: " + label)

func _ready() -> void:
	_run.call_deferred()

func _target(at: Vector2) -> Target:
	var target := Target.new()
	add_child(target)
	target.position = at
	return target

func _find(_from: Vector2, _range: float) -> Node2D:
	return candidates[0] if not candidates.is_empty() else null

func _directed(from: Vector2, reach: float, direction: Vector2, cosine: float, clear: Callable) -> Node2D:
	finder_calls += 1
	return AimAssist.select(candidates, from, direction, reach, cosine, clear)

func _never_clear(_target: Node2D) -> bool:
	path_checks += 1
	return false

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _fresh(id: StringName) -> void:
	BulletPool.release_all()
	wc.position = Vector2.ZERO
	wc.setup(_find, WeaponDB.get_weapon(id), RunStats.new())
	wc.aim_target_finder = _directed
	wc.weapon.crit_chance = 0.0
	wc.trigger = true
	wc.manual_aim = Vector2.RIGHT

func _measure(id: StringName, distance: float, moving: bool = false) -> float:
	var target := _target(Vector2(distance, 0))
	candidates = [target]
	_fresh(id)
	await _wait(0.04)
	for tick in 120:
		if moving:
			wc.position.x = float(tick % 2)
		wc._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
	await _wait(0.6)
	var dps := target.damage / 2.0
	report.append({"weapon": String(id), "distance": distance, "moving": moving, "damage": target.damage, "dps": dps})
	print("BALANCE_MEASURE ", report.back())
	BulletPool.release_all()
	target.free()
	candidates.clear()
	return dps

func _run() -> void:
	wc = WeaponController.new()
	add_child(wc)
	wc.set_physics_process(false)
	# A threatening/closer enemy outside the cone must not suppress the aimed one.
	var side := _target(Vector2(0, 70))
	var front := _target(Vector2(180, 0))
	candidates = [side, front]
	_fresh(&"pistol_v1")
	wc.muzzle_provider = func(_dir: Vector2) -> Vector2: return Vector2(44,-25)
	await _wait(0.05)
	wc._physics_process(1.0 / 60.0)
	_check(wc._target == front, "manual aim selects the enemy under the crosshair")
	var line := AimLine.new()
	line.controller = wc
	add_child(line)
	line.set_process(false)
	line._process(1.0 / 60.0)
	var actual: Bullet = BulletPool._active.back()
	_check(line._from.is_equal_approx(actual.global_position) and line._dir.dot(actual.velocity.normalized()) > 0.999, "aim line matches actual muzzle parallax and projectile origin")
	line.free()
	await _wait(0.4)
	_check(front.damage > 0.0 and side.damage == 0.0, "actual projectile hits the aimed enemy")
	front.position = Vector2(0, -180)
	wc.manual_aim = Vector2.UP
	wc._physics_process(1.0 / 60.0)
	_check(wc._target == front and wc.aim_direction.dot(Vector2.UP) > 0.999, "turning the stick reacquires immediately")
	BulletPool.release_all()
	wc.muzzle_provider = Callable()
	side.free()
	front.free()
	candidates.clear()
	var near := _target(Vector2(90,18))
	var exact := _target(Vector2(180,0))
	_check(AimAssist.select([near,exact], Vector2.ZERO, Vector2.RIGHT,500.0,0.97) == exact, "default preference follows the crosshair")
	_check(AimAssist.select([near,exact], Vector2.ZERO, Vector2.RIGHT,500.0,0.97,Callable(),true) == near, "nearest preference still works inside the manual cone")
	near.free()
	exact.free()
	# A miss is cached too; holding a fixed direction in empty space is not 60 scans/s.
	_fresh(&"pistol_v1")
	finder_calls = 0
	for tick in 60:
		wc._physics_process(1.0 / 60.0)
		BulletPool.release_all()
	_check(finder_calls <= 11, "empty cone searches stay at the retarget cadence")
	var crowd: Array = []
	for index in 12:
		crowd.append(_target(Vector2(200 + index, 0)))
	path_checks = 0
	_check(AimAssist.select(crowd, Vector2.ZERO, Vector2.RIGHT, 500.0, 0.97, _never_clear) == null and path_checks == AimAssist.MAX_CANDIDATES, "occluded crowd has a bounded ray budget")
	for target in crowd: target.free()
	# A long drawn muzzle must not put a bullet behind a nearby body, even without assist.
	side = _target(Vector2(0, 100))
	front = _target(Vector2(25, 0))
	candidates = [side, front]
	_fresh(&"pistol_v1")
	wc.aim_target_finder = Callable()
	wc.muzzle_provider = func(_direction: Vector2) -> Vector2: return Vector2(70, 0)
	await _wait(0.05)
	wc._physics_process(1.0 / 60.0)
	_check(BulletPool._active.back().global_position.x <= WeaponController.POINT_BLANK_SPAWN, "unassisted shot starts before the near body")
	await _wait(0.2)
	_check(front.damage > 0.0, "point-blank projectile actually deals damage")
	BulletPool.release_all()
	wc.muzzle_provider = Callable()
	side.free()
	front.free()
	# Flying enemies' colliders and artwork sit above their ground position.
	var flyer := Enemy.new()
	add_child(flyer)
	flyer.activate(ContentDB.get_enemy(&"dropper"), Vector2(180,46),100.0)
	candidates = [flyer]
	_fresh(&"pistol_v1")
	await _wait(0.05)
	var hp := flyer.hp
	wc._physics_process(1.0 / 60.0)
	_check(absf(wc.aim_direction.y) < 0.001, "flying target aims at the body rather than its shadow")
	await _wait(0.4)
	_check(flyer.hp < hp, "actual shot hits a hovering enemy")
	BulletPool.release_all()
	flyer.free()
	# The best angular target behind a wall cannot steal aim from a visible one.
	front = _target(Vector2(200,0))
	side = _target(Vector2(120,26))
	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var box := RectangleShape2D.new()
	box.size = Vector2(8,12)
	var collision := CollisionShape2D.new()
	collision.shape = box
	wall.add_child(collision)
	add_child(wall)
	wall.position = Vector2(60,0)
	candidates = [front,side]
	_fresh(&"pistol_v1")
	await _wait(0.05)
	wc._physics_process(1.0 / 60.0)
	_check(wc._target == side, "visible target wins over occluded angular target")
	await _wait(0.4)
	_check(side.damage > 0.0 and front.damage == 0.0, "visible target is hit while the wall protects the other")
	BulletPool.release_all()
	wall.free()
	front.free()
	side.free()
	candidates.clear()
	var crate := _target(Vector2(180,0))
	crate.collision_layer = PhysicsLayers.OBSTACLE
	candidates = [crate]
	_fresh(&"pistol_v1")
	await _wait(0.05)
	wc._physics_process(1.0 / 60.0)
	_check(wc._target == crate, "destructible endpoint is not mistaken for intervening cover")
	await _wait(0.4)
	_check(crate.damage > 0.0, "aimed destructible receives the actual shot")
	BulletPool.release_all()
	crate.free()
	candidates.clear()
	front = _target(Vector2(180,0))
	var shield := Area2D.new()
	shield.collision_layer = PhysicsLayers.SHIELD
	shield.collision_mask = 0
	shield.monitoring = false
	var field := CircleShape2D.new()
	field.radius = 40.0
	var field_collision := CollisionShape2D.new()
	field_collision.shape = field
	shield.add_child(field_collision)
	add_child(shield)
	shield.position = Vector2(60,0)
	candidates = [front]
	_fresh(&"pistol_v1")
	await _wait(0.05)
	wc._physics_process(1.0 / 60.0)
	_check(wc._target == front and is_equal_approx(wc.shot_origin.x, WeaponController.MUZZLE_DISTANCE), "friendly raid shield passes player aim and muzzle clearance")
	await _wait(0.4)
	_check(front.damage > 0.0, "player projectile passes through friendly shield")
	BulletPool.release_all()
	shield.free()
	front.free()
	candidates.clear()
	# Fully warmed spin + multishot/rate upgrades must respect the same 70/s budget.
	BulletPool.set_physics_process(false)
	wc.trigger = true
	wc.manual_aim = Vector2.RIGHT
	for multishot in [true, false]:
		var run := RunStats.new()
		run.add_flat(&"fire_rate_mult", 1.0)
		if multishot: run.add_flat(&"extra_projectiles", 3.0)
		wc.setup(_find, WeaponDB.get_weapon(&"minigun_v1"), run)
		wc._spin_up = 1.0
		var count := 0
		var damage := 0.0
		var expected := wc.weapon.damage * wc.weapon.projectiles_per_shot / (wc.weapon.fire_interval * 0.6)
		for tick in 300:
			wc._physics_process(1.0 / 60.0)
			for bullet: Bullet in BulletPool._active:
				count += 1
				damage += bullet.weapon.damage * bullet.damage_scale
			BulletPool.release_all()
		_check(count <= 5.0 * WeaponData.BULLET_BUDGET_PER_SEC + wc.weapon.projectiles_per_shot, "spin and upgrades do not bypass projectile budget")
		_check(absf(damage / 5.0 / expected - 1.0) < 0.03, "60 Hz cadence/budget preserves warmed raw DPS")
		report.append({"weapon":"minigun_v1 + rate/multishot" if multishot else "minigun_v1 + rate", "projectiles_per_second":count/5.0, "damage_per_second":damage/5.0, "expected":expected})
	BulletPool.set_physics_process(true)
	# Risk and position must really matter on the same collider, not just in the card text.
	var pistol_near := await _measure(&"pistol_v1", 70.0)
	var pistol_far := await _measure(&"pistol_v1", 260.0)
	var shotgun_near := await _measure(&"trash_shotgun_v1", 70.0)
	var shotgun_far := await _measure(&"trash_shotgun_v1", 260.0)
	_check(shotgun_near > pistol_near * 1.3, "close-risk shotgun outdamages the safe starting pistol nearby")
	_check(shotgun_far < pistol_far * 0.8, "pistol is more reliable at a distance")
	var focus_still := await _measure(&"sniper_v1", 220.0)
	var focus_moving := await _measure(&"sniper_v1", 220.0, true)
	_check(focus_still > focus_moving * 1.5, "precision weapon rewards holding a position")
	if not OS.get_environment("BALANCE_OUT").is_empty():
		var file := FileAccess.open(OS.get_environment("BALANCE_OUT"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	wc.queue_free()
	BulletPool.release_all()
	for frame in 4: await get_tree().process_frame
	print("AIM_BALANCE failures=", failures)
	get_tree().quit.call_deferred(1 if failures else 0)
