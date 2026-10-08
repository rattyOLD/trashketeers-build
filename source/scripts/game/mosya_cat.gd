class_name MosyaCat
extends Node2D
## Мася, кот Рико, сидит на уровне первой главы. Подойди и тапни по нему: жмурится, мурчит, над ним всплывает «мур».
## Если тыкать слишком быстро, сердится. Кот всегда на месте, просто меняет позу.
## Кадры Астры (6 × 192×256): 0 смотрит, 1 моргает, 2 жмурится, 3 мурчит, 4 шипит, 5 зевает.

const FRAMES := "res://assets/ui/mosya/mosya_frames.png"
const LINES: Array[String] = ["мур", "мррр", "мур-мур", "мрр, ещё", "мяу", "мррр-мяу"]
const FRAME_COUNT := 6
const NEAR := 190.0
const TAP_RADIUS := 100.0
## Плашка «ПОГЛАДИТЬ» над головой (в координатах кота): тап по ней — тоже погладить.
const BUTTON := Rect2(-92, -262, 184, 46)

var player: Player
var fx: FxManager
var _sprite := Sprite2D.new()
var _time := 0.0
var _happy := 0.0
var _angry := 0.0
var _taps: Array[float] = []
var _frames: Array[Texture2D] = []


func _init() -> void:
	z_index = 3


func setup(target: Player, effects: FxManager) -> void:
	player = target
	fx = effects
	var sheet := load(FRAMES) as Texture2D
	for i in FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * 192, 0, 192, 256)
		_frames.append(atlas)
	_sprite.texture = _frames[0]
	_sprite.scale = Vector2(0.5, 0.5)
	_sprite.offset = Vector2(0, -110)
	add_child(_sprite)


func _process(delta: float) -> void:
	_time += delta
	_happy = maxf(_happy - delta, 0.0)
	_angry = maxf(_angry - delta, 0.0)
	var breathe := 1.0 + 0.018 * sin(_time * 2.2)
	_sprite.scale = Vector2(0.5, 0.5 * breathe)
	_sprite.texture = _frames[_pose()]
	queue_redraw()


## Сам по себе кот моргает раз в ~4 с и изредка зевает; когда гладят — жмурится, потом мурчит.
func _pose() -> int:
	if _angry > 0.0:
		return 4
	if _happy > 0.0:
		return 2 if _happy > 0.75 else 3
	var yawn := fmod(_time, 17.0)
	if yawn > 15.6:
		return 5
	return 1 if fmod(_time, 4.3) > 4.12 else 0


func is_near() -> bool:
	return is_instance_valid(player) and not player.is_dead and player.global_position.distance_to(global_position) < NEAR


func _draw() -> void:
	draw_circle(Vector2(0, 2), 38.0, Color(0, 0, 0, 0.25))
	if not is_near():
		return
	var font := ThemeDB.fallback_font
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	draw_style_box(UiStyle.box(Color("#17120e"), Color(Color("#ff8a3d"), 0.6 + 0.4 * pulse), 3, 14), BUTTON)
	draw_string(font, Vector2(-92, -230), "ПОГЛАДИТЬ", HORIZONTAL_ALIGNMENT_CENTER, 184.0, 24, Color("#ffe9cf"))


func _input(event: InputEvent) -> void:
	if not is_near() or get_tree().paused:
		return
	var screen := Vector2.ZERO
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		screen = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not Platform.is_touch():
		screen = (event as InputEventMouseButton).position
	else:
		return
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen
	var local := world - global_position
	if local.distance_to(Vector2(0, -90)) > TAP_RADIUS + 20.0 and not BUTTON.grow(24.0).has_point(local):
		return
	get_viewport().set_input_as_handled()
	_pet()


func _pet() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_taps.append(now)
	while not _taps.is_empty() and now - _taps[0] > 3.0:
		_taps.pop_front()
	SaveService.add_stat("mosya_pets", 1, false)
	if _taps.size() >= 7:
		_angry = 1.6
		_taps.clear()
		fx.popup(global_position + Vector2(0, -250), "ФШШ!", Color("#ff6b6b"), 40.0)
		return
	_happy = 1.0
	var total := SaveService.get_stat("mosya_pets")
	fx.popup(global_position + Vector2(0, -250), LINES[total % LINES.size()], Color("#ffd27a"), 38.0)
