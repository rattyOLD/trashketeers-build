class_name StatusSystem
extends Node
## Боевые механики забега: яд, кровотечение, холод, взрывы, цепная молния, вампиризм.
## Читает бонусы из RunStats, вешает состояния на Enemy (тик состояний живёт в самом враге)
## и реагирует на смерти. Всё без аллокаций узлов: только пулы FX и уже существующие враги.

const POISON_DURATION := 4.0
const POISON_MAX_STACKS := 6
const POISON_DPS_RATIO := 0.35
const BLEED_DPS_RATIO := 0.5
const BLEED_DURATION := 3.0
const BURN_DURATION := 2.6
const BURN_CHANCE_RATIO := 0.9
const SLOW_AMOUNT := 0.35
## Пассивка Снежного Пломбира: постоянный мороз вокруг героя.
const FROST_RADIUS := 170.0
const FROST_SLOW := 0.28
const FROST_INTERVAL := 0.3
const EXECUTE_HP := 0.25
var _frost_aura := false
var _execute_shot := false
var _frost_tick := 0.0
const SLOW_DURATION := 2.0
const SHOCK_RANGE := 210.0
const SHOCK_DAMAGE_RATIO := 0.7
const SHOCK_BASE_JUMPS := 2
const BLAST_RADIUS := 66.0
const BLAST_DAMAGE_RATIO := 0.6
const BLAST_COOLDOWN := 0.14
const SHOCK_COOLDOWN := 0.1
const DEATH_BLAST_RADIUS := 108.0
const TOXIC_RADIUS := 135.0
const MAX_BLAST_DEPTH := 2
const NUMBER_BUDGET := 16.0
const COLOR_POISON := Color("#7cff3d")
const COLOR_BLEED := Color("#ff3b5c")
const COLOR_SLOW := Color("#9ad8ff")
const COLOR_SHOCK := Color("#35e6ff")
const COLOR_BLAST := Color("#ff8a1f")

var stats: RunStats
var player: Player
var enemies: EnemyManager
var fx: FxManager

var _heal_budget := 0.0
var _number_budget := NUMBER_BUDGET
var _blast_cd := 0.0
var _shock_cd := 0.0
var _blast_depth := 0
var extra_shock := 0.0
var extra_poison := 0.0
var extra_regen := 0.0
var _regen_acc := 0.0
var _heal_acc := 0.0
var _heal_popup_cd := 0.0
var _hit_buffer: Array[Enemy] = []


func setup(run_stats: RunStats, target_player: Player, enemy_manager: EnemyManager, effects: FxManager) -> void:
	stats = run_stats
	_frost_aura = SaveService.get_character_id() == "snow"
	_execute_shot = SaveService.get_character_id() == "pigeon_mafioso"
	player = target_player
	enemies = enemy_manager
	fx = effects


func _physics_process(delta: float) -> void:
	if stats == null or player == null or player.is_dead:
		return
	if _frost_aura:
		_frost_tick -= delta
		if _frost_tick <= 0.0:
			_frost_tick = FROST_INTERVAL
			var r2 := FROST_RADIUS * FROST_RADIUS
			for enemy in enemies.get_active():
				if enemy.is_alive() and enemy.global_position.distance_squared_to(player.global_position) < r2:
					enemy.add_slow(FROST_SLOW, FROST_INTERVAL * 2.0)
	_blast_cd -= delta
	_heal_popup_cd -= delta
	_shock_cd -= delta
	_number_budget = minf(_number_budget + NUMBER_BUDGET * delta, NUMBER_BUDGET)
	_heal_budget = minf(_heal_budget + (3.0 + player.max_hp * 0.04) * delta, 12.0 + player.max_hp * 0.1)
	var regen := stats.get_stat(&"regen") + extra_regen
	if regen > 0.0 and player.hp < player.max_hp:
		_regen_acc += regen * delta
		if _regen_acc >= 0.5:
			player.heal(_regen_acc)
			_regen_acc = 0.0


func has_effects() -> bool:
	return stats != null


func power() -> float:
	return 1.0 + stats.get_stat(&"status_power")


## Пуля игрока попала во врага. Вызывается из обработчика BulletPool.bullet_hit.
func on_player_hit(bullet: Bullet, enemy: Enemy) -> void:
	if not enemy.is_alive() or bullet.weapon == null:
		return
	var weapon := bullet.weapon
	var crit := bullet.last_hit_crit
	var damage := weapon.damage * bullet.damage_scale * (weapon.crit_mult if crit else 1.0)
	_vampirism(damage, crit)
	if _execute_shot and crit and enemy.data.boss_pattern.is_empty() and enemy.hp < enemy.max_hp * EXECUTE_HP:
		enemy.take_damage(enemy.hp + 1.0, Vector2.ZERO, true)
		return
	var p := power()
	var at := enemy.get_aim_point()

	var poison_chance := stats.get_stat(&"poison_chance") + extra_poison
	if poison_chance > 0.0 and randf() < poison_chance:
		var per_stack := damage * POISON_DPS_RATIO * (1.0 + stats.get_stat(&"poison_power")) * p
		enemy.add_poison(per_stack, POISON_DURATION * (1.0 + 0.5 * (p - 1.0)), POISON_MAX_STACKS)
		fx.burst(at, COLOR_POISON, 3, 110.0, 3.0)

	var burning := enemy.bleed_left > 0.0
	var burn_vamp := stats.get_stat(&"burn_vamp")
	if burning and burn_vamp > 0.0:
		_heal(damage * burn_vamp)
	var ignite := weapon.burn
	var burn_chance := stats.get_stat(&"burn_chance")
	if burn_chance > 0.0 and randf() < burn_chance:
		ignite += BURN_CHANCE_RATIO
	if ignite > 0.0:
		enemy.add_bleed(damage * ignite * p, BURN_DURATION * (1.0 + 0.25 * (p - 1.0)))
		if randf() < 0.12:
			fx.burst(at, COLOR_BLAST, 2, 120.0, 3.0)

	var bleed_chance := stats.get_stat(&"bleed_chance")
	if bleed_chance > 0.0 and (crit or randf() < bleed_chance):
		enemy.add_bleed(damage * BLEED_DPS_RATIO * p, BLEED_DURATION * p)
		fx.burst(at, COLOR_BLEED, 3, 130.0, 3.0)

	var slow_chance := stats.get_stat(&"slow_chance")
	if slow_chance > 0.0 and randf() < slow_chance:
		enemy.add_slow(SLOW_AMOUNT * minf(p, 1.6), SLOW_DURATION * p)
		fx.burst(at, COLOR_SLOW, 3, 90.0, 3.0)

	var explosive := stats.get_stat(&"explosive_chance")
	if explosive > 0.0 and _blast_cd <= 0.0 and randf() < explosive:
		_blast_cd = BLAST_COOLDOWN
		var boost := 1.0 + stats.get_stat(&"blast_power")
		_blast(enemy.global_position, BLAST_RADIUS * boost, damage * BLAST_DAMAGE_RATIO * boost, COLOR_BLAST)

	var shock := stats.get_stat(&"shock_chance") + extra_shock
	if shock > 0.0 and _shock_cd <= 0.0 and randf() < shock:
		_shock_cd = SHOCK_COOLDOWN
		_chain(enemy, damage * SHOCK_DAMAGE_RATIO)


func _vampirism(damage: float, crit: bool) -> void:
	var vamp := minf(stats.get_stat(&"vampirism"), 0.005)
	if vamp <= 0.0:
		return
	_heal(damage * vamp * (2.0 if crit else 1.0))


func _heal(amount: float) -> void:
	var given := minf(amount, _heal_budget)
	if given <= 0.0 or player.hp >= player.max_hp:
		return
	_heal_budget -= given
	var before := player.hp
	player.heal(given)
	_heal_acc += player.hp - before
	if _heal_acc >= 1.0 and _heal_popup_cd <= 0.0:
		_heal_popup_cd = 0.35
		fx.popup(player.global_position + Vector2(0, -70), "+%d" % int(_heal_acc), Color("#6dff8a"), 22.0)
		_heal_acc = 0.0


func _blast(at: Vector2, radius: float, damage: float, color: Color) -> void:
	_blast_depth += 1
	BulletPool.explode(at, radius, damage, Bullet.Team.PLAYER, color, 0.7)
	_blast_depth -= 1


func _chain(origin: Enemy, damage: float) -> void:
	var jumps := SHOCK_BASE_JUMPS + int(stats.get_stat(&"shock_jumps"))
	var freeze := stats.get_stat(&"evo_static_freeze") > 0.0
	_hit_buffer.clear()
	_hit_buffer.append(origin)
	var current := origin
	for i in jumps:
		var best: Enemy = null
		var best_d := SHOCK_RANGE * SHOCK_RANGE
		for candidate in enemies.get_active():
			if not candidate.is_alive() or _hit_buffer.has(candidate):
				continue
			var d := current.global_position.distance_squared_to(candidate.global_position)
			if d < best_d:
				best_d = d
				best = candidate
		if best == null:
			break
		_hit_buffer.append(best)
		fx.bolt(current.get_aim_point(), best.get_aim_point(), COLOR_SHOCK)
		current = best
	if _hit_buffer.size() <= 1:
		return
	SoundManager.play_pitched(&"hit", 2.3, -9.0)
	for i in range(1, _hit_buffer.size()):
		var target := _hit_buffer[i]
		if not target.is_alive():
			continue
		var amount := damage
		if freeze:
			if target.is_slowed():
				amount *= 2.0
			target.add_slow(SLOW_AMOUNT, 1.6 * power())
		fx.burst(target.get_aim_point(), COLOR_SHOCK, 5, 200.0, 3.0)
		target.take_damage(amount, Vector2.ZERO, false)
	_hit_buffer.clear()


## Состояние нанесло урон: цифры, пузырьки, лечение вампиризмом от яда (эволюция).
func on_status_damage(enemy: Enemy, amount: float, kind: String) -> void:
	var color := COLOR_POISON if kind == "poison" else COLOR_BLEED
	var at := enemy.get_aim_point()
	if _number_budget >= 1.0:
		_number_budget -= 1.0
		fx.status_number(at + Vector2(0, -enemy.data.radius * 1.2), amount, color)
	fx.burst(at, color, 2, 70.0, 2.5)
	if kind == "poison" and stats.get_stat(&"evo_vamp_poison") > 0.0:
		_heal(amount * clampf(stats.get_stat(&"vampirism"), 0.002, 0.005) * 3.0)


## Враг погиб (любой причиной). at — где он стоял.
func on_enemy_died(enemy: Enemy, at: Vector2) -> void:
	if enemy.data == null or enemy.data.is_boss():
		return
	var kill_heal := stats.get_stat(&"kill_heal")
	if kill_heal > 0.0:
		_heal(kill_heal * (1.0 + 0.004 * player.max_hp))
	var poisoned := enemy.is_poisoned()
	var toxic := stats.get_stat(&"evo_toxic_burst") > 0.0 and poisoned
	var chance := stats.get_stat(&"explosive_chance") * 0.5
	if toxic:
		_toxic_cloud(at)
	elif _blast_depth < MAX_BLAST_DEPTH and chance > 0.0 and randf() < chance / float(_blast_depth + 1):
		var boost := 1.0 + stats.get_stat(&"blast_power")
		var damage := clampf(enemy.max_hp * 0.4, 25.0, 260.0) * boost
		_blast(at, DEATH_BLAST_RADIUS * boost, damage, COLOR_BLAST)


func _toxic_cloud(at: Vector2) -> void:
	if _blast_depth >= MAX_BLAST_DEPTH:
		return
	var boost := 1.0 + stats.get_stat(&"blast_power")
	var radius := TOXIC_RADIUS * boost
	fx.burst(at, COLOR_POISON, 26, 380.0, 4.5)
	fx.ring(at, COLOR_POISON, radius)
	fx.splat(at, COLOR_POISON.darkened(0.15), radius * 0.6)
	SoundManager.play(&"acid_splash", -2.0)
	var per_stack := 6.0 * (1.0 + stats.get_stat(&"poison_power")) * power()
	var damage := 30.0 * boost
	_blast_depth += 1
	for candidate in enemies.get_active().duplicate():
		if not candidate.is_alive() or candidate.global_position.distance_squared_to(at) > radius * radius:
			continue
		for i in 3:
			candidate.add_poison(per_stack, POISON_DURATION * power(), POISON_MAX_STACKS)
		candidate.take_damage(damage, (candidate.global_position - at).normalized() * 0.6, false)
	_blast_depth -= 1
