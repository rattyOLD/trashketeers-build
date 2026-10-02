class_name TrainingTarget
extends StaticBody2D
## Мишень-ящик на старте сюжета: учит стрелять в зону зажатого пальца. Ломается с первых попаданий.

signal broken(target: TrainingTarget)

const HP := 45.0
const SIZE := Vector2(86.0, 86.0)
const LINE := Color("#0b1a26")
const WOOD := Color("#9a6a3a")
const WOOD_LIGHT := Color("#c48c52")
const RED := Color("#ff3b5c")

var hp := HP
var _time := 0.0
var _flash := 0.0
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


func is_intact() -> bool:
	return hp > 0.0


func is_targetable() -> bool:
	return hp > 0.0


func take_damage(amount: float, _direction: Vector2 = Vector2.ZERO, _is_crit: bool = false) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.07
	if hp <= 0.0:
		collision_layer = 0
		_shape.set_deferred("disabled", true)
		broken.emit(self)
		queue_free()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var half := SIZE * 0.5
	var body := WOOD.lerp(Color.WHITE, 0.6) if _flash > 0.0 else WOOD
	draw_rect(Rect2(-half, SIZE).grow(3.0), LINE)
	draw_rect(Rect2(-half, SIZE), body)
	draw_rect(Rect2(-half, Vector2(SIZE.x, 14.0)), WOOD_LIGHT)
	draw_line(-half, half, LINE, 4.0)
	draw_line(Vector2(half.x, -half.y), Vector2(-half.x, half.y), LINE, 4.0)
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for r in [30.0, 20.0, 10.0]:
		draw_circle(Vector2.ZERO, r, RED if int(r) % 20 == 10 else Color.WHITE)
	draw_arc(Vector2.ZERO, 38.0 + pulse * 6.0, 0.0, TAU, 28, Color(RED, 0.8 - pulse * 0.5), 3.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(-half.x, -half.y - 12.0), "ЦЕЛЬ", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 22, Color("#ffd257"))
