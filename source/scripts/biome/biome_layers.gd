class_name BiomeLayers
extends Node2D
## Стек слоёв рендеринга биома по паспорту (Z-Index) и Y-Sort для объектов мира.
##
## floor  (z -10) — асфальт, лужи, трещины: рисуются один раз.
## decals (z -5)  — кислотные лужи, следы, тени машин: под персонажами, над полом.
## world  (z 0, y_sort_enabled) — Енот, крысы, заборы, машины, разрушаемые объекты.
## fx     (z 10)  — искры, частицы, цифры урона. Пули (BulletPool) тоже на z 10.
##
## Правило Y-Sort: начало координат каждого узла в world — точка, где объект касается пола.
## Высокие объекты (забор, машина, мониторы) рисуются вверх от origin, коллизия лежит у
## основания. Поэтому Енот, стоящий севернее основания забора, оказывается «за» забором,
## а южнее — «перед» ним: коллизия не даст центру Енота оказаться на неоднозначной высоте.

const Z_FLOOR := -10
const Z_DECALS := -5
const Z_WORLD := 0
const Z_FX := 10
## Бит light_mask пола: неоновый свет освещает только асфальт.
const LIGHT_MASK_FLOOR := 2

var floor_layer: Node2D
var decals: Node2D
var world: Node2D
var fx: Node2D


func _init() -> void:
	floor_layer = _make_layer(&"Floor", Z_FLOOR)
	floor_layer.light_mask = LIGHT_MASK_FLOOR
	decals = _make_layer(&"Decals", Z_DECALS)
	world = _make_layer(&"World", Z_WORLD)
	world.y_sort_enabled = true
	fx = _make_layer(&"Fx", Z_FX)


func _make_layer(layer_name: StringName, z: int) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	layer.z_index = z
	layer.z_as_relative = false
	add_child(layer)
	return layer
