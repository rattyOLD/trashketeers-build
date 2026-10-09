class_name HazardDirector
extends Node2D
## Анти-кемпер: не даёт стоять на месте. Периодически «сверху» падает хлам, открываются лужи яда,
## электрические зоны и лазерные линии. Если Енот почти не двигался последние ~3 секунды,
## удары летят прямо в него и чаще, а крысы ускоряются. Все зоны — фиксированный пул,
## рисуются одним _draw; артобстрел идёт через LobPool.

enum Kind { ACID, SHOCK, LASER, COLLAPSE }

const CAPACITY := 20
const CAMP_SAMPLE := 0.25
const CAMP_WINDOW := 12
const CAMP_DISTANCE := 150.0
const FIRST_DELAY := 9.0
const ACID_LIFE := 7.0
const ACID_RADIUS := 96.0
const SHOCK_RADIUS := 118.0
const LASER_WIDTH := 46.0
## Обвал (Свалка): с неба падает куча хлама — красное кольцо-предупреждение, удар, облако пыли (арт Астры).
const COLLAPSE_RADIUS := 92.0
const COLLAPSE_HIT := 26.0
const COLLAPSE_LIFE := 5.0
const ZAP_TIME := 0.45
const ART := "res://assets/vfx/hazard/"
static var _art: Dictionary = {}
const TELEGRAPH := Color("#ff2e4d")
const COLOR_ACID := Color("#7cff3d")
const COLOR_SHOCK := Color("#35e6ff")
const SHELL_DAMAGE := 18.0
const ACID_DPS_HIT := 10.0
const SHOCK_HIT := 24.0
const LASER_HIT := 28.0

var player: Player
var director: WaveDirector
var map: LevelSpawner
var fx: FxManager
var camping := false

var _kind := PackedInt32Array()
var _pos := PackedVector2Array()
var _dir := PackedVector2Array()
var _time := PackedFloat32Array()
var _warn := PackedFloat32Array()
var _life := PackedFloat32Array()
var _fired := PackedByteArray()
var _next := 0
var _timer := FIRST_DELAY
var _sample_timer := 0.0
var _history: Array[Vector2] = []
var _tick := 0.0
var _rocket: Texture2D
var _blast: Texture2D
var _batch := PolyBatch.new()


func setup(target: Player, wave_director: WaveDirector, level: LevelSpawner, effects: FxManager) -> void:
	player = target
	director = wave_director
	map = level
	fx = effects
	z_index = 2
	_kind.resize(CAPACITY)
	_pos.resize(CAPACITY)
	_dir.resize(CAPACITY)
	_time.resize(CAPACITY)
	_warn.resize(CAPACITY)
	_life.resize(CAPACITY)
	_fired.resize(CAPACITY)
	_life.fill(-1.0)
	_rocket = ArenaProp.texture_of("res://assets/bosses/rocket.png")
	_blast = ArenaProp.texture_of("res://assets/props/ch1/fx_explosion.png")


func attach_level(level: LevelSpawner) -> void:
	map = level
	clear()


func clear() -> void:
	_life.fill(-1.0)
	_timer = FIRST_DELAY
	_history.clear()
	camping = false
	Enemy.global_speed_mult = 1.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	if player == null or director == null or player.is_dead:
		return
	var fighting := director.phase == WaveDirector.Phase.FIGHT
	_track_camping(delta)
	_tick_zones(delta)
	var wave := maxi(director.wave_number, 1)
	Enemy.global_speed_mult = (1.0 + minf(0.012 * wave, 0.14) + (0.22 if camping else 0.0)) if fighting else 1.0
	if not fighting:
		return
	_timer -= delta
	if camping:
		_timer = minf(_timer, 2.0)
	if _timer > 0.0:
		return
	var base := clampf(11.0 - 0.55 * wave, 4.6, 11.0) * (0.7 if director.is_boss_wave() else 1.0)
	_timer = base * randf_range(0.8, 1.2)
	_spawn_event(wave)


func _track_camping(delta: float) -> void:
	_sample_timer -= delta
	if _sample_timer > 0.0:
		return
	_sample_timer = CAMP_SAMPLE
	_history.append(player.global_position)
	if _history.size() > CAMP_WINDOW:
		_history.pop_front()
	if _history.size() < CAMP_WINDOW:
		camping = false
		return
	var far := 0.0
	for point in _history:
		far = maxf(far, point.distance_to(_history[0]))
	camping = far < CAMP_DISTANCE


func _damage_mult() -> float:
	return director.get_damage_mult()


func _spawn_event(wave: int) -> void:
	var bank := director.chapter_index % 2 == 1
	var options: Array = ["shells"]
	if wave >= 2:
		options.append("shock")
		if not bank:
			options.append("collapse")
	if wave >= 3:
		options.append("laser" if bank else "acid")
	if wave >= 5:
		# В Банке кислоты нет: там парк и вода, вместо луж — второй лазер.
		options.append("laser")
		options.append("shells")
	var pick: String = options.pick_random()
	var exact := camping or randf() < 0.35
	var center := _target_point(exact)
	match pick:
		"shells":
			_barrage(center, 3 + mini(wave / 2, 5), exact)
		"acid":
			_add_zone(Kind.ACID, center, Vector2.ZERO, 1.0)
			if wave >= 6:
				_add_zone(Kind.ACID, _target_point(false), Vector2.ZERO, 1.2)
		"shock":
			_add_zone(Kind.SHOCK, center, Vector2.ZERO, 1.35)
			if wave >= 4:
				_add_zone(Kind.SHOCK, _target_point(false), Vector2.ZERO, 1.6)
		"collapse":
			_add_zone(Kind.COLLAPSE, center, Vector2(randi() % 3, randi() % 3), 1.3)
			if wave >= 5:
				_add_zone(Kind.COLLAPSE, _target_point(false), Vector2(randi() % 3, randi() % 3), 1.6)
		"laser":
			var horizontal := randf() < 0.5
			_add_zone(Kind.LASER, center, Vector2.RIGHT if horizontal else Vector2.DOWN, 1.55)
			if wave >= 7:
				_add_zone(Kind.LASER, _target_point(false), Vector2.DOWN if horizontal else Vector2.RIGHT, 1.9)


func _target_point(exact: bool) -> Vector2:
	var at := player.global_position
	if exact:
		at += player.velocity * 0.5
	else:
		at += Vector2.from_angle(randf() * TAU) * randf_range(180.0, 520.0)
	var inner := map.bounds.grow(-150.0)
	return at.clamp(inner.position, inner.end)


func _barrage(center: Vector2, count: int, exact: bool) -> void:
	if LobPool.active == null:
		return
	var damage := SHELL_DAMAGE * _damage_mult()
	for i in count:
		var at := center if (i == 0 and exact) else center + Vector2.from_angle(randf() * TAU) * randf_range(60.0, 240.0)
		var from := at + Vector2(randf_range(-90.0, 90.0), -900.0)
		LobPool.active.throw(from, at, 1.25 + 0.12 * i, 0.0, 84.0, damage, Color("#ff5a1f"), _rocket, _blast, 40.0, 0.0)
	SoundManager.play(&"beam_charge", -12.0, false)


func _add_zone(kind: int, at: Vector2, direction: Vector2, warn: float) -> void:
	var k := _next
	_next = (_next + 1) % CAPACITY
	_kind[k] = kind
	_pos[k] = at
	_dir[k] = direction
	_time[k] = 0.0
	_warn[k] = warn
	_life[k] = warn + (ACID_LIFE if kind == Kind.ACID else (COLLAPSE_LIFE if kind == Kind.COLLAPSE else ZAP_TIME))
	_fired[k] = 0


func _tick_zones(delta: float) -> void:
	var any := false
	_tick -= delta
	var pulse := _tick <= 0.0
	if pulse:
		_tick = 0.5
	for k in CAPACITY:
		if _life[k] < 0.0:
			continue
		any = true
		_time[k] += delta
		_life[k] -= delta
		if _life[k] <= 0.0:
			_life[k] = -1.0
			continue
		if _time[k] < _warn[k]:
			continue
		match _kind[k]:
			Kind.ACID:
				if pulse and _inside_circle(_pos[k], ACID_RADIUS):
					Player.last_source = &"acid"
					player.take_damage(ACID_DPS_HIT * _damage_mult())
					fx.burst(player.global_position, COLOR_ACID, 6, 160.0, 3.0)
				if _fired[k] == 0:
					_fired[k] = 1
					SoundManager.play(&"acid_splash", -8.0)
					fx.burst(_pos[k], COLOR_ACID, 18, 260.0, 4.0)
			Kind.SHOCK:
				if _fired[k] == 0:
					_fired[k] = 1
					_zap(k)
			Kind.LASER:
				if _fired[k] == 0:
					_fired[k] = 1
					_beam(k)
			Kind.COLLAPSE:
				if _fired[k] == 0:
					_fired[k] = 1
					_crash(k)
	queue_redraw()
	if not any:
		queue_redraw()


func _inside_circle(center: Vector2, radius: float) -> bool:
	return player.global_position.distance_squared_to(center) < (radius + Player.RADIUS * 0.5) * (radius + Player.RADIUS * 0.5)


func _zap(k: int) -> void:
	var at := _pos[k]
	fx.ring(at, COLOR_SHOCK, SHOCK_RADIUS)
	fx.burst(at, COLOR_SHOCK, 24, 380.0, 4.0)
	fx.light_flash(at, COLOR_SHOCK, 1.6, SHOCK_RADIUS * 2.4, 0.4)
	for i in 4:
		var angle := randf() * TAU
		fx.bolt(at, at + Vector2.from_angle(angle) * SHOCK_RADIUS * 0.95, COLOR_SHOCK)
	SoundManager.play_pitched(&"hit", 2.0, -4.0)
	if _inside_circle(at, SHOCK_RADIUS):
		Player.last_source = &"shock"
		player.take_damage(SHOCK_HIT * _damage_mult())
		player.snare(0.45)


func _crash(k: int) -> void:
	var at := _pos[k]
	SoundManager.play(&"crate_break", -2.0, false)
	SoundManager.play_pitched(&"explosion", 0.7, -6.0)
	fx.burst(at, Color("#c9a77a"), 22, 300.0, 5.0)
	if _inside_circle(at, COLLAPSE_RADIUS):
		Player.last_source = &"collapse"
		player.take_damage(COLLAPSE_HIT * _damage_mult())
		player.snare(0.35)


static func _tex(name: String) -> Texture2D:
	if not _art.has(name):
		var path := ART + name + ".png"
		_art[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _art[name]


func _beam(k: int) -> void:
	var at := _pos[k]
	var direction := _dir[k]
	var extent := map.bounds.size.length()
	var from := at - direction * extent
	var to := at + direction * extent
	SoundManager.play(&"shot_rail", -8.0, false)
	for step in range(-4, 5):
		var p := at + direction * step * 150.0
		if map.bounds.has_point(p):
			fx.burst(p, Color("#ff5a7a"), 4, 200.0, 3.0)
	fx.bolt(from.clamp(map.bounds.position, map.bounds.end), to.clamp(map.bounds.position, map.bounds.end), Color("#ff5a7a"))
	var along := player.global_position - at
	var perpendicular := absf(along.dot(direction.orthogonal()))
	if perpendicular < LASER_WIDTH * 0.5 + Player.RADIUS * 0.6:
		Player.last_source = &"laser"
		player.take_damage(LASER_HIT * _damage_mult())


func _draw() -> void:
	var clock := Time.get_ticks_msec() * 0.001
	for k in CAPACITY:
		if _life[k] < 0.0:
			continue
		var warming := _time[k] < _warn[k]
		var t := clampf(_time[k] / maxf(_warn[k], 0.01), 0.0, 1.0)
		match _kind[k]:
			Kind.ACID:
				_draw_acid(k, warming, t, clock)
			Kind.SHOCK:
				_draw_ring_zone(_pos[k], SHOCK_RADIUS, t if warming else 1.0, COLOR_SHOCK, warming, clock)
				_draw_shock_art(k, warming, clock)
			Kind.COLLAPSE:
				_draw_collapse(k, warming, t)
			Kind.LASER:
				_draw_laser(k, warming, t, clock)


## Ловушка Короля: магнитная установка с мерцающими катушками, в момент удара — разряд (8 кадров Астры).
func _draw_shock_art(k: int, warming: bool, clock: float) -> void:
	var at := _pos[k]
	if warming:
		var drum := _tex("king_magnet_%02d" % (1 + int(clock * 8.0) % 4))
		if drum != null:
			var w := 120.0
			draw_texture_rect(drum, Rect2(at - Vector2(w * 0.5, w * 0.7), Vector2(w, w)), false)
		return
	var frame := clampi(int((_time[k] - _warn[k]) / ZAP_TIME * 8.0), 0, 7)
	var spark := _tex("king_electric_%02d" % (frame + 1))
	if spark != null:
		var size := SHOCK_RADIUS * 2.3
		draw_texture_rect(spark, Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), false)


## Обвал: кольцо-предупреждение сжимается, куча хлама падает сверху, пыль клубится и тает, обломки лежат и гаснут.
func _draw_collapse(k: int, warming: bool, t: float) -> void:
	var at := _pos[k]
	if warming:
		var ring := _tex("collapse_warning")
		if ring != null:
			var r := COLLAPSE_RADIUS * (1.6 - 0.6 * t)
			draw_texture_rect(ring, Rect2(at - Vector2(r, r * 0.62), Vector2(r * 2.0, r * 1.24)), false, Color(1, 1, 1, 0.4 + 0.6 * t))
		# Тень падающей кучи растёт.
		SoftGlow.pool(self, at, COLLAPSE_RADIUS * t, 0.6, Color(0, 0, 0, 0.35 * t))
		if t > 0.55:
			_draw_debris(k, at - Vector2(0, (1.0 - t) / 0.45 * 420.0), 1.0)
		return
	var since := _time[k] - _warn[k]
	var fade := clampf(_life[k] / 1.0, 0.0, 1.0)
	_draw_debris(k, at, fade)
	var frame := int(since / 0.09)
	if frame < 8:
		var dust := _tex("collapse_dust_%02d" % (frame + 1))
		if dust != null:
			var size := COLLAPSE_RADIUS * 2.8
			draw_texture_rect(dust, Rect2(at - Vector2(size * 0.5, size * 0.72), Vector2(size, size)), false)


func _draw_debris(k: int, at: Vector2, alpha: float) -> void:
	var sizes := ["small", "medium", "large"]
	var pick := _dir[k]
	var tex := _tex("collapse_%s_%02d" % [sizes[int(pick.x) % 3], 1 + int(pick.y) % 3])
	if tex == null:
		return
	var w := COLLAPSE_RADIUS * (1.3 + 0.35 * float(int(pick.x) % 3))
	draw_texture_rect(tex, Rect2(at - Vector2(w * 0.5, w * 0.78), Vector2(w, w)), false, Color(1, 1, 1, alpha))


func _draw_acid(k: int, warming: bool, t: float, clock: float) -> void:
	var at := _pos[k]
	if warming:
		_draw_ring_zone(at, ACID_RADIUS, t, COLOR_ACID, true, clock)
		return
	var fade := clampf(_life[k] / 1.2, 0.0, 1.0)
	SoftGlow.pool(self, at, ACID_RADIUS * 1.15, 0.6, Color(COLOR_ACID, 0.16 * fade))
	LiquidDraw.puddle(self, at, ACID_RADIUS, COLOR_ACID.darkened(0.15), k, clock, fade)


func _draw_ring_zone(at: Vector2, radius: float, t: float, color: Color, warming: bool, clock: float) -> void:
	var urgent := (0.5 + 0.5 * sin(clock * 22.0)) if warming and t > 0.7 else 0.0
	var tint := color.lerp(Color(1.0, 0.92, 0.5), urgent * 0.6)
	SoftGlow.pool(self, at, radius * 1.08, 0.6, Color(0.05, 0.0, 0.08, 0.16))
	SoftGlow.pool(self, at, radius * (0.25 + 0.75 * t if warming else 1.0), 0.6, Color(tint, 0.2 if warming else 0.38))
	SoftGlow.rim(self, at, radius * 1.1, 0.6, Color(tint, 0.5 + 0.3 * urgent if warming else 0.55))


func _draw_laser(k: int, warming: bool, t: float, clock: float) -> void:
	var at := _pos[k]
	var direction := _dir[k]
	var reach := map.bounds.size.length()
	var a := (at - direction * reach).clamp(map.bounds.position, map.bounds.end)
	var b := (at + direction * reach).clamp(map.bounds.position, map.bounds.end)
	var normal := direction.orthogonal() * LASER_WIDTH * 0.5
	var batch := _batch
	if warming:
		var blink := 0.35 + 0.65 * absf(sin(clock * (8.0 + 16.0 * t)))
		batch.polygon(PackedVector2Array([a + normal, b + normal, b - normal, a - normal]), Color(TELEGRAPH, 0.12 + 0.1 * t))
		batch.line(a + normal, b + normal, Color(TELEGRAPH, 0.8 * blink), 3.0)
		batch.line(a - normal, b - normal, Color(TELEGRAPH, 0.8 * blink), 3.0)
		batch.line(a, b, Color(1.0, 0.5, 0.5, 0.5 * blink), 2.0)
	else:
		var fade := clampf(_life[k] / 0.45, 0.0, 1.0)
		batch.polygon(PackedVector2Array([a + normal, b + normal, b - normal, a - normal]), Color(1.0, 0.35, 0.45, 0.6 * fade))
		batch.line(a, b, Color(1, 1, 1, fade), LASER_WIDTH * 0.35 * fade + 2.0)
	batch.flush(self)
