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
const COVER_SPOTS := 11
const SCENE_SPACING := 380.0
const RIPPLE_INTERVAL := 0.3
const PUDDLE_COUNT := 9

var chapter: Dictionary = {}
var layout := "junkyard"
var grid_size := Vector2i(40, 50)
var cells := PackedByteArray()
var zones := PackedByteArray()
var destructibles: Array[DestructibleObject] = []
var player_start := Vector2.ZERO
var bounds := Rect2()
var boss_rect := Rect2()
var boss_point := Vector2.ZERO
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


func build(layers: BiomeLayers, chapter_def: Dictionary) -> void:
	_layers = layers
	chapter = chapter_def
	layout = str(chapter.get("layout", "junkyard"))
	var size: Array = chapter.get("size", [40, 50])
	grid_size = Vector2i(int(size[0]), int(size[1]))
	_origin = -Vector2(grid_size) * CELL * 0.5
	bounds = Rect2(_origin, Vector2(grid_size) * CELL)
	cells.resize(grid_size.x * grid_size.y)
	cells.fill(CellType.EMPTY)
	zones.resize(grid_size.x * grid_size.y)
	_assign_zones()
	_build_floor()
	_build_shadow_layers()
	_build_walls()
	_build_border()
	_build_boss_zone()
	_build_center()
	_build_gates()
	_build_lamps()
	_build_spotlights()
	_build_cover()
	_build_destructibles()
	_build_decor()
	_ensure_connectivity()
	_build_crate_pool()
	_place_crate(player_start + Vector2(0, -210))
	_flow.setup(grid_size, _blocked_mask())


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
	gate_rects.clear()
	_portal = null


func attach_player(player: Player) -> void:
	_player = player


# --- Координаты -------------------------------------------------------------------------------

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
	return Vector2.INF


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
	return _flow.direction_at(world_to_cell(from))


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
		_flow.rebuild(world_to_cell(_player.global_position), FLOW_RADIUS)


# --- Зоны пола ---------------------------------------------------------------------------------

func _assign_zones() -> void:
	var w := grid_size.x
	var h := grid_size.y
	var mid_y := h / 2
	var cx := w / 2
	boss_rect = _cells_rect(Vector2i(cx - 6, RING_TOP), Vector2i(12, 6))
	boss_point = boss_rect.get_center() + Vector2(0, -20)
	for y in h:
		for x in w:
			var zone := Zone.FLOOR
			var in_gate := absi(y - mid_y) < GATE_HALF and (x < RING_SIDE or x >= w - RING_SIDE)
			if in_gate:
				zone = Zone.GATE
			elif x < RING_SIDE or x >= w - RING_SIDE or y < RING_TOP or y >= h - RING_BOTTOM:
				zone = Zone.EDGE
			elif x >= cx - 6 and x < cx + 6 and y < RING_TOP + 6:
				zone = Zone.BOSS
			elif layout == "bank":
				zone = _bank_zone(x, y, cx, mid_y)
			else:
				zone = Zone.LANE if _junk_lane(x, y, cx, mid_y) else Zone.FLOOR
			zones[_index(Vector2i(x, y))] = zone
	player_start = cell_to_world(Vector2i(cx, h - RING_BOTTOM - 4)) + Vector2(-CELL * 0.5, 0)


## Рисунок дорожек свалки по варианту локации: крест, кольцо, диагонали, три полосы.
func _junk_lane(x: int, y: int, cx: int, mid_y: int) -> bool:
	match int(chapter.get("variant", 0)):
		1:
			var ring_x := absi(absi(x - cx) - 11)
			var ring_y := absi(absi(y - mid_y) - 12)
			var inside_x := absi(x - cx) <= 13
			var inside_y := absi(y - mid_y) <= 14
			return (ring_x < 2 and inside_y) or (ring_y < 2 and inside_x)
		2:
			var dx := float(x - cx) + 0.5
			var dy := float(y - mid_y) * 0.8
			return absf(absf(dx) - absf(dy)) < 2.2 and y >= RING_TOP + 6
		3:
			return absi(y - mid_y) < 2 or absi(y - mid_y - 12) < 2 or absi(y - mid_y + 12) < 2
	return absi(y - mid_y) < 2 or (absi(x - cx + 0.5) < 2.0 and y >= RING_TOP + 6)


## Банк: крест площади по центру, газоны по четвертям, розовые дорожки у боковых стен,
## круг площади под медальоном.
func _bank_zone(x: int, y: int, cx: int, mid_y: int) -> Zone:
	if x < RING_SIDE + 3 or x >= grid_size.x - RING_SIDE - 3:
		return Zone.LANE
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
func _build_floor() -> void:
	var texture: Texture2D = ArenaProp.texture_of(str(chapter.get("floor", "")))
	if texture == null:
		return
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(256, 256)
	var cols := int(texture.get_width() / 256)
	var rows := int(texture.get_height() / 256)
	for r in rows:
		for c in cols:
			source.create_tile(Vector2i(c, r))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(256, 256)
	tile_set.add_source(source, 0)
	var tile_map := TileMapLayer.new()
	tile_map.tile_set = tile_set
	tile_map.position = _origin
	tile_map.scale = Vector2.ONE * (CELL * 2.0 / 256.0)
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
	else:
		for side in [-1.0, 1.0]:
			_decor_prop(Vector2(cx + side * 150.0, back_y - 20.0), "container", 1 if side < 0.0 else -1)
		var sign := NeonSign.new()
		sign.setup(NeonSign.Icon.CHEESE, Color("#ff2e63"))
		sign.position = Vector2(cx, back_y - 150.0)
		sign.scale = Vector2.ONE * 1.4
		_own(sign, _layers.world)
		for side in [-1.0, 1.0]:
			_place_prop(Vector2(boss_rect.get_center().x + side * (boss_rect.size.x * 0.5 + 60.0), boss_rect.end.y - 10.0), "floodlight", true)


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


func _build_center() -> void:
	var center := Vector2(0, _origin.y + grid_size.y * 0.5 * CELL)
	if layout == "bank":
		var medal := ArenaDecor.floor_image("res://assets/props/ch2/medallion.png", 360.0)
		medal.position = cell_to_world(Vector2i(grid_size.x / 2, grid_size.y / 2 + 8)) + Vector2(-CELL * 0.5, 0)
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
		var post := "tire_stack" if layout != "bank" else "lamp_banner"
		for dy in [-1.0, 1.0]:
			var at := Vector2(r.get_center().x, r.get_center().y + dy * (GATE_HALF * CELL + 26.0) + (40.0 if dy > 0.0 else 0.0))
			_decor_prop(at, post)


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
	return true


func _build_cover() -> void:
	if chapter.has("scenes"):
		_build_scenes()
		return
	var big: Array = chapter.get("cover_big", [])
	var small: Array = chapter.get("cover_small", [])
	if big.is_empty():
		return
	var area := _interior_rect()
	for attempt in 500:
		if _cover_spots.size() >= COVER_SPOTS:
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
	for entry in chapter.get("scenes", []):
		var scene: Dictionary = library.get(str(entry[0]), {})
		if scene.is_empty():
			continue
		var done := 0
		for attempt in 120:
			if done >= int(entry[1]):
				break
			var p := _scene_point(str(scene.get("anchor", "open")), area)
			if p == Vector2.INF or not _scene_spacing_ok(p):
				continue
			if _place_scene(scene, p):
				_cover_spots.append(p)
				done += 1


func _scene_point(anchor: String, area: Rect2) -> Vector2:
	var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
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
	return p


func _scene_spacing_ok(p: Vector2) -> bool:
	for q in _cover_spots:
		if q.distance_to(p) < SCENE_SPACING:
			return false
	return true


func _place_scene(scene: Dictionary, anchor: Vector2) -> bool:
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
		var need := int(table[prop_id]) - int(_destr_done.get(prop_id, 0))
		var done := 0
		for attempt in need * 40:
			if done >= need:
				break
			var p: Vector2
			if not _cover_spots.is_empty() and (chapter.has("scenes") or (prop_id == "d_barrel" and randf() < 0.6)):
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


func _build_decor() -> void:
	var area := _interior_rect()
	for id in chapter.get("flat", []):
		for n in 2:
			for attempt in 30:
				var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
				if _cover_allowed(p, 40.0) and is_area_clear(p, CELL * 1.6):
					var prop := ArenaProp.new()
					prop.position = p
					prop.setup(str(id), false)
					_own(prop, _layers.decals)
					break
	if layout == "bank":
		return
	var stains := ArenaDecor.Stains.new()
	for i in 16:
		stains.spots.append([Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)), randf_range(26.0, 64.0), randf_range(-0.6, 0.6)])
	_own(stains, _layers.decals)
	var puddles := ArenaDecor.Puddles.new()
	for attempt in PUDDLE_COUNT * 8:
		if _puddles.size() >= PUDDLE_COUNT:
			break
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		if is_walkable(p) and zone_at(p) != Zone.BOSS:
			_puddles.append([p, Vector2(randf_range(70, 130), randf_range(28, 48)), randf_range(-0.4, 0.4), randf() * TAU])
	puddles.puddles = _puddles
	_own(puddles, _layers.decals)
	for i in 3:
		for attempt in 30:
			var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
			if _cover_allowed(p, 20.0) and is_area_clear(p, CELL):
				var vent := ArenaDecor.SteamVent.new()
				vent.position = p
				_own(vent, _layers.decals)
				break


# --- Размещение с проверкой наложений ------------------------------------------------------------

func _place_prop(base: Vector2, id: String, allow_hub: bool) -> ArenaProp:
	var shape := ArenaProp.make_shape(id)
	var center := base + ArenaProp.shape_offset(id)
	if not _can_place(shape, center):
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
	if not _can_place(shape, center):
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
