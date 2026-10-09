class_name LevelSpawner
extends Node2D
## Генератор арены главы (data/chapters.json) в духе концепт-листов «Arena Layout».
##
## Сетка grid_size клеток по CELL = 64 px, центр арены — (0, 0). По краю — кольцо стен
## (сверху толще: там задник с помостом босса), слева и справа — ворота спавна.
## Внутри: зоны пола (плиты/асфальт у Свалки; площадь, газоны, розовые дорожки у Банка),
## помост босса наверху, центральная декаль (граффити / золотой медальон), кластеры укрытий
## (крупный проп + мелкие рядом, раскладка «пуассоном» с минимальным шагом), разрушаемые
## объекты, фонари. Кольцо — сплошные коллизии; пропы на нём — только картинка.
##
## Перед установкой любого объекта: клетки под формой свободны, форма не пересекается с уже
## поставленными (Shape2D.collide). _ensure_connectivity() проверяет BFS, что каждая
## проходимая клетка достижима от старта, и сносит преграду, если нет.
## Y-Sort: все объекты — в layers.world, origin — точка касания пола.
## clear() удаляет всё построенное: так портал переносит забег в следующую главу без смены сцены.

signal object_destroyed(object: DestructibleObject)
signal crate_landed(crate: DestructibleObject)

enum CellType { EMPTY, WALL, COVER, DESTRUCTIBLE }
enum Zone { EDGE, FLOOR, LANE, LAWN, BOSS, GATE }

const CELL := 64.0
const RING_SIDE := 3
const RING_TOP := 5
const RING_BOTTOM := 3
const GATE_HALF := 2
const SECTOR := 10
const OVERLAP_MARGIN := 2.0
const FLOW_RADIUS := 26
const FLOW_INTERVAL := 0.3
const CRATE_POOL := 6
const AIRDROP_HEIGHT := 760.0
const AIRDROP_MIN := 240.0
const AIRDROP_MAX := 460.0
const COVER_SPACING := 330.0
const COVER_SPOTS := 7
## Доля предметов от исходной расстановки главы: карта не должна быть свалкой из контейнеров.
const PROP_DENSITY := 0.55
const SCENE_SPACING := 380.0
const RIPPLE_INTERVAL := 0.3
const PUDDLE_COUNT := 9
const BASE_AREA := 2000.0
const DOOR_GAP := 6
const DOOR_LEAD := 0.03
const WALL_THICK := 2
## Выживание: арена крупнее сюжетной (по каждой стороне), а на Свалке — сетка дорог на районы.
const SURVIVAL_SCALE := 1.5
const DISTRICTS := 3

var chapter: Dictionary = {}
var layout := "junkyard"
var grid_size := Vector2i(40, 50)
var cells := PackedByteArray()
var zones := PackedByteArray()
var destructibles: Array[DestructibleObject] = []
var player_start := Vector2.ZERO
var bounds := Rect2()
## Что видит камера: арена плюс район за забором (ArenaDistrict), если для стиля есть арт.
var view_bounds := Rect2()
var district: ArenaDistrict
var boss_rect := Rect2()
var story_gates: Dictionary = {}
var story_cells: Dictionary = {}
var boss_point := Vector2.ZERO
var _in_scene := false
var gate_rects: Array[Rect2] = []
## Засад в аренах нет; поле оставлено для совместимости с режимами, которые его читают.
var ambush_active := false

var _layers: BiomeLayers
var _player: Player
var _flow := FlowField.new()
var _flow_timer := 0.0
var _origin := Vector2.ZERO
var _owned: Array[Node] = []
var _shadows: Dictionary = {}
var _occupants: Dictionary = {}
var _wall_nodes: Dictionary = {}
var _crate_pool: Array[DestructibleObject] = []
var _cover_spots: Array[Vector2] = []
var _destr_done: Dictionary = {}
var _puddles: Array = []
var _ripple_timer := 0.0
var _portal: Portal
var _story: Dictionary = {}
var _boss_cells := Vector2i(16, 8)
var _area_scale := 1.0
var _story_clear: Array[Rect2] = []
var _flow_ready := false


func build(layers: BiomeLayers, chapter_def: Dictionary) -> void:
	_layers = layers
	chapter = chapter_def
	layout = str(chapter.get("layout", "junkyard"))
	var size: Array = chapter.get("size", [40, 50])
	grid_size = Vector2i(int(size[0]), int(size[1]))
	_story = chapter.get("story", {})
	_organic = _story.is_empty() and (layout == "junkyard" or layout == "bank")
	_noise.seed = randi()
	_park = null
	_streets = null
	_world_life = null
	_fire_spots.clear()
	_ropes.clear()
	_windows.clear()
	_music_spots.clear()
	# Дворы прошлой главы — иначе новые «упираются» в них, а шаги звучат по чужому покрытию.
	_sectors.clear()
	if _story.is_empty():
		grid_size = Vector2i((Vector2(grid_size) * SURVIVAL_SCALE).round())
	_origin = -Vector2(grid_size) * CELL * 0.5
	bounds = Rect2(_origin, Vector2(grid_size) * CELL)
	_area_scale = float(grid_size.x * grid_size.y) / BASE_AREA
	_story = chapter.get("story", {})
	if _story.has("boss_cells"):
		_boss_cells = Vector2i(int(_story["boss_cells"][0]), int(_story["boss_cells"][1]))
	cells.resize(grid_size.x * grid_size.y)
	cells.fill(CellType.EMPTY)
	zones.resize(grid_size.x * grid_size.y)
	_assign_zones()
	_build_floor()
	_build_shadow_layers()
	_build_walls()
	_river_points = PackedVector2Array()
	river = null
	if _organic:
		_plan_river()
	_build_district()
	if district == null:
		_build_border()
	if _organic:
		_build_river()
	_build_boss_zone()
	if _story.is_empty():
		_build_center()
	else:
		_build_story_walls()
	_build_gates()
	_build_lamps()
	_build_spotlights()
	_build_cover()
	_build_destructibles()
	_build_decor()
	_ensure_connectivity()
	_seal_story_gates()
	_build_crate_pool()
	_place_crate(player_start + Vector2(0, -210))
	_flow.setup(grid_size, _blocked_mask())
	_flow_ready = true


## Снос всего построенного (переход в следующую главу).
func clear() -> void:
	for node in _owned:
		if is_instance_valid(node):
			node.queue_free()
	_owned.clear()
	destructibles.clear()
	_occupants.clear()
	_wall_nodes.clear()
	_shadows.clear()
	_crate_pool.clear()
	_cover_spots.clear()
	_destr_done.clear()
	_puddles.clear()
	_lots.clear()
	_life = null
	for id in _life_lights:
		EnvLights.remove(id)
	_life_lights.clear()
	gate_rects.clear()
	story_gates.clear()
	story_cells.clear()
	_story_clear.clear()
	_portal = null


func attach_player(player: Player) -> void:
	if river != null:
		river.attach(player)
	_player = player
	if _world_life != null and is_instance_valid(_world_life):
		_world_life.attach(player)


# --- Координаты -------------------------------------------------------------------------------

## Поверхность под ногами для звука шагов.
func surface_at(p: Vector2) -> StringName:
	if river != null:
		var kind := river.surface_at(p)
		if kind != &"":
			return kind
	if boss_rect.has_point(p):
		return &"stone" if layout == "bank" else &"metal"
	for sec: Array in _sectors:
		if p.distance_to(sec[0]) < float(sec[1]):
			return sec[2]
	if layout == "bank":
		if _park != null and _park.distance_to(p) < _park.width * 0.5:
			return &"stone"
		return &"grass" if zone_at(p) == Zone.LAWN else &"stone"
	return &"asphalt"


func cell_to_world(cell: Vector2i) -> Vector2:
	return _origin + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


func world_to_cell(point: Vector2) -> Vector2i:
	var local := (point - _origin) / CELL
	return Vector2i(floori(local.x), floori(local.y))


func cell_type(cell: Vector2i) -> CellType:
	return cells[_index(cell)] if _inside(cell) else CellType.WALL


func zone_at(point: Vector2) -> Zone:
	var cell := world_to_cell(point)
	return zones[_index(cell)] if _inside(cell) else Zone.EDGE


func is_walkable(point: Vector2) -> bool:
	var cell := world_to_cell(point)
	return _inside(cell) and cells[_index(cell)] == CellType.EMPTY


func clamp_inside(point: Vector2, margin: float) -> Vector2:
	return point.clamp(bounds.position + Vector2.ONE * margin, bounds.end - Vector2.ONE * margin)


## Свободная точка в кольце [min_r, max_r] вокруг center: все клетки в радиусе clearance
## пусты, в первую очередь — точки, до которых есть путь по полю.
func find_spawn_point(center: Vector2, min_r: float, max_r: float, clearance: float = 0.0) -> Vector2:
	var inner := bounds.grow(-CELL - clearance)
	for attempt in 24:
		var p := center + Vector2.from_angle(randf() * TAU) * randf_range(min_r, max_r)
		if inner.has_point(p) and is_area_clear(p, clearance) and _flow.distance_at(world_to_cell(p)) != -1:
			return p
	for attempt in 24:
		var p := center + Vector2.from_angle(randf() * TAU) * randf_range(min_r, max_r)
		if inner.has_point(p) and is_area_clear(p, clearance):
			return p
	return _far_clear_point(center, min_r * 0.5, clearance)


## Запасной поиск, когда кольцо вокруг Енота целиком вне карты (угол арены, узкая вертикальная арена):
## любая свободная точка не ближе min_dist, иначе самая дальняя из найденных.
func _far_clear_point(center: Vector2, min_dist: float, clearance: float) -> Vector2:
	var inner := bounds.grow(-CELL - clearance)
	var best := Vector2.INF
	var best_dist := -1.0
	for attempt in 48:
		var p := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		if not is_area_clear(p, clearance):
			continue
		var d := p.distance_to(center)
		if d >= min_dist:
			return p
		if d > best_dist:
			best_dist = d
			best = p
	return best


## Точка в воротах спавна, дальняя от Енота не ближе min_distance (INF — все ворота рядом).
func gate_spawn_point(from: Vector2, min_distance: float, clearance: float) -> Vector2:
	var order := range(gate_rects.size())
	order.shuffle()
	for i in order:
		var r: Rect2 = gate_rects[i]
		if r.get_center().distance_to(from) < min_distance:
			continue
		for attempt in 8:
			var p := Vector2(randf_range(r.position.x + clearance, r.end.x - clearance), randf_range(r.position.y + clearance, r.end.y - clearance))
			if is_area_clear(p, clearance * 0.5):
				return p
	return Vector2.INF


func is_area_clear(point: Vector2, clearance: float) -> bool:
	var from := world_to_cell(point - Vector2.ONE * clearance)
	var to := world_to_cell(point + Vector2.ONE * clearance)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var cell := Vector2i(x, y)
			if not _inside(cell) or cells[_index(cell)] != CellType.EMPTY:
				return false
	return true


## Направление обхода стен к Еноту (ZERO — поле тут не посчитано, бежать напрямую).
func nav_direction(from: Vector2) -> Vector2:
	var cell := world_to_cell(from)
	var step := _flow.direction_at(cell)
	if step == Vector2.ZERO:
		return step
	var next := cell + Vector2i(roundi(step.x * 1.4142), roundi(step.y * 1.4142))
	var to_center := cell_to_world(next) - from
	return to_center.normalized() if to_center.length() > 4.0 else step


func find_nearest_destructible(from: Vector2, max_distance: float) -> DestructibleObject:
	var best: DestructibleObject = null
	var best_dist_sq := max_distance * max_distance
	for object in destructibles:
		if not object.is_intact():
			continue
		var dist_sq := from.distance_squared_to(object.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = object
	return best


func update_ripples(player: Player, fx: FxManager, delta: float) -> void:
	_ripple_timer -= delta
	if _ripple_timer > 0.0 or player.velocity.length_squared() < 400.0:
		return
	for p in _puddles:
		var local: Vector2 = (player.global_position - p[0]).rotated(-p[2])
		var r: Vector2 = p[1]
		if (local.x * local.x) / (r.x * r.x) + (local.y * local.y) / (r.y * r.y) <= 1.0:
			_ripple_timer = RIPPLE_INTERVAL
			fx.ring(player.global_position + Vector2(0, 18), Color(0.7, 0.6, 1.0, 0.45), 34.0)
			return


## Портал в следующую главу — на помосте босса.
func open_portal(main_color: Color, second_color: Color) -> Portal:
	if _portal == null:
		_portal = Portal.new()
		_own(_portal, _layers.world)
	_portal.open(boss_point + Vector2(0, 60), main_color, second_color)
	return _portal


func get_portal() -> Portal:
	return _portal


func _physics_process(delta: float) -> void:
	if _player == null or cells.is_empty():
		return
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		_flow_timer = FLOW_INTERVAL
		_flow.rebuild(_flow_target(world_to_cell(_player.global_position)), FLOW_RADIUS)


## Цель поля путей: клетка героя, а если он стоит вброд в протоке — ближайшая сухая клетка берега
## (иначе поле не строится, и толпа бежит напрямую в воду).
func _flow_target(cell: Vector2i) -> Vector2i:
	if not _inside(cell) or cells[_index(cell)] != CellType.WALL:
		return cell
	for r in range(1, 6):
		for dx in [-r, r]:
			var c := cell + Vector2i(dx, 0)
			if _inside(c) and cells[_index(c)] != CellType.WALL:
				return c
	return cell


# --- Зоны пола ---------------------------------------------------------------------------------

var _lane_shift := 0
var _lane_wide := 0.0
## Дороги-границы районов (номера клеток) и тема каждого района (id сцены, "" — площадь).
var _road_x: Array[int] = []
var _road_y: Array[int] = []
var _district_theme: Array[String] = []
## Прямоугольники собранных кварталов: остаток разрушаемого и мусор ставятся только в них.
var _lots: Array[Rect2] = []
## Ряды стен сюжетной карты (клетки): между ними — комнаты, в комнате два двора по сторонам дороги.
var _story_rows: Array[int] = []
## Выживание на Свалке — органическая местность без сетки дорог: шум задаёт «захламлённые» зоны и чистые
## площадки, точки интереса — пуассоновский разброс (_build_organic); земля Свалки — тайл района, у Банка дорожки по второму шуму.
var _organic := false
## Ряды стен сюжета с проёмами: [ряд клеток, левая клетка проёма] — по ним строится маршрут комнат.
var _story_gaps: Array = []
var _noise := _make_noise()
var _park: ParkPaths
var _river_points := PackedVector2Array()
## Секторы выживания: [центр, радиус].
var _sectors: Array = []
var _life: AmbientLife
var _life_lights: PackedInt32Array = PackedInt32Array()
var _river_side := 1.0
var river: AcidRiver
const POI_SPACING := 560.0
const RIVER_WIDTH := 200.0
## Среднее русло — на таком расстоянии от бокового забора.
const RIVER_EDGE := 470.0
const RIVER_BRIDGE := 430.0
const RIVER_BRIDGE_BAND := 70.0
const POI_OPEN := -0.16
const LOTS_PATH := "res://data/lots.json"


## Каждый забег двигает и утолщает дорожки, поэтому даже одна и та же глава каждый раз выглядит иначе.
func _roll_run_twist() -> void:
	_lane_shift = randi_range(-2, 2)
	_lane_wide = randf_range(-0.4, 1.0)
	_road_x.clear()
	_road_y.clear()
	if _story.is_empty() and not _organic:
		var inner_w := grid_size.x - RING_SIDE * 2
		var top := RING_TOP + _boss_cells.y + 2
		var inner_h := grid_size.y - RING_BOTTOM - top
		for k in range(1, DISTRICTS):
			_road_x.append(RING_SIDE + inner_w * k / DISTRICTS + randi_range(-2, 2))
			_road_y.append(top + inner_h * k / DISTRICTS + randi_range(-2, 2))


func _assign_zones() -> void:
	_roll_run_twist()
	var w := grid_size.x
	var h := grid_size.y
	var mid_y := h / 2
	var cx := w / 2
	boss_rect = _cells_rect(Vector2i(cx - _boss_cells.x / 2, RING_TOP), _boss_cells)
	boss_point = boss_rect.get_center() + Vector2(0, -20)
	for y in h:
		for x in w:
			var zone := Zone.FLOOR
			var in_gate := absi(y - mid_y) < GATE_HALF and (x < RING_SIDE or x >= w - RING_SIDE)
			if in_gate:
				zone = Zone.GATE
			elif x < RING_SIDE or x >= w - RING_SIDE or y < RING_TOP or y >= h - RING_BOTTOM:
				zone = Zone.EDGE
			elif x >= cx - _boss_cells.x / 2 and x < cx + _boss_cells.x / 2 and y < RING_TOP + _boss_cells.y:
				zone = Zone.BOSS
			elif layout == "bank":
				zone = _bank_zone(x, y, cx, mid_y)
			else:
				zone = Zone.LANE if _junk_lane(x, y, cx, mid_y) else Zone.FLOOR
			zones[_index(Vector2i(x, y))] = zone
	player_start = cell_to_world(Vector2i(cx, h - RING_BOTTOM - 4)) + Vector2(-CELL * 0.5, 0)


## Рисунок дорожек свалки по варианту локации: крест, кольцо, диагонали, три полосы.
func _junk_lane(x: int, y: int, cx: int, mid_y: int) -> bool:
	if _natural():
		return false
	var width := 2.0 + _lane_wide
	if not _road_x.is_empty():
		return _district_lane(x, y, cx, mid_y, width)
	match int(chapter.get("variant", 0)):
		1:
			var radius_x := 11 + _lane_shift
			var radius_y := 12 + _lane_shift
			var ring_x := absi(absi(x - cx) - radius_x)
			var ring_y := absi(absi(y - mid_y) - radius_y)
			var inside_x := absi(x - cx) <= radius_x + 2
			var inside_y := absi(y - mid_y) <= radius_y + 2
			return (ring_x < width and inside_y) or (ring_y < width and inside_x)
		2:
			var dx := float(x - cx) + 0.5
			var dy := float(y - mid_y + _lane_shift) * 0.8
			return absf(absf(dx) - absf(dy)) < 2.2 + _lane_wide and y >= RING_TOP + 6
		3:
			var gap := 12 + _lane_shift
			var mid := absi(y - mid_y - _lane_shift) < width
			return mid or absi(y - mid_y - gap) < width or absi(y - mid_y + gap) < width
	return absi(y - mid_y - _lane_shift) < width or (absi(x - cx + 0.5 + _lane_shift) < width and y >= RING_TOP + 6)


## Выживание на Свалке: сетка дорог делит арену на районы 3×3; вариант главы добавляет свою черту
## (1 — кольцо вокруг центральной площади, 3 — средняя поперечная улица).
func _district_lane(x: int, y: int, cx: int, mid_y: int, width: float) -> bool:
	if y < RING_TOP + _boss_cells.y + 1:
		return false
	for rx in _road_x:
		if absf(x - rx + 0.5) < width:
			return true
	for ry in _road_y:
		if absf(y - ry + 0.5) < width:
			return true
	match int(chapter.get("variant", 0)):
		1:
			var rx := absi(x - cx)
			var ry := absi(y - mid_y)
			return (absi(rx - 6) < 2 and ry <= 7) or (absi(ry - 6) < 2 and rx <= 7)
		3:
			return absi(y - mid_y) < 2 and x > RING_SIDE + 2 and x < grid_size.x - RING_SIDE - 2
	return false


## Номер района 0..8 по клетке (столбец + 3 × ряд); -1 — вне сетки районов.
func _district_of(p: Vector2) -> int:
	if _road_x.is_empty():
		return -1
	var c := world_to_cell(p)
	var col := 0
	for rx in _road_x:
		if c.x >= rx:
			col += 1
	var row := 0
	for ry in _road_y:
		if c.y >= ry:
			row += 1
	return col + DISTRICTS * row


## Банк: крест площади по центру, газоны по четвертям, розовые дорожки у боковых стен,
## круг площади под медальоном.
func _bank_zone(x: int, y: int, cx: int, mid_y: int) -> Zone:
	if x < RING_SIDE + 3 or x >= grid_size.x - RING_SIDE - 3:
		return Zone.LANE
	if _natural():
		# Парк поместья: сплошной газон, площадь и дорожки рисует ParkPaths, у помоста — мрамор.
		return Zone.FLOOR if y < RING_TOP + 8 else Zone.LAWN
	if not _road_x.is_empty():
		# Выживание: мощёные аллеи делят парк на районы, центральный район — площадь с медальоном.
		if y < RING_TOP + 8 or _district_of(cell_to_world(Vector2i(x, y))) == DISTRICTS * DISTRICTS / 2:
			return Zone.FLOOR
		for rx in _road_x:
			if absi(x - rx) < 2:
				return Zone.FLOOR
		for ry in _road_y:
			if absi(y - ry) < 2:
				return Zone.FLOOR
		return Zone.LAWN
	var variant := int(chapter.get("variant", 0))
	var medal := Vector2(x - cx + 0.5, (y - (mid_y + 8)) * 1.25).length() < 6.5
	if variant == 1:
		if absi(x - cx) + absi(y - mid_y) < 11 or y < RING_TOP + 8:
			return Zone.FLOOR
		return Zone.LAWN
	if variant == 2:
		var stripe := (x - RING_SIDE - 3) / 5
		if stripe % 2 == 0 or absi(y - mid_y) < 3 or y < RING_TOP + 8:
			return Zone.FLOOR
		return Zone.LAWN
	if absi(x - cx) < 5 or absi(y - mid_y) < 4 or medal or y < RING_TOP + 8:
		return Zone.FLOOR
	return Zone.LAWN


func _cells_rect(cell: Vector2i, size_cells: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(cell) * CELL, Vector2(size_cells) * CELL)


# --- Пол ---------------------------------------------------------------------------------------

## Тайлы пола — 128 px мира (2×2 клетки), атлас главы 256 px/тайл, ряд — по зоне.
## Земля Свалки во всех режимах — асфальт района Астры в трещинах (лужи, решётки, мусор): одна
## тайловая картинка на всю карту, как за забором — арена и район один мир.
const JUNK_GROUND := "res://assets/district/junkyard/rats_ground_tile.png"
const GROUND_SCALE := 1.35
static var _calm: Shader


static func _calm_shader() -> Shader:
	if _calm == null:
		_calm = Shader.new()
		_calm.code = """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	vec3 grey = vec3(l);
	vec3 rgb = mix(grey, c.rgb, 0.55);
	rgb = mix(vec3(0.22, 0.2, 0.3), rgb, 0.72);
	COLOR = vec4(rgb * vec3(0.92, 0.9, 1.0), c.a);
}
"""
	return _calm


func _build_floor() -> void:
	if layout == "junkyard" and ResourceLoader.exists(JUNK_GROUND):
		var ground := Sprite2D.new()
		ground.texture = load(JUNK_GROUND) as Texture2D
		ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ground.region_enabled = true
		ground.region_rect = Rect2(bounds.position, bounds.size)
		ground.centered = false
		ground.position = bounds.position
		ground.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
		# Земля спокойнее: приглушённые цвета и пониже контраст, крупнее рисунок (меньше повторов) —
		# лужи и мусор на ней больше не рябят в глазах и не спорят с врагами.
		ground.scale = Vector2.ONE * GROUND_SCALE
		ground.region_rect = Rect2(bounds.position / GROUND_SCALE, bounds.size / GROUND_SCALE)
		ground.position = bounds.position
		var calm := ShaderMaterial.new()
		calm.shader = _calm_shader()
		ground.material = calm
		_own(ground, self)
		_add_macro_overlay(float(chapter.get("macro", 1.0)))
		return
	var texture: Texture2D = ArenaProp.texture_of(str(chapter.get("floor", "")))
	if texture == null:
		return
	# Атлас — 8 плиток в ряд; плитка на экране — 2×2 клетки (128 px), поэтому атлас хранится в 128 px
	# на плитку: вчетверо меньше видеопамяти без потери чёткости.
	var tile := int(texture.get_width() / 8)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile, tile)
	var cols := int(texture.get_width() / tile)
	var rows := int(texture.get_height() / tile)
	for r in rows:
		for c in cols:
			source.create_tile(Vector2i(c, r))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile, tile)
	tile_set.add_source(source, 0)
	var tile_map := TileMapLayer.new()
	tile_map.tile_set = tile_set
	tile_map.position = _origin
	tile_map.scale = Vector2.ONE * (CELL * 2.0 / tile)
	tile_map.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	for ty in grid_size.y / 2:
		for tx in grid_size.x / 2:
			var zone: int = zones[_index(Vector2i(tx * 2, ty * 2))]
			tile_map.set_cell(Vector2i(tx, ty), 0, Vector2i(_pick_column(zone), _zone_row(zone)))
	_own(tile_map, self)
	_add_macro_overlay(float(chapter.get("macro", 1.0)))


func _zone_row(zone: int) -> int:
	if layout == "bank":
		match zone:
			Zone.LAWN, Zone.EDGE:
				return 1
			Zone.LANE, Zone.GATE:
				return 2
			Zone.BOSS:
				return 3
		return 0
	match zone:
		Zone.LANE, Zone.GATE:
			return 1
		Zone.EDGE:
			return 2
	return 0


func _pick_column(zone: int) -> int:
	var roll := randf()
	if zone == Zone.EDGE or zone == Zone.BOSS:
		return randi() % 8
	if roll < 0.55:
		return 0
	if roll < 0.7:
		return 1 + randi() % 2
	return 3 + randi() % 5


## Крупные пятна грязи/сырости поверх плитки (умножение) — ломают повторяемость атласа.
func _add_macro_overlay(strength: float) -> void:
	const MACRO_PATH := "res://assets/biome/macro.png"
	const MACRO_SCALE := 6.0
	if strength <= 0.0 or SaveService.get_quality() == 0 or not ResourceLoader.exists(MACRO_PATH):
		return
	var overlay := Sprite2D.new()
	overlay.texture = load(MACRO_PATH)
	overlay.centered = false
	overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	overlay.region_enabled = true
	overlay.region_rect = Rect2(Vector2.ZERO, bounds.size / MACRO_SCALE)
	overlay.scale = Vector2.ONE * MACRO_SCALE
	overlay.position = bounds.position
	overlay.self_modulate = Color.WHITE.lerp(Color(1, 1, 1, 1), 0.0)
	overlay.modulate = Color(1, 1, 1, clampf(strength, 0.0, 1.0))
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	overlay.material = material
	_own(overlay, self)


## Узлы теней по секторам — первыми детьми слоя декалей, чтобы тени лежали под светом.
func _build_shadow_layers() -> void:
	if SaveService.get_quality() == 0:
		return
	for sy in ceili(float(grid_size.y) / SECTOR):
		for sx in ceili(float(grid_size.x) / SECTOR):
			var node := ShadowDecals.new()
			_own(node, _layers.decals)
			_shadows[Vector2i(sx, sy)] = node


func _add_shadow(shape: Shape2D, center: Vector2, height: float) -> void:
	var cell := world_to_cell(center)
	var sector := Vector2i(clampi(cell.x / SECTOR, 0, (grid_size.x - 1) / SECTOR), clampi(cell.y / SECTOR, 0, (grid_size.y - 1) / SECTOR))
	var node: ShadowDecals = _shadows.get(sector)
	if node == null:
		return
	if shape is CircleShape2D:
		node.add_circle(center, (shape as CircleShape2D).radius, height)
	else:
		var rect := shape.get_rect()
		rect.position += center
		node.add_rect(rect, height)


# --- Кольцо стен и бордюр -----------------------------------------------------------------------

func _build_walls() -> void:
	var w := grid_size.x
	var h := grid_size.y
	var mid_y := h / 2
	var blocks: Array[Rect2i] = [
		Rect2i(0, 0, w, RING_TOP),
		Rect2i(0, h - RING_BOTTOM, w, RING_BOTTOM),
		Rect2i(0, RING_TOP, RING_SIDE, mid_y - GATE_HALF - RING_TOP),
		Rect2i(0, mid_y + GATE_HALF, RING_SIDE, h - RING_BOTTOM - mid_y - GATE_HALF),
		Rect2i(w - RING_SIDE, RING_TOP, RING_SIDE, mid_y - GATE_HALF - RING_TOP),
		Rect2i(w - RING_SIDE, mid_y + GATE_HALF, RING_SIDE, h - RING_BOTTOM - mid_y - GATE_HALF),
	]
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	for b in blocks:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(b.size) * CELL
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = _origin + (Vector2(b.position) + Vector2(b.size) * 0.5) * CELL
		body.add_child(collision)
		for y in range(b.position.y, b.end.y):
			for x in range(b.position.x, b.end.x):
				cells[_index(Vector2i(x, y))] = CellType.WALL
	# за воротами — стена по краю карты, чтобы крысы не выходили за bounds
	for side in [-1.0, 1.0]:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(40, GATE_HALF * 2 * CELL)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		var x := bounds.position.x - 20.0 if side < 0.0 else bounds.end.x + 20.0
		collision.position = Vector2(x, _origin.y + mid_y * CELL)
		body.add_child(collision)
	_own(body, self)


## Сплошной вал пропов по кольцу. Верх — два ряда (задний выше), бока — столбцом,
## низ — только низкие пропы у самого края, чтобы не закрывать нижнюю часть арены.
func _build_border() -> void:
	var list: Array = chapter.get("border", [])
	if list.is_empty():
		return
	var w := bounds.size.x
	var top_front := _origin.y + RING_TOP * CELL - 6.0
	var top_back := _origin.y + RING_TOP * CELL * 0.62
	var skip := Rect2(boss_rect.position.x - 40.0, _origin.y, boss_rect.size.x + 80.0, RING_TOP * CELL)
	for row in [top_back, top_front]:
		var x := _origin.x + randf_range(20.0, 80.0)
		while x < bounds.end.x:
			var id: String = list.pick_random()
			var size := ArenaProp.visual_size(id)
			var at := Vector2(x + size.x * 0.5, row + randf_range(-10.0, 8.0))
			if row == top_front and skip.has_point(at):
				x += size.x * 0.8
				continue
			_decor_prop(at, id)
			x += size.x * randf_range(0.72, 0.9)
	var low := ["tire_stack", "oil_barrels", "fence", "railing_low", "planter", "railing"]
	var bottom_list: Array = list.filter(func(id: String) -> bool: return low.has(id))
	if bottom_list.is_empty():
		bottom_list = list
	var bx := _origin.x + randf_range(10.0, 60.0)
	while bx < bounds.end.x:
		var id: String = bottom_list.pick_random()
		var size := ArenaProp.visual_size(id)
		_decor_prop(Vector2(bx + size.x * 0.5, bounds.end.y - 14.0), id)
		bx += size.x * randf_range(0.75, 0.92)
	var mid_y := _origin.y + grid_size.y * 0.5 * CELL
	for side in [0, 1]:
		var cx := _origin.x + RING_SIDE * CELL * 0.5 if side == 0 else bounds.end.x - RING_SIDE * CELL * 0.5
		var y := _origin.y + RING_TOP * CELL + 40.0
		while y < bounds.end.y - RING_BOTTOM * CELL:
			if absf(y - mid_y) < (GATE_HALF + 1.2) * CELL:
				y += CELL
				continue
			var id: String = list.pick_random()
			var size := ArenaProp.visual_size(id)
			_decor_prop(Vector2(cx + randf_range(-14.0, 14.0), y), id, 1 if side == 0 else -1)
			y += maxf(size.y * 0.42, 70.0)


func _build_district() -> void:
	district = null
	view_bounds = bounds
	if not ArenaDistrict.has_art(layout):
		return
	district = ArenaDistrict.new()
	_own(district, _layers.floor_layer)
	if not _river_points.is_empty():
		district.avoid = [_river_points[0].x, _river_points[_river_points.size() - 1].x, RIVER_WIDTH * 0.5 + 80.0]
	district.build(layout, str(chapter.get("id", "")), bounds, _arena_inner(), _origin.y + grid_size.y / 2 * CELL, GATE_HALF * CELL)
	view_bounds = ArenaDistrict.view_rect(bounds)


func _decor_prop(at: Vector2, id: String, flip: int = 0) -> ArenaProp:
	var prop := ArenaProp.new()
	prop.position = at
	prop.setup(id, false, flip)
	_own(prop, _layers.world)
	return prop


# --- Помост босса, центр, ворота, фонари -----------------------------------------------------------

func _build_boss_zone() -> void:
	var stage := ArenaDecor.BossStage.new()
	stage.rect = boss_rect
	stage.style = layout
	_own(stage, _layers.decals)
	var back_y := _origin.y + RING_TOP * CELL - 4.0
	var cx := boss_rect.get_center().x
	if layout == "bank":
		_decor_prop(Vector2(cx, back_y), "vault_door")
		for side in [-1.0, 1.0]:
			_decor_prop(Vector2(cx + side * 215.0, back_y + 4.0), "pig_statue", 1 if side < 0.0 else -1)
			# Фонари с флагами по передним углам помоста.
			_decor_prop(Vector2(cx + side * (boss_rect.size.x * 0.5 + 34.0), boss_rect.end.y + 36.0), "lamp_banner")
	else:
		_build_boss_set(cx, back_y)


## Арена Короля Свалки: за помостом трон из хлама с короной, по бокам стеки колонок, у передних углов
## прожекторы (их лучи рисует BossStage), над троном — неоновая вывеска банды. Всё без коллизий.
func _build_boss_set(cx: float, back_y: float) -> void:
	var pieces := ArenaDecor.BossSet.new()
	_own(pieces, _layers.world)
	var top := boss_rect.position.y
	pieces.piece("res://assets/story/boss/throne.png", Rect2(), Vector2(cx, top + 96.0), 330.0)
	pieces.piece("res://assets/story/boss/speakers.png", Rect2(0, 0, 272, 384), Vector2(cx - 270.0, top + 70.0), 170.0)
	pieces.piece("res://assets/story/boss/speakers.png", Rect2(268, 0, 244, 384), Vector2(cx + 270.0, top + 70.0), 150.0, true)
	for side in [-1.0, 1.0]:
		var inset := 70.0 if not _story.is_empty() else -40.0
		var at := Vector2(cx + side * (boss_rect.size.x * 0.5 - inset), boss_rect.end.y + (-30.0 if not _story.is_empty() else 40.0))
		pieces.piece("res://assets/story/boss/spotlights.png", Rect2(0, 0, 268, 384) if side < 0.0 else Rect2(270, 0, 242, 384), at, 120.0, side > 0.0)
		pieces.light(at + Vector2(0, -90), Color(1.0, 0.86, 0.55), 280.0, 0.7)
	pieces.light(Vector2(cx, top + 40.0), Color("#ff2e63"), 320.0, 0.6)
	pieces.light(boss_rect.get_center(), Color(1.0, 0.9, 0.7), 320.0, 0.45)
	var sign := NeonSign.new()
	sign.setup(NeonSign.Icon.CHEESE, Color("#ff2e63"))
	sign.position = Vector2(cx, top - 150.0)
	sign.scale = Vector2.ONE * 1.1
	_own(sign, _layers.world)


func _build_spotlights() -> void:
	if SaveService.get_quality() < 1:
		return
	var tint := Color("#ffe2a8") if layout == "bank" else Color("#9fd8ff")
	var count := 4
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(chapter.get("id", "")) + str(grid_size))
	for i in count:
		var spot := PointLight2D.new()
		spot.texture = NeonSign.get_light_texture()
		spot.texture_scale = rng.randf_range(4.2, 5.6)
		spot.color = tint.lerp(Color("#ff9ac8"), 0.25 * float(i % 2))
		spot.energy = 0.42
		spot.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
		spot.position = _origin + Vector2(rng.randf_range(0.12, 0.88) * bounds.size.x, rng.randf_range(0.2, 0.85) * bounds.size.y)
		_own(spot, _layers.world)


## Сюжетная карта: стены-перегородки с воротами между комнатами засад и закрытый зал босса.
func _build_story_walls() -> void:
	var w := grid_size.x
	var rows: Array = []
	var index := 0
	for door in _story.get("doors", []):
		var y := lerpf(player_start.y, boss_point.y, float(door) + DOOR_LEAD)
		var gap_x: int = [w / 2 - DOOR_GAP / 2, RING_SIDE + 3, w - RING_SIDE - DOOR_GAP - 3][index % 3]
		rows.append([world_to_cell(Vector2(0.0, y)).y, door_key(float(door)), gap_x])
		index += 1
	rows.append([RING_TOP + _boss_cells.y, "boss", w / 2 - DOOR_GAP / 2])
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	_story_rows.clear()
	_story_gaps.clear()
	for entry in rows:
		var row: int = entry[0]
		_story_rows.append(row)
		_story_gaps.append([row, int(entry[2])])
		var gap_x: int = entry[2]
		_wall_block(body, Rect2i(RING_SIDE, row, gap_x - RING_SIDE, WALL_THICK))
		_wall_block(body, Rect2i(gap_x + DOOR_GAP, row, w - RING_SIDE - gap_x - DOOR_GAP, WALL_THICK))
		var gate_cells := Rect2i(gap_x, row, DOOR_GAP, WALL_THICK)
		var gate := StoryGate.new()
		gate.setup(_cells_rect(gate_cells.position, gate_cells.size))
		_own(gate, _layers.world)
		story_gates[entry[1]] = gate
		story_cells[entry[1]] = gate_cells
		_story_clear.append(_cells_rect(Vector2i(gap_x - 1, row - 4), Vector2i(DOOR_GAP + 2, WALL_THICK + 8)))
	var half := _boss_cells.x / 2
	_wall_block(body, Rect2i(RING_SIDE, RING_TOP, w / 2 - half - RING_SIDE, _boss_cells.y))
	_wall_block(body, Rect2i(w / 2 + half, RING_TOP, w - RING_SIDE - w / 2 - half, _boss_cells.y))
	_own(body, self)
	_story_boss_visuals()


func _tiled_sprite(path: String, rect: Rect2, scale_k: float, tint: Color = Color.WHITE) -> Sprite2D:
	var tex: Texture2D = ArenaProp.texture_of(path)
	if tex == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.scale = Vector2.ONE * scale_k
	sprite.region_rect = Rect2(Vector2.ZERO, rect.size / scale_k)
	sprite.position = rect.position
	sprite.modulate = tint
	return sprite


## Стены сюжетных комнат: полосы листов Астры вместо голой заливки; вертикальные тянутся по высоте.
func _story_wall_visual(block: Rect2i) -> void:
	if _story.is_empty() or block.size.x <= 0 or block.size.y <= 0:
		return
	var rect := _cells_rect(block.position, block.size)
	var vertical := rect.size.y > rect.size.x
	var tex_w := 192.0
	var tex_h := 128.0
	var k := rect.size.x / tex_w if vertical else rect.size.y / tex_h
	var sprite := _tiled_sprite("res://assets/story/walls/%d.png" % (1 + randi() % 3), rect, k)
	if sprite != null:
		_own(sprite, self)


## Тронный зал: плиты пола с жёлто-чёрной окантовкой и трон за спиной Короля.
func _story_boss_visuals() -> void:
	if layout != "bank":
		return
	var floor_sprite := _tiled_sprite("res://assets/story/boss/floor_1.png", boss_rect, 0.5, Color(1, 1, 1, 0.92))
	if floor_sprite != null:
		_own(floor_sprite, self)
	var throne: Texture2D = ArenaProp.texture_of("res://assets/story/boss/throne.png")
	if throne != null:
		var sprite := Sprite2D.new()
		sprite.texture = throne
		sprite.scale = Vector2.ONE * (340.0 / throne.get_width())
		sprite.position = Vector2(boss_rect.get_center().x, boss_rect.position.y + 150.0)
		sprite.z_index = 1
		_own(sprite, self)


func _wall_block(body: StaticBody2D, block: Rect2i) -> void:
	if block.size.x <= 0 or block.size.y <= 0:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(block.size) * CELL
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = _origin + (Vector2(block.position) + Vector2(block.size) * 0.5) * CELL
	body.add_child(collision)
	for y in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			var i := _index(Vector2i(x, y))
			cells[i] = CellType.WALL
			zones[i] = Zone.EDGE
	_story_wall_visual(block)
	var ids: Array = (chapter.get("border", []) as Array).filter(func(id: String) -> bool: return id == "container" or id == "junk_pile" or id == "dumpster")
	if ids.is_empty():
		return
	var rect := _cells_rect(block.position, block.size)
	var vertical := block.size.y > block.size.x
	# Хлам стоит только над самой стеной и не свешивается в проём ворот: иначе герой, проходя в ворота,
	# оказывался «внутри» контейнера (картинка без коллизии висела над проходом).
	const EDGE := 28.0
	var at := rect.position + Vector2(EDGE, rect.size.y * 0.5 + 12.0)
	if vertical:
		at = Vector2(rect.get_center().x, rect.position.y + 50.0)
	while (at.y <= rect.end.y - 10.0) if vertical else (at.x < rect.end.x - EDGE):
		var id: String = ids.pick_random()
		var size := ArenaProp.visual_size(id)
		if vertical:
			_decor_prop(at, id, 1 if randf() < 0.5 else -1)
			at.y += maxf(size.y * 0.5, 70.0)
		else:
			if at.x + size.x > rect.end.x - EDGE:
				# Не влез — пробуем предмет поуже, иначе ряд закончен.
				var fit := ids.filter(func(other: String) -> bool: return at.x + ArenaProp.visual_size(other).x <= rect.end.x - EDGE)
				if fit.is_empty():
					break
				id = fit.pick_random()
				size = ArenaProp.visual_size(id)
			_decor_prop(at + Vector2(size.x * 0.5, 0.0), id, 1 if randf() < 0.5 else -1)
			at.x += size.x * 0.82


static func door_key(at: float) -> String:
	return "g%d" % roundi(at * 1000.0)


func _seal_story_gates() -> void:
	for key in story_cells:
		_set_gate_cells(story_cells[key], CellType.WALL)


func _set_gate_cells(gate_cells: Rect2i, kind: CellType) -> void:
	for y in range(gate_cells.position.y, gate_cells.end.y):
		for x in range(gate_cells.position.x, gate_cells.end.x):
			var cell := Vector2i(x, y)
			cells[_index(cell)] = kind
			if _flow_ready:
				_flow.set_blocked(cell, kind != CellType.EMPTY)


func open_story_gate(key: String) -> void:
	if story_gates.has(key):
		(story_gates[key] as StoryGate).open()
		_set_gate_cells(story_cells[key], CellType.EMPTY)


func close_story_gate(key: String) -> void:
	if story_gates.has(key):
		(story_gates[key] as StoryGate).close()
		_set_gate_cells(story_cells[key], CellType.WALL)


func _build_center() -> void:
	var center := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
	if layout == "bank":
		var medal := ArenaDecor.floor_image("res://assets/props/ch2/medallion.png", 360.0)
		medal.position = cell_to_world(Vector2i(grid_size.x / 2, grid_size.y / 2 + 8)) + Vector2(-CELL * 0.5, 0)
		if not _road_x.is_empty():
			medal.position = cell_to_world(Vector2i((_road_x[0] + _road_x[1]) / 2, (_road_y[0] + _road_y[1]) / 2))
		elif _organic:
			medal.position = center
			_build_park(center)
		_own(medal, _layers.decals)
		var curbs := ArenaDecor.Curbs.new()
		curbs.segments = _zone_edges([Zone.LAWN])
		_own(curbs, _layers.decals)
		var lanes := ArenaDecor.Curbs.new()
		lanes.segments = _zone_edges([Zone.LANE])
		lanes.color = Color("#e7b3cb")
		lanes.shade = Color("#a25a7a")
		_own(lanes, _layers.decals)
	else:
		var graffiti := ArenaDecor.floor_image("res://assets/props/ch1/graffiti.png", 400.0, 0.4)
		graffiti.position = center
		_own(graffiti, _layers.decals)
		if not _road_x.is_empty():
			# Бордюры вдоль дорог: районы читаются как кварталы.
			var curbs := ArenaDecor.Curbs.new()
			curbs.segments = _zone_edges([Zone.LANE])
			curbs.color = Color("#6d6a86")
			curbs.shade = Color("#2a2740")
			_own(curbs, _layers.decals)


## Отрезки границ между клетками выбранных зон и остальными (бордюры газонов/дорожек).
func _zone_edges(targets: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for y in range(RING_TOP, grid_size.y - RING_BOTTOM):
		for x in range(RING_SIDE, grid_size.x - RING_SIDE):
			var inside := targets.has(int(zones[_index(Vector2i(x, y))]))
			if not inside:
				continue
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + offset
				if not _inside(n) or targets.has(int(zones[_index(n)])) or zones[_index(n)] == Zone.EDGE:
					continue
				var a := _origin + Vector2(x, y) * CELL
				if offset.x == 1:
					out.append(a + Vector2(CELL, 0))
					out.append(a + Vector2(CELL, CELL))
				elif offset.x == -1:
					out.append(a)
					out.append(a + Vector2(0, CELL))
				elif offset.y == 1:
					out.append(a + Vector2(0, CELL))
					out.append(a + Vector2(CELL, CELL))
				else:
					out.append(a)
					out.append(a + Vector2(CELL, 0))
	return out


func _build_gates() -> void:
	var mid_y := grid_size.y / 2
	var color := Color("#2e9bff") if layout != "bank" else Color("#ffcf4a")
	for side in [0, 1]:
		var x0 := 0 if side == 0 else grid_size.x - RING_SIDE
		var r := _cells_rect(Vector2i(x0, mid_y - GATE_HALF), Vector2i(RING_SIDE, GATE_HALF * 2))
		gate_rects.append(r)
		var gate := ArenaDecor.Gate.new()
		gate.rect = r
		gate.inward = 1.0 if side == 0 else -1.0
		gate.color = color
		_own(gate, _layers.decals)
		if district != null:
			_gate_frame(side, r)
			continue
		var post := "tire_stack" if layout != "bank" else "lamp_banner"
		for dy in [-1.0, 1.0]:
			var at := Vector2(r.get_center().x, r.get_center().y + dy * (GATE_HALF * CELL + 26.0) + (40.0 if dy > 0.0 else 0.0))
			_decor_prop(at, post)


## Ворота в линии забора, стоят вертикально («|»): на Свалке — рама с поднятой ставней (арт Астры,
## повёрнут вдоль стены), в Банке — фонари с флагами ровно по краям проёма.
func _gate_frame(side: int, r: Rect2) -> void:
	var inner := _arena_inner()
	var x := inner.position.x - 30.0 if side == 0 else inner.end.x + 30.0
	var cy := r.get_center().y
	var half := GATE_HALF * CELL * ArenaDistrict.GATE_CLEAR
	if layout == "bank":
		for dy in [-1.0, 1.0]:
			_decor_prop(Vector2(x, cy + dy * half + (24.0 if dy > 0.0 else 0.0)), "lamp_banner")
		return
	var tex := load("res://assets/story/gates/open.png") as Texture2D
	if tex == null:
		return
	var frame := Sprite2D.new()
	frame.texture = tex
	frame.rotation = PI * 0.5 if side == 0 else -PI * 0.5
	frame.scale = Vector2.ONE * (half * 2.0 + 30.0) / tex.get_width()
	frame.position = Vector2(x, cy)
	_own(frame, _layers.decals)


func _build_lamps() -> void:
	var lamp := str(chapter.get("lamp", ""))
	if lamp.is_empty():
		return
	var inner := Rect2(bounds.position + Vector2(RING_SIDE + 1.5, RING_TOP + 8.5) * CELL, Vector2.ZERO)
	inner.end = bounds.end - Vector2(RING_SIDE + 1.5, RING_BOTTOM + 1.2) * CELL
	var spots: Array[Vector2] = [inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), inner.end]
	if layout == "bank":
		var mid := inner.get_center()
		for dx in [-1.0, 1.0]:
			for dy in [-1.0, 1.0]:
				spots.append(mid + Vector2(dx * 5.6 * CELL, dy * 4.6 * CELL))
	for p in spots:
		_place_prop(p, lamp, false)


# --- Укрытия и разрушаемые -----------------------------------------------------------------------

func _interior_rect() -> Rect2:
	var r := Rect2(bounds.position + Vector2(RING_SIDE + 1.2, RING_TOP + 7.5) * CELL, Vector2.ZERO)
	r.end = bounds.end - Vector2(RING_SIDE + 1.2, RING_BOTTOM + 1.6) * CELL
	return r


## Точка допустима для укрытия: не на дорожках, не у центра, старта, помоста и ворот.
func _cover_allowed(p: Vector2, margin: float) -> bool:
	# Берега протоки и съезды с мостов свободны: ничего не загораживает переправу.
	if not _river_points.is_empty() and absf(p.x - AcidRiver._x_at(_river_points, p.y)) < RIVER_WIDTH * 0.5 + 190.0 + margin * 0.5:
		return false
	var zone := zone_at(p)
	if zone == Zone.LANE or zone == Zone.BOSS or zone == Zone.GATE or zone == Zone.EDGE:
		return false
	if layout == "bank" and zone == Zone.FLOOR and randf() < 0.85:
		return false
	var center := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
	if p.distance_to(center) < 260.0 + margin or p.distance_to(player_start) < 230.0 + margin:
		return false
	for r in gate_rects:
		if r.grow(170.0 + margin).has_point(p):
			return false
	for r in _story_clear:
		if r.has_point(p):
			return false
	return true


func _build_cover() -> void:
	if _organic:
		_build_organic()
		return
	if chapter.has("scenes"):
		_build_scenes()
		return
	var big: Array = chapter.get("cover_big", [])
	var small: Array = chapter.get("cover_small", [])
	if big.is_empty():
		return
	var area := _interior_rect()
	for attempt in 500:
		if _cover_spots.size() >= int(COVER_SPOTS * _area_scale):
			break
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		if not _cover_allowed(p, 0.0):
			continue
		var close := false
		for q in _cover_spots:
			if q.distance_to(p) < COVER_SPACING:
				close = true
				break
		if close:
			continue
		var id: String = big.pick_random()
		var main := _place_prop(p, id, true)
		if main == null:
			continue
		_cover_spots.append(p)
		if small.is_empty():
			continue
		var width := ArenaProp.visual_size(id).x
		for k in randi_range(0, 2):
			var side := -1.0 if k == 0 and randf() < 0.5 else 1.0
			var sid: String = small.pick_random()
			var offset := Vector2(side * (width * 0.5 + ArenaProp.visual_size(sid).x * 0.45 + 10.0), randf_range(-10.0, 50.0))
			_place_prop(p + offset, sid, true)


## Сцены вместо россыпи: у каждой есть «якорь» — где она уместна (задник, бок, у дорожки, спереди, открытое место),
## главный предмет обязан встать, остальные — по возможности. Разрушаемое из сцены (бочки у генератора, банки у мусорок)
## считается в общий лимит главы, остаток _build_destructibles раскидывает только рядом со сценами.
func _build_scenes() -> void:
	var library: Dictionary = ConfigLoader.load_json("res://data/scenes.json").get("scenes", {})
	var area := _interior_rect()
	if not _road_x.is_empty():
		_build_districts(library, area)
		return
	if not _story.is_empty() and _build_story_organic():
		return
	var entries: Array = chapter.get("scenes", []).duplicate()
	entries.shuffle()
	for index in entries.size():
		var entry: Array = entries[index]
		if index >= 3 and randf() < 0.45:
			continue
		var scene: Dictionary = library.get(str(entry[0]), {})
		if scene.is_empty():
			continue
		var done := 0
		for attempt in int(120 * _area_scale):
			if done >= maxi(int(round(float(entry[1]) * PROP_DENSITY * _area_scale)), 1):
				break
			var p := _scene_point(str(scene.get("anchor", "open")), area)
			if p == Vector2.INF or not _scene_spacing_ok(p):
				continue
			if _place_scene(scene, p):
				_cover_spots.append(p)
				done += 1


## Районы-кварталы: у каждого своя тема (из сцен главы), и квартал собирается по планировке из
## data/lots.json — ряды контейнеров, мусорный переулок вдоль бордюра, шиномонтаж, газон с пикником,
## всё по осям квартала и с проходами. Центр (площадь), квартал под помостом босса и стартовый — пустые.
func _build_districts(library: Dictionary, area: Rect2) -> void:
	var lots_root: Dictionary = ConfigLoader.load_json(LOTS_PATH)
	var lots: Dictionary = lots_root.get("lots", {})
	var themes: Array = []
	for entry: Array in chapter.get("scenes", []):
		var key := str(entry[0])
		if (lots.has(key) or library.has(key)) and not themes.has(key):
			themes.append(key)
	for key in lots_root.get("extra", {}).get(layout, []):
		if lots.has(key) and not themes.has(key):
			themes.append(key)
	if themes.is_empty():
		return
	themes.shuffle()
	_district_theme.clear()
	var center := DISTRICTS * DISTRICTS / 2
	var start := _district_of(player_start)
	var boss := _district_of(boss_rect.get_center() + Vector2(0, boss_rect.size.y))
	var next := 0
	for d in DISTRICTS * DISTRICTS:
		if d == center or d == start or d == boss:
			_district_theme.append("")
		else:
			_district_theme.append(str(themes[next % themes.size()]))
			next += 1
	for d in _district_theme.size():
		var theme := _district_theme[d]
		if theme.is_empty():
			continue
		if lots.has(theme):
			_build_lot(lots[theme], _lot_rect(d), str(lots_root.get("frame", {}).get(layout, "")))
			continue
		var scene: Dictionary = library[theme]
		var done := 0
		for attempt in 160:
			if done >= 3:
				break
			var p := _district_point(d, area)
			if p == Vector2.INF or not _scene_spacing_ok(p):
				continue
			if _place_scene(scene, p):
				_cover_spots.append(p)
				done += 1


## Игровая площадка без кольца стен.
func _arena_inner() -> Rect2:
	return Rect2(bounds.position + Vector2(RING_SIDE, RING_TOP) * CELL, bounds.size - Vector2(RING_SIDE * 2, RING_TOP + RING_BOTTOM) * CELL)


## Кислотная протока (AcidRiver): извилистая линия сверху вниз по левой или правой трети площадки,
## три моста (один — на уровне ворот, чтобы толпа из боковых ворот шла через него). Клетки протоки —
## стены сетки (поле потока ведёт пеших к мостам, расстановка их обходит), коллизия — слой TERRAIN.
## Дорожки парка: от площади к обоим воротам (прямо — через мост протоки), к помосту босса и к старту.
func _build_park(center: Vector2) -> void:
	_park = ParkPaths.new()
	var inner := _arena_inner()
	var mid_y := _origin.y + grid_size.y / 2 * CELL
	_park.paths.append(ParkPaths.curve(center, Vector2(inner.position.x - 20.0, mid_y), 0.0))
	_park.paths.append(ParkPaths.curve(center, Vector2(inner.end.x + 20.0, mid_y), 0.0))
	_park.paths.append(ParkPaths.curve(center, Vector2(boss_rect.get_center().x, boss_rect.end.y + 60.0), randf_range(-150.0, 150.0)))
	_park.paths.append(ParkPaths.curve(center, Vector2(player_start.x, inner.end.y + 20.0), randf_range(-150.0, 150.0)))
	_own(_park, _layers.floor_layer)
	_park.build(center, 300.0)
	_park.z_index = 1


## Средняя линия протоки (до района: тот должен расступиться над её истоком и устьем).
func _plan_river() -> void:
	var inner := _arena_inner()
	var side := -1.0 if randf() < 0.5 else 1.0
	# Русло в боковой полосе площадки: далеко от помоста босса и центра, у забора остаётся проход.
	var x0 := inner.get_center().x + side * (inner.size.x * 0.5 - RIVER_EDGE)
	var ph := randf() * TAU
	var ph2 := randf() * TAU
	var points := PackedVector2Array()
	var top := inner.position.y
	var bottom := inner.end.y
	var y := top
	while y < bottom:
		points.append(Vector2(x0 + _river_bend(y, top, bottom, ph, ph2), y))
		y += 48.0
	points.append(Vector2(x0, bottom))
	_river_points = points
	_river_side = side


## Изгиб русла: у заборов — ноль (протока входит и выходит прямо, через водосток), посередине — плавные петли.
static func _river_bend(y: float, top: float, bottom: float, ph: float, ph2: float) -> float:
	var edge := minf(y - top, bottom - y)
	var taper := smoothstep(0.0, 420.0, edge)
	return taper * (190.0 * sin(y * 0.0021 + ph) + 50.0 * sin(y * 0.006 + ph2))


func _build_river() -> void:
	if _river_points.is_empty():
		return
	var inner := _arena_inner()
	var width := RIVER_WIDTH
	var points := _river_points
	var mid_y := _origin.y + grid_size.y / 2 * CELL
	var bridges := [mid_y, inner.position.y + inner.size.y * 0.24 + randf_range(-60, 60), inner.position.y + inner.size.y * 0.8 + randf_range(-60, 60)]
	river = AcidRiver.new()
	_own(river, _layers.decals)
	river.water = layout == "bank"
	river.build(points, width, bridges, RIVER_BRIDGE)
	river.add_culvert(points[0].x, inner.position.y, true)
	river.add_culvert(points[points.size() - 1].x, inner.end.y, false)
	# Исток и устье: протока выходит из-под верхнего забора и уходит под нижний (рисует район — под забором и толпой).
	if district != null:
		var view := view_bounds
		var top := PackedVector2Array([Vector2(points[0].x, view.position.y - 20.0), points[0] + Vector2(0, 40)])
		var tail := points[points.size() - 1]
		var bottom := PackedVector2Array([tail - Vector2(0, 40), Vector2(tail.x, view.end.y + 20.0)])
		district.add_stream(top, width, river.water, true)
		district.add_stream(bottom, width, river.water, false)
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.TERRAIN
	body.collision_mask = 0
	var first := world_to_cell(inner.position)
	var last := world_to_cell(inner.end - Vector2.ONE)
	for cy in range(first.y, last.y + 1):
		var run_start := -1
		for cx in range(first.x, last.x + 2):
			var wet := false
			if cx <= last.x:
				var p := cell_to_world(Vector2i(cx, cy))
				wet = absf(p.x - AcidRiver._x_at(points, p.y)) < width * 0.5 + 10.0
				for by: float in bridges:
					if absf(p.y - by) < RIVER_BRIDGE_BAND:
						wet = false
			if wet:
				cells[_index(Vector2i(cx, cy))] = CellType.WALL
				if run_start == -1:
					run_start = cx
			elif run_start != -1:
				var shape := RectangleShape2D.new()
				shape.size = Vector2(cx - run_start, 1) * CELL
				var collision := CollisionShape2D.new()
				collision.shape = shape
				collision.position = _origin + (Vector2(run_start, cy) + Vector2(cx - run_start, 1) * 0.5) * CELL
				body.add_child(collision)
				run_start = -1
	_own(body, self)


## Местность без сетки дорог: выживание (органика) и сюжетные комнаты.
func _natural() -> bool:
	return _organic or not _story.is_empty()


## Сюжет: маршрут от старта через проёмы всех стен к боссу; в каждой комнате — 2–4 точки интереса
## по сторонам маршрута и одиночные укрытия, сам маршрут свободен. В Банке маршрут — мощёная аллея
## (ParkPaths) по газону, на Свалке — протоптанная тёмная тропа.
func _build_story_organic() -> bool:
	if _story_gaps.is_empty():
		return false
	var root: Dictionary = ConfigLoader.load_json(LOTS_PATH)
	var defs: Dictionary = root.get("poi", {})
	var names: Array = root.get("poi_sets", {}).get(str(chapter.get("id", "")).get_slice("_", 0), [])
	if names.is_empty():
		return false
	var gaps := _story_gaps.duplicate()
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var route := PackedVector2Array([player_start + Vector2(0, 120)])
	for g: Array in gaps:
		var c := _origin + Vector2(float(g[1]) + DOOR_GAP * 0.5, float(g[0]) + WALL_THICK * 0.5) * CELL
		route.append(c + Vector2(0, WALL_THICK * CELL))
		route.append(c - Vector2(0, WALL_THICK * CELL))
	var trail := ParkPaths.new()
	for k in range(0, route.size() - 1, 2):
		trail.paths.append(ParkPaths.curve(route[k], route[k + 1], randf_range(-120.0, 120.0)))
	if layout == "bank":
		_own(trail, _layers.floor_layer)
		trail.z_index = 1
		trail.build(Vector2.ZERO, 0.0)
	else:
		trail.width = 230.0
		_own(trail, _layers.floor_layer)
		trail.z_index = 1
		trail.build_trail(Color(0.02, 0.0, 0.05, 0.28))
	_park = trail
	# Свет у каждого проёма: тёплый прожектор на Свалке, мягкий фонарь в Банке — маршрут читается в темноте.
	var lights := ArenaDecor.BossSet.new()
	_own(lights, _layers.decals)
	for k in range(1, route.size(), 2):
		lights.light(route[k] + Vector2(0, 40), Color("#ffb45a") if layout != "bank" else Color("#fff0c0"), 300.0, 0.55 if layout != "bank" else 0.35)
	var area := _interior_rect()
	area.position.y = boss_rect.end.y + CELL * 3.0
	area.end.y = player_start.y + CELL
	var bag: Array = []
	var target := int(area.get_area() / (520.0 * 520.0))
	for attempt in 3000:
		if _cover_spots.size() >= target:
			break
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)).snapped(Vector2(16, 16))
		if trail.distance_to(p) < 250.0 or not _cover_allowed(p, 60.0) or not _scene_spacing_ok_by(p, 470.0):
			continue
		if bag.is_empty():
			bag = names.duplicate()
			bag.shuffle()
		var poi: Array = defs.get(str(bag.pop_back()), [])
		if not poi.is_empty() and _build_poi(poi, p):
			_cover_spots.append(p)
	_scatter_singles(area, Vector2(1e6, 1e6))
	# Сюжетные комнаты тоже живые: стаи у маршрута, ветер, пыль из-под ног, листья из кустов.
	var perches: Array[Vector2] = []
	for k in range(1, route.size()):
		perches.append(route[k] + Vector2(randf_range(-280.0, 280.0), 90.0))
	_build_world_life(route[route.size() - 1], perches)
	return true


static func _make_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0011
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	return noise


## Плотность хлама в точке (-1..1): выше — захламлённая зона, ниже — чистая площадка.
func _density(p: Vector2) -> float:
	return _noise.get_noise_2d(p.x, p.y)


## Органическая местность: точки интереса (компактные сцены из data/lots.json → poi) пуассоновским
## разбросом с шагом POI_SPACING только там, где шум не «чистый»; между ними — одиночные укрытия
## и обломки по плотности шума. Чистые площадки, центр, старт, ворота и помост босса остаются свободными.
func _build_organic() -> void:
	var root: Dictionary = ConfigLoader.load_json(LOTS_PATH)
	var defs: Dictionary = root.get("poi", {})
	var sets: Dictionary = root.get("poi_sets", {})
	var names: Array = sets.get(str(chapter.get("id", "")), sets.get("junkyard", []))
	if names.is_empty():
		return
	var area := _interior_rect()
	var target := int(round(7.5 * _area_scale))
	var bag: Array = []
	var center := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
	if _build_quarters(root, defs, area) < 3:
		_build_sectors(root, defs, area, center)
	target += _cover_spots.size()
	for attempt in 2500:
		if _cover_spots.size() >= target:
			break
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)).snapped(Vector2(16, 16))
		if _density(p) < POI_OPEN or not _cover_allowed(p, 120.0) or p.distance_to(center) < 420.0 or boss_rect.grow(300.0).has_point(p):
			continue
		if not _scene_spacing_ok_by(p, POI_SPACING) or _in_sector(p, 140.0) or (_streets != null and _streets.distance_to(p) < 170.0):
			continue
		if layout == "bank" and (zone_at(p) != Zone.LAWN or (_park != null and _park.distance_to(p) < 260.0)):
			continue
		if bag.is_empty():
			bag = names.duplicate()
			bag.shuffle()
		var poi: Array = defs.get(str(bag.pop_back()), [])
		if not poi.is_empty() and _build_poi(poi, p):
			_cover_spots.append(p)
	_scatter_singles(area, center)
	_spawn_walkers()
	_build_ground_detail()
	_build_world_life(center)


## Секторы выживания: мини-парки, кафе, стоянки, полянки — у каждого своё покрытие и свои предметы
## (data/lots.json → sectors по главе). Ставятся первыми, общий разброс обходит их.
func _build_sectors(root: Dictionary, defs: Dictionary, area: Rect2, center: Vector2) -> void:
	var all: Dictionary = root.get("sectors", {})
	var themes: Array = all.get(str(chapter.get("id", "")), all.get(layout, []))
	if themes.is_empty():
		return
	var queue: Array = []
	for theme: Dictionary in themes:
		for i in int(theme.get("n", 1)):
			queue.append(theme)
	queue.shuffle()
	var rng_seed := randi()
	for theme: Dictionary in queue:
		var r_range: Array = theme.get("r", [280, 360])
		var radius := randf_range(float(r_range[0]), float(r_range[1]))
		for attempt in 200:
			var p := Vector2(randf_range(area.position.x + radius, area.end.x - radius), randf_range(area.position.y + radius * 0.8, area.end.y - radius * 0.8)).snapped(Vector2(16, 16))
			if p.distance_to(center) < 420.0 + radius or p.distance_to(player_start) < 200.0 + radius or boss_rect.grow(radius + 160.0).has_point(p):
				continue
			if not _cover_allowed(p, radius * 0.6) or _in_sector(p, radius + 120.0):
				continue
			if _park != null and _park.distance_to(p) < radius + 60.0:
				continue
			_make_sector(theme, p, radius, defs, rng_seed + _sectors.size())
			break


## Двор/сектор в точке p: покрытие, своя планировка предметов и жители (или 1–2 точки интереса).
func _make_sector(theme: Dictionary, p: Vector2, radius: float, defs: Dictionary, seed_value: int) -> void:
	var ground := str(theme.get("ground", ""))
	_sectors.append([p, radius, &"grass" if ground.contains("grass") or ground.is_empty() else (&"asphalt" if ground.contains("asphalt") else &"stone")])
	if not ground.is_empty() and ResourceLoader.exists(ground):
		var patch := SectorPatch.new()
		_own(patch, _layers.floor_layer)
		var grass := ground.contains("grass")
		var tint := Color(0.92, 0.9, 0.94)
		if layout != "bank" and grass:
			tint = Color(0.5, 0.62, 0.52)
		elif layout == "bank" and grass:
			tint = Color(1.0, 1.0, 1.0)
		patch.build(p, radius, load(ground) as Texture2D, tint, Color("#c9962e") if layout == "bank" else Color("#4a4766"), seed_value, str(theme.get("shape", "blob")), theme.get("deco", []))
	# Своя планировка сектора: предметы по долям его прямоугольника (столики рядами, машины на местах).
	var plan: Array = theme.get("layout", [])
	if not plan.is_empty():
		var half := Vector2(radius, radius * 0.72)
		var mirror := -1.0 if randf() < 0.5 else 1.0
		_in_scene = true
		for item: Array in plan:
			_lot_item(str(item[0]), (p + Vector2(float(item[1]) * mirror * half.x, float(item[2]) * half.y)).snapped(Vector2(8, 8)))
		_in_scene = false
		_cover_spots.append(p)
		_spawn_life(theme.get("life", []), p, half, mirror)
		if (theme.get("deco", []) as Array).has("pool"):
			_block_rect(Rect2(p - half * Vector2(0.5, 0.42), half * Vector2(1.0, 0.84)))
		return
	var pois: Array = theme.get("poi", [])
	var placed := 0
	for k in 8:
		if placed >= 2 or pois.is_empty():
			break
		var at := p + Vector2.from_angle(randf() * TAU) * randf_range(0.0, radius * 0.45)
		var items: Array = defs.get(str(pois[placed % pois.size()]), [])
		if not items.is_empty() and _scene_spacing_ok_by(at, 260.0) and _build_poi(items, at.snapped(Vector2(16, 16))):
			_cover_spots.append(at)
			placed += 1


var _quarter_doors: Array[Vector2] = []
var _streets: ParkPaths
var _world_life: WorldLife
var _fire_spots: Array[Vector2] = []
var _ropes: Array = []
var _windows: Array = []
var _music_spots: Array[Vector2] = []


## Кварталы выживания (data/lots.json → quarters): внутренность карты делится на 3×3. Центр (бой), клетка
## старта и клетка помоста босса свободны; в остальных — квартал: 1–2 здания в глубине, перед ними двор
## (сектор по имени), жители, тёплый свет окон. Возвращает число поставленных кварталов.
func _build_quarters(root: Dictionary, defs: Dictionary, area: Rect2) -> int:
	var chapter_id := str(chapter.get("id", ""))
	var list: Array = ((root.get("quarters", {}) as Dictionary).get(layout, []) as Array).filter(
		func(q: Dictionary) -> bool: return not q.has("chapters") or (q["chapters"] as Array).has(chapter_id))
	if list.is_empty():
		return 0
	list.shuffle()
	# Бар с музыкой есть в каждом забеге: игрок слышит его издалека и идёт посмотреть.
	for i in list.size():
		if _is_music_quarter(str((list[i] as Dictionary).get("name", ""))):
			list.push_front(list.pop_at(i))
			break
	var yards := {}
	var all: Dictionary = root.get("sectors", {})
	for key: String in [chapter_id, layout] + all.keys():
		for theme: Dictionary in all.get(key, []):
			if not yards.has(str(theme.get("name", ""))):
				yards[str(theme.get("name", ""))] = theme
	var cell := area.size / 3.0
	var cells: Array[Rect2] = []
	for gy in 3:
		for gx in 3:
			var r := Rect2(area.position + cell * Vector2(gx, gy), cell)
			if (gx == 1 and gy == 1) or r.has_point(player_start) or r.has_point(boss_rect.get_center()):
				continue
			cells.append(r)
	cells.shuffle()
	var placed := 0
	_quarter_doors.clear()
	for r in cells:
		if _place_quarter(list[placed % list.size()], r.grow(-50.0), yards, defs):
			placed += 1
	if layout != "bank" and not _quarter_doors.is_empty():
		# Протоптанные улицы от каждого квартала к центральной площади: карта читается как посёлок, а не россыпь.
		var center := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
		_streets = ParkPaths.new()
		for door: Vector2 in _quarter_doors:
			_streets.paths.append(ParkPaths.curve(door, center + (door - center).normalized() * 300.0, randf_range(-90.0, 90.0)))
		_streets.width = 150.0
		_own(_streets, _layers.floor_layer)
		_streets.z_index = 1
		_streets.build_trail(Color(0.02, 0.0, 0.05, 0.22))
		# Столбы с фонарями вдоль улиц: пятна тёплого света ведут взгляд от кварталов к площади.
		for line in _streets.paths:
			for t in [0.35, 0.75]:
				var i := int(t * (line.size() - 1))
				var along := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
				var spot := (line[i] + along.orthogonal() * 120.0 * (1.0 if randf() < 0.5 else -1.0)).snapped(Vector2(8, 8))
				if _cover_allowed(spot, 30.0) and is_walkable(spot) and _place_prop(spot, "z_wire_pole", false) != null:
					_windows.append([spot + Vector2(0, -60), Color("#ffb45a")])
	return placed


func _is_music_quarter(qname: String) -> bool:
	return qname.contains("Бар") or qname.contains("Пивн") or qname.contains("Шаурм") or qname.contains("Ресторан") or qname.contains("Бутик")


func _place_quarter(q: Dictionary, r: Rect2, yards: Dictionary, defs: Dictionary) -> bool:
	var ids: Array = []
	var widths: Array[float] = []
	var total := 0.0
	for id: String in q.get("buildings", []):
		var w := ArenaProp.visual_size(id).x
		if not ids.is_empty() and total + w > r.size.x:
			break
		ids.append(id)
		widths.append(w)
		total += w + 50.0
	var x := r.get_center().x - (total - 50.0) * 0.5 + randf_range(-40.0, 40.0)
	var foot_y := r.position.y + r.size.y * 0.42
	var built := 0
	var roofs: Array[Vector2] = []
	for i in ids.size():
		var w: float = widths[i]
		var base := Vector2(x + w * 0.5, foot_y + randf_range(-24.0, 24.0)).snapped(Vector2(8, 8))
		x += w + 50.0
		for shift in 5:
			# Здание у протоки — сдвигаем к середине карты, пока берег не освободится.
			if _quarter_ok(base, w):
				break
			base.x = move_toward(base.x, 0.0, 90.0)
		if not _quarter_ok(base, w):
			continue
		var prop := _place_prop(base, str(ids[i]), false)
		if prop == null:
			continue
		built += 1
		var vis := ArenaProp.visual_size(str(ids[i]))
		roofs.append(base + Vector2((w * 0.32) * (1.0 if roofs.is_empty() else -1.0), -vis.y * 0.5))
		_cover_spots.append(base)
		# Свет из окон и над дверью (им управляет WorldLife: иногда гаснет и загорается).
		_windows.append([base + Vector2(0, -ArenaProp.visual_size(str(ids[i])).y * 0.3), Color("#ffc46b") if layout != "bank" else Color("#fff0c8")])
		if _is_music_quarter(str(q.get("name", ""))):
			_music_spots.append(base)
	if built == 0:
		return false
	if roofs.size() >= 2:
		# Между домами квартала — бельё на верёвке (Свалка) или флажки (Банк).
		var colors: Array = []
		var palette: Array = [Color("#d94a3a"), Color("#3a6fd9"), Color("#f0e6d0"), Color("#e8c23a"), Color("#5aa05a")] if layout != "bank" else [Color("#ff8fb0"), Color("#ffd86b"), Color("#8fd0ff"), Color("#ffffff"), Color("#c9a0ff")]
		for k in randi_range(4, 7):
			colors.append(palette.pick_random())
		_ropes.append([roofs[0], roofs[1], colors])
	var theme: Dictionary = yards.get(str(q.get("yard", "")), {})
	if not theme.is_empty():
		var radius := clampf(minf(r.size.x * 0.4, r.size.y * 0.3), 220.0, 340.0)
		var p := Vector2(r.get_center().x, r.position.y + r.size.y * 0.76)
		for shift in 5:
			# Двор у протоки — сдвигаем к середине карты, пока берег не станет свободным.
			if _yard_ok(p, radius):
				_make_sector(theme, p.snapped(Vector2(16, 16)), radius, defs, randi())
				break
			p.x = move_toward(p.x, 0.0, 90.0)
	_spawn_life(q.get("life", []), r.get_center(), r.size * 0.5, 1.0)
	# Табличка с названием у входа во двор — квартал узнаётся с первого взгляда.
	var sign_at := Vector2(r.get_center().x + (r.size.x * 0.36 if randf() < 0.5 else -r.size.x * 0.36), r.position.y + r.size.y * 0.56).snapped(Vector2(8, 8))
	if is_walkable(sign_at):
		var plate := QuarterSign.new()
		plate.position = sign_at
		plate.setup(str(q.get("name", "")), layout == "bank", _quarter_doors.size())
		_own(plate, _layers.world)
		if layout != "bank" and SaveService.get_quality() > 0:
			_life_lights.append(EnvLights.add(sign_at + Vector2(0, -80), plate.tint, 150.0, 0.35))
	# Выход квартала — ближняя к центру точка его клетки: оттуда улица к площади.
	var hub := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
	_quarter_doors.append(Vector2(clampf(hub.x, r.position.x, r.end.x), clampf(hub.y, r.position.y, r.end.y)))
	return true


## Место под здание: не на берегу протоки, не на аллеях/воротах/помосте, не у старта и центра.
func _quarter_ok(p: Vector2, width: float) -> bool:
	if not _river_points.is_empty() and absf(p.x - AcidRiver._x_at(_river_points, p.y)) < RIVER_WIDTH * 0.5 + 190.0 + width * 0.5:
		return false
	var zone := zone_at(p)
	if zone == Zone.LANE or zone == Zone.BOSS or zone == Zone.GATE or zone == Zone.EDGE:
		return false
	var center := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
	if p.distance_to(center) < 420.0 + width * 0.5 or p.distance_to(player_start) < 320.0 or boss_rect.grow(220.0).has_point(p):
		return false
	for g in gate_rects:
		if g.grow(260.0 + width * 0.5).has_point(p):
			return false
	if _park != null and _park.distance_to(p) < width * 0.55:
		return false
	return true


func _yard_ok(p: Vector2, radius: float) -> bool:
	if not _river_points.is_empty() and absf(p.x - AcidRiver._x_at(_river_points, p.y)) < RIVER_WIDTH * 0.5 + 120.0 + radius:
		return false
	if _in_sector(p, radius + 60.0) or (_park != null and _park.distance_to(p) < radius + 40.0):
		return false
	return p.distance_to(player_start) > 200.0 + radius and not boss_rect.grow(radius + 120.0).has_point(p)


## Живой мир (WorldLife): стаи птиц на дворах, площади и у кварталов, ветер с листьями/бумажками,
## светлячки над травой, искры над бочками, пар из люков, бельё/флажки между домами, реплики жителей.
func _build_world_life(center: Vector2, extra: Array[Vector2] = []) -> void:
	var life := WorldLife.new()
	for p in extra:
		if is_walkable(p):
			life.spots.append(p)
	life.bank = layout == "bank"
	life.bounds = _interior_rect()
	for sec: Array in _sectors:
		# Стая садится на открытую землю перед двором, а не на столики и машины.
		var front: Vector2 = sec[0] + Vector2(randf_range(-0.3, 0.3) * float(sec[1]), float(sec[1]) * 0.95)
		if is_walkable(front):
			life.spots.append(front)
		if sec[2] == &"grass":
			life.meadows.append([sec[0], float(sec[1])])
	for door in _quarter_doors:
		life.spots.append(door)
	life.spots.append(center + Vector2(randf_range(-160.0, 160.0), 260.0))
	life.spots.shuffle()
	life.fires = _fire_spots.duplicate()
	life.ropes = _ropes.duplicate()
	life.windows = _windows.duplicate()
	life.music = _music_spots.duplicate()
	life.surface = surface_at
	if _streets != null:
		life.streets = _streets.paths.duplicate()
	if _life != null:
		life.actors = _life.actors
	_own(life, self)
	life.build(_layers.decals, _layers.fx)
	_world_life = life
	if _player != null and is_instance_valid(_player):
		life.attach(_player)


## Мелочь на земле (трещины, пятна, лужи, люки — Свалка; лепестки, камешки, монетки — Банк): пол не читается
## плиткой. Четыре узла по четвертям карты — экранная отбраковка отсекает невидимые.
func _build_ground_detail() -> void:
	var area := _interior_rect()
	var quads: Array = [[], [], [], []]
	for attempt in 600:
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		if not is_walkable(p) or boss_rect.grow(80.0).has_point(p):
			continue
		if not _river_points.is_empty() and absf(p.x - AcidRiver._x_at(_river_points, p.y)) < RIVER_WIDTH * 0.5 + 60.0:
			continue
		var q := (1 if p.x > area.get_center().x else 0) + (2 if p.y > area.get_center().y else 0)
		(quads[q] as Array).append(p)
		if quads.reduce(func(acc: int, a: Array) -> int: return acc + a.size(), 0) >= 140:
			break
	for i in 4:
		var spots: Array[Vector2] = []
		spots.assign(quads[i])
		var detail := GroundDetail.new()
		detail.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
		detail.z_index = 1
		_own(detail, _layers.floor_layer)
		detail.build(spots, randi(), layout == "bank")


## Прохожие: жители ходят по улицам кварталов (Свалка) или аллеям парка (Банк) туда-обратно,
## останавливаются поглазеть, пугаются взрывов. На качестве 0 — нет; чем выше качество, тем больше.
func _spawn_walkers() -> void:
	var quality := SaveService.get_quality()
	if quality == 0:
		return
	var lines: Array[PackedVector2Array] = []
	if _streets != null:
		lines.append_array(_streets.paths)
	if _park != null:
		lines.append_array(_park.paths)
	if lines.is_empty():
		return
	var kinds: Array = ["npc_rat_grandma", "npc_rat_worker", "npc_robot_cleaner", "npc_cat_stray"] if layout != "bank" else ["npc_pigeon_postman", "npc_pig_guard", "npc_pig_mechanic"]
	if _life == null:
		_life = AmbientLife.new()
		_life.setup(is_walkable)
		_own(_life, self)
	lines.shuffle()
	for i in mini(lines.size(), 6 if quality > 1 else 3):
		var side := (lines[i][-1] - lines[i][0]).orthogonal().normalized() * randf_range(-40.0, 40.0)
		var route := PackedVector2Array()
		for point in lines[i]:
			route.append(point + side)
		var actor := _life.spawn(str(kinds[i % kinds.size()]), route[0], _layers.world, "walker")
		if actor == null:
			continue
		actor.set_route(route, randi() % route.size())
		actor.speed = randf_range(26.0, 40.0)
		_owned.append(actor)


## Жители секторов (арт Астры из assets/npc): кот в парке, рабочий в кафе, робот-уборщик на стоянке,
## бочка с огнём, ворона на фонаре; в Банке — голубь-почтальон, свин-охранник. Без коллизий, пугаются взрывов.
func _spawn_life(list: Array, at: Vector2, half: Vector2, mirror: float) -> void:
	if list.is_empty() or SaveService.get_quality() == 0:
		return
	if _life == null:
		_life = AmbientLife.new()
		_life.setup(is_walkable)
		_own(_life, self)
	for item: Array in list:
		var p := at + Vector2(float(item[1]) * mirror * half.x, float(item[2]) * half.y)
		var actor := _life.spawn(str(item[0]), p, _layers.world)
		if actor == null:
			continue
		_owned.append(actor)
		if str(item[0]) == "npc_barrel_fire":
			_fire_spots.append(p)
			_life_lights.append(EnvLights.add(p + Vector2(0, -30), Color("#ff9a3d"), 220.0, 0.6))


## Вода бассейна: в неё не заходят (клетки — стена сетки, коллизия — рельеф, пули пролетают).
func _block_rect(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.TERRAIN | PhysicsLayers.OBSTACLE
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)
	_own(body, self)
	var a := world_to_cell(rect.position)
	var b := world_to_cell(rect.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if _inside(Vector2i(x, y)):
				cells[_index(Vector2i(x, y))] = CellType.WALL


func _in_sector(p: Vector2, pad: float) -> bool:
	for s: Array in _sectors:
		if p.distance_to(s[0]) < float(s[1]) + pad:
			return true
	return false


func _scene_spacing_ok_by(p: Vector2, spacing: float) -> bool:
	for q in _cover_spots:
		if q.distance_to(p) < spacing:
			return false
	return true


func _build_poi(items: Array, at: Vector2) -> bool:
	var mirror := -1.0 if randf() < 0.5 else 1.0
	_in_scene = true
	var ok := false
	for i in items.size():
		var item: Array = items[i]
		var id := str(item[0])
		var p := at + Vector2(float(item[1]) * mirror, float(item[2]))
		var placed := false
		if ArenaProp.is_flat(id):
			if is_area_clear(p, CELL):
				var flat := ArenaProp.new()
				flat.position = p
				flat.setup(id, false)
				_own(flat, _layers.decals)
				placed = true
		else:
			placed = _lot_item(id, p)
		if i == 0 and not placed:
			break
		ok = true
	_in_scene = false
	return ok


## Между точками интереса: одиночные укрытия (бочка, ящик, шина, мешки) и плоские обломки — по сетке
## с дрожанием, только в захламлённых зонах и не вплотную к сценам.
func _scatter_singles(area: Rect2, center: Vector2) -> void:
	var singles := ["m1_tire", "m1_crate", "m1_garbage", "d_rust_barrel", "d_barrel", "tire_stack"]
	if layout == "bank":
		singles = ["planter", "column", "umbrella", "crystals", "cash_pile", "lamp_banner"]
	var flats: Array = chapter.get("flat", [])
	var step := 430.0
	var y := area.position.y + step * 0.5
	while y < area.end.y:
		var x := area.position.x + step * 0.5
		while x < area.end.x:
			var p := Vector2(x, y) + Vector2(randf_range(-150, 150), randf_range(-150, 150))
			x += step
			var d := _density(p)
			if d < POI_OPEN + 0.18 or p.distance_to(center) < 400.0 or not _cover_allowed(p, 40.0) or boss_rect.grow(220.0).has_point(p):
				continue
			if not _scene_spacing_ok_by(p, 300.0):
				continue
			if (layout == "bank" and zone_at(p) == Zone.FLOOR) or (_park != null and _park.distance_to(p) < 140.0) or _in_sector(p, 40.0):
				continue
			if randf() < 0.5:
				_in_scene = true
				_lot_item(str(singles.pick_random()), p.snapped(Vector2(16, 16)))
				_in_scene = false
			elif not flats.is_empty() and is_area_clear(p, CELL * 1.4):
				var flat := ArenaProp.new()
				flat.position = p
				flat.setup(str(flats.pick_random()), false)
				_own(flat, _layers.decals)
		y += step


## Прямоугольник квартала d без дорог и тротуара (мировые координаты).
func _lot_rect(d: int) -> Rect2:
	var col := d % DISTRICTS
	var row := d / DISTRICTS
	var road := 4 if layout != "bank" else 3
	var side := RING_SIDE + (4 if layout == "bank" else 1)
	var left := side if col == 0 else _road_x[col - 1] + road
	var right := grid_size.x - side if col == DISTRICTS - 1 else _road_x[col] - road
	var top := RING_TOP + _boss_cells.y + 2 if row == 0 else _road_y[row - 1] + road
	var bottom := grid_size.y - RING_BOTTOM - 2 if row == DISTRICTS - 1 else _road_y[row] - road
	return Rect2(_origin + Vector2(left, top) * CELL, Vector2(right - left, bottom - top) * CELL)


## Квартал по планировке: каждый предмет — на своей доле прямоугольника, ряды — с шагом вдоль линии.
## Планировка случайно зеркалится; если предмет не влез (занято), квартал просто без него.
func _build_lot(plan: Array, rect: Rect2, frame: String = "") -> void:
	if rect.size.x < CELL * 5 or rect.size.y < CELL * 5:
		return
	var flip_u := randf() < 0.5
	var flip_v := randf() < 0.5
	var at := func(u: float, v: float) -> Vector2:
		var uu := 1.0 - u if flip_u else u
		var vv := 1.0 - v if flip_v else v
		return (rect.position + Vector2(uu, vv) * rect.size).snapped(Vector2(16.0, 16.0))
	_in_scene = true
	if not frame.is_empty():
		# Ограда двора вдоль дальнего края (после зеркала — ближнего), проход посередине и по краям.
		var step := ArenaProp.visual_size(frame).x * 0.92
		var y: float = at.call(0.5, -0.02).y
		var count := int(rect.size.x / step)
		var left := rect.get_center().x - step * (count - 1) * 0.5
		for k in count:
			if k == count / 2 and count >= 4:
				continue
			_lot_item(frame, Vector2(left + step * k, y).snapped(Vector2(16, 16)))
	for item: Array in plan:
		if str(item[0]) == "row":
			var from: Vector2 = at.call(float(item[2]), float(item[3]))
			var to: Vector2 = at.call(float(item[4]), float(item[5]))
			var count := maxi(int(from.distance_to(to) / float(item[6])) + 1, 1)
			for k in count:
				var t := 0.5 if count == 1 else float(k) / float(count - 1)
				_lot_item(str(item[1]), from.lerp(to, t))
		else:
			_lot_item(str(item[0]), at.call(float(item[1]), float(item[2])))
	_in_scene = false
	_cover_spots.append(rect.get_center())
	_lots.append(rect)
	if layout != "junkyard":
		_lot_ground(rect)


## Двор Свалки — земля района Астры (асфальт в трещинах, лужи, мусор), как за забором: карта и фон — один мир.
func _lot_ground(rect: Rect2) -> void:
	var path := "res://assets/district/junkyard/rats_ground_tile.png" if layout == "junkyard" else ""
	if path.is_empty():
		return
	var ground := Sprite2D.new()
	ground.texture = load(path) as Texture2D
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	var area := rect.grow(CELL * 0.75)
	ground.region_rect = Rect2(area.position, area.size)
	ground.centered = false
	ground.position = area.position
	ground.modulate = Color(0.95, 0.92, 1.0, 0.9)
	ground.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	_own(ground, _layers.floor_layer)


func _lot_item(id: String, p: Vector2) -> bool:
	if p.distance_to(player_start) < 200.0:
		return false
	var ok := false
	if not ArenaProp.get_def(id).has("destructible"):
		ok = _place_prop(p, id, true) != null
	elif _place_destructible(p, id) != null:
		_destr_done[id] = int(_destr_done.get(id, 0)) + 1
		ok = true
	return ok


## Точка в районе d у его дороги (2–5 клеток от линии дороги), по сетке 32 px.
func _district_point(d: int, area: Rect2) -> Vector2:
	var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
	if _district_of(p) != d or not _cover_allowed(p, 0.0):
		return Vector2.INF
	var c := world_to_cell(p)
	var near := 99
	for rx in _road_x:
		near = mini(near, absi(c.x - rx))
	for ry in _road_y:
		near = mini(near, absi(c.y - ry))
	if near < 3 or near > 6:
		return Vector2.INF
	return p.snapped(Vector2(32.0, 32.0))


func _scene_point(anchor: String, area: Rect2) -> Vector2:
	var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
	# Посреди квартала сцены не висят: «открытые» тоже встают у дороги (как у обочины).
	if anchor == "open":
		anchor = "lane"
	match anchor:
		"back":
			p.y = randf_range(area.position.y, area.position.y + 240.0)
		"front":
			p.y = randf_range(area.end.y - 240.0, area.end.y)
		"side":
			p.x = randf_range(area.position.x, area.position.x + 200.0) if randf() < 0.5 else randf_range(area.end.x - 380.0, area.end.x - 100.0)
		"lane":
			var near_lane := false
			for offset in [Vector2(0, 120), Vector2(0, -120), Vector2(140, 0), Vector2(-140, 0)]:
				if zone_at(p + offset) == Zone.LANE:
					near_lane = true
					break
			if not near_lane:
				return Vector2.INF
	if not _cover_allowed(p, 0.0):
		return Vector2.INF
	# Шаг сетки 32 px: соседние сцены и их предметы встают рядами, а не вразброс.
	return p.snapped(Vector2(32.0, 32.0))


func _scene_spacing_ok(p: Vector2) -> bool:
	for q in _cover_spots:
		if q.distance_to(p) < SCENE_SPACING:
			return false
	return true


func _scene_blocked_any(p: Vector2) -> bool:
	return chapter.has("scenes") and _scene_blocked(p)


func _scene_blocked(p: Vector2) -> bool:
	var zone := zone_at(p)
	if zone == Zone.BOSS or zone == Zone.GATE or zone == Zone.EDGE:
		return true
	if boss_rect.grow(90.0).has_point(p) or p.distance_to(boss_point + Vector2(0, 60)) < 220.0:
		return true
	for r in gate_rects:
		if r.grow(110.0).has_point(p):
			return true
	for r in _story_clear:
		if r.has_point(p):
			return true
	return false


func _place_scene(scene: Dictionary, anchor: Vector2) -> bool:
	_in_scene = true
	var placed := _place_scene_items(scene, anchor)
	_in_scene = false
	return placed


func _place_scene_items(scene: Dictionary, anchor: Vector2) -> bool:
	var mirror := -1.0 if randf() < 0.5 else 1.0
	var items: Array = scene.get("items", [])
	if items.is_empty():
		return false
	var main := _place_prop(anchor + Vector2(float(items[0][1]) * mirror, float(items[0][2])), str(items[0][0]), true)
	if main == null:
		return false
	for i in range(1, items.size()):
		var item: Array = items[i]
		_place_prop(anchor + Vector2(float(item[1]) * mirror, float(item[2])), str(item[0]), true)
	for item in scene.get("destr", []):
		var id := str(item[0])
		var limit: int = int(chapter.get("destructibles", {}).get(id, 0))
		if int(_destr_done.get(id, 0)) >= limit:
			continue
		if _place_destructible(anchor + Vector2(float(item[1]) * mirror, float(item[2])), id) != null:
			_destr_done[id] = int(_destr_done.get(id, 0)) + 1
	return true


func _build_destructibles() -> void:
	var table: Dictionary = chapter.get("destructibles", {})
	var area := _interior_rect()
	var placed: Array[Vector2] = []
	for prop_id in table:
		var need := int(round(float(table[prop_id]) * PROP_DENSITY * _area_scale)) - int(_destr_done.get(prop_id, 0))
		var done := 0
		for attempt in need * 40:
			if done >= need:
				break
			var p: Vector2
			if not _lots.is_empty():
				p = _lot_edge_point(_lots.pick_random())
			elif not _cover_spots.is_empty() and (chapter.has("scenes") or (prop_id == "d_barrel" and randf() < 0.6)):
				p = _cover_spots.pick_random() + Vector2(randf_range(-190, 190), randf_range(50, 130))
			else:
				p = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
			if not _cover_allowed(p, -60.0) and zone_at(p) != Zone.LANE:
				continue
			var near := false
			for q in placed:
				if q.distance_to(p) < 150.0:
					near = true
					break
			if near:
				continue
			if _place_destructible(p, str(prop_id)) != null:
				placed.append(p)
				done += 1


## Точка у края квартала (у забора двора / бордюра): бочки и ящики стоят вдоль стен, а не посреди двора.
func _lot_edge_point(rect: Rect2) -> Vector2:
	var inner := rect.grow(-28.0)
	var t := randf()
	match randi() % 4:
		0:
			return Vector2(lerpf(inner.position.x, inner.end.x, t), inner.position.y).snapped(Vector2(16, 16))
		1:
			return Vector2(lerpf(inner.position.x, inner.end.x, t), inner.end.y).snapped(Vector2(16, 16))
		2:
			return Vector2(inner.position.x, lerpf(inner.position.y, inner.end.y, t)).snapped(Vector2(16, 16))
	return Vector2(inner.end.x, lerpf(inner.position.y, inner.end.y, t)).snapped(Vector2(16, 16))


func _build_decor() -> void:
	var area := _interior_rect()
	if not _lots.is_empty():
		_build_lot_flats()
	for id in ([] if not _lots.is_empty() or _natural() else chapter.get("flat", [])):
		for n in 1:
			for attempt in 30:
				var p := _near_scene_point(area, 160.0, 320.0)
				if _cover_allowed(p, 40.0) and is_area_clear(p, CELL * 1.6):
					var prop := ArenaProp.new()
					prop.position = p
					prop.setup(str(id), false)
					_own(prop, _layers.decals)
					break
	if layout == "bank":
		return
	var stains := ArenaDecor.Stains.new()
	# Масло и грязь — там, где стоит хлам и техника, а не равномерно по полу.
	for i in int(16 * _area_scale):
		stains.spots.append([_near_scene_point(area, 40.0, 190.0), randf_range(26.0, 64.0), randf_range(-0.6, 0.6)])
	_own(stains, _layers.decals)
	var puddles := ArenaDecor.Puddles.new()
	for attempt in int(PUDDLE_COUNT * 8 * _area_scale):
		if _puddles.size() >= int(PUDDLE_COUNT * _area_scale):
			break
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		# Вода собирается на дороге у обочины, на органической Свалке — на краю замусоренных пятен.
		var wet := absf(_density(p) - (POI_OPEN + 0.12)) < 0.08 and is_area_clear(p, CELL) if _natural() else zone_at(p) == Zone.LANE and _near_curb(p)
		if is_walkable(p) and wet:
			_puddles.append([p, Vector2(randf_range(70, 130), randf_range(28, 48)), randf_range(-0.4, 0.4), randf() * TAU])
	puddles.puddles = _puddles
	_own(puddles, _layers.decals)
	for i in 3:
		for attempt in 30:
			var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
			# Пар идёт из люков посреди дороги.
			var road := zone_at(p) == Zone.LANE and not _near_curb(p)
			if (road or (_natural() and _density(p) < POI_OPEN)) and is_area_clear(p, CELL):
				var vent := ArenaDecor.SteamVent.new()
				vent.position = p
				_own(vent, _layers.decals)
				break


## Обломки (плоские пропы) в кварталах: по одному у угла двора, не посреди прохода.
func _build_lot_flats() -> void:
	var flats: Array = chapter.get("flat", []).duplicate()
	flats.shuffle()
	for i in mini(_lots.size(), flats.size()):
		var rect := _lots[i].grow(-70.0)
		var corner := Vector2(rect.position.x if randf() < 0.5 else rect.end.x, rect.position.y if randf() < 0.5 else rect.end.y)
		if not is_area_clear(corner, CELL * 1.4):
			continue
		var prop := ArenaProp.new()
		prop.position = corner
		prop.setup(str(flats[i]), false)
		_own(prop, _layers.decals)


## Точка в кольце min..max вокруг случайной уже поставленной сцены (без сцен — случайная по арене).
func _near_scene_point(area: Rect2, min_r: float, max_r: float) -> Vector2:
	if _cover_spots.is_empty():
		return Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
	var anchor: Vector2 = _cover_spots.pick_random()
	return (anchor + Vector2.from_angle(randf() * TAU) * randf_range(min_r, max_r)).clamp(area.position, area.end)


## Дорога, у которой рядом (в пределах полутора клеток) начинается не-дорога — обочина.
func _near_curb(p: Vector2) -> bool:
	for offset in [Vector2(CELL * 1.5, 0), Vector2(-CELL * 1.5, 0), Vector2(0, CELL * 1.5), Vector2(0, -CELL * 1.5)]:
		if zone_at(p + offset) != Zone.LANE:
			return true
	return false


# --- Размещение с проверкой наложений ------------------------------------------------------------

func _place_prop(base: Vector2, id: String, allow_hub: bool) -> ArenaProp:
	var shape := ArenaProp.make_shape(id)
	var center := base + ArenaProp.shape_offset(id)
	if (_in_scene and _scene_blocked(center)) or not _can_place(shape, center):
		return null
	if not allow_hub and base.distance_to(player_start) < 120.0:
		return null
	var prop := ArenaProp.new()
	prop.position = base
	prop.setup(id, true)
	_own(prop, _layers.world)
	_commit(shape, center, CellType.COVER, prop, float(ArenaProp.get_def(id).get("shadow", 40.0)))
	return prop


func _place_destructible(base: Vector2, id: String) -> DestructibleObject:
	var shape := DestructibleObject.shape_for(DestructibleObject.Kind.ART, id)
	var center := base + DestructibleObject.offset_for(DestructibleObject.Kind.ART, id)
	if _scene_blocked_any(center) or not _can_place(shape, center):
		return null
	var object := DestructibleObject.new()
	object.position = base
	object.setup_art(id, _layers.decals)
	object.destroyed.connect(_on_object_destroyed)
	_own(object, _layers.world)
	destructibles.append(object)
	_commit(shape, center, CellType.DESTRUCTIBLE, null, 0.0)
	return object


func _place_crate(base: Vector2) -> DestructibleObject:
	var shape := DestructibleObject.shape_for(DestructibleObject.Kind.WEAPON_CRATE, "")
	var center := base + DestructibleObject.offset_for(DestructibleObject.Kind.WEAPON_CRATE, "")
	if not _can_place(shape, center):
		return null
	var crate := DestructibleObject.new()
	crate.position = base
	crate.setup_crate()
	crate.destroyed.connect(_on_object_destroyed)
	_own(crate, _layers.world)
	destructibles.append(crate)
	_commit(shape, center, CellType.DESTRUCTIBLE, null, 0.0)
	return crate


## 1) все клетки под формой пусты; 2) Shape2D.collide с уже поставленными формами в соседних
## клетках (с запасом OVERLAP_MARGIN).
func _can_place(shape: Shape2D, center: Vector2) -> bool:
	var covered := _covered_cells(shape, center)
	for cell in covered:
		if not _inside(cell) or cells[_index(cell)] != CellType.EMPTY:
			return false
		var zone: int = zones[_index(cell)]
		if zone == Zone.EDGE or zone == Zone.GATE:
			return false
	var probe := _shrunk(shape)
	var xform := Transform2D(0.0, center)
	var checked := {}
	for cell in covered:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := cell + Vector2i(dx, dy)
				var key := _index(n) if _inside(n) else -1
				if key == -1 or checked.has(key) or not _occupants.has(key):
					continue
				checked[key] = true
				for entry in _occupants[key]:
					if probe.collide(xform, entry[0], entry[1]):
						return false
	return true


func _commit(shape: Shape2D, center: Vector2, kind: CellType, wall_node: Node2D, shadow_height: float) -> void:
	if shadow_height > 0.0:
		_add_shadow(shape, center, shadow_height)
	var entry := [_shrunk(shape), Transform2D(0.0, center)]
	for cell in _covered_cells(shape, center):
		var i := _index(cell)
		cells[i] = kind
		if not _occupants.has(i):
			_occupants[i] = []
		_occupants[i].append(entry)
		if wall_node != null:
			_wall_nodes[i] = wall_node


func _covered_cells(shape: Shape2D, center: Vector2) -> Array[Vector2i]:
	var rect := shape.get_rect()
	rect.position += center
	var from := world_to_cell(rect.position + Vector2.ONE * 0.5)
	var to := world_to_cell(rect.end - Vector2.ONE * 0.5)
	var result: Array[Vector2i] = []
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			result.append(Vector2i(x, y))
	return result


func _shrunk(shape: Shape2D) -> Shape2D:
	if shape is RectangleShape2D:
		var r := RectangleShape2D.new()
		r.size = ((shape as RectangleShape2D).size - Vector2.ONE * OVERLAP_MARGIN * 2.0).max(Vector2.ONE)
		return r
	var c := CircleShape2D.new()
	c.radius = maxf((shape as CircleShape2D).radius - OVERLAP_MARGIN, 1.0)
	return c


func _own(node: Node, parent: Node) -> void:
	parent.add_child(node)
	_owned.append(node)


# --- Связность ---------------------------------------------------------------------------------

func _ensure_connectivity() -> void:
	var start := world_to_cell(player_start)
	for pass_index in 40:
		var reached := _reachable_from(start)
		var isolated := _first_isolated(reached)
		if isolated == Vector2i(-1, -1):
			return
		_carve_to_reached(isolated, reached)


func _reachable_from(start: Vector2i) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(cells.size())
	var queue: Array[Vector2i] = [start]
	reached[_index(start)] = 1
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if not _inside(next) or reached[_index(next)] == 1 or _is_blocking(next):
				continue
			reached[_index(next)] = 1
			queue.append(next)
	return reached


func _first_isolated(reached: PackedByteArray) -> Vector2i:
	for i in cells.size():
		if reached[i] == 0 and not _is_blocking(Vector2i(i % grid_size.x, i / grid_size.x)):
			return Vector2i(i % grid_size.x, i / grid_size.x)
	return Vector2i(-1, -1)


## BFS от изолированной клетки до ближайшей достижимой; пропы на пути сносятся.
func _carve_to_reached(from: Vector2i, reached: PackedByteArray) -> void:
	var parent := {}
	var queue: Array[Vector2i] = [from]
	parent[from] = from
	var head := 0
	var target := Vector2i(-1, -1)
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if reached[_index(cell)] == 1:
			target = cell
			break
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if _inside(next) and not parent.has(next):
				parent[next] = cell
				queue.append(next)
	if target == Vector2i(-1, -1):
		cells[_index(from)] = CellType.WALL
		return
	var cell := target
	while cell != from:
		_clear_cell(cell)
		cell = parent[cell]
	_clear_cell(from)


func _clear_cell(cell: Vector2i) -> void:
	if not _inside(cell):
		return
	var i := _index(cell)
	if cells[i] == CellType.WALL:
		cells[i] = CellType.EMPTY
		return
	if cells[i] != CellType.COVER:
		return
	if _wall_nodes.has(i):
		var node: Node2D = _wall_nodes[i]
		for key in _wall_nodes.keys():
			if _wall_nodes[key] == node:
				cells[key] = CellType.EMPTY
				_occupants.erase(key)
				_wall_nodes.erase(key)
		node.queue_free()
	cells[i] = CellType.EMPTY
	_occupants.erase(i)


func _is_blocking(cell: Vector2i) -> bool:
	var t := cells[_index(cell)]
	return t == CellType.WALL or t == CellType.COVER


## Для поля путей непроходимо всё, что стоит на земле (разрушаемые — пока целы).
func _blocked_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(cells.size())
	for i in cells.size():
		mask[i] = 0 if cells[i] == CellType.EMPTY else 1
	return mask


# --- Ящики со сбросом -------------------------------------------------------------------------------

func _build_crate_pool() -> void:
	for i in CRATE_POOL:
		var crate := DestructibleObject.new()
		crate.position = bounds.position - Vector2(400, 400)
		crate.setup_crate()
		crate.hp = 0.0
		crate.visible = false
		crate.collision_layer = 0
		crate.destroyed.connect(_on_object_destroyed)
		crate.landed.connect(func(c: DestructibleObject) -> void: crate_landed.emit(c))
		_own(crate, _layers.world)
		_crate_pool.append(crate)


## Сброс ящика с оружием рядом с Енотом (начало волны). null — свободных ящиков/места нет.
func airdrop(near: Vector2) -> DestructibleObject:
	var crate: DestructibleObject = null
	for candidate in _crate_pool:
		if candidate.hp <= 0.0 and candidate.drop_height <= 0.0:
			crate = candidate
			break
	if crate == null:
		return null
	var at := find_spawn_point(near, AIRDROP_MIN, AIRDROP_MAX, 48.0)
	if at == Vector2.INF:
		return null
	crate.respawn(at, AIRDROP_HEIGHT)
	if not destructibles.has(crate):
		destructibles.append(crate)
	return crate


func _on_object_destroyed(object: DestructibleObject) -> void:
	var shape := DestructibleObject.shape_for(object.kind, object.prop_id)
	for cell in _covered_cells(shape, object.position + DestructibleObject.offset_for(object.kind, object.prop_id)):
		if _inside(cell) and cells[_index(cell)] == CellType.DESTRUCTIBLE:
			cells[_index(cell)] = CellType.EMPTY
			_flow.set_blocked(cell, false)
			_occupants.erase(_index(cell))
	destructibles.erase(object)
	object_destroyed.emit(object)


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _index(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x
