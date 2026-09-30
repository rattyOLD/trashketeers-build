class_name JunkDrone
extends Node2D
## Помощник из хлама: кружит вокруг Енота и стреляет по ближайшему врагу.
## Пули берутся из BulletPool, узел создаётся один раз при выборе усиления.

const ORBIT_RADIUS := 62.0
const ORBIT_SPEED := 2.2
const RANGE := 520.0
const BASE_INTERVAL := 0.85

var player: Player
var enemies: EnemyManager
var stats: RunStats
var slot := 0
var slots := 1

var _weapon: WeaponData
var _angle := 0.0
var _cooldown := 0.4
var _kick := 0.0
var _time := 0.0


func setup(target_player: Player, enemy_manager: EnemyManager, run_stats: RunStats, index: int) -> void:
	player = target_player
	enemies = enemy_manager
	stats = run_stats
	slot = index
	z_index = 8
	_angle = TAU * randf()


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead:
		return
	_time += delta
	slots = maxi(int(stats.get_stat(&"drone_count")), 1)
	_angle += ORBIT_SPEED * delta
	var target_angle := _angle + TAU * float(slot) / slots
	var want := player.global_position + Vector2.from_angle(target_angle) * ORBIT_RADIUS * Vector2(1.0, 0.7) + Vector2(0, -34.0 + sin(_time * 5.0 + slot) * 4.0)
	global_position = global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_kick = maxf(_kick - delta * 6.0, 0.0)
	queue_redraw()
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := enemies.find_nearest(global_position, RANGE)
	if target == null:
		_cooldown = 0.15
		return
	_cooldown = BASE_INTERVAL / (1.0 + stats.get_stat(&"fire_rate_mult") * 0.5)
	_fire(target)


func _fire(target: Enemy) -> void:
	if _weapon == null:
		var base := WeaponDB.get_weapon(&"pistol_v1")
		if base == null:
			return
		_weapon = base.duplicate_data()
		_weapon.effect_color = Color("#ffd257")
		_weapon.bullet_modulate = Color("#ffe58a")
		_weapon.crit_chance = 0.0
		_weapon.projectiles_per_shot = 1
		_weapon.spread_rad = 0.0
	var owner_weapon := player.weapon_controller.weapon
	_weapon.damage = maxf(owner_weapon.damage * 0.5, 6.0) if owner_weapon != null else 8.0
	var direction := (target.get_aim_point() - global_position).normalized()
	BulletPool.spawn(_weapon, global_position, direction, Bullet.Team.PLAYER)
	_kick = 1.0
	SoundManager.play_pitched(&"shot_pistol", 1.6, -18.0)


func _draw() -> void:
	var glow := Color("#ffd257")
	draw_circle(Vector2(0, 26), 9.0, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, 13.0 + _kick * 2.0, Color(glow, 0.16))
	draw_circle(Vector2.ZERO, 8.0, Color("#3b3040"))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color("#140a1e"), 2.5, true)
	draw_circle(Vector2(0, -1), 4.0, glow.lightened(0.2))
	var spin := _time * 18.0
	for side in [-1.0, 1.0]:
		var base := Vector2(side * 9.0, -3.0)
		draw_line(base, base + Vector2(side * 9.0, -4.0 + sin(spin) * 3.0), Color("#9aa4bd"), 3.0)
