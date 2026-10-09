class_name FlailRig
extends Node2D
## Моргенштерн: шипастый шар на цепи живёт по физике. Цепь натягивается (шар не дальше длины цепи),
## шар сохраняет инерцию, стик прицела тянет его к своей точке — раскручиваешь пальцем по кругу; в автоматическом
## режиме шар крутится сам. Урон — по скорости шара (медленный почти не бьёт, разогнанный ломает толпу).
## Натяжение цепи тянет героя к шару: скорость зависит от направления и раскрутки (идея тестеров).
## Арт Астры (бриф v30): assets/weapons/flail/ — шар, 4 кадра шара в движении, звено цепи, вспышка удара.

const BALL_RADIUS := 24.0
const CONTROL_SPRING := 26.0
const AUTO_ACCEL := 1100.0
const MAX_SPEED := 980.0
const DAMPING := 0.55
const REF_SPEED := 650.0
const MIN_HIT_SPEED := 140.0
const HIT_COOLDOWN := 0.28
const PULL_K := 0.22
const PULL_MAX := 110.0
const LINKS := 6
const TRAIL := 6

signal ball_hit(at: Vector2, count: int, strong: bool)

const ART_DIR := "res://assets/weapons/flail/"
const BALL_DRAW := 76.0
const LINK_DRAW := 16.0
## Шаг между центрами звеньев: меньше длины звена — соседние заходят друг в друга.
const LINK_STEP := 9.0
const FAST_FPS := 14.0
const HIT_FPS := 16.0
const HIT_DRAW := 120.0
static var _tex := {}
var _time := 0.0
## Вспышки удара: [позиция, возраст].
var _hits: Array = []

var ball := Vector2.ZERO
var velocity := Vector2.ZERO
var anchor := Vector2.ZERO
var length := 150.0
## Сила, с которой цепь тянет героя (добавляется к его скорости).
var pull := Vector2.ZERO
var _cooldown := {}
var _trail: Array[Vector2] = []
var _query := PhysicsShapeQueryParameters2D.new()
var _shape := CircleShape2D.new()
var _ready_ball := false


func _ready() -> void:
	top_level = true
	z_index = 3
	_shape.radius = BALL_RADIUS + 6.0
	_query.shape = _shape
	# Враги и ломаемые объекты (ящики с оружием, бочки): шар бьёт и их.
	_query.collision_mask = PhysicsLayers.ENEMY | PhysicsLayers.OBSTACLE
	_query.collide_with_areas = false


static func _art(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := ART_DIR + name + ".png"
		_tex[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[name]


func reset(at: Vector2) -> void:
	anchor = at
	ball = at + Vector2(length * 0.8, 0)
	velocity = Vector2.ZERO
	_trail.clear()
	_ready_ball = true


## control — направление стика (ноль — без управления); auto — сам крутится.
func tick(delta: float, at: Vector2, control: Vector2, auto: bool, weapon: WeaponData) -> void:
	if not _ready_ball:
		reset(at)
	_time += delta
	for h: Array in _hits:
		h[1] = float(h[1]) + delta
	_hits = _hits.filter(func(h: Array) -> bool: return float(h[1]) < 4.0 / HIT_FPS)
	anchor = at
	length = clampf(weapon.melee_reach * 0.56, 70.0, 150.0)
	var rel := ball - anchor
	if control.length_squared() > 0.01:
		var desired := anchor + control.normalized() * length
		velocity += (desired - ball) * CONTROL_SPRING * delta
	elif auto:
		var tangent := rel.orthogonal().normalized() if rel.length_squared() > 1.0 else Vector2.UP
		velocity += tangent * AUTO_ACCEL * delta
	velocity *= exp(-DAMPING * delta)
	velocity = velocity.limit_length(MAX_SPEED)
	ball += velocity * delta
	# Цепь: шар не дальше длины, наружная скорость гасится.
	rel = ball - anchor
	var d := rel.length()
	pull = Vector2.ZERO
	if d > length and d > 0.001:
		var n := rel / d
		ball = anchor + n * length
		var vr := velocity.dot(n)
		if vr > 0.0:
			velocity -= n * vr
		var vt := (velocity - n * velocity.dot(n)).length()
		pull = n * minf(vt * vt / length * PULL_K, PULL_MAX)
	_trail.push_front(ball)
	if _trail.size() > TRAIL:
		_trail.pop_back()
	_hit_enemies(delta, weapon)
	queue_redraw()


func _hit_enemies(delta: float, weapon: WeaponData) -> void:
	for key in _cooldown.keys():
		_cooldown[key] = float(_cooldown[key]) - delta
		if _cooldown[key] <= 0.0:
			_cooldown.erase(key)
	var speed := velocity.length()
	if speed < MIN_HIT_SPEED or not is_inside_tree():
		return
	_query.transform = Transform2D(0.0, ball)
	var count := 0
	var mult := clampf(speed / REF_SPEED, 0.2, 2.2)
	for hit in get_world_2d().direct_space_state.intersect_shape(_query, 12):
		var box := hit["collider"] as DestructibleObject
		if box != null and is_instance_valid(box):
			var box_id := box.get_instance_id()
			if not _cooldown.has(box_id):
				_cooldown[box_id] = HIT_COOLDOWN
				box.take_damage(weapon.damage * mult, velocity.normalized())
				count += 1
			continue
		var enemy := hit["collider"] as Enemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var id := enemy.get_instance_id()
		if _cooldown.has(id):
			continue
		_cooldown[id] = HIT_COOLDOWN
		var crit := randf() < weapon.crit_chance
		enemy.take_damage(weapon.damage * mult * (weapon.crit_mult if crit else 1.0), velocity.normalized(), crit)
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy.push(velocity.normalized() * 260.0 * weapon.knockback * mult)
			enemy.add_stagger(float(weapon.stagger) * 0.1 * mult)
		count += 1
	if count > 0:
		# Отдача: шар теряет часть скорости о толпу.
		velocity *= 0.82
		if _hits.size() < 4:
			_hits.append([ball, 0.0])
		ball_hit.emit(ball, count, mult > 1.5)


func _draw() -> void:
	var link := _art("flail_link")
	var ball_tex := _art("flail_ball")
	var fast := _art("flail_ball_fast")
	var hit := _art("flail_hit")
	if link == null or ball_tex == null:
		_draw_placeholder()
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Цепь: звенья цепляются друг за друга — шаг меньше длины звена (перекрытие), каждое второе повёрнуто
	# ребром (узкое), как в настоящей цепи. Число звеньев — по длине цепи, с лёгким провисом.
	var rel := ball - anchor
	var slack := maxf(length - rel.length(), 0.0) * 0.5
	var sag := rel.orthogonal().normalized() * slack
	var count := maxi(int(ceil(rel.length() / LINK_STEP)), 2)
	var k := LINK_DRAW / link.get_width()
	var prev := anchor
	for i in count + 1:
		var t := float(i) / count
		var p := anchor.lerp(ball, t) + sag * sin(t * PI)
		var dir := (p - prev).angle() if i > 0 else rel.angle()
		var flat := i % 2 == 0
		draw_set_transform(p, dir, Vector2(k, k * (1.0 if flat else 0.42)))
		draw_texture(link, -link.get_size() * 0.5, Color.WHITE if flat else Color(0.8, 0.8, 0.85))
		prev = p
	draw_set_transform(Vector2.ZERO)
	# Шар: разогнанный — кадры со следом движения, повёрнутые по скорости; иначе — обычный.
	var speed := velocity.length()
	if fast != null and speed > REF_SPEED * 0.6:
		var cell := fast.get_height()
		var frame := int(_time * FAST_FPS) % 4
		draw_set_transform(ball, velocity.angle(), Vector2.ONE * (BALL_DRAW / cell))
		draw_texture_rect_region(fast, Rect2(-cell * 0.5, -cell * 0.5, cell, cell), Rect2(frame * cell, 0, cell, cell))
	else:
		draw_set_transform(ball, _time * speed * 0.01, Vector2.ONE * (BALL_DRAW / ball_tex.get_width()))
		draw_texture(ball_tex, -ball_tex.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO)
	# Вспышки удара.
	if hit != null:
		var cell := hit.get_height()
		for h: Array in _hits:
			var frame := mini(int(float(h[1]) * HIT_FPS), 3)
			draw_set_transform(h[0], 0.0, Vector2.ONE * (HIT_DRAW / cell))
			draw_texture_rect_region(hit, Rect2(-cell * 0.5, -cell * 0.5, cell, cell), Rect2(frame * cell, 0, cell, cell))
		draw_set_transform(Vector2.ZERO)


## Запасной рисунок кодом (если файлов арта нет).
func _draw_placeholder() -> void:
	var dark := Color("#120d1c")
	# Цепь: звенья от руки к шару с лёгким провисом, если цепь не натянута.
	var rel := ball - anchor
	var slack := maxf(length - rel.length(), 0.0) * 0.5
	var sag := rel.orthogonal().normalized() * slack
	for i in LINKS:
		var t := (float(i) + 0.5) / LINKS
		var p := anchor.lerp(ball, t) + sag * sin(t * PI)
		draw_circle(p, 4.6, dark)
		draw_circle(p, 3.2, Color("#9aa7b5"))
	# След разогнанного шара.
	var speed := velocity.length()
	if speed > REF_SPEED * 0.6:
		for i in range(1, _trail.size()):
			draw_circle(_trail[i], BALL_RADIUS * (1.0 - float(i) / TRAIL), Color(1.0, 0.55, 0.25, 0.18 * (1.0 - float(i) / TRAIL)))
	# Шар с шипами.
	var spin := atan2(velocity.y, velocity.x) if speed > 1.0 else 0.0
	for k in 8:
		var a := spin + TAU * k / 8.0
		var dir := Vector2.from_angle(a)
		var tip := ball + dir * (BALL_RADIUS + 12.0)
		var side := dir.orthogonal() * 6.0
		draw_colored_polygon(PackedVector2Array([ball + dir * BALL_RADIUS * 0.8 + side, tip, ball + dir * BALL_RADIUS * 0.8 - side]), dark)
		draw_colored_polygon(PackedVector2Array([ball + dir * BALL_RADIUS * 0.8 + side * 0.6, tip - dir * 3.0, ball + dir * BALL_RADIUS * 0.8 - side * 0.6]), Color("#c9c3d9"))
	draw_circle(ball, BALL_RADIUS + 3.0, dark)
	draw_circle(ball, BALL_RADIUS, Color("#4a4458"))
	draw_circle(ball + Vector2(-7, -8), BALL_RADIUS * 0.35, Color(1, 1, 1, 0.25))
