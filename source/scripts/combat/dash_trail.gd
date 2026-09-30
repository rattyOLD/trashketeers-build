class_name DashTrail
extends Node2D
## Боевая часть рывка: урон по пути, ядовитые/огненные лужи-следы и взрывы на старте/финише.
## Зоны живут в фиксированном пуле, рисует их одна нода; враги — из EnemyManager без запросов физики.

const CAPACITY := 28
const ZONE_RADIUS := 48.0
const ZONE_LIFE := 2.8
const TICK := 0.3
const SPACING := 56.0
const BODY_RADIUS := 34.0
const KIND_POISON := 1
const KIND_FIRE := 2
const COLOR_POISON := Color("#7cff3d")
const COLOR_FIRE := Color("#ff8a1f")
const REFUND_GRACE := 0.4
const BLAST_BASE_RADIUS := 84.0
const BLAST_STEP_RADIUS := 22.0

var player: Player
var enemies: EnemyManager
var stats: RunStats
var fx: FxManager

var _pos := PackedVector2Array()
var _life := PackedFloat32Array()
var _kind := PackedByteArray()
var _next := 0
var _tick_timer := 0.0
var _since_zone := 0.0
var _alternate := 0
var _grace := 0.0
var _hit: Dictionary = {}
var _alive_zones := 0


func _init() -> void:
	z_index = -3
	z_as_relative = false
	_pos.resize(CAPACITY)
	_life.resize(CAPACITY)
	_kind.resize(CAPACITY)
	_life.fill(0.0)


func setup(target: Player, manager: EnemyManager, run_stats: RunStats, effects: FxManager) -> void:
	player = target
	enemies = manager
	stats = run_stats
	fx = effects
	player.dashed.connect(_on_dashed)
	player.dash_moved.connect(_on_moved)
	player.dash_ended.connect(_on_ended)


func on_enemy_died() -> void:
	if _grace <= 0.0 and not player.is_dashing():
		return
	var refund := stats.get_stat(&"dash_refund")
	if refund > 0.0:
		player.refund_dash(refund)


func _power() -> float:
	return 1.0 + stats.get_stat(&"damage_mult") * 0.5 + stats.get_stat(&"status_power") * 0.5


func _on_dashed() -> void:
	_hit.clear()
	_since_zone = SPACING
	_blast(player.global_position)


func _on_ended(at: Vector2) -> void:
	_grace = REFUND_GRACE
	_blast(at)


func _blast(at: Vector2) -> void:
	var stacks := stats.get_stat(&"dash_blast")
	if stacks <= 0.0:
		return
	var radius := BLAST_BASE_RADIUS + BLAST_STEP_RADIUS * stacks
	var damage := (35.0 + 25.0 * stacks) * _power()
	BulletPool.explode(at, radius, damage, Bullet.Team.PLAYER, COLOR_FIRE, 1.2)


func _on_moved(from: Vector2, to: Vector2) -> void:
	var damage := stats.get_stat(&"dash_damage") * _power()
	if damage > 0.0:
		var segment := to - from
		var length_sq := maxf(segment.length_squared(), 0.001)
		var direction := segment.normalized()
		for enemy in enemies.get_active():
			if not enemy.is_alive() or _hit.has(enemy.get_instance_id()):
				continue
			var t := clampf((enemy.global_position - from).dot(segment) / length_sq, 0.0, 1.0)
			var reach := BODY_RADIUS + enemy.data.radius
			if (from + segment * t).distance_squared_to(enemy.global_position) > reach * reach:
				continue
			_hit[enemy.get_instance_id()] = true
			enemy.take_damage(damage, direction * 1.4, false)
			fx.burst(enemy.get_aim_point(), Color("#8cf7ff"), 5, 240.0, 3.0)
	var poison := stats.get_stat(&"dash_poison") > 0.0
	var fire := stats.get_stat(&"dash_fire") > 0.0
	if not poison and not fire:
		return
	_since_zone += segment_length(from, to)
	if _since_zone < SPACING:
		return
	_since_zone = 0.0
	var kind := KIND_POISON if poison else KIND_FIRE
	if poison and fire:
		_alternate += 1
		kind = KIND_POISON if _alternate % 2 == 0 else KIND_FIRE
	_spawn_zone(to, kind)


func segment_length(from: Vector2, to: Vector2) -> float:
	return from.distance_to(to)


func _spawn_zone(at: Vector2, kind: int) -> void:
	_pos[_next] = at
	_life[_next] = ZONE_LIFE
	_kind[_next] = kind
	_next = (_next + 1) % CAPACITY
	fx.burst(at, COLOR_POISON if kind == KIND_POISON else COLOR_FIRE, 4, 120.0, 3.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)
	var live := 0
	for i in CAPACITY:
		if _life[i] > 0.0:
			_life[i] -= delta
			live += 1
	if live == 0 and _alive_zones == 0:
		return
	_alive_zones = live
	queue_redraw()
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = TICK
	var poison_stacks := stats.get_stat(&"dash_poison")
	var fire_stacks := stats.get_stat(&"dash_fire")
	var power := _power()
	for enemy in enemies.get_active():
		if not enemy.is_alive():
			continue
		var reach := ZONE_RADIUS + enemy.data.radius * 0.5
		for i in CAPACITY:
			if _life[i] <= 0.0 or _pos[i].distance_squared_to(enemy.global_position) > reach * reach:
				continue
			if _kind[i] == KIND_POISON:
				enemy.add_poison((6.0 + 5.0 * poison_stacks) * power, 3.0, 6)
			else:
				enemy.add_bleed((12.0 + 9.0 * fire_stacks) * power, 2.0)
			break


func _draw() -> void:
	for i in CAPACITY:
		var life := _life[i]
		if life <= 0.0:
			continue
		var fade := clampf(life / 0.8, 0.0, 1.0)
		var color := COLOR_POISON if _kind[i] == KIND_POISON else COLOR_FIRE
		var wobble := 1.0 + 0.06 * sin(life * 9.0 + i)
		SoftGlow.pool(self, _pos[i], ZONE_RADIUS * 1.1 * wobble, 0.6, Color(color, 0.3 * fade))
		SoftGlow.pool(self, _pos[i], ZONE_RADIUS * 0.6 * wobble, 0.6, Color(color.lightened(0.25), 0.22 * fade))
		SoftGlow.rim(self, _pos[i], ZONE_RADIUS * 1.15 * wobble, 0.6, Color(color.lightened(0.3), 0.35 * fade))
