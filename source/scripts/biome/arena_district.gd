class_name ArenaDistrict
extends Node2D
## Живой район за забором арены (арт Астры, docs/briefs/astra_full.txt, части 3–4).
## Камера заходит за край арены на MARGIN_*: там земля района, забор по краю, за забором толпа
## зрителей (крысы на Свалке, свиньи в Банке, плюс двое особых зрителей главы), дальше дома,
## машины и объекты главы. Чистая картинка без коллизий: стены арены остаются как были.
## Зрители — лента 4 кадра (стоит / машет / прыгает / хлопает): чем жарче бой, тем чаще
## реагируют; появление и смерть босса поднимают всю трибуну. Анимация — 10 раз в секунду.

const ROOT := "res://assets/district/"
const MARGIN_TOP := 360.0
const MARGIN_SIDE := 340.0
const MARGIN_BOTTOM := 190.0
const TICK := 0.1
const FENCE_SCALE := 0.75
const SIDE_FENCE_SCALE := 0.5
const SPECTATOR_SCALE := 0.82
const TOP_SPACING := 92.0
const SIDE_SPACING := 118.0
const GATE_CLEAR := 3.4

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
## Ночью на Свалке у домов горят вывески и окна: мягкие пятна света (EnvLights), иначе район тонет в темноте.
var _neon := false
var _lights: PackedInt32Array = PackedInt32Array()
const NEON := [Color("#3df2ff"), Color("#ff7a3d"), Color("#ff4fd8"), Color("#ffd257")]


## Видимая область с районом (камера ограничена ею, а не стенами арены).
static func view_rect(bounds: Rect2) -> Rect2:
	return bounds.grow_individual(MARGIN_SIDE, MARGIN_TOP, MARGIN_SIDE, MARGIN_BOTTOM)


static func has_art(layout: String) -> bool:
	return DISTRICTS.has(layout)


func build(layout: String, chapter_id: String, bounds: Rect2, gate_y: float, gate_half: float) -> void:
	y_sort_enabled = true
	var district: Dictionary = DISTRICTS[layout]
	_neon = layout == "junkyard"
	# Ночная Свалка темнее карты освещения: район чуть подсвечен, чтобы толпу и дома было видно.
	modulate = Color(1.45, 1.4, 1.5) if _neon else Color.WHITE
	var dir := ROOT + layout + "/"
	var chapter_key: String = CHAPTER_OF.get(chapter_id, CHAPTER_OF.get(chapter_id.get_slice("_", 0), "ch1" if layout == "junkyard" else "ch4"))
	var special: Array = CHAPTERS[chapter_key]
	var chapter_dir := ROOT + chapter_key + "/"
	_ground(dir + str(district["prefix"]) + "_ground_tile.png", view_rect(bounds))
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
	# Верх: забор по краю, за ним трибуна в два ряда, дальше дома вперемешку с машинами и объектами.
	_fence_row(fence_h, bounds.position.x - MARGIN_SIDE, bounds.end.x + MARGIN_SIDE, bounds.position.y + 4.0)
	_crowd_row(crowd, bounds.position.x - MARGIN_SIDE + 40.0, bounds.end.x + MARGIN_SIDE, bounds.position.y - 64.0, TOP_SPACING)
	_crowd_row(crowd, bounds.position.x - MARGIN_SIDE + 86.0, bounds.end.x + MARGIN_SIDE, bounds.position.y - 104.0, TOP_SPACING * 1.25)
	_backdrop_row(buildings, small, bounds.position.x - MARGIN_SIDE, bounds.end.x + MARGIN_SIDE, bounds.position.y - 146.0, 0.7)
	# Низ: забор у края, перед ним (ближе к камере) машины и объекты — без зрителей: там кнопки.
	_fence_row(fence_h, bounds.position.x - MARGIN_SIDE, bounds.end.x + MARGIN_SIDE, bounds.end.y + 92.0)
	_backdrop_row(small, small, bounds.position.x - MARGIN_SIDE, bounds.end.x + MARGIN_SIDE, bounds.end.y + MARGIN_BOTTOM - 6.0, 0.62)
	# Бока: забор столбом (с проходом у ворот), зрители вдоль него, дома дальним столбцом.
	for side: float in [-1.0, 1.0]:
		var edge: float = bounds.position.x if side < 0.0 else bounds.end.x
		var fence_x := edge + side * 34.0
		var spans := [Vector2(bounds.position.y - MARGIN_TOP * 0.2, gate_top), Vector2(gate_bottom, bounds.end.y + 92.0)]
		for span: Vector2 in spans:
			_fence_column(fence_v, fence_x, span.x, span.y)
			var y := span.x + 90.0
			while y < span.y - 20.0:
				_spectator(crowd.pick_random(), Vector2(edge + side * randf_range(105.0, 135.0), y))
				y += SIDE_SPACING * randf_range(0.8, 1.2)
			var by := span.x + 200.0
			while by < span.y:
				var path: String = buildings.pick_random() if randf() < 0.7 else small.pick_random()
				var item := _backdrop(path, Vector2(edge + side * 245.0, by), 0.6)
				item.flip_h = side < 0.0
				by += maxf(item.get_rect().size.y * item.scale.y * 0.82, 150.0)
	set_process(not _crowd.is_empty())


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
	if texture == null:
		return
	var ground := Sprite2D.new()
	ground.texture = texture
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(Vector2.ZERO, rect.size)
	ground.centered = false
	ground.position = rect.position
	ground.z_index = -1
	ground.modulate = Color(0.9, 0.88, 0.94)
	add_child(ground)
	move_child(ground, 0)


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


func _spectator(path: String, foot: Vector2) -> void:
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
