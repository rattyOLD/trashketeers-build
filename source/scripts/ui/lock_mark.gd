class_name LockMark
extends Control
## Замок по центру кнопки режима и цепи по обе стороны. play_open() — «взлом»: замок трескается и падает,
## цепи рвутся и уходят в стороны.

signal opened

const BREAK_TIME := 1.1
const LINK_STEP := 13.0
const INK := Color("#1a0033")
const STEEL := Color("#c3bfd8")
const GOLD := Color("#ffd257")

var _t := -1.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_process(false)


func play_open() -> void:
	_t = 0.0
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= BREAK_TIME:
		_t = -1.0
		visible = false
		set_process(false)
		opened.emit()


func _draw() -> void:
	var mid := Vector2(size.x * 0.5, size.y * 0.5)
	var p := 0.0 if _t < 0.0 else clampf(_t / BREAK_TIME, 0.0, 1.0)
	var alpha := 1.0 - maxf(p - 0.55, 0.0) / 0.45
	var shake := Vector2(sin(p * 90.0) * 3.0 * (1.0 - p), 0.0) if p > 0.0 and p < 0.4 else Vector2.ZERO
	var spread := maxf(p - 0.35, 0.0) * 140.0
	var fall := maxf(p - 0.35, 0.0) * maxf(p - 0.35, 0.0) * 260.0
	for side in [-1.0, 1.0]:
		var x := 26.0
		var i := 0
		while x < size.x * 0.5 - 6.0:
			var pos := mid + Vector2(side * x + side * spread, 0.0)
			pos.y += fall * (0.6 + 0.4 * float(i % 2)) * (1.0 if side > 0.0 else 0.8)
			_link(pos, i % 2 == 0, alpha)
			x += LINK_STEP
			i += 1
	var c := mid + shake + Vector2(0.0, fall * 0.9)
	var wob := 0.0 if p < 0.35 else (p - 0.35) * 2.2
	draw_set_transform(c, wob, Vector2.ONE)
	draw_arc(Vector2(0, -9), 9.0, PI, TAU, 14, Color(INK, alpha), 8.0, true)
	draw_arc(Vector2(0, -9), 9.0, PI, TAU, 14, Color(STEEL, alpha), 4.0, true)
	var body := Rect2(-14, -9, 28, 22)
	draw_rect(body.grow(3.0), Color(INK, alpha))
	draw_rect(body, Color(GOLD, alpha))
	draw_rect(Rect2(body.position, Vector2(body.size.x, 5.0)), Color(1, 1, 1, 0.3 * alpha))
	draw_circle(Vector2(0, 1), 3.5, Color(INK, alpha))
	draw_line(Vector2(0, 1), Vector2(0, 8), Color(INK, alpha), 3.5)
	if p > 0.3:
		draw_polyline(PackedVector2Array([Vector2(-2, -9), Vector2(2, -3), Vector2(-3, 2), Vector2(1, 13)]), Color(INK, alpha), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _link(at: Vector2, flat: bool, alpha: float) -> void:
	var w := 11.0 if flat else 6.0
	var h := 6.0 if flat else 9.0
	var rect := Rect2(at - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(rect.grow(1.5), Color(INK, alpha * 0.9))
	draw_rect(rect, Color(STEEL, alpha * 0.9))
	draw_rect(rect.grow(-2.0), Color(0.09, 0.05, 0.16, alpha * 0.8))
