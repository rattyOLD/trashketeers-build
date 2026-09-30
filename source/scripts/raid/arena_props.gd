class_name ArenaProps
extends Node2D
## Декор арены Хладгора: разбитый корабль, ящики, ангар, ледяные глыбы. Стоят вокруг круга льда и внутри него,
## не мешают Еноту (без коллизий), но сортируются по Y вместе с миром. В финальной фазе Хладгор всё сносит:
## smash() запускает волну от дракона — каждый предмет в момент касания меняется на руины и сыплет обломками.

signal prop_smashed(at: Vector2, height: float, tint: Color)

const CELL := 224.0
const FOOT := 0.93
const SMASH_SPEED := 1100.0
const SHEETS := ["props_a", "props_b"]
const SNOW := Color("#e8fbff")
const WOOD := Color("#8a5a3c")
const METAL := Color("#8a9099")
const ICE := Color("#8fdcff")
## [лист, ячейка, угол°, радиус, ширина в мире, цвет обломков]
const LAYOUT := [
	[0, 4, 30.0, 900.0, 300.0, WOOD], [1, 6, 45.0, 892.0, 260.0, WOOD], [0, 2, 17.0, 885.0, 250.0, WOOD],
	[0, 6, 27.0, 800.0, 210.0, SNOW], [0, 7, 36.0, 760.0, 200.0, ICE],
	[0, 0, 205.0, 890.0, 360.0, WOOD], [1, 3, 188.0, 900.0, 210.0, METAL], [1, 1, 226.0, 900.0, 220.0, WOOD],
	[0, 2, 218.0, 870.0, 230.0, WOOD],
	[1, 4, 290.0, 905.0, 320.0, ICE], [0, 1, 271.0, 880.0, 270.0, ICE], [0, 5, 309.0, 880.0, 240.0, ICE],
	[1, 5, 130.0, 895.0, 250.0, METAL], [0, 3, 117.0, 890.0, 200.0, METAL], [0, 3, 143.0, 890.0, 200.0, METAL],
	[0, 3, 75.0, 900.0, 200.0, METAL], [0, 3, 250.0, 900.0, 200.0, METAL], [0, 3, 345.0, 900.0, 200.0, METAL],
]

var _props: Array[Sprite2D] = []
var _bodies: Array[StaticBody2D] = []
var _tints: Array[Color] = []
var _ruined: Array[Texture2D] = []
var _smashed := false


static func _cell_texture(sheet: String, index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = ArenaProp.texture_of("res://assets/raid/%s.png" % sheet)
	atlas.region = Rect2((index % 4) * CELL, (index / 4) * CELL, CELL, CELL)
	return atlas


func build(world: Node2D) -> void:
	world.add_child(self)
	y_sort_enabled = true
	for entry in LAYOUT:
		var sheet: String = SHEETS[entry[0]]
		var sprite := Sprite2D.new()
		sprite.texture = _cell_texture(sheet, entry[1])
		sprite.centered = false
		sprite.offset = Vector2(-CELL * 0.5, -CELL * FOOT)
		sprite.scale = Vector2.ONE * float(entry[4]) / CELL
		sprite.position = Vector2.from_angle(deg_to_rad(entry[2])) * float(entry[3])
		add_child(sprite)
		_props.append(sprite)
		_bodies.append(_make_body(sprite.position, float(entry[4])))
		_tints.append(entry[5])
		_ruined.append(_cell_texture(sheet + "_ruin", entry[1]))


## Основание предмета держит Енота и пули, пока предмет цел; снесённый — проходим.
func _make_body(at: Vector2, width: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.OBSTACLE
	body.collision_mask = 0
	body.position = at + Vector2(0, -width * 0.08)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width * 0.6, width * 0.16)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	return body


func is_smashed() -> bool:
	return _smashed


func smash(origin: Vector2) -> void:
	if _smashed:
		return
	_smashed = true
	for i in _props.size():
		var delay := origin.distance_to(_props[i].position) / SMASH_SPEED
		get_tree().create_timer(delay, false).timeout.connect(_break.bind(i))


func _break(index: int) -> void:
	var sprite := _props[index]
	if not is_instance_valid(sprite):
		return
	if is_instance_valid(_bodies[index]):
		_bodies[index].queue_free()
	sprite.texture = _ruined[index]
	var base := sprite.scale
	sprite.scale = base * Vector2(1.18, 0.82)
	sprite.create_tween().tween_property(sprite, "scale", base, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	prop_smashed.emit(sprite.position + Vector2(0, -CELL * 0.3 * sprite.scale.y), CELL * sprite.scale.y, _tints[index])
