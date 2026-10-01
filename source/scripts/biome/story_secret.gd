class_name StorySecret
extends StaticBody2D
## Треснувшая плита в боковой стене комнаты: автоприцел бьёт по ней, когда рядом нет врагов.
## Разбитая плита открывает нишу с тайником или пасхалкой (награду выдаёт StoryRun).

signal broken(secret: StorySecret)

const HP := 140.0
const SIZE := Vector2(78.0, 128.0)
const LINE := Color("#1a0f2a")
const STONE := Color("#6d6a7a")
const STONE_LIGHT := Color("#8c8a9c")
const CRACK := Color("#2a2838")
const SEAM := Color("#5ff2ff")
const FLASH_TIME := 0.07

var entry: Dictionary = {}
var side := 1.0
var hp := HP
var _time := 0.0
var _flash := 0.0
var _shake := 0.0
var _shape: CollisionShape2D


func _init() -> void:
	collision_layer = PhysicsLayers.OBSTACLE
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = SIZE
	_shape.shape = box
	add_child(_shape)
	z_index = 1
	_time = randf() * TAU


func is_intact() -> bool:
	return hp > 0.0


func is_targetable() -> bool:
	return hp > 0.0


func take_damage(amount: float, _direction: Vector2 = Vector2.ZERO, _is_crit: bool = false) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = FLASH_TIME
	_shake = 1.0
	if hp <= 0.0:
		collision_layer = 0
		_shape.set_deferred("disabled", true)
		broken.emit(self)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta, 0.0)
	_shake = maxf(_shake - delta * 5.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var half := SIZE * 0.5
	if hp <= 0.0:
		_draw_breach(half)
		return
	var jitter := Vector2(randf_range(-2.5, 2.5), 0.0) * _shake
	draw_set_transform(jitter, 0.0, Vector2.ONE)
	var body := STONE.lerp(Color.WHITE, 0.7) if _flash > 0.0 else STONE
	draw_rect(Rect2(-half, SIZE).grow(3.0), LINE)
	draw_rect(Rect2(-half, SIZE), body)
	draw_rect(Rect2(-half, Vector2(SIZE.x, 18.0)), STONE_LIGHT if _flash <= 0.0 else body)
	var glow := 0.45 + 0.35 * sin(_time * 3.0)
	for line in [[Vector2(-6, -60), Vector2(4, -30), Vector2(-10, -4), Vector2(8, 26), Vector2(-2, 58)],
			[Vector2(4, -30), Vector2(26, -22)], [Vector2(-10, -4), Vector2(-32, 6)], [Vector2(8, 26), Vector2(30, 34)]]:
		var points := PackedVector2Array(line)
		draw_polyline(points, Color(SEAM, glow * 0.45), 7.0, true)
		draw_polyline(points, CRACK, 3.0, true)
	draw_rect(Rect2(-half + Vector2(6, 6), Vector2(10, 10)), Color(CRACK, 0.6))
	draw_rect(Rect2(half - Vector2(16, 16), Vector2(10, 10)), Color(CRACK, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_breach(half: Vector2) -> void:
	var niche := Rect2(-half + Vector2(6, 8), SIZE - Vector2(12, 16))
	draw_rect(niche.grow(5.0), LINE)
	var rows := 8
	for i in rows:
		var t := float(i) / float(rows - 1)
		var color := Color("#2b2233").lerp(Color("#5a4636"), t)
		draw_rect(Rect2(niche.position + Vector2(0, niche.size.y / rows * i), Vector2(niche.size.x, niche.size.y / rows + 1.0)), color)
	var beam := 0.16 + 0.06 * sin(_time * 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-half.x + 8, -half.y + 10), Vector2(half.x - 8, -half.y + 10), Vector2(half.x * 0.6, half.y - 8), Vector2(-half.x * 0.6, half.y - 8)]), Color(SEAM, beam))
	draw_rect(Rect2(-half.x + 6, half.y - 30, SIZE.x - 12, 22), Color(0, 0, 0, 0.28))
	var jag := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, -half.y + 14), Vector2(half.x * 0.5, -half.y + 24), Vector2(half.x * 0.1, -half.y + 12), Vector2(-half.x * 0.35, -half.y + 26), Vector2(-half.x, -half.y + 16)])
	draw_colored_polygon(jag, STONE)
	draw_polyline(PackedVector2Array([jag[6], jag[5], jag[4], jag[3], jag[2]]), LINE, 3.0, true)
	var floor_y := half.y - 12.0
	for p in [Vector2(-24, floor_y), Vector2(-6, floor_y + 3), Vector2(16, floor_y - 1), Vector2(28, floor_y + 2), Vector2(-30, floor_y - 12), Vector2(8, floor_y - 10)]:
		var size := Vector2(14, 9)
		draw_rect(Rect2(p - size * 0.5, size).grow(1.5), LINE)
		draw_rect(Rect2(p - size * 0.5, size), STONE.darkened(0.12 + 0.06 * absf(p.x) / 30.0))
	draw_rect(Rect2(-half + Vector2(2, 0), Vector2(5, SIZE.y)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(half - Vector2(7, half.y * 2.0 - 0.0), Vector2(5, SIZE.y)), Color(0, 0, 0, 0.35))
