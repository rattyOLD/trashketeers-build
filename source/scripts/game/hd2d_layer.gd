class_name HD2DLayer
extends CanvasLayer
## Слой между миром и цветокоррекцией (её размытие краёв и дымка ложатся и на него):
##   лучи света сквозь дымку — наискосок сверху слева, как в Octopath;
##   передний план — крупные тёмные силуэты ближе к камере, плывут быстрее мира и становятся
##   прозрачными у середины экрана, где идёт бой.

const LAYER := 1
## Передний план движется быстрее мира: так он ощущается ближе к камере.
const PARALLAX := 1.35
const FOREGROUND_SCALE := 1.3
const FOREGROUND_STEP := 760.0
const FOREGROUND_JITTER := 260.0
## Силуэты стоят и за краем карты: у края камеры они въезжают в кадр с параллаксом.
const FOREGROUND_MARGIN := 700.0
const FOREGROUND_TINT := Color(0.16, 0.13, 0.2)
const FOREGROUND_ALPHA := 0.8
## Прозрачность силуэта в центре экрана — не закрывает врагов и героя.
const FOREGROUND_CENTER_ALPHA := 0.1
const FOREGROUND := {
	"junkyard": ["res://assets/props/ch1/spruce.png", "res://assets/props/ch1/floodlight.png"],
	"bank": ["res://assets/props/ch2/lamp_banner.png", "res://assets/props/ch2/column.png"],
}

var shafts: LightShafts
var foreground: Foreground


func _init() -> void:
	layer = LAYER
	shafts = LightShafts.new()
	shafts.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shafts)
	foreground = Foreground.new()
	add_child(foreground)


## Лучи света: дрейфующие полосы с мягкими краями, складываются со сценой (ADD).
class LightShafts:
	extends Control

	const COUNT := 5
	var strength := 0.0
	var color := Color(1.0, 0.92, 0.75)
	var _time := 0.0
	var _seeds := PackedFloat32Array()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		_seeds.resize(COUNT)
		for i in COUNT:
			_seeds[i] = randf()

	func _process(delta: float) -> void:
		_time += delta
		visible = strength > 0.001
		if visible:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Свет сверху слева: полосы уходят вниз вправо и гаснут к середине кадра.
		var slant := Vector2(0.55, 1.0).normalized()
		var across := Vector2(slant.y, -slant.x)
		var length := h * 0.95
		for i in COUNT:
			var s := _seeds[i]
			var drift := sin(_time * 0.11 + s * TAU) * w * 0.04
			var top := Vector2(w * (-0.15 + 0.3 * i + 0.12 * s) + drift, -h * 0.08)
			var width := w * (0.05 + 0.07 * fposmod(s * 7.3, 1.0))
			var breathe := 0.65 + 0.35 * sin(_time * (0.35 + 0.2 * s) + s * 9.0)
			var a := strength * breathe
			var edge := Color(color, 0.0)
			var core := Color(color, a)
			var fade := Color(color, 0.0)
			var a_end := top + slant * length
			# Каждая полоса — три полосы-ленты: мягкий край, ядро, мягкий край.
			var l0 := top - across * width
			var l1 := top - across * width * 0.35
			var r1 := top + across * width * 0.35
			var r0 := top + across * width
			var e := a_end - top
			draw_polygon(PackedVector2Array([l0, l1, l1 + e, l0 + e]), PackedColorArray([edge, core, fade, fade]))
			draw_polygon(PackedVector2Array([l1, r1, r1 + e, l1 + e]), PackedColorArray([core, core, fade, fade]))
			draw_polygon(PackedVector2Array([r1, r0, r0 + e, r1 + e]), PackedColorArray([core, edge, fade, fade]))


## Силуэты переднего плана по сетке карты; рисуются только видимые.
class Foreground:
	extends Node2D

	var _textures: Array[Texture2D] = []
	var _points := PackedVector2Array()
	var _kinds := PackedInt32Array()
	var _flips := PackedByteArray()

	func setup(layout: String, bounds: Rect2) -> void:
		_textures.clear()
		_points.clear()
		_kinds.clear()
		_flips.clear()
		for path: String in FOREGROUND.get(layout, []):
			if ResourceLoader.exists(path):
				_textures.append(load(path) as Texture2D)
		if _textures.is_empty() or not bounds.has_area():
			queue_redraw()
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(layout) ^ int(bounds.size.x)
		var area := bounds.grow(FOREGROUND_MARGIN)
		var y := area.position.y
		while y < area.end.y:
			var x := area.position.x
			while x < area.end.x:
				_points.append(Vector2(x, y) + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * FOREGROUND_JITTER)
				_kinds.append(rng.randi() % _textures.size())
				_flips.append(rng.randi() % 2)
				x += FOREGROUND_STEP
			y += FOREGROUND_STEP
		queue_redraw()

	func _process(_delta: float) -> void:
		if not _points.is_empty():
			queue_redraw()

	func _draw() -> void:
		if _points.is_empty():
			return
		var view := get_viewport().get_visible_rect().size
		var canvas := get_viewport().get_canvas_transform()
		var zoom := canvas.get_scale().x
		var center := view * 0.5
		var scale := zoom * PARALLAX * FOREGROUND_SCALE
		for i in _points.size():
			var at := center + (canvas * _points[i] - center) * PARALLAX
			var texture := _textures[_kinds[i]]
			var size := texture.get_size() * scale
			var rect := Rect2(at - Vector2(size.x * 0.5, size.y), size)
			if not rect.intersects(Rect2(Vector2.ZERO, view)):
				continue
			# Чем ближе силуэт к середине кадра по высоте, тем он прозрачнее (там бой).
			var middle := clampf(1.0 - absf(rect.get_center().y - center.y) / (view.y * 0.5), 0.0, 1.0)
			var alpha := lerpf(FOREGROUND_ALPHA, FOREGROUND_CENTER_ALPHA, smoothstep(0.0, 0.6, middle))
			if _flips[i] == 1:
				rect = Rect2(rect.position + Vector2(rect.size.x, 0.0), Vector2(-rect.size.x, rect.size.y))
			draw_texture_rect(texture, rect, false, Color(FOREGROUND_TINT, alpha))
