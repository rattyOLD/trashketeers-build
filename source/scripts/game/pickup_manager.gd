class_name PickupManager
extends Node2D
## Гайки и кристаллы опыта. Данные-ориентированный пул: позиции, скорости и вид в Packed-
## массивах, вся отрисовка — один _draw. Нода на каждую гайку не создаётся вообще:
## копилки «засыпают экран золотом», и сотни нод убили бы WebView.
## В радиусе магнита лут притягивается к Еноту с ускорением; vacuum() тянет всё сразу
## (награда за очистку волны).

signal collected(amount: int)
signal xp_collected(amount: int)

enum Kind { NUT, XP, XP_GOLD }

const CAPACITY := 320
const COLLECT_DISTANCE := 24.0
const FRICTION := 5.0
const ATTRACT_ACCEL := 2600.0
const MAX_SPEED := 1200.0
const ATTRACT_START := 260.0
## Притянутый лут дольше этого времени зачисляется сразу (страховка от любых орбит).
const ATTRACT_TIMEOUT := 1.6

var nut_texture: Texture2D
var xp_texture: Texture2D
var xp_gold_texture: Texture2D

var _player: Player
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _attracted := PackedByteArray()
var _attract_time := PackedFloat32Array()
var _kind := PackedByteArray()
var _value := PackedInt32Array()
var _count := 0
var _time := 0.0


func _init() -> void:
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_attracted.resize(CAPACITY)
	_attract_time.resize(CAPACITY)
	_kind.resize(CAPACITY)
	_value.resize(CAPACITY)
	nut_texture = make_coin_texture(26)
	xp_texture = make_xp_texture()
	xp_gold_texture = make_xp_texture(true)


func setup(player: Player) -> void:
	_player = player


func spawn(at: Vector2, amount: int) -> void:
	var overflow := 0
	for i in amount:
		if not _add(at, Kind.NUT, 1):
			overflow += 1
	if overflow > 0:
		collected.emit(overflow)


## Опыт падает одним-тремя кристаллами (крупный враг — крупнее кристалл).
func spawn_xp_gold(at: Vector2, amount: int) -> void:
	if not _add(at, Kind.XP_GOLD, amount):
		xp_collected.emit(amount)


func spawn_xp(at: Vector2, amount: int) -> void:
	var pieces := clampi(amount, 1, 3)
	var per := int(ceil(float(amount) / pieces))
	var left := amount
	for i in pieces:
		var value := mini(per, left)
		left -= value
		if value > 0 and not _add(at, Kind.XP, value):
			xp_collected.emit(value)


func vacuum() -> void:
	for i in _count:
		if _attracted[i] == 0:
			_attracted[i] = 1
			_attract_time[i] = 0.0


func _add(at: Vector2, kind: Kind, value: int) -> bool:
	if _count >= CAPACITY:
		return false
	_pos[_count] = at
	_vel[_count] = Vector2.from_angle(randf() * TAU) * randf_range(90.0, 240.0)
	_attracted[_count] = 0
	_attract_time[_count] = 0.0
	_kind[_count] = kind
	_value[_count] = value
	_count += 1
	return true


func clear() -> void:
	_count = 0
	queue_redraw()


func position_at(index: int) -> Vector2:
	return _pos[index]


func is_xp_at(index: int) -> bool:
	return _kind[index] != Kind.NUT


func is_gold_at(index: int) -> bool:
	return _kind[index] == Kind.XP_GOLD


func get_count() -> int:
	return _count


func _physics_process(delta: float) -> void:
	if _player == null or _count == 0:
		return
	_time += delta
	var target := _player.global_position
	var magnet_sq := _player.magnet_radius * _player.magnet_radius
	var collect_sq := COLLECT_DISTANCE * COLLECT_DISTANCE
	var picked := 0
	var picked_xp := 0
	var i := 0
	while i < _count:
		var p := _pos[i]
		var v := _vel[i]
		var dist_sq := p.distance_squared_to(target)
		if _attracted[i] == 0 and dist_sq < magnet_sq:
			_attracted[i] = 1
			_attract_time[i] = 0.0
		var reached := false
		if _attracted[i] == 1:
			# Чистое самонаведение без инерции: скорость растёт, направление — всегда на Енота.
			# Раньше лут разгонялся ускорением, проскакивал мимо и выходил на орбиту вокруг
			# бегущего Енота — монеты летали за ним всю игру.
			_attract_time[i] += delta
			var speed := minf(maxf(v.length(), ATTRACT_START) + ATTRACT_ACCEL * delta, MAX_SPEED)
			var step := speed * delta
			var dist := sqrt(dist_sq)
			reached = dist <= step + COLLECT_DISTANCE or _attract_time[i] > ATTRACT_TIMEOUT
			v = (target - p) / maxf(dist, 0.001) * speed
			p += v * delta
		else:
			v = v.lerp(Vector2.ZERO, clampf(FRICTION * delta, 0.0, 1.0))
			p += v * delta

		if reached or p.distance_squared_to(target) < collect_sq:
			if _kind[i] != Kind.NUT:
				picked_xp += _value[i]
			else:
				picked += _value[i]
			_count -= 1
			_pos[i] = _pos[_count]
			_vel[i] = _vel[_count]
			_attracted[i] = _attracted[_count]
			_attract_time[i] = _attract_time[_count]
			_kind[i] = _kind[_count]
			_value[i] = _value[_count]
			continue
		_pos[i] = p
		_vel[i] = v
		i += 1

	if picked > 0:
		collected.emit(picked)
	if picked_xp > 0:
		xp_collected.emit(picked_xp)
	queue_redraw()


## Видимая область в мировых координатах с запасом: за кадром лут не рисуем (до 320 штук = сотни команд отрисовки).
func _view_rect() -> Rect2:
	var size := get_viewport_rect().size
	var inverse := get_canvas_transform().affine_inverse()
	var top_left := inverse * Vector2.ZERO
	var bottom_right := inverse * size
	return Rect2(top_left, bottom_right - top_left).abs().grow(48.0)


func _draw() -> void:
	var nut_half := nut_texture.get_size() * 0.5
	var xp_half := xp_texture.get_size() * 0.5
	var view := _view_rect()
	for i in _count:
		if not view.has_point(_pos[i]):
			continue
		if _kind[i] == Kind.XP_GOLD:
			var glow := 1.35 + 0.12 * sin(_time * 6.0 + i)
			draw_circle(_pos[i] + Vector2(0, 8), 9.0, Color(0, 0, 0, 0.25))
			draw_circle(_pos[i] + Vector2(0, -4), 15.0 * glow, Color(1.0, 0.82, 0.25, 0.18))
			draw_set_transform(_pos[i] + Vector2(0, sin(_time * 5.0 + i) * 3.0 - 5), 0.0, Vector2.ONE * 1.35)
			draw_texture(xp_gold_texture, -xp_half)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif _kind[i] == Kind.XP:
			var bob := sin(_time * 5.0 + i) * 3.0
			var big := 1.0 + 0.25 * (_value[i] - 1)
			draw_circle(_pos[i] + Vector2(0, 8), 7.0 * big, Color(0, 0, 0, 0.25))
			draw_set_transform(_pos[i] + Vector2(0, bob - 4), 0.0, Vector2.ONE * big)
			draw_texture(xp_texture, -xp_half)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture(nut_texture, _pos[i] - nut_half)


## Кристалл опыта 20×26: бирюзовый ромб с контуром и бликом.
static func make_xp_texture(gold: bool = false) -> ImageTexture:
	var w := 20
	var h := 26
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var center := Vector2(w, h) * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var d := absf(p.x) / (w * 0.5) + absf(p.y) / (h * 0.5)
			var color := Color(0, 0, 0, 0)
			if d <= 1.0:
				color = Color("#180e22")
			if d <= 0.78:
				var mix := clampf((p.y + p.x * 0.5) / 12.0 + 0.5, 0.0, 1.0)
				color = Color("#ffe27a").lerp(Color("#ff9a1f"), mix) if gold else Color("#00f5ff").lerp(Color("#1a7dff"), mix)
			if d <= 0.78 and p.x < -1.0 and p.y < -2.0 and d > 0.3:
				color = Color("#fffbe0") if gold else Color("#c8ffff")
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


## Золотая монета Сетки (общая валюта всех игр): ободок, выпуклый центр со звездой и блик.
## Рисуется с 3× суперсэмплингом, результат кэшируется по размеру.
static var _coin_cache: Dictionary = {}


static func make_coin_texture(size: int = 24) -> ImageTexture:
	if _coin_cache.has(size):
		return _coin_cache[size]
	var ss := 3
	var big := size * ss
	var image := Image.create(big, big, false, Image.FORMAT_RGBA8)
	var center := Vector2(big, big) * 0.5
	var r_out := big * 0.47
	var r_rim := big * 0.4
	var outline := Color("#3a1d06")
	for y in big:
		for x in big:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var r := p.length()
			var color := Color(0, 0, 0, 0)
			if r <= r_out:
				color = outline
			if r <= r_out - big * 0.05:
				var t := clampf((p.y + p.x * 0.4) / (r_out * 1.6) + 0.5, 0.0, 1.0)
				color = Color("#ffe27a").lerp(Color("#c7780f"), t)
			if r <= r_rim:
				var t2 := clampf((-p.y - p.x * 0.4) / (r_rim * 1.6) + 0.5, 0.0, 1.0)
				color = Color("#ffcf3f").lerp(Color("#f3a712"), t2)
				if _star_distance(p / r_rim) <= 0.0:
					color = Color("#fff3b0").lerp(Color("#e08a0c"), clampf(p.y / r_rim + 0.5, 0.0, 1.0))
			if r > r_rim - big * 0.035 and r <= r_rim:
				color = Color("#a85f08")
			var shine := p - Vector2(-r_out * 0.35, -r_out * 0.4)
			if r <= r_out - big * 0.05 and shine.length() < r_out * 0.16:
				color = color.lerp(Color.WHITE, 0.75)
			image.set_pixel(x, y, color)
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_coin_cache[size] = texture
	return texture


## Пятиконечная звезда в единичных координатах: <= 0 внутри.
static func _star_distance(p: Vector2) -> float:
	var angle := atan2(p.y, p.x) + PI * 0.5
	var sector := TAU / 5.0
	var a := fposmod(angle, sector) - sector * 0.5
	var radius := lerpf(0.26, 0.62, pow(absf(cos(a * 2.5)), 6.0))
	return p.length() - radius


static func _hex_distance(p: Vector2, radius: float) -> float:
	var q := p.abs()
	return maxf(q.x - radius * 0.866, q.y + q.x * 0.577 - radius)
