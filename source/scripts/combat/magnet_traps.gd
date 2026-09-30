class_name MagnetTraps
extends Node2D
## Магнитные мины Магнитчика. Мина летит по дуге к точке у Енота, втыкается и взводится
## (ARM_TIME); взведённая тянет Енота к себе в радиусе PULL_RADIUS и тормозит его, у самого
## центра — защёлкивается: урон и короткий «захват» (скорость почти ноль). Рывок рвёт захват
## и не тянется. Через LIFETIME мина разряжается. Пул фиксирован, рисуется одним _draw.

const CAPACITY := 8
const FLIGHT := 0.55
const ARM_TIME := 0.45
const LIFETIME := 6.0
const PULL_RADIUS := 170.0
const PULL_FORCE := 210.0
const SLOW := 0.4
const SNAP_RADIUS := 34.0
const SNAP_DAMAGE := 10.0
const SNARE_TIME := 0.7
const COLOR := Color("#35e6ff")

static var active: MagnetTraps

var player: Player

var _from := PackedVector2Array()
var _to := PackedVector2Array()
var _age := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _used: Array[bool] = []
var _next := 0
var _time := 0.0
var _texture: Texture2D


func _init() -> void:
	z_index = -4
	z_as_relative = false
	_from.resize(CAPACITY)
	_to.resize(CAPACITY)
	_age.resize(CAPACITY)
	_damage.resize(CAPACITY)
	_age.fill(-1.0)
	_used.resize(CAPACITY)
	_used.fill(false)
	_texture = ArenaProp.texture_of("res://assets/enemies/trap_mine.png")


func _enter_tree() -> void:
	active = self


func _exit_tree() -> void:
	if active == self:
		active = null


func deploy(from: Vector2, to: Vector2, damage_mult: float) -> void:
	var k := _next
	_next = (_next + 1) % CAPACITY
	_from[k] = from
	_to[k] = to
	_age[k] = 0.0
	_damage[k] = SNAP_DAMAGE * damage_mult
	_used[k] = false
	SoundManager.play(&"wing_flap", -8.0)


func clear() -> void:
	_age.fill(-1.0)
	if player != null:
		player.external_pull = Vector2.ZERO
		player.move_slow = 1.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time += delta
	var pull := Vector2.ZERO
	var slow := 1.0
	for k in CAPACITY:
		if _age[k] < 0.0:
			continue
		_age[k] += delta
		var armed_at := FLIGHT + ARM_TIME
		if _age[k] > FLIGHT + LIFETIME:
			_age[k] = -1.0
			continue
		if _age[k] < armed_at or player == null or player.is_dead or player.is_dashing():
			continue
		var to := _to[k] - player.global_position
		var d := to.length()
		if d > PULL_RADIUS:
			continue
		var k_near := 1.0 - d / PULL_RADIUS
		pull += to.normalized() * PULL_FORCE * (0.45 + 0.55 * k_near)
		slow = minf(slow, 1.0 - SLOW * (0.5 + 0.5 * k_near))
		if d < SNAP_RADIUS and not _used[k]:
			_used[k] = true
			Player.last_source = &"trap"
			player.take_damage(_damage[k], Vector2.ZERO)
			player.snare(SNARE_TIME)
			_age[k] = FLIGHT + LIFETIME - 0.35
			SoundManager.play(&"shield_up", -4.0)
	if player != null:
		player.external_pull = pull
		player.move_slow = slow
	queue_redraw()


func _draw() -> void:
	for k in CAPACITY:
		var age := _age[k]
		if age < 0.0:
			continue
		if age < FLIGHT:
			var t := age / FLIGHT
			var p := _from[k].lerp(_to[k], t) + Vector2(0, -sin(t * PI) * 120.0)
			_draw_mine(p, 0.85, 0.0, t * 9.0)
			continue
		var armed := clampf((age - FLIGHT) / ARM_TIME, 0.0, 1.0)
		var left := FLIGHT + LIFETIME - age
		var fade := clampf(left / 0.35, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_time * 7.0 + k)
		SoftGlow.pool(self, _to[k], PULL_RADIUS * 1.05, 0.5, Color(COLOR, 0.13 * armed * fade))
		SoftGlow.rim(self, _to[k], PULL_RADIUS * 1.1, 0.5, Color(COLOR, (0.25 + 0.2 * pulse) * armed * fade))
		var wave := fmod(_time * 0.9 + k * 0.3, 1.0)
		SoftGlow.rim(self, _to[k], PULL_RADIUS * (1.0 - wave), 0.5, Color(COLOR, 0.28 * wave * armed * fade))
		if player != null and not player.is_dead and armed >= 1.0 and _to[k].distance_to(player.global_position) < PULL_RADIUS:
			_draw_arc_bolt(_to[k] + Vector2(0, -12), player.global_position + Vector2(0, -10))
		_draw_mine(_to[k], fade, armed * pulse, 0.0)


func _draw_mine(at: Vector2, alpha: float, glow: float, spin: float) -> void:
	if _texture == null:
		draw_circle(at, 18.0, Color(COLOR, alpha))
		return
	var scale := 58.0 / _texture.get_width()
	draw_set_transform(at + Vector2(0, -10), spin, Vector2.ONE * scale)
	draw_texture(_texture, -_texture.get_size() * 0.5, Color(1.0 + glow * 0.5, 1.0 + glow * 0.5, 1.0 + glow * 0.5, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Ломаная «молния» от мины к Еноту: видно, что тянет именно она.
func _draw_arc_bolt(a: Vector2, b: Vector2) -> void:
	var pts := PackedVector2Array([a])
	var n := 6
	var side := (b - a).orthogonal().normalized()
	for i in range(1, n):
		var t := float(i) / n
		pts.append(a.lerp(b, t) + side * sin(_time * 40.0 + i * 1.7) * 7.0)
	pts.append(b)
	draw_polyline(pts, Color(COLOR, 0.35), 5.0, true)
	draw_polyline(pts, Color(0.85, 1.0, 1.0, 0.8), 2.0, true)
