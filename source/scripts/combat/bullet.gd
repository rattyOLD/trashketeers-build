class_name Bullet
extends Area2D
## Пулируемый снаряд. Жизненным циклом владеет только BulletPool:
## пуля никогда не удаляет и не выключает себя сама, а сообщает пулу через tick() -> false.
##
## Контракт цели: узел, в который попала пуля (PhysicsBody2D или Area2D-хёртбокс),
## может реализовать take_damage(amount: float, direction: Vector2). Проверка через
## has_method, чтобы пул не зависел от классов врагов и разрушаемых объектов.
##
## Попадания из сигналов только складываются в очередь и разбираются в tick():
## во время физических сигналов Godot запрещает менять состояние коллизий и
## делать запросы к PhysicsDirectSpaceState2D.

signal target_hit(bullet: Bullet, target: Node2D)
signal detonated(bullet: Bullet)

enum Team { PLAYER, ENEMY }

const RICOCHET_QUERY_LIMIT := 16
const RICOCHET_DISTANCE_MARGIN := 1.15
const TRAIL_WIDTH_SCALE := 1.5

static var _trail_gradient: Gradient
static var _trail_curve: Curve
## Жидкие снаряды (пиво, рвота): вместо линии-хвоста за каплей летят брызги — их рисует FxManager
## в общем батче (см. BattleBase). Задаётся боем: func(at, velocity, color).
const LIQUID_IDS: Array[StringName] = [&"beer_jet_v1", &"puke_v1"]
static var liquid_sink: Callable

var weapon: WeaponData
var team: Team = Team.PLAYER
var velocity := Vector2.ZERO
var spawn_frame := 0
var pool_index := -1
## Было ли последнее попадание критом (читают эффекты в обработчике target_hit).
var last_hit_crit := false
## Множитель урона снаряда (сложность волны для вражеских пуль).
var damage_scale := 1.0
var _age := 0.0
## Уровень упрощения при большой плотности снарядов: 1 — без шлейфа, 2 — ещё и без луча-свипа.
var _lod := 0
## Капля жидкой струи (пиво/рвота): FxManager соединяет соседние капли очереди в сплошную струю.
var is_liquid := false
## Сколько врагов эта пуля уже пробила (рельсотрон растит урон с каждым).
var pierced := 0

var _sprite: Sprite2D
var _shape: CircleShape2D
var _collision: CollisionShape2D
var _time_left := 0.0
var _distance_left := 0.0
var _ricochets_left := 0
var _unit_mask := 0
var _pending_hits: Array[Node2D] = []
var _hit_ids: Dictionary = {}
var _ricochet_query: PhysicsShapeQueryParameters2D
var _trail: Line2D
var _trail_count := 0


func _init() -> void:
	# monitorable не выключаем: в Godot 4 Area2D с monitorable = false
	# перестаёт детектить StaticBody2D (стены, разрушаемые объекты).
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	visible = false

	_sprite = Sprite2D.new()
	add_child(_sprite)

	_shape = CircleShape2D.new()
	_collision = CollisionShape2D.new()
	_collision.shape = _shape
	_collision.disabled = true
	add_child(_collision)

	# Шлейф (паспорт биома, §5): Line2D из нескольких последних позиций пули.
	# top_level — точки задаются в мировых координатах и не вращаются вместе с пулей.
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.gradient = _get_trail_gradient()
	_trail.width_curve = _get_trail_curve()
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.visible = false
	add_child(_trail)

	body_entered.connect(_on_contact)
	area_entered.connect(_on_contact)


func activate(data: WeaponData, origin: Vector2, direction: Vector2, owner_team: Team, lod: int = 0) -> void:
	_lod = lod
	pierced = 0
	damage_scale = 1.0
	_age = 0.0
	_sprite.rotation = 0.0
	weapon = data
	team = owner_team
	global_position = origin
	velocity = direction.normalized() * data.bullet_speed
	rotation = velocity.angle()
	spawn_frame = Engine.get_physics_frames()

	_time_left = data.bullet_lifetime
	_distance_left = data.max_distance
	_ricochets_left = data.ricochet_count
	_pending_hits.clear()
	_hit_ids.clear()

	_sprite.texture = data.bullet_texture
	_sprite.scale = data.sprite_scale
	_sprite.modulate = data.bullet_modulate
	_shape.radius = data.bullet_radius

	_apply_team_masks(owner_team)
	_reset_trail(origin)
	is_liquid = LIQUID_IDS.has(data.id)
	if is_liquid:
		# В струе капли — лишь пузыри внутри потока: сам поток рисует FxManager лентой.
		_sprite.scale = data.sprite_scale * 0.55
		_sprite.modulate = Color(data.bullet_modulate, 0.8)
		_trail_count = 0
		_trail.visible = false
	if lod > 0 and owner_team == Team.PLAYER:
		_trail_count = 0
		_trail.visible = false
	visible = true
	reset_physics_interpolation()
	# set_deferred безопасен, даже если выстрел пришёл из физического сигнала
	# (например, из Area2D-детектора целей). Deferred-вызовы исполняются
	# в конце physics-кадра, до следующего шага физики, так что пуля не пропустит ни одного тика.
	set_deferred("monitoring", true)
	_collision.set_deferred("disabled", false)


func deactivate() -> void:
	visible = false
	weapon = null
	velocity = Vector2.ZERO
	_pending_hits.clear()
	_hit_ids.clear()
	_trail.clear_points()
	_trail.visible = false
	# Выключение monitoring сбрасывает внутренний список пересечений Area2D,
	# иначе при повторном использовании пуля не получит body_entered от уже задетых тел.
	set_deferred("monitoring", false)
	_collision.set_deferred("disabled", true)


## Возвращает false, когда пулю нужно вернуть в пул.
func tick(delta: float) -> bool:
	if not _resolve_pending_hits():
		_detonate()
		return false

	if weapon.homing > 0.0 and team == Team.ENEMY and BulletPool.homing_target != null and _age < weapon.homing_time:
		var want := global_position.direction_to(BulletPool.homing_target.global_position).angle()
		velocity = Vector2.from_angle(rotate_toward(velocity.angle(), want, weapon.homing * delta)) * velocity.length()
		if weapon.spin == 0.0:
			rotation = velocity.angle()
	_age += delta
	if weapon.spin != 0.0:
		_sprite.rotation += weapon.spin * delta
	var step := velocity * delta
	# Быстрые пули (снайперка, рельса) за кадр пролетают больше своего диаметра и могли бы
	# «перепрыгнуть» тонкий забор или крысу: луч вдоль шага ставит пулю в точку касания,
	# и перекрытие Area2D честно срабатывает на следующем физическом кадре.
	if _lod < 2 and step.length() > _shape.radius * 2.5:
		step = _sweep(step)
	global_position += step
	_advance_trail()
	if is_liquid and (Engine.get_physics_frames() + spawn_frame) % 3 == 0 and liquid_sink.is_valid():
		liquid_sink.call(global_position, velocity, weapon.effect_color)
	_distance_left -= step.length()
	_time_left -= delta
	var alive := _distance_left > 0.0 and _time_left > 0.0
	if not alive:
		_detonate()
	return alive


func _sweep(step: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return step
	var to_hit: Vector2 = hit["position"] - global_position
	return to_hit + step.normalized() * _shape.radius * 0.5


## Гранаты рвутся и при попадании, и в конце полёта; урон по площади считает BulletPool.
func _detonate() -> void:
	if weapon != null and weapon.explosion_radius > 0.0:
		detonated.emit(self)


## Трассер-скин игрока: свой рисунок пули (Астра) вместо стандартной капсулы, шлейф — цветом скина.
func apply_skin(texture: Texture2D, color: Color) -> void:
	_sprite.texture = texture
	var k := clampf(weapon.bullet_radius / 5.0, 0.8, 1.6) if weapon != null else 1.0
	_sprite.scale = Vector2.ONE * (38.0 / maxf(texture.get_width(), 1.0)) * k
	_sprite.modulate = Color.WHITE
	_trail.modulate = Color(color, 0.85)


func apply_tint(color: Color) -> void:
	_sprite.modulate = color
	_trail.modulate = Color(color, 0.85)


func _reset_trail(origin: Vector2) -> void:
	_trail.clear_points()
	_trail_count = weapon.trail_points
	for i in _trail_count:
		_trail.add_point(origin)
	_trail.width = weapon.bullet_radius * 2.0 * TRAIL_WIDTH_SCALE
	_trail.modulate = Color(weapon.effect_color, 0.85)
	_trail.visible = _trail_count > 0


func _advance_trail() -> void:
	if _trail_count == 0:
		return
	for i in _trail_count - 1:
		_trail.set_point_position(i, _trail.get_point_position(i + 1))
	_trail.set_point_position(_trail_count - 1, global_position)


static func _get_trail_gradient() -> Gradient:
	if _trail_gradient == null:
		_trail_gradient = Gradient.new()
		_trail_gradient.set_color(0, Color(1, 1, 1, 0))
		_trail_gradient.set_color(1, Color(1, 1, 1, 0.9))
	return _trail_gradient


static func _get_trail_curve() -> Curve:
	if _trail_curve == null:
		_trail_curve = Curve.new()
		_trail_curve.add_point(Vector2(0.0, 0.15))
		_trail_curve.add_point(Vector2(1.0, 1.0))
	return _trail_curve


func _apply_team_masks(owner_team: Team) -> void:
	if owner_team == Team.PLAYER:
		collision_layer = PhysicsLayers.PLAYER_BULLET
		_unit_mask = PhysicsLayers.ENEMY
	else:
		collision_layer = PhysicsLayers.ENEMY_BULLET
		_unit_mask = PhysicsLayers.PLAYER
	collision_mask = _unit_mask | PhysicsLayers.OBSTACLE | PhysicsLayers.WORLD
	if owner_team == Team.ENEMY:
		collision_mask |= PhysicsLayers.SHIELD


func _on_contact(node: Node2D) -> void:
	if weapon == null or _hit_ids.has(node.get_instance_id()):
		return
	_pending_hits.append(node)


func _resolve_pending_hits() -> bool:
	if _pending_hits.is_empty():
		return true

	var alive := true
	for target in _pending_hits:
		if not is_instance_valid(target) or _hit_ids.has(target.get_instance_id()):
			continue
		_hit_ids[target.get_instance_id()] = true

		var layer := _get_layer(target)
		if layer & PhysicsLayers.BULLET_BLOCKERS:
			alive = false
			break

		_apply_damage(target)
		if weapon == null:
			# Обработчик попадания сам вернул пулю в пул (например, release_all при смерти игрока).
			return false
		if layer & _unit_mask and _ricochets_left > 0 and _try_ricochet(target):
			continue
		if not weapon.piercing:
			alive = false
			break

	_pending_hits.clear()
	return alive


func _apply_damage(target: Node2D) -> void:
	last_hit_crit = team == Team.PLAYER and randf() < weapon.crit_chance
	var amount := weapon.damage * damage_scale * (weapon.crit_mult if last_hit_crit else 1.0)
	if weapon.pierce_ramp > 0.0 and team == Team.PLAYER:
		amount *= 1.0 + weapon.pierce_ramp * pierced
		pierced += 1
	if target is Enemy:
		Enemy.next_kind = &"fire" if weapon.burn > 0.0 else &""
		(target as Enemy).take_bullet(amount, velocity.normalized(), weapon.knockback, last_hit_crit, weapon.piercing)
		Enemy.next_kind = &""
	elif target.has_method("take_damage"):
		if target is Player:
			Player.last_source = &"projectile"
		target.call("take_damage", amount, velocity.normalized() * weapon.knockback, last_hit_crit)
	target_hit.emit(self, target)


func _try_ricochet(from_target: Node2D) -> bool:
	var next := _find_ricochet_target(from_target.global_position)
	if next == null:
		return false

	var to_next := next.global_position - global_position
	var distance := to_next.length()
	velocity = to_next.normalized() * weapon.bullet_speed
	rotation = velocity.angle()
	_ricochets_left -= 1
	_distance_left = maxf(_distance_left, distance * RICOCHET_DISTANCE_MARGIN)
	_time_left = maxf(_time_left, _distance_left / weapon.bullet_speed)
	return true


func _find_ricochet_target(from_position: Vector2) -> Node2D:
	if weapon.ricochet_range <= 0.0:
		return null

	var query := _get_ricochet_query()
	(query.shape as CircleShape2D).radius = weapon.ricochet_range
	query.transform = Transform2D(0.0, from_position)
	query.collision_mask = _unit_mask

	var results := get_world_2d().direct_space_state.intersect_shape(query, RICOCHET_QUERY_LIMIT)
	var best: Node2D = null
	var best_dist_sq := INF
	for hit in results:
		var candidate := hit["collider"] as Node2D
		if candidate == null or _hit_ids.has(candidate.get_instance_id()):
			continue
		var dist_sq := from_position.distance_squared_to(candidate.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


func _get_ricochet_query() -> PhysicsShapeQueryParameters2D:
	if _ricochet_query == null:
		_ricochet_query = PhysicsShapeQueryParameters2D.new()
		_ricochet_query.shape = CircleShape2D.new()
		_ricochet_query.collide_with_areas = true
		_ricochet_query.collide_with_bodies = true
	return _ricochet_query


## TileMapLayer и прочие не-CollisionObject2D коллайдеры считаются стенами.
static func _get_layer(target: Node2D) -> int:
	var collision_object := target as CollisionObject2D
	if collision_object != null:
		return collision_object.collision_layer
	return PhysicsLayers.WORLD
