class_name DragonArena
extends Node2D
## «Алтарь Вечности» по документу геометрии рейда. Окружность R = 800 с центром (0, 0):
##   Центральное ядро   0…250  — сюда приземляется Сириус; удар приземления отбрасывает Енота.
##   Призменное кольцо  250…600 — кристаллы-укрытия в полярных координатах r ∈ [300, 550].
##   Мёртвая зона       > 800  — стен нет: Енот, вышедший за край, падает в космос.
## Менеджер кристаллов раз в CRYSTAL_CHECK_INTERVAL проверяет живые кристаллы и, если их меньше
## MIN_ALIVE_CRYSTALS, ставит новые в секторе напротив Енота (перебежки через опасные зоны).
## Кристаллы — пул узлов PrismCrystal: «спавн» = place() разрушенного узла, без instantiate.
##
## Слои: космос — ParallaxBackground (звёзды + туманность с вращением UV в шейдере),
## пол z -10 (обсидиан), подсказки тени z -8, мир z 0 (Y-Sort), FX z 10.

signal crystal_destroyed(crystal: PrismCrystal)
signal ice_cracking
signal ice_dropped(radius: float)

const RADIUS := 1000.0
const CORE_RADIUS := 300.0
const RING_INNER := 300.0
const RING_OUTER := 760.0
const CRYSTAL_MIN_R := 380.0
const CRYSTAL_MAX_R := 700.0
const CRYSTAL_POOL := 8
const START_CRYSTALS := 6
const MIN_ALIVE_CRYSTALS := 4
const CRYSTAL_CHECK_INTERVAL := 30.0
const CRYSTAL_SPACING := 180.0
const OPPOSITE_SPREAD := PI / 3.0
const RUNE_COUNT := 44
const RUNE_BREATH_SPEED := 1.6
const SAFE_RADIUS_PHASE2 := 820.0
const SAFE_RADIUS_PHASE3 := 600.0
const CRACK_WARN := 3.5
const CRACK_DROP := 1.4
const WATER := Color("#031022")

const SPACE := Color("#061226")
const FURY_SPACE := Color("#1a1040")
const OBSIDIAN := Color("#1d4a75")
const EDGE := Color("#bff0ff")
const NEBULA_PURPLE := Color("#0d3566")
const NEBULA_PINK := Color("#1c8aa6")
const RUNE_TEAL := Color("#e8fbff")
const RUNE_PURPLE := Color("#8fd0ff")
const PUDDLE_ART := "res://assets/raid/ice_puddle.png"
const GLINT_ART := "res://assets/vfx/ice_glints.png"
const GLINT_CELL := 192.0
const DECAL_COUNT := 20

const RUNE_PATTERNS := [
	[Vector2(0, -1), Vector2(0, 1), Vector2(-0.7, -0.3), Vector2(0.7, -0.3)],
	[Vector2(-0.8, -1), Vector2(0.8, 1), Vector2(0.8, -1), Vector2(-0.8, 1), Vector2(-0.8, 0), Vector2(0.8, 0)],
	[Vector2(-0.7, 1), Vector2(0, -1), Vector2(0, -1), Vector2(0.7, 1), Vector2(-0.4, 0.2), Vector2(0.4, 0.2)],
	[Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, -0.8), Vector2(0, 1), Vector2(0, 1), Vector2(-0.8, -0.8)],
	[Vector2(0, -1), Vector2(0, 1), Vector2(-0.8, -0.6), Vector2(0, 0), Vector2(0, 0), Vector2(0.8, 0.6)],
	[Vector2(-0.8, -1), Vector2(-0.8, 1), Vector2(-0.8, 0), Vector2(0.8, -1), Vector2(-0.8, 0), Vector2(0.8, 1)],
]

var crystals: Array[PrismCrystal] = []
var crystal_spawning := true
var min_alive_crystals := MIN_ALIVE_CRYSTALS
## Радиус, внутри которого лёд ещё держит: сужается по фазам боя.
var safe_radius := RADIUS

var _player: Player
var _world: Node2D
var _check_timer := CRYSTAL_CHECK_INTERVAL
var _parallax: ParallaxBackground
var _nebula_material: ShaderMaterial
var _shadow_hints: ShadowHints
var _default_clear := Color.BLACK
var _crack_state := 0
var _crack_time := 0.0
var _crack_from := RADIUS
var _crack_to := RADIUS
var _thin_ice: ThinIce


func build(layers: BiomeLayers, player: Player) -> void:
	_player = player
	_world = layers.world
	_default_clear = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.BLACK)
	RenderingServer.set_default_clear_color(SPACE)
	_build_space()
	var runes := RuneRing.new()
	runes.radius = RADIUS - 40.0
	add_child(runes)
	_shadow_hints = ShadowHints.new()
	_shadow_hints.arena = self
	_shadow_hints.z_index = -8
	_shadow_hints.z_as_relative = false
	add_child(_shadow_hints)
	_build_ambient(layers.fx)
	_thin_ice = ThinIce.new()
	_thin_ice.arena = self
	_thin_ice.z_index = -7
	_thin_ice.z_as_relative = false
	add_child(_thin_ice)
	_build_crystal_pool(layers)
	queue_redraw()


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(_default_clear)


func is_in_void(point: Vector2) -> bool:
	return point.length() > safe_radius


func is_in_core(point: Vector2) -> bool:
	return point.length() <= CORE_RADIUS


func clamp_inside(point: Vector2, margin: float) -> Vector2:
	return point.limit_length(safe_radius - margin)


func random_point(margin: float) -> Vector2:
	return Vector2.from_angle(randf() * TAU) * sqrt(randf()) * (safe_radius - margin)


func alive_crystal_count() -> int:
	var count := 0
	for crystal in crystals:
		if crystal.is_intact():
			count += 1
	return count


## Проверка тени: защищён ли круг радиусом body_radius в точке point от источника source.
func is_shielded(point: Vector2, source: Vector2, body_radius: float) -> bool:
	for crystal in crystals:
		if crystal.shields_point(point, source, body_radius):
			return true
	return false


## Подсказка на полу: откуда сейчас светит луч (Vector2.INF — луча нет).
func set_shadow_source(source: Vector2) -> void:
	_shadow_hints.source = source
	_shadow_hints.queue_redraw()


## Фаза ярости: космос багровеет, новые кристаллы больше не появляются.
func enter_fury() -> void:
	crystal_spawning = false
	RenderingServer.set_default_clear_color(FURY_SPACE)
	var tween := create_tween()
	tween.tween_method(func(a: float) -> void: _nebula_material.set_shader_parameter(&"crimson", Color(FURY_SPACE.lightened(0.25), a)), 0.0, 0.6, 1.2)


## «Тонкий лёд»: за CRACK_WARN секунд край трескается, затем за CRACK_DROP уходит под воду.
func shrink_to(target: float) -> void:
	if target >= safe_radius or (_crack_state != 0 and target >= _crack_to):
		return
	_crack_from = safe_radius
	_crack_to = target
	_crack_state = 1
	_crack_time = 0.0
	ice_cracking.emit()
	SoundManager.play(&"ice_blast", -6.0, false)


func is_cracking() -> bool:
	return _crack_state == 1


func _tick_crack(delta: float) -> void:
	_crack_time += delta
	if _crack_state == 1:
		_thin_ice.queue_redraw()
		if _crack_time >= CRACK_WARN:
			_crack_state = 2
			_crack_time = 0.0
			SoundManager.play(&"dragon_land", -4.0, false)
		return
	var t := clampf(_crack_time / CRACK_DROP, 0.0, 1.0)
	safe_radius = lerpf(_crack_from, _crack_to, t * t * (3.0 - 2.0 * t))
	_thin_ice.queue_redraw()
	if t >= 1.0:
		_crack_state = 0
		safe_radius = _crack_to
		for crystal in crystals:
			if crystal.is_intact() and crystal.position.length() > safe_radius - 70.0:
				crystal.retire()
		ice_dropped.emit(safe_radius)


func _physics_process(delta: float) -> void:
	if _crack_state != 0:
		_tick_crack(delta)
	if not crystal_spawning or _player == null:
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CRYSTAL_CHECK_INTERVAL
	if alive_crystal_count() < min_alive_crystals:
		for crystal in crystals:
			if not crystal.is_intact() and alive_crystal_count() < START_CRYSTALS:
				crystal.place(_opposite_sector_point())


## Кристаллы: Vector2(randf_range(300, 550), 0).rotated(randf_range(0, TAU)) с разносом.
func _build_crystal_pool(layers: BiomeLayers) -> void:
	for i in CRYSTAL_POOL:
		var crystal := PrismCrystal.new()
		crystal.setup(layers.fx)
		crystal.destroyed.connect(func(c: PrismCrystal) -> void: crystal_destroyed.emit(c))
		layers.world.add_child(crystal)
		crystals.append(crystal)
		if i < START_CRYSTALS:
			crystal.place(_free_polar_point(func() -> float: return randf_range(0.0, TAU)))
		else:
			crystal.retire()


func _opposite_sector_point() -> Vector2:
	var player_angle := _player.global_position.angle() if _player.global_position.length() > 1.0 else randf() * TAU
	return _free_polar_point(func() -> float: return player_angle + PI + randf_range(-OPPOSITE_SPREAD, OPPOSITE_SPREAD))


func _free_polar_point(angle_source: Callable) -> Vector2:
	var best := Vector2.ZERO
	for attempt in 30:
		var p := Vector2(randf_range(CRYSTAL_MIN_R, CRYSTAL_MAX_R), 0.0).rotated(angle_source.call())
		best = p
		var ok := true
		for crystal in crystals:
			if crystal.is_intact() and crystal.position.distance_to(p) < CRYSTAL_SPACING:
				ok = false
				break
		if ok and (_player == null or _player.global_position.distance_to(p) > PrismCrystal.FIELD_RADIUS + 40.0):
			return p
	return best


func _build_space() -> void:
	_parallax = ParallaxBackground.new()
	_parallax.layer = -100
	add_child(_parallax)

	var nebula_layer := ParallaxLayer.new()
	nebula_layer.motion_scale = Vector2(0.1, 0.1)
	_parallax.add_child(nebula_layer)
	var nebula := Sprite2D.new()
	nebula.texture = _make_nebula_texture()
	nebula.scale = Vector2.ONE * 28.0
	_nebula_material = ShaderMaterial.new()
	_nebula_material.shader = load("res://shaders/nebula_rotate.gdshader")
	nebula.material = _nebula_material
	nebula_layer.add_child(nebula)

	var star_layer := ParallaxLayer.new()
	star_layer.motion_scale = Vector2(0.25, 0.25)
	_parallax.add_child(star_layer)
	star_layer.add_child(StarField.new())


## Туманность: шум FastNoiseLite в 128×128, раскрашенный в #4B0082 → #8B008B.
static func _make_nebula_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n := clampf(noise.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			var color := NEBULA_PURPLE.lerp(NEBULA_PINK, n)
			image.set_pixel(x, y, Color(color, smoothstep(0.35, 0.85, n) * 0.55))
	return ImageTexture.create_from_image(image)


func _build_ambient(fx_layer: Node2D) -> void:
	for texture in [ParticleFactory.tex_rhombus(), ParticleFactory.tex_triangle()]:
		var m := ParticleFactory.material({
			"direction": Vector2(0.3, 1.0), "spread": 14.0, "velocity": Vector2(40, 110),
			"spin": Vector2(-60, 60), "angle": Vector2(0, 360), "scale": Vector2(0.5, 1.3),
			"colors": [Color(1, 1, 1, 0.75), Color(RUNE_PURPLE, 0.6)],
			"emission_box": Vector2(RADIUS, RADIUS), "fade_from": 0.25,
		})
		var p := ParticleFactory.stream(texture, 60, 9.0, m)
		p.preprocess = 9.0
		p.visibility_rect = Rect2(-RADIUS * 1.3, -RADIUS * 1.3, RADIUS * 2.6, RADIUS * 2.6)
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = additive
		fx_layer.add_child(p)
		p.emitting = true


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 60.0, Color(EDGE, 0.05))
	draw_circle(Vector2.ZERO, RADIUS + 26.0, Color(1, 1, 1, 0.9))
	draw_circle(Vector2.ZERO, RADIUS + 8.0, Color("#cfeeff"))
	draw_circle(Vector2.ZERO, RADIUS, OBSIDIAN)
	for ring in 5:
		draw_circle(Vector2.ZERO, RADIUS * (0.9 - ring * 0.17), OBSIDIAN.lerp(Color("#4f93c4"), 0.12 * (ring + 1)))
	_draw_decals()
	_draw_cracks()
	_draw_mirror_sheen()
	draw_arc(Vector2.ZERO, RING_OUTER, 0.0, TAU, 96, Color(RUNE_PURPLE, 0.14), 2.0, true)
	_draw_core_sigil()
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 128, Color(EDGE, 0.3), 16.0, true)


## Блики и наледь на зеркальном льду: ячейки листа Astra (лужи, зигзаги, завитки, искры, осколки).
func _draw_decals() -> void:
	var sheet := ArenaProp.texture_of(GLINT_ART)
	if sheet == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for i in DECAL_COUNT:
		var cell := rng.randi_range(0, 7)
		var at := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (RADIUS - 140.0)
		var w := rng.randf_range(170.0, 300.0) * (0.55 if cell == 3 else 1.0)
		var src := Rect2((cell % 4) * GLINT_CELL, (cell / 4) * GLINT_CELL, GLINT_CELL, GLINT_CELL)
		draw_texture_rect_region(sheet, Rect2(at - Vector2(w, w * 0.62) * 0.5, Vector2(w, w * 0.62)), src, Color(1, 1, 1, 0.34))


func _draw_cracks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1993
	for i in 26:
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (RADIUS - 60.0)
		var a := rng.randf() * TAU
		var pts := PackedVector2Array([p])
		for k in rng.randi_range(3, 6):
			a += rng.randf_range(-0.7, 0.7)
			p += Vector2.from_angle(a) * rng.randf_range(30.0, 80.0)
			pts.append(p)
		draw_polyline(pts, Color(0.85, 0.96, 1.0, 0.22), 2.0, true)


func _draw_mirror_sheen() -> void:
	var clip := PackedVector2Array()
	for i in 64:
		clip.append(Vector2.from_angle(TAU * i / 64.0) * (RADIUS - 6.0))
	for k in 5:
		var x := -RADIUS + k * RADIUS * 0.45
		var band := PackedVector2Array([
			Vector2(x, -RADIUS), Vector2(x + 90.0, -RADIUS),
			Vector2(x + 90.0 - RADIUS * 0.55, RADIUS), Vector2(x - RADIUS * 0.55, RADIUS),
		])
		for poly in Geometry2D.intersect_polygons(band, clip):
			draw_colored_polygon(poly, Color(1, 1, 1, 0.03))


## Ядро приземления: опасная зона отмечена красноватым кругом с рунами.
func _draw_core_sigil() -> void:
	draw_circle(Vector2.ZERO, CORE_RADIUS, Color("#ff4466", 0.06))
	draw_arc(Vector2.ZERO, CORE_RADIUS, 0.0, TAU, 64, Color("#ff6f8a", 0.55), 3.0, true)
	draw_arc(Vector2.ZERO, CORE_RADIUS - 50.0, 0.0, TAU, 64, Color(RUNE_PURPLE, 0.5), 2.0, true)
	for i in 12:
		var dir := Vector2.from_angle(TAU * i / 12.0)
		draw_line(dir * (CORE_RADIUS - 50.0), dir * CORE_RADIUS, Color(RUNE_TEAL, 0.4), 2.0, true)


## Вода на месте провалившегося льда и мигающая трещина на той полосе, что вот-вот уйдёт вниз.
class ThinIce:
	extends Node2D
	var arena: DragonArena

	func _draw() -> void:
		var safe := arena.safe_radius
		if safe < DragonArena.RADIUS - 0.5:
			var outer := DragonArena.RADIUS + 34.0
			draw_arc(Vector2.ZERO, (safe + outer) * 0.5, 0.0, TAU, 128, Color(DragonArena.WATER, 0.97), outer - safe + 2.0, true)
			draw_arc(Vector2.ZERO, safe, 0.0, TAU, 128, Color(1, 1, 1, 0.85), 5.0, true)
			draw_arc(Vector2.ZERO, safe - 8.0, 0.0, TAU, 128, Color(DragonArena.EDGE, 0.35), 10.0, true)
		if arena._crack_state == 1:
			var target := arena._crack_to
			var from := arena._crack_from
			var blink := 0.5 + 0.5 * sin(arena._crack_time * 14.0)
			draw_arc(Vector2.ZERO, (target + from) * 0.5, 0.0, TAU, 128, Color(1.0, 0.55, 0.45, 0.10 + 0.14 * blink), from - target, true)
			draw_arc(Vector2.ZERO, target, 0.0, TAU, 128, Color(1.0, 0.85, 0.8, 0.5 + 0.4 * blink), 6.0, true)
			var rng := RandomNumberGenerator.new()
			rng.seed = 4242
			for i in 46:
				var a := TAU * i / 46.0 + rng.randf_range(-0.05, 0.05)
				var p := Vector2.from_angle(a) * target
				var pts := PackedVector2Array([p])
				for k in 3:
					a += rng.randf_range(-0.12, 0.12)
					p += Vector2.from_angle(a) * (from - target) / 3.0
					pts.append(p)
				draw_polyline(pts, Color(1.0, 0.95, 0.9, 0.35 + 0.4 * blink), 2.5, true)


## Подсветка геометрической тени кристаллов, пока горит луч.
class ShadowHints:
	extends Node2D
	var arena: DragonArena
	var source := Vector2.INF

	func _draw() -> void:
		if source == Vector2.INF:
			return
		for crystal in arena.crystals:
			var poly := crystal.shadow_polygon(source)
			if poly.size() >= 3:
				var clipped := Geometry2D.intersect_polygons(poly, _disc())
				for part in clipped:
					draw_colored_polygon(part, Color(EDGE, 0.1))

	func _disc() -> PackedVector2Array:
		var disc := PackedVector2Array()
		for i in 48:
			disc.append(Vector2.from_angle(TAU * i / 48.0) * RADIUS)
		return disc


class StarField:
	extends Node2D
	var _stars: Array = []
	var _time := 0.0

	func _init() -> void:
		for i in 420:
			var p := Vector2(randf_range(-2400, 2400), randf_range(-2400, 2400))
			var tint: Color = [Color.WHITE, Color("#9ff6ff"), Color("#ff9ff3")].pick_random()
			_stars.append([p, randf_range(1.5, 3.5), tint, randf() * TAU, randf_range(1.0, 3.0)])

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var twinkle := 0.35 + 0.65 * absf(sin(_time * s[4] + s[3]))
			draw_rect(Rect2(s[0], Vector2(s[1], s[1])), Color(s[2], twinkle))


class RuneRing:
	extends Node2D
	var radius := 760.0
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		modulate.a = 0.75 + 0.25 * sin(_time * RUNE_BREATH_SPEED)

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 555
		for i in 70:
			var angle := TAU * i / 70.0 + rng.randf_range(-0.03, 0.03)
			var base := Vector2.from_angle(angle) * (radius + 30.0)
			var tip := Vector2.from_angle(angle) * (radius - rng.randf_range(10.0, 60.0))
			var side := Vector2.from_angle(angle + PI * 0.5) * rng.randf_range(9.0, 18.0)
			draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(0.85, 0.96, 1.0, 0.9))
			draw_line(base, tip, Color(1, 1, 1, 0.9), 1.5, true)
