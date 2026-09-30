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
		draw_rect(Rect2(-half, SIZE), Color(0.03, 0.02, 0.07, 0.92))
		draw_rect(Rect2(-half, SIZE), Color(SEAM, 0.35), false, 3.0)
		for p in [Vector2(-18, 30), Vector2(14, 38), Vector2(-4, 48), Vector2(22, 12), Vector2(-24, 6)]:
			draw_rect(Rect2(p - Vector2(9, 5), Vector2(18, 10)), STONE.darkened(0.25))
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
