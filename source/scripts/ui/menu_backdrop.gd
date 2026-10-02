class_name MenuBackdrop
extends Node2D
## Живой фон хаба: кусок Неоновой Свалки из того же атласа пола и пропов, что и арена главы 1,
## по которому бродят крысы и свин-охранник, а камера медленно плывёт.
## Строится один раз при открытии меню; без света и физики — только спрайты, чтобы хаб
## ничего не стоил на телефоне.

const AREA := Vector2(1408, 1792)
const TILE_WORLD := 128.0
const PAN_AMPLITUDE := Vector2(150, 110)
const PAN_SPEED := 0.07
const FLOOR_DIR := "res://assets/biome/m1/"
const FLOORS := ["floor_yard_dark", "floor_scrapyard_dark", "floor_yard_light", "floor_gate_dark"]
const PROPS := [
	["container", Vector2(250, 420), false],
	["junk_pile", Vector2(1120, 560), true],
	["generator", Vector2(860, 300), false],
	["crt_terminal", Vector2(420, 980), false],
	["d_rust_barrel", Vector2(1150, 1080), true],
	["tire_stack", Vector2(200, 1320), false],
	["dumpster", Vector2(780, 1500), true],
	["fence", Vector2(560, 640), false],
	["m1_garbage", Vector2(1000, 1400), false],
	["m1_fridge", Vector2(640, 1120), false],
	["m1_crate", Vector2(930, 800), true],
	["m1_skull_sign", Vector2(1260, 880), false],
]
const WALKERS := [
	["res://assets/enemies/rat_gang.png", 150.0, Vector2(380, 760), Vector2(820, 820), 0.08, 0.0],
	["res://assets/enemies/rat_mad.png", 130.0, Vector2(940, 1220), Vector2(1180, 860), 0.07, 0.4],
	["res://assets/enemies/spark_rat.png", 140.0, Vector2(320, 1140), Vector2(680, 1200), 0.1, 0.7],
	["res://assets/enemies/pig_default.png", 150.0, Vector2(600, 400), Vector2(1000, 460), 0.06, 0.2],
]

var _layers: BiomeLayers
var _walkers: Array[Sprite2D] = []
var _scales: PackedFloat32Array = PackedFloat32Array()
var _time := 0.0
var _base := Vector2.ZERO


func build(view_size: Vector2) -> void:
	_base = view_size * 0.5 - AREA * 0.5
	position = _base
	_layers = BiomeLayers.new()
	add_child(_layers)
	_build_floor()
	_build_props()
	_build_walkers()


func _process(delta: float) -> void:
	_time += delta
	position = _base + Vector2(sin(_time * PAN_SPEED * TAU), cos(_time * PAN_SPEED * 0.7 * TAU)) * PAN_AMPLITUDE
	for i in _walkers.size():
		var path: Array = WALKERS[i]
		var t := fmod(_time * float(path[4]) + float(path[5]), 1.0)
		var from: Vector2 = path[2]
		var to: Vector2 = path[3]
		var forward := t < 0.5
		var k := t * 2.0 if forward else (1.0 - t) * 2.0
		var walker := _walkers[i]
		walker.position = from.lerp(to, smoothstep(0.0, 1.0, k))
		var facing := 1.0 if (to.x > from.x) == forward else -1.0
		var s := _scales[i]
		var step := absf(sin(_time * 11.0 + i))
		walker.scale = Vector2(s * facing, s * (1.0 - 0.05 * step))
		walker.rotation = sin(_time * 11.0 + i) * 0.06


func _build_floor() -> void:
	# Бетонный двор базы: тайлы пола миссии 1 (тёмный двор и металлолом), у центральной полосы ворот.
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(256, 256)
	var ids := {}
	for name in FLOORS:
		var texture := ArenaProp.texture_of(FLOOR_DIR + name + ".png")
		if texture == null:
			continue
		var source := TileSetAtlasSource.new()
		source.texture = texture
		source.texture_region_size = Vector2i(256, 256)
		source.create_tile(Vector2i.ZERO)
		ids[name] = tile_set.add_source(source)
	if ids.is_empty():
		return
	var tiles := TileMapLayer.new()
	tiles.tile_set = tile_set
	tiles.scale = Vector2.ONE * (TILE_WORLD / 256.0)
	var count := Vector2i(AREA / TILE_WORLD) + Vector2i.ONE
	for y in count.y:
		for x in count.x:
			var lane := x == 5 or y == 7
			var pick := "floor_gate_dark" if lane else FLOORS[0]
			var roll := randf()
			if not lane:
				pick = FLOORS[0] if roll < 0.62 else (FLOORS[1] if roll < 0.82 else FLOORS[2])
			if not ids.has(pick):
				pick = ids.keys()[0]
			tiles.set_cell(Vector2i(x, y), int(ids[pick]), Vector2i.ZERO)
	_layers.floor_layer.add_child(tiles)


func _build_props() -> void:
	for entry in PROPS:
		var def := ArenaProp.get_def(str(entry[0]))
		if def.is_empty():
			continue
		var sprite := ArenaProp.make_sprite(str(def.get("texture", "")), float(def.get("width", 0.0)))
		sprite.position = entry[1]
		sprite.flip_h = bool(entry[2])
		_layers.world.add_child(sprite)


func _build_walkers() -> void:
	for entry in WALKERS:
		var texture := ArenaProp.texture_of(str(entry[0]))
		if texture == null:
			continue
		var walker := Sprite2D.new()
		walker.texture = texture
		walker.offset = Vector2(0, -texture.get_height() * 0.5)
		_layers.world.add_child(walker)
		_walkers.append(walker)
		_scales.append(float(entry[1]) / texture.get_width())
