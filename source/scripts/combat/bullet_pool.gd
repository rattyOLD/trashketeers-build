extends Node2D
## Autoload "BulletPool". Все пули создаются один раз в _ready и живут всё время работы приложения.
##
## Устройство пула:
## - _free: стек свободных пуль (pop_back/append — O(1)).
## - _active: плотный массив летящих пуль; bullet.pool_index хранит позицию в нём,
##   поэтому удаление — swap-remove за O(1) без поиска.
## - При исчерпании capacity новая пуля НЕ создаётся (ТЗ запрещает instantiate в геймплее):
##   переиспользуется самая старая летящая. Предупреждение выводится один раз — сигнал поднять capacity.
## - Двигает пули сам пул одним циклом, а не каждая пуля в своём _physics_process:
##   единая точка владения жизненным циклом и детерминированный порядок обновления.

signal bullet_hit(bullet: Bullet, target: Node2D)
signal exploded(at: Vector2, radius: float, color: Color, team: Bullet.Team)

const EXPLOSION_QUERY_LIMIT := 48
## Порог активных снарядов, после которых новые пули упрощаются (шлейф, свип-луч).
const LOD_TRAILS_OFF := 70
const LOD_SWEEP_OFF := 150
const RECYCLE_SAMPLES := 6
const EXPLOSION_KNOCKBACK := 1.8

@export var capacity := 384
## Паспорт биома: снаряды на верхнем слое FX.
@export var draw_z_index := BiomeLayers.Z_FX

var _free: Array[Bullet] = []
var _active: Array[Bullet] = []
var _exhausted_warned := false
## Окраска всех вражеских снарядов (фаза ярости Сириуса). Альфа 0 — окраски нет.
var _enemy_tint := Color(0, 0, 0, 0)
## Кого догоняют самонаводящиеся вражеские снаряды (фишки Крупье); ставит режим боя.
var homing_target: Node2D
var _blast_query: PhysicsShapeQueryParameters2D
var _lod := 0
var _recycle_cursor := 0
var _finisher_cd := 0.0


func _ready() -> void:
	z_index = draw_z_index
	capacity = maxi(capacity, 1)
	_prewarm(capacity)


## Один выстрел оружия: projectiles_per_shot пуль с разбросом из конфига.
func fire(weapon: WeaponData, origin: Vector2, direction: Vector2, team: Bullet.Team = Bullet.Team.PLAYER, damage_scale: float = 1.0) -> void:
	if weapon == null:
		push_error("BulletPool.fire: weapon == null")
		return
	if direction.is_zero_approx():
		return

	if weapon.fire_sound != &"":
		SoundManager.play(weapon.fire_sound, -4.0 if team == Bullet.Team.ENEMY else 0.0)
	var base_angle := direction.angle()
	var count := weapon.projectiles_per_shot
	for i in count:
		var angle := base_angle + _spread_offset(weapon, i, count)
		var bullet := spawn(weapon, origin, Vector2.from_angle(angle), team)
		if bullet != null:
			bullet.damage_scale = damage_scale


func spawn(weapon: WeaponData, origin: Vector2, direction: Vector2, team: Bullet.Team = Bullet.Team.PLAYER) -> Bullet:
	var bullet := _acquire()
	bullet.activate(weapon, origin, direction, team, _lod)
	if team == Bullet.Team.ENEMY and _enemy_tint.a > 0.0:
		bullet.apply_tint(_enemy_tint)
	return bullet


## Перекрашивает все летящие и будущие вражеские снаряды.
func set_enemy_tint(color: Color) -> void:
	_enemy_tint = color
	for bullet in _active:
		if bullet.team == Bullet.Team.ENEMY:
			bullet.apply_tint(color)


func clear_enemy_tint() -> void:
	_enemy_tint = Color(0, 0, 0, 0)


func release(bullet: Bullet) -> void:
	if bullet == null or bullet.pool_index < 0:
		return
	_remove_active(bullet)
	bullet.deactivate()
	_free.append(bullet)


## Вызывать при выходе из боя/смене уровня: пул — автолоад и переживает смену сцен.
func release_all() -> void:
	while not _active.is_empty():
		release(_active.back())


## 0 — полная картинка, 1 — без шлейфов, 2 — без свипа. Эффекты игры тоже читают этот уровень.
func get_lod() -> int:
	return _lod


func get_active_count() -> int:
	return _active.size()


func get_capacity() -> int:
	return _active.size() + _free.size()


func _physics_process(delta: float) -> void:
	_finisher_cd = maxf(_finisher_cd - delta, 0.0)
	var live := _active.size()
	_lod = 2 if live > LOD_SWEEP_OFF else (1 if live > LOD_TRAILS_OFF else 0)
	# Обход с конца: swap-remove переносит в i уже обработанный последний элемент,
	# поэтому ни одна пуля не пропускается и не тикает дважды. Проверка размера нужна,
	# если обработчик попадания вызвал release_all() посреди цикла.
	var i := _active.size() - 1
	while i >= 0:
		if i < _active.size():
			var bullet := _active[i]
			if not bullet.tick(delta):
				release(bullet)
		i -= 1


func _prewarm(count: int) -> void:
	for i in count:
		var bullet := Bullet.new()
		bullet.target_hit.connect(_on_bullet_target_hit)
		bullet.detonated.connect(_on_bullet_detonated)
		add_child(bullet)
		_free.append(bullet)


func _acquire() -> Bullet:
	var bullet: Bullet = _free.pop_back() if not _free.is_empty() else _recycle_oldest()
	bullet.pool_index = _active.size()
	_active.append(bullet)
	return bullet


func _recycle_oldest() -> Bullet:
	if not _exhausted_warned:
		_exhausted_warned = true
		push_warning("BulletPool: capacity (%d) исчерпана, переиспользуются самые старые пули" % capacity)

	# Полный поиск самой старой пули стоил O(n) на каждый выстрел при переполнении:
	# берём несколько соседей от бегущего курсора и вытесняем самую старую из них.
	var oldest := _active[_recycle_cursor % _active.size()]
	for k in RECYCLE_SAMPLES:
		var candidate := _active[(_recycle_cursor + k) % _active.size()]
		if candidate.spawn_frame < oldest.spawn_frame:
			oldest = candidate
	_recycle_cursor = (_recycle_cursor + RECYCLE_SAMPLES) % _active.size()
	_remove_active(oldest)
	oldest.deactivate()
	return oldest


func _remove_active(bullet: Bullet) -> void:
	var index := bullet.pool_index
	var last: Bullet = _active.pop_back()
	if last != bullet:
		_active[index] = last
		last.pool_index = index
	bullet.pool_index = -1


func _spread_offset(weapon: WeaponData, index: int, count: int) -> float:
	if weapon.spread_rad <= 0.0:
		return 0.0
	var half := weapon.spread_rad * 0.5
	if count == 1:
		return randf_range(-half, half)
	return -half + weapon.spread_rad * float(index) / float(count - 1)


func _on_bullet_target_hit(bullet: Bullet, target: Node2D) -> void:
	bullet_hit.emit(bullet, target)


func _on_bullet_detonated(bullet: Bullet) -> void:
	var w := bullet.weapon
	if w.finisher_radius > 0.0:
		if _finisher_cd > 0.0 or randf() > w.finisher_chance:
			return
		_finisher_cd = 0.06
	explode(bullet.global_position, w.explosion_radius, w.explosion_damage, bullet.team, w.effect_color, w.knockback)


## Взрыв по площади: урон спадает от 100% в центре до 50% на краю, всех отбрасывает наружу.
## Взрыв игрока бьёт крыс и разрушаемые объекты; взрыв Бомбо-Крысы — Енота и самих крыс
## (цепные реакции — приятный бонус игроку). Вызывается вне физических сигналов.
func explode(at: Vector2, radius: float, damage: float, team: Bullet.Team, color: Color, knockback: float = 1.0, kind: StringName = &"blast") -> void:
	if radius <= 0.0 or not is_inside_tree():
		return
	var query := _get_blast_query()
	(query.shape as CircleShape2D).radius = radius
	query.transform = Transform2D(0.0, at)
	query.collision_mask = PhysicsLayers.ENEMY | PhysicsLayers.OBSTACLE
	if team == Bullet.Team.ENEMY:
		query.collision_mask |= PhysicsLayers.PLAYER
	var hits := get_world_2d().direct_space_state.intersect_shape(query, EXPLOSION_QUERY_LIMIT)
	exploded.emit(at, radius, color, team)
	for hit in hits:
		var target := hit["collider"] as Node2D
		if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
			continue
		var offset := target.global_position - at
		var falloff := lerpf(1.0, 0.5, clampf(offset.length() / radius, 0.0, 1.0))
		var push := offset.normalized() * EXPLOSION_KNOCKBACK * knockback if offset.length_squared() > 1.0 else Vector2.ZERO
		Enemy.next_kind = kind
		target.call("take_damage", damage * falloff, push, false)
		Enemy.next_kind = &""
		if target is Player:
			(target as Player).apply_knockback(push * 260.0)


func _get_blast_query() -> PhysicsShapeQueryParameters2D:
	if _blast_query == null:
		_blast_query = PhysicsShapeQueryParameters2D.new()
		_blast_query.shape = CircleShape2D.new()
		_blast_query.collide_with_bodies = true
		_blast_query.collide_with_areas = false
	return _blast_query
