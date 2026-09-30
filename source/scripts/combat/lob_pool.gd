class_name LobPool
extends Node2D
## Навесные снаряды врагов: бутылки шампанского Дивидендщика, ракеты Короля Хлама, мешки
## с монетами Магната. Снаряд летит по дуге из точки броска в точку цели; на земле заранее
## виден телеграф — круг, который наполняется к моменту падения (игрок успевает уйти рывком).
## При падении — взрыв BulletPool.explode (урон Еноту), вспышка-спрайт взрыва. Пул фиксирован,
## всё рисуется одним _draw в слое FX. Доступ из врагов — через статический LobPool.active.

const CAPACITY := 40
const TELEGRAPH := Color("#ff2e4d")

static var active: LobPool

var fx: FxManager

var _from := PackedVector2Array()
var _to := PackedVector2Array()
var _time := PackedFloat32Array()
var _total := PackedFloat32Array()
var _height := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _color := PackedColorArray()
var _tex: Array[Texture2D] = []
var _blast: Array[Texture2D] = []
var _size := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _next := 0


func _init() -> void:
	z_index = 12
	z_as_relative = false
	_time.resize(CAPACITY)
	_total.resize(CAPACITY)
	_height.resize(CAPACITY)
	_radius.resize(CAPACITY)
	_damage.resize(CAPACITY)
	_color.resize(CAPACITY)
	_size.resize(CAPACITY)
	_spin.resize(CAPACITY)
	_tex.resize(CAPACITY)
	_blast.resize(CAPACITY)
	_from.resize(CAPACITY)
	_to.resize(CAPACITY)
	_time.fill(-1.0)


func _enter_tree() -> void:
	active = self


func _exit_tree() -> void:
	if active == self:
		active = null


## Бросок: from → to за flight секунд, дуга высотой height. texture — снаряд, blast — вспышка.
func throw(from: Vector2, to: Vector2, flight: float, height: float, radius: float, damage: float, color: Color,
		texture: Texture2D, blast: Texture2D, size: float, spin: float = 9.0) -> void:
	var k := _next
	_next = (_next + 1) % CAPACITY
	_from[k] = from
	_to[k] = to
	_time[k] = 0.0
	_total[k] = maxf(flight, 0.2)
	_height[k] = height
	_radius[k] = radius
	_damage[k] = damage
	_color[k] = color
	_tex[k] = texture
	_blast[k] = blast
	_size[k] = size
	_spin[k] = spin
	set_physics_process(true)


func clear() -> void:
	_time.fill(-1.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	var any := false
	for k in CAPACITY:
		if _time[k] < 0.0:
			continue
		_time[k] += delta
		if _time[k] >= _total[k]:
			_time[k] = -1.0
			_land(k)
			continue
		any = true
	queue_redraw()
	if not any:
		set_physics_process(false)


func _land(k: int) -> void:
	BulletPool.explode(_to[k], _radius[k], _damage[k], Bullet.Team.ENEMY, _color[k], 0.9)
	if fx != null and _blast[k] != null:
		fx.sprite_flash(_blast[k], _to[k] + Vector2(0, -_radius[k] * 0.25), _radius[k] * 2.3, 0.4)


func _draw() -> void:
	for k in CAPACITY:
		if _time[k] < 0.0:
			continue
		var t := _time[k] / _total[k]
		var to := _to[k]
		var r := _radius[k]
		var pulse := 0.5 + 0.5 * sin(_time[k] * (10.0 + 14.0 * t))
		var hot := t > 0.72 and int(_time[k] * 14.0) % 2 == 0
		var tint := TELEGRAPH.lerp(Color(1.0, 0.92, 0.5), 0.55 if hot else 0.0)
		SoftGlow.pool(self, to, r * 1.08, 0.58, Color(0.06, 0.0, 0.05, 0.14 + 0.1 * t))
		SoftGlow.pool(self, to, r * maxf(t, 0.2), 0.58, Color(tint, 0.16 + 0.16 * pulse))
		SoftGlow.rim(self, to, r * 1.1, 0.58, Color(tint, 0.5 + 0.25 * t))
		var cr := r * 0.24
		var cc := Color(tint.lightened(0.2), 0.45 + 0.2 * t)
		draw_set_transform(to, 0.0, Vector2(1.0, 0.58))
		draw_line(Vector2(-cr, 0), Vector2(cr, 0), cc, 2.0, true)
		draw_line(Vector2(0, -cr), Vector2(0, cr), cc, 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var ground := _from[k].lerp(to, t)
		var lift := sin(t * PI) * _height[k]
		var pos := ground + Vector2(0, -lift)
		draw_set_transform(ground, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, _size[k] * 0.42 * (1.0 - 0.35 * sin(t * PI)), Color(0, 0, 0, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var ahead := minf(t + 0.03, 1.0)
		var next_pos := _from[k].lerp(to, ahead) + Vector2(0, -sin(ahead * PI) * _height[k])
		var heading := (next_pos - pos).angle() if next_pos.distance_squared_to(pos) > 0.01 else 0.0
		var oriented := _spin[k] == 0.0
		if oriented:
			for j in 5:
				var tt := maxf(t - 0.025 * (j + 1), 0.0)
				var tp := _from[k].lerp(to, tt) + Vector2(0, -sin(tt * PI) * _height[k])
				draw_circle(tp, _size[k] * (0.2 - 0.03 * j), Color(1.0, 0.62 - 0.08 * j, 0.2, 0.55 - 0.1 * j))
		var tex := _tex[k]
		if tex == null:
			draw_circle(pos, _size[k] * 0.4, _color[k])
			continue
		var length := _size[k] * (2.4 if oriented else 1.6)
		var scale := length / maxf(tex.get_width() if oriented else tex.get_height(), 1.0)
		var angle := heading if oriented else _time[k] * _spin[k]
		draw_set_transform(pos, angle, Vector2.ONE * scale)
		draw_texture(tex, -tex.get_size() * 0.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
