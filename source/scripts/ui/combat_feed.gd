class_name CombatFeed
extends Control
## Боевой импакт поверх арены (как в шутерах уровня CoD): счётчик очков у прицела со стопкой строк
## «+10 УБИЙСТВО» и растущей суммой серии, медали серий по центру сверху с ударным появлением,
## красные дуги урона у края экрана со стороны удара и пульсирующая красная виньетка на низком здоровье.
## Один Control рисует всё сам и обрабатывается, только пока есть что показывать.

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const LINE_LIFE := 1.5
const MAX_LINES := 4
const TOTAL_HOLD := 2.2
const MEDAL_LIFE := 1.5
const DAMAGE_LIFE := 0.9
const GOLD := Color("#ffd257")
const HOT := Color("#ff3b30")
const OUTLINE := Color(0.03, 0.02, 0.04, 0.9)

var low_hp := 0.0

var _font: Font
var _lines: Array[Dictionary] = []
var _total := 0
var _total_life := 0.0
var _total_pop := 0.0
var _medal := ""
var _medal_color := GOLD
var _medal_life := 0.0
var _hits: Array[Dictionary] = []
var _time := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_font = load(FONT_PATH) as Font
	set_process(false)


## Убийство: строка в стопку и прибавка к сумме серии.
func kill(points: int, label: String, color: Color = Color.WHITE) -> void:
	_lines.push_front({"text": "+%d %s" % [points, label], "color": color, "life": LINE_LIFE})
	while _lines.size() > MAX_LINES:
		_lines.pop_back()
	_total += points
	_total_life = TOTAL_HOLD
	_total_pop = 1.0
	_wake()


## Медаль серии: крупная надпись, влетает с перебором масштаба и гаснет.
signal medaled


func medal(text: String, heat: float) -> void:
	medaled.emit()
	_medal = text
	_medal_color = GOLD.lerp(HOT, clampf(heat, 0.0, 1.0))
	_medal_life = MEDAL_LIFE
	_wake()


## Урон по герою: direction — откуда прилетело (из героя к источнику).
func damage_from(direction: Vector2) -> void:
	if direction.length_squared() < 0.01:
		return
	_hits.append({"angle": direction.angle(), "life": DAMAGE_LIFE})
	while _hits.size() > 4:
		_hits.pop_front()
	_wake()


func set_low_hp(amount: float) -> void:
	low_hp = clampf(amount, 0.0, 1.0)
	if low_hp > 0.0:
		_wake()


func _wake() -> void:
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for line in _lines:
		line["life"] = float(line["life"]) - delta
	while not _lines.is_empty() and float(_lines.back()["life"]) <= 0.0:
		_lines.pop_back()
	_total_life = maxf(_total_life - delta, 0.0)
	if _total_life <= 0.0:
		_total = 0
	_total_pop = maxf(_total_pop - delta * 5.0, 0.0)
	_medal_life = maxf(_medal_life - delta, 0.0)
	for hit in _hits:
		hit["life"] = float(hit["life"]) - delta
	while not _hits.is_empty() and float(_hits.front()["life"]) <= 0.0:
		_hits.pop_front()
	queue_redraw()
	if _lines.is_empty() and _total_life <= 0.0 and _medal_life <= 0.0 and _hits.is_empty() and low_hp <= 0.0:
		set_process(false)


func _draw() -> void:
	if _font == null:
		return
	if low_hp > 0.0:
		_draw_low_hp()
	for hit in _hits:
		_draw_hit(float(hit["angle"]), float(hit["life"]) / DAMAGE_LIFE)
	_draw_ticker()
	if _medal_life > 0.0:
		_draw_medal()


func _text(at: Vector2, text: String, font_size: int, color: Color, align: HorizontalAlignment) -> void:
	var width := 600.0
	var x := at.x - (width if align == HORIZONTAL_ALIGNMENT_RIGHT else (width * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0))
	var p := Vector2(x, at.y)
	draw_string_outline(_font, p, text, align, width, font_size, maxi(int(font_size * 0.3), 4), Color(OUTLINE, OUTLINE.a * color.a))
	draw_string(_font, p, text, align, width, font_size, color)


## Сумма серии и строки под ней — справа от центра, рядом с тем местом, куда смотрит игрок.
func _draw_ticker() -> void:
	var anchor := Vector2(size.x * 0.5 + 150.0, size.y * 0.36)
	if _total > 0 and _total_life > 0.0:
		var fade := clampf(_total_life / 0.5, 0.0, 1.0)
		var font_size := int(34.0 * (1.0 + 0.35 * _total_pop))
		_text(anchor, "+%d" % _total, font_size, Color(GOLD.lerp(Color.WHITE, _total_pop * 0.6), fade), HORIZONTAL_ALIGNMENT_LEFT)
	var y := anchor.y + 30.0
	for i in _lines.size():
		var line: Dictionary = _lines[i]
		var life := float(line["life"])
		var alpha := clampf(life / 0.4, 0.0, 1.0) * (1.0 - 0.18 * i)
		var slide := clampf((LINE_LIFE - life) / 0.12, 0.0, 1.0)
		var color: Color = line["color"]
		_text(Vector2(anchor.x + 24.0 * (1.0 - slide), y), str(line["text"]), 19, Color(color, alpha), HORIZONTAL_ALIGNMENT_LEFT)
		y += 24.0


## Медаль: влетает крупно (×1.7 → ×1.0 за 0.18 с), под ней две полосы-«шевроны».
func _draw_medal() -> void:
	var age := MEDAL_LIFE - _medal_life
	var punch := 1.0 + 0.7 * pow(1.0 - clampf(age / 0.18, 0.0, 1.0), 2.0)
	var alpha := clampf(_medal_life / 0.35, 0.0, 1.0) * clampf(age / 0.06, 0.0, 1.0)
	var center := Vector2(size.x * 0.5, size.y * 0.66)
	var font_size := int(44.0 * punch)
	_text(center + Vector2(0.0, font_size * 0.35), _medal, font_size, Color(_medal_color, alpha), HORIZONTAL_ALIGNMENT_CENTER)
	var half := 120.0 * punch
	var y := center.y + font_size * 0.55
	draw_line(center + Vector2(-half, y - center.y), center + Vector2(-26.0, y - center.y), Color(_medal_color, alpha * 0.8), 3.0, true)
	draw_line(center + Vector2(26.0, y - center.y), center + Vector2(half, y - center.y), Color(_medal_color, alpha * 0.8), 3.0, true)


## Красная дуга у края в сторону удара.
func _draw_hit(angle: float, fade: float) -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	var spread := 0.38
	var color := Color(HOT, 0.85 * fade)
	draw_arc(center, radius, angle - spread, angle + spread, 18, color, 10.0 * (0.6 + 0.4 * fade), true)
	draw_arc(center, radius - 9.0, angle - spread * 0.6, angle + spread * 0.6, 12, Color(1.0, 0.6, 0.5, 0.5 * fade), 3.0, true)


## Низкое здоровье: красные края экрана бьются как сердце (два удара на цикл).
func _draw_low_hp() -> void:
	var cycle := fmod(_time, 1.05)
	var beat := maxf(exp(-pow((cycle - 0.08) / 0.07, 2.0)), 0.7 * exp(-pow((cycle - 0.32) / 0.07, 2.0)))
	var alpha := low_hp * (0.28 + 0.32 * beat)
	var edge := Color(0.85, 0.02, 0.05, alpha)
	var clear := Color(0.85, 0.02, 0.05, 0.0)
	var w := size.x
	var h := size.y
	var depth := minf(w, h) * (0.16 + 0.04 * beat)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - depth, depth), Vector2(depth, depth)]), PackedColorArray([edge, edge, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, h), Vector2(depth, h - depth), Vector2(w - depth, h - depth), Vector2(w, h)]), PackedColorArray([edge, clear, clear, edge]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(depth, depth), Vector2(depth, h - depth), Vector2(0, h)]), PackedColorArray([edge, clear, clear, edge]))
	draw_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w, h), Vector2(w - depth, h - depth), Vector2(w - depth, depth)]), PackedColorArray([edge, edge, clear, clear]))
