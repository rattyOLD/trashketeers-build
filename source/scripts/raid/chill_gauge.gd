class_name ChillGauge
extends Node2D
## Озноб над Енотом: шкала, иней на лапах и плечах по мере роста и ледяной куб при заморозке.
## Куб «оживает»: всплывает с пружиной, дрожит, в последние доли секунды трескается перед тем, как Raid разобьёт его.

const WIDTH := 70.0
const HEIGHT := 9.0
const BODY_CENTER := Vector2(0, 52)
const CRACK_TIME := 0.5
const ICE_CELL := 160
const BLOCK_HEIGHT := 150.0
static var _cells := {}
const FROST_SPOTS := 9

var value := 0.0
var frozen := false
var frozen_left := 0.0
var frozen_total := 1.3

var _time := 0.0
var _frozen_age := 0.0


func _init() -> void:
	z_index = 20
	position = Vector2(0, -84)


func _process(delta: float) -> void:
	_time += delta
	_frozen_age = _frozen_age + delta if frozen else 0.0
	queue_redraw()


func _draw() -> void:
	var fill := clampf(value / 100.0, 0.0, 1.0)
	if frozen:
		_draw_block()
	elif fill > 0.12:
		_draw_creeping_frost(fill)
	if value < 2.0 and not frozen:
		return
	var back := Rect2(Vector2(-WIDTH * 0.5, 0), Vector2(WIDTH, HEIGHT))
	draw_rect(back.grow(3.0), Color("#0b1a33", 0.85))
	var pulse := 0.5 + 0.5 * sin(_time * 12.0)
	var tint := Color("#7fdcff").lerp(Color("#ffffff"), pulse * fill * fill)
	draw_rect(Rect2(back.position, Vector2(WIDTH * fill, HEIGHT)), tint)
	draw_rect(back, Color(0.75, 0.95, 1.0, 0.9), false, 2.0)


## Иней ползёт по Еноту: кристаллики у лап, затем на боках и плечах, дыхание паром.
func _draw_creeping_frost(fill: float) -> void:
	var count := int(ceil(fill * FROST_SPOTS))
	for i in count:
		var a := TAU * i / FROST_SPOTS + 0.4
		var base := BODY_CENTER + Vector2(cos(a) * 30.0, sin(a) * 40.0 + 6.0)
		var size := 6.0 + 7.0 * fill
		var tip := base + Vector2(cos(a) * size * 0.6, sin(a) * size - 4.0)
		var side := Vector2(-sin(a), cos(a)) * size * 0.35
		draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(0.82, 0.96, 1.0, 0.55 + 0.35 * fill))
		draw_line(base, tip, Color(1, 1, 1, 0.8), 1.2, true)
	draw_circle(Vector2(0, 92), 26.0 + 20.0 * fill, Color(0.75, 0.93, 1.0, 0.12 + 0.18 * fill))
	var puff := fmod(_time * 1.4, 1.0)
	draw_circle(Vector2(10.0 + 14.0 * puff, 34.0 - 26.0 * puff), 4.0 + 6.0 * puff, Color(1, 1, 1, 0.5 * (1.0 - puff) * fill))


static func block_texture(stage: int) -> Texture2D:
	return _ice_cell(clampi(stage, 0, 3))


static func shard_texture(index: int) -> Texture2D:
	return _ice_cell(4 + clampi(index, 0, 3))


static func _ice_cell(index: int) -> Texture2D:
	if _cells.has(index):
		return _cells[index]
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/vfx/ice_block.png") as Texture2D
	atlas.region = Rect2((index % 4) * ICE_CELL, (index / 4) * ICE_CELL, ICE_CELL, ICE_CELL)
	_cells[index] = atlas
	return atlas


func _draw_block() -> void:
	var age := _frozen_age
	var pop := 1.0 + 0.28 * exp(-age * 9.0) * cos(age * 22.0) if age < 0.6 else 1.0
	var shiver := Vector2(sin(_time * 70.0) * 1.4, 0.0) if frozen_left > CRACK_TIME else Vector2(sin(_time * 90.0) * 3.0, cos(_time * 77.0) * 1.5)
	var ground := PackedVector2Array()
	for i in 24:
		ground.append(Vector2(0, 92) + Vector2(cos(TAU * i / 24.0) * 58.0 * pop, sin(TAU * i / 24.0) * 15.0 * pop))
	draw_colored_polygon(ground, Color(0.8, 0.95, 1.0, 0.35))
	draw_polyline(ground + PackedVector2Array([ground[0]]), Color(1, 1, 1, 0.75), 2.0, true)

	var progress := 1.0 - clampf(frozen_left / maxf(frozen_total, 0.01), 0.0, 1.0)
	var stage := 0 if progress < 0.4 else (1 if progress < 0.68 else (2 if progress < 0.86 else 3))
	var tex := block_texture(stage)
	var height := BLOCK_HEIGHT * pop
	var width := BLOCK_HEIGHT * 0.92 * (2.0 - pop)
	var rect := Rect2(BODY_CENTER + shiver - Vector2(width, height) * 0.5 + Vector2(0, 4), Vector2(width, height))
	draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.66))
	var glint := 0.5 + 0.5 * sin(_time * 3.0)
	draw_texture_rect(tex, rect.grow(4.0), false, Color(0.6, 0.9, 1.0, 0.12 + 0.1 * glint))

	for i in 6:
		var phase := _time * 2.0 + i * 1.7
		var tw := maxf(sin(phase), 0.0)
		var at := BODY_CENTER + Vector2(cos(i * 2.4) * 30.0, sin(i * 3.1) * 40.0)
		var r := 3.0 + 5.0 * tw
		draw_line(at - Vector2(r, 0), at + Vector2(r, 0), Color(1, 1, 1, tw), 2.0, true)
		draw_line(at - Vector2(0, r), at + Vector2(0, r), Color(1, 1, 1, tw), 2.0, true)
