class_name ArenaDistrict
extends Node2D
## Живой район за забором арены (арт Астры, docs/briefs/astra_full.txt, части 3–4).
## Забор стоит ровно по краю игровой площадки, на кольце стен за ним — трибуны зрителей (крысы на
## Свалке, свиньи в Банке, плюс двое особых зрителей главы), дальше, за краем карты (камера заходит
## на MARGIN_*), — дома, машины и объекты главы. Чистая картинка без коллизий: стены кольца как были.
## Зрители — лента 4 кадра (стоит / машет / прыгает / хлопает): чем жарче бой, тем чаще
## реагируют; появление и смерть босса поднимают всю трибуну. Анимация — 10 раз в секунду.

const ROOT := "res://assets/district/"
const MARGIN_TOP := 160.0
const MARGIN_SIDE := 260.0
const MARGIN_BOTTOM := 120.0
const TICK := 0.1
const FENCE_SCALE := 0.75
const SIDE_FENCE_SCALE := 0.5
const SPECTATOR_SCALE := 0.82
const TOP_SPACING := 84.0
const SIDE_SPACING := 96.0
const GATE_CLEAR := 1.7

const DISTRICTS := {
	"junkyard": {
		"prefix": "rats",
		"buildings": ["rats_apartment", "rats_bar_hangar", "rats_garage", "rats_shack", "rats_shawarma_kiosk"],
		"cars": ["rats_car", "rats_van", "rats_scooter"],
	},
	"bank": {
		"prefix": "pigs",
		"buildings": ["pigs_boutique", "pigs_chalet_pool", "pigs_gazebo", "pigs_restaurant", "pigs_villa"],
		"cars": ["pigs_convertible", "pigs_limousine", "pigs_sportscar"],
	},
}
const CHAPTERS := {
	"ch1": [["ch1_beer_pub", "ch1_brewery", "ch1_draft_kiosk"], ["ch1_keg_stack", "ch1_plastic_tables"], ["ch1_spectator_bartender", "ch1_spectator_drunk"]],
	"ch2": [["ch2_substation", "ch2_electrician_hut", "ch2_power_pylon"], ["ch2_transformer_box", "ch2_sparking_wires"], ["ch2_spectator_electrician", "ch2_spectator_static"]],
	"ch3": [["ch3_fish_market", "ch3_port_crane", "ch3_rickety_dock"], ["ch3_fish_crates", "ch3_anchor_chain"], ["ch3_spectator_fisherman", "ch3_spectator_sailor"]],
	"ch4": [["ch4_mansion", "ch4_helipad", "ch4_tennis_court"], ["ch4_pig_fountain", "ch4_pool_loungers"], ["ch4_spectator_cigar", "ch4_spectator_butler"]],
	"ch5": [["ch5_restaurant", "ch5_patisserie", "ch5_food_truck"], ["ch5_cloche_tables", "ch5_cake_cart"], ["ch5_spectator_gourmet", "ch5_spectator_waiter"]],
	"ch6": [["ch6_golf_clubhouse", "ch6_yacht", "ch6_casino"], ["ch6_golf_cart", "ch6_golf_flag"], ["ch6_spectator_golfer", "ch6_spectator_diamonds"]],
}
const CHAPTER_OF := {"junkyard": "ch1", "junkyard_2": "ch2", "junkyard_3": "ch3", "bank": "ch4", "bank_2": "ch5", "bank_3": "ch6"}

## Возбуждение трибун 0..1: растёт от убийств, спадает само.
var heat := 0.0

var _crowd: Array[Sprite2D] = []
var _base_y: PackedFloat32Array = PackedFloat32Array()
var _timer: PackedFloat32Array = PackedFloat32Array()
var _tick := 0.0
var _time := 0.0
var _textures := {}
## Протока: [x у верхнего края, x у нижнего края, полуширина просвета] — там толпа и дома расступаются.
var avoid: Array = []
var _inner := Rect2()
var _holder: Node2D
## Ночью на Свалке у домов горят вывески и окна: мягкие пятна света (EnvLights), иначе район тонет в темноте.
var _neon := false
var _lights: PackedInt32Array = PackedInt32Array()
const NEON := [Color("#3df2ff"), Color("#ff7a3d"), Color("#ff4fd8"), Color("#ffd257")]


## Видимая область с районом (камера ограничена ею, а не стенами арены).
static func view_rect(bounds: Rect2) -> Rect2:
	return bounds.grow_individual(MARGIN_SIDE, MARGIN_TOP, MARGIN_SIDE, MARGIN_BOTTOM)


static func has_art(layout: String) -> bool:
	return DISTRICTS.has(layout)


func build(layout: String, chapter_id: String, bounds: Rect2, inner: Rect2, gate_y: float, gate_half: float) -> void:
	y_sort_enabled = true
	var district: Dictionary = DISTRICTS[layout]
	_neon = layout == "junkyard"
	# Ночная Свалка темнее карты освещения: район чуть подсвечен, чтобы толпу и дома было видно.
	modulate = Color(1.45, 1.4, 1.5) if _neon else Color.WHITE
	var dir := ROOT + layout + "/"
	var chapter_key: String = CHAPTER_OF.get(chapter_id, CHAPTER_OF.get(chapter_id.get_slice("_", 0), "ch1" if layout == "junkyard" else "ch4"))
	var special: Array = CHAPTERS[chapter_key]
	var chapter_dir := ROOT + chapter_key + "/"
	var view := view_rect(bounds)
	_inner = inner
	# Земля района — всё вне игровой площадки: кольцо стен и поля камеры за ним.
	var ground := dir + str(district["prefix"]) + "_ground_tile.png"
	_ground(ground, Rect2(view.position, Vector2(view.size.x, inner.position.y - view.position.y)))
	_ground(ground, Rect2(Vector2(view.position.x, inner.end.y), Vector2(view.size.x, view.end.y - inner.end.y)))
	_ground(ground, Rect2(Vector2(view.position.x, inner.position.y), Vector2(inner.position.x - view.position.x, inner.size.y)))
	_ground(ground, Rect2(Vector2(inner.end.x, inner.position.y), Vector2(view.end.x - inner.end.x, inner.size.y)))
	var buildings: Array[String] = []
	for id in district["buildings"]:
		buildings.append(dir + str(id) + ".png")
	for id in special[0]:
		# Свои здания главы попадаются вдвое чаще общих.
		buildings.append(chapter_dir + str(id) + ".png")
		buildings.append(chapter_dir + str(id) + ".png")
	var small: Array[String] = []
	for id in district["cars"]:
		small.append(dir + str(id) + ".png")
	for id in special[1]:
		small.append(chapter_dir + str(id) + ".png")
		small.append(chapter_dir + str(id) + ".png")
	var crowd: Array[String] = []
	for i in 6:
		crowd.append(dir + "%s_spectator_%d.png" % [district["prefix"], i + 1])
	for id in special[2]:
		crowd.append(chapter_dir + str(id) + ".png")
		crowd.append(chapter_dir + str(id) + ".png")
	var fence_h := dir + str(district["prefix"]) + "_fence_horizontal.png"
	var fence_v := dir + str(district["prefix"]) + "_fence_vertical.png"
	var gate_top := gate_y - gate_half * GATE_CLEAR
	var gate_bottom := gate_y + gate_half * GATE_CLEAR
	var lite := SaveService.get_quality() == 0
	# Верх: забор ровно по краю площадки, сразу за ним трибуна в два-три ряда, дальше дома.
	_fence_row(fence_h, inner.position.x - 40.0, inner.end.x + 40.0, inner.position.y + 6.0)
	_crowd_row(crowd, inner.position.x, inner.end.x, inner.position.y - 58.0, TOP_SPACING)
	_crowd_row(crowd, inner.position.x + 46.0, inner.end.x, inner.position.y - 108.0, TOP_SPACING * (1.6 if lite else 1.1))
	if not lite:
		_crowd_row(crowd, inner.position.x + 20.0, inner.end.x, inner.position.y - 158.0, TOP_SPACING * 1.5)
	_backdrop_row(buildings, small, view.position.x, view.end.x, inner.position.y - 215.0, 0.72)
	# Низ: забор по краю, за ним (ближе к камере) машины и объекты — без зрителей: там кнопки.
	_fence_row(fence_h, inner.position.x - 40.0, inner.end.x + 40.0, inner.end.y + 92.0)
	_backdrop_row(small, small, view.position.x, view.end.x, inner.end.y + 200.0, 0.62)
	# Бока: забор столбом по краю площадки (проход у ворот), зрители в два столбца, дома дальше.
	for side: float in [-1.0, 1.0]:
		var edge: float = inner.position.x if side < 0.0 else inner.end.x
		var spans := [Vector2(inner.position.y + 6.0, gate_top), Vector2(gate_bottom, inner.end.y + 92.0)]
		for span: Vector2 in spans:
			_fence_column(fence_v, edge + side * 30.0, span.x, span.y)
			var y := span.x + 70.0
			while y < span.y - 20.0:
				_spectator(crowd.pick_random(), Vector2(edge + side * randf_range(86.0, 100.0), y))
				if not lite and randf() < 0.55:
					_spectator(crowd.pick_random(), Vector2(edge + side * randf_range(148.0, 162.0), y - 40.0))
				y += SIDE_SPACING * randf_range(0.75, 1.1)
			var by := span.x + 120.0
			while by < span.y:
				var path: String = buildings.pick_random() if randf() < 0.7 else small.pick_random()
				var item := _backdrop(path, Vector2(edge + side * 330.0, by), 0.6)
				item.flip_h = side < 0.0
				by += maxf(item.get_rect().size.y * item.scale.y * 0.82, 150.0)
	if _neon:
		# Гирлянды над трибунами: ночью толпа у забора видна, а не тонет в темноте.
		var x := inner.position.x + 120.0
		while x < inner.end.x:
			_lights.append(EnvLights.add(Vector2(x, inner.position.y - 90.0), NEON.pick_random(), 300.0, 0.5))
			x += 380.0
		for side: float in [-1.0, 1.0]:
			var edge: float = inner.position.x if side < 0.0 else inner.end.x
			var y := inner.position.y + 160.0
			while y < inner.end.y:
				if absf(y - gate_y) > gate_half * GATE_CLEAR:
					_lights.append(EnvLights.add(Vector2(edge + side * 110.0, y), NEON.pick_random(), 300.0, 0.5))
				y += 380.0
	set_process(not _crowd.is_empty() and not lite)


## Минимальная бодрость трибуны: убийство (+0.07), элита (+0.15), босс (1.0).
func cheer(amount: float) -> void:
	heat = clampf(heat + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	heat = maxf(heat - delta * 0.18, 0.0)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var react := 0.08 + 0.8 * heat
	for i in _crowd.size():
		var fan := _crowd[i]
		_timer[i] -= TICK
		if _timer[i] <= 0.0:
			if fan.frame == 0 and randf() < react:
				fan.frame = 1 + randi() % 3
				_timer[i] = randf_range(0.35, 0.8)
			else:
				fan.frame = 0
				_timer[i] = randf_range(0.5, 2.6) * (1.0 - 0.6 * heat)
		# Кадр «прыгает» — ещё и подскок по высоте.
		fan.position.y = _base_y[i] - (absf(sin(_time * 11.0 + i)) * 9.0 if fan.frame == 2 else 0.0)


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]


func _ground(path: String, rect: Rect2) -> void:
	var texture := _texture(path)
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ground := Sprite2D.new()
	ground.texture = texture
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	# Регион в мировых координатах: четыре полосы вокруг площадки стыкуются без шва.
	ground.region_rect = Rect2(rect.position, rect.size)
	ground.centered = false
	ground.position = rect.position - _ground_holder().position
	ground.modulate = Color(0.9, 0.88, 0.94)
	_ground_holder().add_child(ground)


## Протока за забором (исток/устье): под забором и толпой, над землёй района.
func add_stream(points: PackedVector2Array, width: float, water: bool, _top: bool) -> void:
	var stream := AcidRiver.new()
	stream.water = water
	_ground_holder().add_child(stream)
	stream.position = -_ground_holder().position
	stream.build(points, width, [], 1.0)


## Земля — в отдельном узле далеко «сверху» по Y: в сортировке по Y он всегда первый, поэтому земля под
## толпой и домами, но над плиткой пола арены (тот же слой, без отрицательного z).
func _ground_holder() -> Node2D:
	if _holder == null:
		_holder = Node2D.new()
		_holder.position = Vector2(0, -100000)
		add_child(_holder)
	return _holder


func _fence_row(path: String, from_x: float, to_x: float, foot_y: float) -> void:
	var texture := _texture(path)
	if texture == null:
		return
	var fence := Sprite2D.new()
	fence.texture = texture
	fence.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	fence.region_enabled = true
	fence.region_rect = Rect2(0, 0, (to_x - from_x) / FENCE_SCALE, texture.get_height())
	fence.scale = Vector2.ONE * FENCE_SCALE
	fence.centered = false
	fence.offset = Vector2(0, -texture.get_height())
	fence.position = Vector2(from_x, foot_y)
	add_child(fence)


func _fence_column(path: String, center_x: float, from_y: float, to_y: float) -> void:
	var texture := _texture(path)
	if texture == null or to_y <= from_y:
		return
	var fence := Sprite2D.new()
	fence.texture = texture
	fence.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	fence.region_enabled = true
	fence.region_rect = Rect2(0, 0, texture.get_width(), (to_y - from_y) / SIDE_FENCE_SCALE)
	fence.scale = Vector2.ONE * SIDE_FENCE_SCALE
	fence.centered = false
	fence.offset = Vector2(-texture.get_width() * 0.5, -fence.region_rect.size.y)
	fence.position = Vector2(center_x, to_y)
	add_child(fence)


func _crowd_row(paths: Array[String], from_x: float, to_x: float, foot_y: float, spacing: float) -> void:
	var x := from_x
	while x < to_x:
		_spectator(paths.pick_random(), Vector2(x + randf_range(-14.0, 14.0), foot_y + randf_range(-6.0, 6.0)))
		x += spacing * randf_range(0.8, 1.25)


func _blocked(x: float, y: float, half: float) -> bool:
	if avoid.is_empty():
		return false
	var sx: float = avoid[0] if y < _inner.get_center().y else avoid[1]
	if y > _inner.position.y and y < _inner.end.y:
		return false
	return absf(x - sx) < float(avoid[2]) + half


func _spectator(path: String, foot: Vector2) -> void:
	if _blocked(foot.x, foot.y, 30.0):
		return
	var texture := _texture(path)
	if texture == null:
		return
	var fan := Sprite2D.new()
	fan.texture = texture
	fan.hframes = 4
	fan.offset = Vector2(0, -60)
	fan.scale = Vector2.ONE * SPECTATOR_SCALE * randf_range(0.92, 1.06)
	fan.flip_h = randf() < 0.5
	fan.position = foot
	add_child(fan)
	_crowd.append(fan)
	_base_y.append(foot.y)
	_timer.append(randf_range(0.0, 2.0))


func _backdrop_row(big: Array[String], small: Array[String], from_x: float, to_x: float, foot_y: float, scale_k: float) -> void:
	var x := from_x + randf_range(0.0, 60.0)
	while x < to_x:
		var path: String = big.pick_random() if randf() < 0.65 else small.pick_random()
		var item := _backdrop(path, Vector2.ZERO, scale_k)
		var width := item.get_rect().size.x * item.scale.x
		item.position = Vector2(x + width * 0.5, foot_y + randf_range(-10.0, 10.0))
		if _blocked(item.position.x, foot_y, width * 0.5):
			item.queue_free()
			x += width
			continue
		item.flip_h = randf() < 0.5
		x += width * randf_range(0.92, 1.08)


func _backdrop(path: String, foot: Vector2, scale_k: float) -> Sprite2D:
	var item := Sprite2D.new()
	item.texture = _texture(path)
	item.scale = Vector2.ONE * scale_k
	item.offset = Vector2(0, -item.texture.get_height() * 0.5)
	item.position = foot
	add_child(item)
	if _neon and item.texture.get_width() * scale_k > 120.0:
		_light.call_deferred(item)
	return item


func _light(item: Sprite2D) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return
	var height := item.texture.get_height() * item.scale.y
	_lights.append(EnvLights.add(item.global_position - Vector2(0, height * 0.4), NEON.pick_random(), 220.0, 0.55))


func _exit_tree() -> void:
	for id in _lights:
		EnvLights.remove(id)
	_lights.clear()
