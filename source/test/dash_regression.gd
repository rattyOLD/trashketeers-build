extends Node

var failures := 0
var player: Player
var effects: DashEffects
var perks: Dictionary = {}

class Target:
	extends CharacterBody2D
	var hits := 0
	var damage := 0.0
	func _init() -> void:
		collision_layer = PhysicsLayers.ENEMY
		collision_mask = 0
		var shape := CircleShape2D.new()
		shape.radius = 12.0
		var body := CollisionShape2D.new()
		body.shape = shape
		add_child(body)
	func take_damage(amount: float, _direction: Vector2, _crit: bool) -> void:
		hits += 1
		damage += amount

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("DASH_REGRESSION FAIL: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	for upgrade in ContentDB.get_upgrades():
		if upgrade.category in ["dash", "dash_element"]:
			perks[upgrade.id] = upgrade
	_check(perks.size() == 6, "all six dash upgrades load")
	var stats := RunStats.new()
	for id in [&"dodge_blast", &"dodge_poison", &"dodge_shock"]:
		_check(not stats.is_available(perks[id]), "element requires impact " + str(id))
	stats.apply(perks[&"dodge_impact"])
	stats.apply(perks[&"dodge_shock"])
	stats.apply(perks[&"dodge_blast"])
	_check(stats.get_stat(&"dodge_blast") == 0.0, "exclusive branch enforced on apply")
	for i in 10:
		for id in perks:
			if id != &"dodge_poison" and id != &"dodge_blast":
				stats.apply(perks[id])
	_check(stats.get_stacks(&"dodge_impact") == 3 and stats.get_stat(&"dodge_damage") == 3.0, "impact capped at three")
	_check(stats.get_stat(&"dodge_cooldown") == 1.5 and is_equal_approx(stats.get_stat(&"dodge_distance"), 0.2), "cooldown and reach caps")
	for i in 30:
		for offer in stats.roll_choices(ContentDB.get_upgrades(), 3):
			_check(not perks.has(offer.id), "exhausted/excluded dash perks never offered")
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.setup(func(_at: Vector2) -> Node2D: return null, WeaponDB.get_weapon(&"pistol_v1"), stats)
	player.weapon_controller.set_process(false)
	player.weapon_controller.set_physics_process(false)
	_check(is_equal_approx(player.dash_cooldown, 3.5), "minimum cooldown 3.5 seconds")
	stats.uncapped = true
	stats.add_flat(&"dodge_cooldown", 1000.0)
	stats.add_flat(&"dodge_distance", 1000.0)
	player.apply_run_stats(stats)
	_check(is_equal_approx(player.dash_cooldown, 3.5) and is_equal_approx(player._dash_distance_mult, 1.2), "runtime caps survive tester/flat bonuses")
	for hero in CharacterDB.all():
		player.dash_remaining = 0.0
		player._dash_left = 0.0
		var skill := HeroSkills.new()
		add_child(skill)
		skill.setup(str(hero["id"]), player, null, stats, func(_amount: float) -> void: pass)
		var before := skill.fraction()
		_check(player.try_dash(), "dash available for " + str(hero["id"]))
		_check(is_equal_approx(before, skill.fraction()), "dash preserves hero skill cooldown")
		_check(not player.try_dash(), "cooldown prevents repeated activation")
		skill.queue_free()
	player._dash_left = 0.0
	player.dash_remaining = 0.0
	player.stun(1.0)
	_check(not player.try_dash(), "stun blocks dash")
	player._stun = 0.0
	player.is_falling = true
	_check(not player.try_dash(), "fall blocks dash")
	player.is_falling = false
	player.is_dead = true
	_check(not player.try_dash(), "death blocks dash")
	player.is_dead = false
	get_tree().paused = true
	_check(not player.try_dash(), "pause blocks dash")
	get_tree().paused = false
	player.apply_run_stats(RunStats.new())
	player.position = Vector2.ZERO
	player.move_input = Vector2.RIGHT
	_check(player.try_dash(), "open ground dash starts")
	player.move_input = Vector2.ZERO
	await _frames(18)
	_check(absf(player.position.x - 171.6) < 15.0 and absf(player.position.y) < 1.0, "dash distance independent of walk speed/frame end")
	var remaining := player.dash_remaining
	get_tree().paused = true
	await get_tree().create_timer(0.15, true).timeout
	_check(is_equal_approx(player.dash_remaining, remaining), "cooldown freezes in background pause")
	get_tree().paused = false
	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var box := RectangleShape2D.new()
	box.size = Vector2(12, 400)
	var shape := CollisionShape2D.new()
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector2(100, 0)
	add_child(wall)
	player.position = Vector2.ZERO
	player.dash_remaining = 0.0
	await _frames(2)
	player.move_input = Vector2.RIGHT
	player.try_dash()
	player.move_input = Vector2.ZERO
	await _frames(18)
	_check(player.position.x < 80.0 and player.position.x > 60.0, "dash collides with walls")
	wall.queue_free()
	player.set_physics_process(false)
	var contact_stats := RunStats.new()
	contact_stats.apply(perks[&"dodge_impact"])
	effects = DashEffects.new()
	add_child(effects)
	effects.setup(player, contact_stats, null)
	var targets: Array[Target] = []
	for i in 12:
		var target := Target.new()
		target.position = Vector2(250 + i * 20, 300)
		add_child(target)
		targets.append(target)
	await _frames(2)
	player.dash_started.emit()
	effects._on_moved(Vector2(200, 300), Vector2(520, 300))
	effects._on_moved(Vector2(200, 300), Vector2(520, 300))
	var contacts := 0
	for target in targets:
		contacts += target.hits
		_check(target.hits <= 1 and target.damage <= 18.0, "each target hit once per dash")
	_check(contacts == 8, "swept hit catches skipped targets with eight target limit")
	for target in targets:
		target.queue_free()
	await _frames(2)
	var primary := Target.new()
	primary.position = Vector2(100, 300)
	add_child(primary)
	var neighbors: Array[Target] = []
	for i in 4:
		var target := Target.new()
		target.position = Vector2(100 + i * 16, 380)
		add_child(target)
		neighbors.append(target)
	contact_stats.apply(perks[&"dodge_shock"])
	await _frames(2)
	player.dash_started.emit()
	effects._on_moved(Vector2(60, 300), Vector2(130, 300))
	effects._on_moved(Vector2(60, 300), Vector2(130, 300))
	var jumps := 0
	for target in neighbors:
		jumps += target.hits
	_check(jumps == 2 and primary.hits == 1, "lightning jumps to two extra targets once per dash")
	var blast_stats := RunStats.new()
	blast_stats.apply(perks[&"dodge_impact"])
	blast_stats.apply(perks[&"dodge_blast"])
	effects._stats = blast_stats
	primary.hits = 0
	primary.damage = 0.0
	for target in neighbors:
		target.hits = 0
		target.damage = 0.0
		target.position.y = 350.0
	await _frames(2)
	player.dash_started.emit()
	effects._on_moved(Vector2(60, 300), Vector2(130, 300))
	effects._on_moved(Vector2(60, 300), Vector2(130, 300))
	_check(primary.hits == 2 and is_equal_approx(primary.damage, 32.0), "blast triggers only once at first contact")
	for target in neighbors:
		_check(target.hits == 1 and target.damage <= 14.0, "blast radius/damage bounded")
	primary.queue_free()
	for target in neighbors:
		target.queue_free()
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.activate(ContentDB.get_enemy(ContentDB.get_enemy_ids()[0]), Vector2(2000, 2000), 100.0)
	enemy.set_physics_process(false)
	enemy.add_poison(2.0, 5.0, 4)
	enemy.add_poison(2.0, 5.0, 4)
	for i in 8:
		enemy.add_dash_poison(7.0)
	_check(enemy.poison_stacks == 2 and enemy.poison_dps == 2.0 and enemy.dash_poison_dps == 7.0, "dash poison does not stack or multiply weapon poison")
	var before_hp := enemy.hp
	enemy._tick_status(0.5)
	_check(before_hp - enemy.hp <= 5.5, "combined poison tick remains bounded")
	for i in 7:
		enemy._tick_status(0.5)
	_check(enemy.dash_poison_left == 0.0 and enemy.dash_poison_dps == 0.0, "dash poison expires")
	enemy.queue_free()
	var legacy := Controls.default_config()
	legacy["layout_v"] = 10
	legacy["keys"] = {"dash": [KEY_SPACE, KEY_SHIFT]}
	SaveService.data["controls"] = legacy
	_check(Controls.keys_for(&"dash") == [KEY_SPACE, KEY_SHIFT] and Controls.keys_for(&"dodge") == [KEY_C], "old skill bindings survive without dash conflicts")
	_check(Controls.config().has("landscape_layout_backup"), "old landscape layout backed up")
	print("DASH_REGRESSION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
