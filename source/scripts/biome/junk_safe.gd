class_name JunkSafe
extends Node2D
## Сейф хлама (Выживание 2.0): стоит на карте, открывается за гайки забега; цена растёт с каждым открытым.
## Подойди и постой — Game проверит гайки, откроет сейф и предложит выбор 1 из 3 предметов (редкость тянет Удача).
## Рисунок временный (код); арт Астры — assets/world/junk_safe.png (закрытый) и junk_safe_open.png.

signal open_requested(safe: JunkSafe)

const RADIUS := 85.0
const HOLD := 0.6
const ART := "res://assets/world/junk_safe.png"
const ART_OPEN := "res://assets/world/junk_safe_open.png"

var player: Node2D
var price := 0
var opened := false
var _hold := 0.0
var _cooldown := 0.0
var _time := randf() * 10.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_price(value: int) -> void:
	price = value
	queue_redraw()


func open() -> void:
	opened = true
	set_process(false)
	queue_redraw()


func refuse() -> void:
	_cooldown = 2.0
	_hold = 0.0


func _process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if player == null or not is_instance_valid(player):
		return
	var inside := player.global_position.distance_squared_to(global_position) < RADIUS * RADIUS
	var before := _hold
	_hold = clampf(_hold + (delta if inside and _cooldown <= 0.0 else -delta * 2.0), 0.0, HOLD)
	if _hold >= HOLD:
		_hold = 0.0
		open_requested.emit(self)
	if before != _hold or int(_time * 8.0) != int((_time - delta) * 8.0):
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 40.0, Color(0, 0, 0, 0.35))
	if not opened:
		# Золотое свечение у закрытого сейфа: видно, что тут есть добыча.
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		draw_circle(Vector2.ZERO, 70.0, Color(1.0, 0.82, 0.25, 0.10 + 0.08 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * 1.25)
	var path := ART_OPEN if opened else ART
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		draw_texture(tex, Vector2(-tex.get_width() * 0.5, -tex.get_height() + 4.0))
	else:
		var body := Rect2(-34, -62, 68, 62)
		draw_rect(body.grow(4.0), Color("#120d1c"))
		draw_rect(body, Color("#5b5f7a") if not opened else Color("#3a3d4f"))
		draw_rect(Rect2(-28, -56, 56, 50), Color("#7a7f9e") if not opened else Color("#2a2c38"))
		if opened:
			draw_colored_polygon(PackedVector2Array([Vector2(-34, -62), Vector2(-60, -50), Vector2(-60, 2), Vector2(-34, -6)]), Color("#5b5f7a"))
		else:
			draw_circle(Vector2(0, -32), 12.0, Color("#120d1c"))
			draw_circle(Vector2(0, -32), 9.0, Color("#ffd23f"))
			for i in 4:
				var a := TAU * i / 4.0 + _time
				draw_line(Vector2(0, -32), Vector2(0, -32) + Vector2.from_angle(a) * 8.0, Color("#120d1c"), 2.0)
	draw_set_transform(Vector2.ZERO)
	if opened:
		return
	# Цена и кольцо удержания.
	var text := "%d" % price
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 30.0
	var plate := Rect2(-w * 0.5, -98, w, 28)
	draw_rect(plate.grow(2.0), Color("#120d1c"))
	draw_rect(plate, Color("#2a2140"))
	draw_circle(Vector2(plate.position.x + 14, -84), 8.0, Color("#ffd23f"))
	draw_string_outline(_font, Vector2(plate.position.x + 26, -77), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, Color("#120d1c"))
	draw_string(_font, Vector2(plate.position.x + 26, -77), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#ffd23f"))
	if _hold > 0.0:
		draw_arc(Vector2(0, -32), 46.0, -PI * 0.5, -PI * 0.5 + TAU * _hold / HOLD, 32, Color("#ffd23f"), 6.0)
