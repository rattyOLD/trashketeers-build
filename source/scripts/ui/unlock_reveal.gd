class_name UnlockReveal
extends Control
## Полноэкранный показ нового героя или оружия: белая вспышка, вращающиеся лучи, вылет арта, имя и реплика.

signal finished

const SPARKS := 26

var _accent := Color.WHITE
var _time := 0.0
var _rays: Control
var _flash: ColorRect
var _dismiss_ready := false
var _power := 1
var _spark_seed: Array[Vector3] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 50


## art - уже готовый Control с героем или иконкой оружия; кикер - «НОВЫЙ ГЕРОЙ!».
## power 1..3 (редкий/эпический/легендарный): больше лучей, искр, ударных волн и тряски.
func play(kicker: String, title: String, sub: String, quote: String, accent: Color, art: Control, power: int = 1) -> void:
	for child in get_children():
		child.queue_free()
	_accent = accent
	_power = clampi(power, 1, 3)
	_spark_seed.clear()
	for i in SPARKS * _power:
		_spark_seed.append(Vector3(randf(), randf(), randf()))
	_time = 0.0
	_dismiss_ready = false
	visible = true

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.06, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_rays = Control.new()
	_rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays.draw.connect(_draw_rays)
	add_child(_rays)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var head := UiStyle.label(kicker, 62, UiStyle.GOLD, 14)
	column.add_child(head)
	art.custom_minimum_size = Vector2(0, 420)
	art.size_flags_horizontal = Control.SIZE_FILL
	column.add_child(art)
	var name_label := UiStyle.label(title, 48, accent.lightened(0.35), 12)
	column.add_child(name_label)
	column.add_child(UiStyle.label(sub, 26, UiStyle.TEXT, 6))
	var words := UiStyle.label("«%s»" % quote, 26, Color("#ffe2b8"), 5)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(560, 0)
	words.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(words)
	var hint := UiStyle.label("ТАПНИ, ЧТОБЫ ПРОДОЛЖИТЬ", 22, UiStyle.TEXT_DIM, 5)
	column.add_child(hint)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 1)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	head.pivot_offset = head.size * 0.5
	for node in [head, art, name_label]:
		(node as Control).modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.6)
	tween.parallel().tween_property(art, "modulate:a", 1.0, 0.35).set_delay(0.1)
	tween.parallel().tween_property(head, "modulate:a", 1.0, 0.3).set_delay(0.25)
	tween.parallel().tween_property(name_label, "modulate:a", 1.0, 0.3).set_delay(0.45)
	tween.tween_callback(func() -> void: _dismiss_ready = true)
	art.pivot_offset = Vector2(art.size.x * 0.5, art.size.y * 0.5)
	art.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(art, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	UiStyle.pop_in(head)
	SoundManager.play(&"achievement", 0.0, false)
	SoundManager.play(&"star_dust")
	if _power >= 2:
		SoundManager.play(&"level_up", 0.0, false)
		var shake := create_tween()
		for i in 8:
			shake.tween_property(column, "position", Vector2(randf_range(-10, 10), randf_range(-8, 8)) * (_power - 1), 0.04)
		shake.tween_property(column, "position", Vector2.ZERO, 0.06)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _rays != null:
		_rays.queue_redraw()


func _draw_rays() -> void:
	var center := _rays.size * Vector2(0.5, 0.42)
	var reach := maxf(_rays.size.x, _rays.size.y)
	var grow := clampf(_time * 2.4, 0.0, 1.0)
	var count := 10 + 4 * _power
	for i in count:
		var a := TAU * i / count + _time * (0.18 + 0.08 * _power)
		var half := 0.07 + 0.02 * _power
		var pts := PackedVector2Array([center, center + Vector2.from_angle(a - half) * reach * grow, center + Vector2.from_angle(a + half) * reach * grow])
		var alpha := (0.10 + 0.05 * _power) if i % 2 == 0 else 0.05
		_rays.draw_colored_polygon(pts, Color(_accent.r, _accent.g, _accent.b, alpha))
	for layer in 6:
		var radius := 250.0 - layer * 36.0
		draw_glow(center + Vector2(0, 40), radius * (0.9 + 0.06 * sin(_time * 3.0)), Color(_accent.r, _accent.g, _accent.b, 0.05 + 0.02 * _power))
	for wave in _power:
		var t := fmod(_time * 0.9 - wave * 0.28, 1.4)
		if t > 0.0 and _time > wave * 0.28:
			var fade := 1.0 - t / 1.4
			_rays.draw_arc(center + Vector2(0, 40), 60.0 + t * reach * 0.55, 0.0, TAU, 64, Color(_accent.lightened(0.4), fade * 0.7), 8.0 * fade + 1.0, true)
	for i in _spark_seed.size():
		var sp := _spark_seed[i]
		var life := fmod(_time * (0.25 + sp.z * 0.35) + sp.x, 1.0)
		var x := _rays.size.x * sp.y + sin(_time * 2.0 + sp.x * 9.0) * 14.0
		var y := _rays.size.y * (1.05 - life * 1.1)
		var r := (2.0 + sp.z * 4.0) * sin(life * PI)
		_rays.draw_circle(Vector2(x, y), r, Color(_accent.lightened(0.5), 0.9 * sin(life * PI)))
		if _power >= 3 and i % 3 == 0:
			_rays.draw_line(Vector2(x - r * 2.0, y), Vector2(x + r * 2.0, y), Color(1, 1, 1, 0.7 * sin(life * PI)), 1.5)
			_rays.draw_line(Vector2(x, y - r * 2.0), Vector2(x, y + r * 2.0), Color(1, 1, 1, 0.7 * sin(life * PI)), 1.5)


func draw_glow(at: Vector2, radius: float, color: Color) -> void:
	_rays.draw_circle(at, radius, color)


func _input(event: InputEvent) -> void:
	if not visible or not _dismiss_ready:
		return
	var tapped := UiStyle.is_tap(event)
	if tapped:
		get_viewport().set_input_as_handled()
		visible = false
		finished.emit()
