extends Node
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL DAMAGE_ATTRIBUTION ", label)
func _ready() -> void:
	var report := CombatReport.new()
	var enemy := Enemy.new()
	enemy.data = ContentDB.get_enemy(&"rat_punk")
	enemy.pool_index = 0
	enemy.hp = 100.0
	enemy.max_hp = 100.0
	enemy.damage_reported.connect(report.record_actual)
	Enemy.next_source = &"pistol_v1"
	enemy.take_damage(30.0)
	_check(is_equal_approx(report.enemy_damage, 30.0), "actual HP")
	_check(Enemy.next_source == &"", "context consumed")
	Enemy.next_source = &"pistol_v1"
	enemy.take_damage(1000.0)
	_check(is_equal_approx(report.enemy_damage, 100.0), "overkill excluded")
	Enemy.next_source = &"trash_shotgun_v1"
	enemy.take_damage(1.0)
	_check(Enemy.next_source == &"" and is_equal_approx(report.enemy_damage, 100.0), "dead target consumes context")
	var rows := report.contribution_rows()
	_check(rows.size() == 1 and rows[0]["source"] == &"pistol_v1" and rows[0]["ratio"] == 1.0, "weapon aggregation")
	enemy.hp = 100.0
	enemy.add_poison(10.0, 3.0, 3, &"pistol_v1")
	enemy.add_poison(2.0, 5.0, 3, &"trash_shotgun_v1")
	_check(enemy.poison_source == &"pistol_v1", "stronger poison keeps origin")
	enemy._take_dot(10.0, "poison", enemy.poison_source)
	_check(is_equal_approx(report.enemy_damage, 110.0), "dot recorded once")
	enemy.free()
	var bullet_report := CombatReport.new()
	var victim := Enemy.new()
	victim.data = ContentDB.get_enemy(&"rat_punk")
	victim.pool_index = 0
	victim.hp = 200.0
	victim.max_hp = 200.0
	victim.damage_reported.connect(bullet_report.record_actual)
	var bullet := Bullet.new()
	bullet.weapon = WeaponDB.get_weapon(&"pistol_v1").duplicate_data()
	bullet.weapon.crit_chance = 0.0
	bullet.weapon.damage = 25.0
	bullet.velocity = Vector2.RIGHT
	bullet._apply_damage(victim)
	_check(is_equal_approx(bullet_report.enemy_damage, 25.0) and bullet_report.damage_by_source.has(&"pistol_v1"), "actual projectile routes origin")
	bullet.weapon.damage_source = &"skill:turret"
	bullet._apply_damage(victim)
	_check(is_equal_approx(float(bullet_report.damage_by_source.get(&"skill:turret", 0.0)), 25.0), "turret origin survives derived weapon")
	bullet.free()
	var nested_report := CombatReport.new()
	victim.damage_reported.disconnect(bullet_report.record_actual)
	victim.damage_reported.connect(nested_report.record_actual)
	victim.hp = 100.0
	var nested := [false]
	victim.damaged.connect(func(_enemy: Enemy, _amount: float, _crit: bool, _kind: StringName) -> void:
		if not nested[0]:
			nested[0] = true
			Enemy.next_source = &"skill:hero"
			victim.take_damage(100.0))
	Enemy.next_source = &"pistol_v1"
	victim.take_damage(30.0)
	_check(is_equal_approx(nested_report.enemy_damage, 100.0), "nested reaction cannot distort outer HP snapshot")
	_check(is_equal_approx(float(nested_report.damage_by_source.get(&"pistol_v1", 0.0)), 30.0) and is_equal_approx(float(nested_report.damage_by_source.get(&"skill:hero", 0.0)), 70.0), "nested source separation")
	victim.free()
	var count_before := report.enemy_damage
	report.record_actual(100.0, &"", &"cleanup")
	_check(report.enemy_damage == count_before, "cleanup HP excluded")
	for i in 500:
		var identity := StringName("mod-%d" % i)
		var weapon := WeaponData.new()
		weapon.id = identity
		weapon.display_name = str(identity)
		WeaponDB._weapons[identity] = weapon
		report.record_actual(1.0, &"other", identity)
	var total := 0.0
	for row: Dictionary in report.contribution_rows(): total += float(row["amount"])
	_check(report.damage_by_source.size() <= CombatReport.SOURCE_LIMIT and is_equal_approx(total, report.enemy_damage), "bounded complete totals")
	print("DAMAGE_ATTRIBUTION failures=%d" % failures)
	get_tree().quit(failures)
