class_name AtmosphereFX
extends Node
## Атмосфера боя: у каждой волны своё настроение (ТЗ: «арена не должна ощущаться одинаковой»).
##   CanvasModulate — цветокоррекция мира (HUD на своём CanvasLayer её не получает);
##   слой погоды в экранных координатах — дождь, пылинки, споры, угли, туман, молнии;
##   виньетка — дешёвый шейдер на полноэкранном ColorRect;
##   леттербокс — чёрные полосы для кинематографичных заставок волн;
##   цветокоррекция (shaders/color_grade.gdshader) — отдельный CanvasLayer под погодой и HUD:
##   сплит-тонирование, контраст, зерно, аберрация при уроне (выключается в настройках).
## Всё рисуется примитивами из Packed-массивов: никаких нод на частицу.

const MOODS := {
	"clear": {"tint": Color("#d6dbf2"), "rain": 0.0, "motes": 1.0, "fog": Color(0.5, 0.4, 1.0, 0.0), "vignette": 0.42, "lightning": false, "pulse": false, "motes_color": Color(0.8, 0.9, 1.0), "rise": false},
	"pink_haze": {"tint": Color("#e8cfe0"), "rain": 0.35, "motes": 0.6, "fog": Color(1.0, 0.3, 0.7, 0.10), "vignette": 0.48, "lightning": false, "pulse": false, "motes_color": Color(1.0, 0.6, 0.85), "rise": false},
	"toxic": {"tint": Color("#cde6c6"), "rain": 0.0, "motes": 1.4, "fog": Color(0.4, 1.0, 0.3, 0.12), "vignette": 0.5, "lightning": false, "pulse": false, "motes_color": Color(0.55, 1.0, 0.35), "rise": true},
	"storm": {"tint": Color("#aeb9e6"), "rain": 1.0, "motes": 0.2, "fog": Color(0.3, 0.4, 0.9, 0.10), "vignette": 0.58, "lightning": true, "pulse": false, "motes_color": Color(0.7, 0.8, 1.0), "rise": false},
	"night": {"tint": Color("#5b6796"), "rain": 0.0, "motes": 0.5, "fog": Color(0.3, 0.4, 0.8, 0.06), "vignette": 0.68, "lightning": false, "pulse": false, "motes_color": Color(0.6, 0.75, 1.0), "rise": false},
	"alarm": {"tint": Color("#e8bdb7"), "rain": 0.0, "motes": 1.2, "fog": Color(1.0, 0.15, 0.1, 0.10), "vignette": 0.6, "lightning": false, "pulse": true, "motes_color": Color(1.0, 0.55, 0.2), "rise": true},
	"sunny": {"tint": Color("#fbf1dc"), "rain": 0.0, "motes": 0.5, "fog": Color(1.0, 0.9, 0.6, 0.0), "vignette": 0.3, "lightning": false, "pulse": false, "motes_color": Color(1.0, 0.95, 0.7), "rise": false},
	"golden": {"tint": Color("#f6e2bd"), "rain": 0.0, "motes": 1.0, "fog": Color(1.0, 0.8, 0.3, 0.06), "vignette": 0.38, "lightning": false, "pulse": false, "motes_color": Color(1.0, 0.85, 0.35), "rise": true},
	"party": {"tint": Color("#f3dcec"), "rain": 0.0, "motes": 1.3, "fog": Color(1.0, 0.4, 0.8, 0.06), "vignette": 0.4, "lightning": false, "pulse": false, "motes_color": Color(1.0, 0.55, 0.85), "rise": false},
	"vault": {"tint": Color("#e0cca8"), "rain": 0.0, "motes": 1.0, "fog": Color(0.9, 0.55, 0.15, 0.08), "vignette": 0.55, "lightning": false, "pulse": true, "motes_color": Color(1.0, 0.8, 0.3), "rise": true},
}
const RAIN_COUNT := 150
const MOTE_COUNT := 60
const FOG_BLOBS := 7
const DEBRIS_COUNT := 7
const LETTERBOX := 92.0

var _modulate: CanvasModulate
var _grade: ColorRect
var _aberration := 0.0
var _weather_layer: CanvasLayer
var _weather: WeatherDraw
var _vignette: ColorRect
var _flash: ColorRect
var _fade: ColorRect
var _fade_tween: Tween
var _bars: Array[ColorRect] = []
var _mood: Dictionary = MOODS["clear"]
var _mood_name := "clear"
var _base_tint := Color.WHITE
var _time := 0.0
var _lightning_timer := 6.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func build(parent: Node) -> void:
	_modulate = CanvasModulate.new()
	_modulate.color = MOODS["clear"]["tint"]
	parent.add_child(_modulate)

	if SaveService.is_grade_enabled():
		var grade_layer := CanvasLayer.new()
		grade_layer.layer = 2
		parent.add_child(grade_layer)
		_grade = ColorRect.new()
		_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var grade_material := ShaderMaterial.new()
		grade_material.shader = load("res://shaders/color_grade.gdshader")
		_grade.material = grade_material
		grade_layer.add_child(_grade)

	_weather_layer = CanvasLayer.new()
	_weather_layer.layer = 3
	parent.add_child(_weather_layer)

	_weather = WeatherDraw.new()
	_weather.density = 1.0 if SaveService.get_quality() >= 1 else 0.3
	_weather.set_anchors_preset(Control.PRESET_FULL_RECT)
	_weather_layer.add_child(_weather)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vignette.gdshader")
	_vignette.material = material
	_weather_layer.add_child(_vignette)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_flash.visible = false
	_weather_layer.add_child(_flash)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0.02, 0.0, 0.05, 0.0)
	_fade.visible = false
	_weather_layer.add_child(_fade)

	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.offset_top = -LETTERBOX
			bar.offset_bottom = 0.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = 0.0
			bar.offset_bottom = LETTERBOX
		_weather_layer.add_child(bar)
		_bars.append(bar)
	set_mood("clear", false)


func set_mood(mood_name: String, animate: bool = true) -> void:
	_mood_name = mood_name if MOODS.has(mood_name) else "clear"
	_mood = MOODS[_mood_name]
	_base_tint = _mood["tint"]
	_weather.configure(_mood)
	var material := _vignette.material as ShaderMaterial
	var strength: float = _mood["vignette"]
	if animate:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_modulate, "color", _base_tint, 1.6)
		tween.tween_method(func(v: float) -> void: material.set_shader_parameter(&"strength", v), float(material.get_shader_parameter(&"strength")), strength, 1.6)
	else:
		_modulate.color = _base_tint
		material.set_shader_parameter(&"strength", strength)
	material.set_shader_parameter(&"tint", Color(0.55, 0.0, 0.05) if _mood["pulse"] else Color(0.02, 0.0, 0.06))


## Сплит-тонирование главы: тени и света в свой оттенок (без цветокоррекции — просто no-op).
func set_grade(shadow_tint: Vector3, highlight_tint: Vector3) -> void:
	if _grade == null:
		return
	var material := _grade.material as ShaderMaterial
	material.set_shader_parameter(&"shadow_tint", shadow_tint)
	material.set_shader_parameter(&"highlight_tint", highlight_tint)


## Затемнение всего мира (переход через портал). Работает и на паузе дерева.
func fade(alpha: float, duration: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade.visible = true
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade, "color:a", alpha, duration)
	if alpha <= 0.0:
		_fade_tween.tween_callback(func() -> void: _fade.visible = false)


## Кинематографичные полосы сверху и снизу на время заставки волны.
func letterbox(show: bool) -> void:
	for i in _bars.size():
		var bar := _bars[i]
		var tween := create_tween()
		var target := LETTERBOX if show else 0.0
		if i == 0:
			tween.tween_property(bar, "offset_bottom", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(bar, "offset_top", target - LETTERBOX, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(bar, "offset_top", -target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(bar, "offset_bottom", LETTERBOX - target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Удар по игроку: короткая хроматическая аберрация по краям экрана.
func hit_pulse(strength: float = 1.0) -> void:
	_aberration = maxf(_aberration, strength)


## Вспышка экрана (левел-ап, молния, взрыв босса).
func flash(color: Color, strength: float, duration: float) -> void:
	_flash.color = Color(color, strength)
	_flash.visible = true
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, duration)
	tween.tween_callback(func() -> void: _flash.visible = _flash.color.a > 0.01)


func _process(delta: float) -> void:
	if _grade != null and _aberration > 0.0:
		_aberration = maxf(_aberration - delta * 3.0, 0.0)
		(_grade.material as ShaderMaterial).set_shader_parameter(&"aberration", _aberration)
	_time += delta
	if _mood["pulse"]:
		_modulate.color = _base_tint.lerp(Color("#ff9a8a"), 0.25 * (0.5 + 0.5 * sin(_time * 3.2)))
	if _mood["lightning"]:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(4.0, 9.0)
			flash(Color(0.85, 0.9, 1.0), 0.55, 0.35)
			SoundManager.play(&"comet_impact", -8.0)


## Погода в экранных координатах: дождь, пылинки/споры/угли и дрейфующие пятна тумана.
class WeatherDraw:
	extends Control

	var _rain_pos := PackedVector2Array()
	var _rain_len := PackedFloat32Array()
	var _mote_pos := PackedVector2Array()
	var _mote_phase := PackedFloat32Array()
	var _fog_pos := PackedVector2Array()
	var _fog_radius := PackedFloat32Array()
	var _debris_pos := PackedVector2Array()
	var _debris_spin := PackedFloat32Array()
	var density := 1.0
	var _rain := 0.0
	var _motes := 1.0
	var _fog := Color(0, 0, 0, 0)
	var _mote_color := Color.WHITE
	var _rise := false
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rain_pos.resize(RAIN_COUNT)
		_rain_len.resize(RAIN_COUNT)
		_mote_pos.resize(MOTE_COUNT)
		_mote_phase.resize(MOTE_COUNT)
		_fog_pos.resize(FOG_BLOBS)
		_fog_radius.resize(FOG_BLOBS)
		for i in RAIN_COUNT:
			_rain_pos[i] = Vector2(randf() * 900.0, randf() * 1500.0)
			_rain_len[i] = randf_range(18.0, 34.0)
		for i in MOTE_COUNT:
			_mote_pos[i] = Vector2(randf() * 900.0, randf() * 1500.0)
			_mote_phase[i] = randf() * TAU
		for i in FOG_BLOBS:
			_fog_pos[i] = Vector2(randf() * 900.0, randf() * 1500.0)
			_fog_radius[i] = randf_range(220.0, 380.0)
		_debris_pos.resize(DEBRIS_COUNT)
		_debris_spin.resize(DEBRIS_COUNT)
		for i in DEBRIS_COUNT:
			_debris_pos[i] = Vector2(randf() * 900.0, randf() * 1500.0)
			_debris_spin[i] = randf() * TAU

	func configure(mood: Dictionary) -> void:
		_rain = float(mood["rain"]) * density
		_motes = float(mood["motes"]) * density
		_fog = Color(0, 0, 0, 0)
		_mote_color = mood["motes_color"]
		_rise = mood["rise"]

	func _process(delta: float) -> void:
		_time += delta
		var w := maxf(size.x, 1.0)
		var h := maxf(size.y, 1.0)
		var fall := Vector2(-160.0, 1250.0) * delta
		for i in int(RAIN_COUNT * _rain):
			var p := _rain_pos[i] + fall
			if p.y > h + 40.0:
				# Перенос наверх с сохранением разброса: после подвисания кадра капли не собираются в одну «стену».
				p = Vector2(randf() * (w + 200.0), fposmod(p.y + 40.0, h + 80.0) - 40.0)
			if p.x < -40.0:
				p.x += w + 80.0
			_rain_pos[i] = p
		var drift := Vector2(12.0, -26.0 if _rise else 8.0) * delta
		for i in int(MOTE_COUNT * minf(_motes, 1.5) / 1.5):
			var p := _mote_pos[i] + drift + Vector2(sin(_time + _mote_phase[i]) * 10.0 * delta, 0.0)
			_mote_pos[i] = Vector2(fposmod(p.x, w), fposmod(p.y, h))
		for i in FOG_BLOBS:
			_fog_pos[i] = Vector2(fposmod(_fog_pos[i].x + 14.0 * delta, w + 400.0), _fog_pos[i].y)
		var gust := 1.0 + 0.8 * maxf(sin(_time * 0.4), 0.0) + _rain
		for i in DEBRIS_COUNT:
			var p := _debris_pos[i] + Vector2(90.0 * gust, 20.0 + sin(_time * 2.0 + i) * 40.0) * delta
			if p.x > w + 40.0:
				p = Vector2(-40.0, randf() * h)
			_debris_pos[i] = Vector2(p.x, fposmod(p.y, h))
			_debris_spin[i] += delta * (3.0 + i % 3) * gust
		queue_redraw()

	func _draw() -> void:
		if _fog.a > 0.001:
			for i in FOG_BLOBS:
				var p := _fog_pos[i] - Vector2(200.0, 0.0)
				draw_circle(p, _fog_radius[i], Color(_fog, _fog.a * 0.6))
		var rain_color := Color(0.75, 0.85, 1.0, 0.35)
		for i in int(RAIN_COUNT * _rain):
			var p := _rain_pos[i]
			draw_line(p, p - Vector2(-0.128, 0.992) * _rain_len[i], rain_color, 2.0)
		for i in int(MOTE_COUNT * minf(_motes, 1.5) / 1.5):
			var twinkle := 0.5 + 0.5 * sin(_time * 2.0 + _mote_phase[i])
			draw_circle(_mote_pos[i], 2.0 + 1.5 * twinkle, Color(_mote_color, 0.25 + 0.35 * twinkle))
		for i in DEBRIS_COUNT:
			var c := _debris_pos[i]
			var flip := cos(_debris_spin[i])
			var axis := Vector2.from_angle(_debris_spin[i] * 0.5)
			if absf(flip) < 0.1:
				draw_line(c - axis * 9.0, c + axis * 9.0, Color(0.85, 0.82, 0.92, 0.4), 2.0)
				continue
			var side := axis.orthogonal() * 7.0 * flip
			var sheet := PackedVector2Array([c - axis * 9.0 - side, c + axis * 9.0 - side, c + axis * 9.0 + side, c - axis * 9.0 + side])
			draw_colored_polygon(sheet, Color(0.85, 0.82, 0.92, 0.35 + 0.25 * absf(flip)))
