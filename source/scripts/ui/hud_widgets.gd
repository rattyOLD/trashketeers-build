class_name HudWidgets
extends RefCounted
## Виджеты шапки боя: полоса здоровья/опыта на рисованной рамке Астры и портрет енота,
## которому по мере потери здоровья становится всё хуже (перекос, трещины, красная вуаль).

const DIR := "res://assets/ui/hud/"


## Полоса из рамки и заливки: рамка режется на три части (углы не растягиваются), заливка обрезается по значению.
class TexBar:
	extends Control

	const END_SRC := 64.0
	const SRC_H := 48.0

	var frame: Texture2D
	var fills: Array[Texture2D] = []
	var max_value := 1.0:
		set(v):
			max_value = maxf(v, 0.001)
			queue_redraw()
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	## Какая заливка: индекс в fills.
	var fill_index := 0:
		set(v):
			fill_index = v
			queue_redraw()

	func _init(frame_name: String, fill_names: Array) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame = _load(frame_name)
		for n in fill_names:
			fills.append(_load(str(n)))

	static func _load(name: String) -> Texture2D:
		var path := HudWidgets.DIR + name + ".png"
		return load(path) as Texture2D if ResourceLoader.exists(path) else null

	func _draw() -> void:
		var frac := clampf(value / max_value, 0.0, 1.0)
		var end_w := minf(END_SRC * size.y / SRC_H, size.x * 0.33)
		var inset := end_w * 0.5
		var inner := Rect2(inset, size.y * 0.2, size.x - inset * 2.0, size.y * 0.6)
		draw_rect(inner, Color(0.092, 0.088, 0.083, 0.85), true)
		var fill: Texture2D = fills[clampi(fill_index, 0, fills.size() - 1)] if not fills.is_empty() else null
		if fill != null and frac > 0.0:
			var src := Rect2(0, 0, fill.get_width() * frac, fill.get_height())
			draw_texture_rect_region(fill, Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y)), src)
		elif frac > 0.0:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y)), Color("#e8283f"), true)
		if frame == null:
			draw_rect(Rect2(Vector2.ZERO, size), Color("#d8a773"), false, 3.0)
			return
		var fw := float(frame.get_width())
		var fh := float(frame.get_height())
		draw_texture_rect_region(frame, Rect2(0, 0, end_w, size.y), Rect2(0, 0, END_SRC, fh))
		draw_texture_rect_region(frame, Rect2(end_w, 0, size.x - end_w * 2.0, size.y), Rect2(END_SRC, 0, fw - END_SRC * 2.0, fh))
		draw_texture_rect_region(frame, Rect2(size.x - end_w, 0, end_w, size.y), Rect2(fw - END_SRC, 0, END_SRC, fh))


## Простая полоса: тёмная подложка, цветная заливка и обводка. Без рисованной рамки, места занимает мало.
class OutlineBar:
	extends Control

	const HP_COLORS: Array[Color] = [Color("#3fdc55"), Color("#ffb020"), Color("#ff3b3b")]
	# Опыт — голубой: с первого взгляда не путается с зелёным здоровьем.
	const XP_COLORS: Array[Color] = [Color("#3fb8ff")]

	var colors: Array[Color] = HP_COLORS
	var max_value := 1.0:
		set(v):
			max_value = maxf(v, 0.001)
			queue_redraw()
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var fill_index := 0:
		set(v):
			fill_index = v
			queue_redraw()
	var _back := StyleBoxFlat.new()
	var _fill := StyleBoxFlat.new()
	var _art: StyleBoxTexture

	func _init(palette: Array[Color] = HP_COLORS) -> void:
		colors = palette
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.bg_color = Color(0.04, 0.02, 0.08, 0.82)
		_back.border_color = Color(0.96, 0.92, 1.0, 0.9)
		_back.set_border_width_all(3)
		_back.set_corner_radius_all(9)
		_fill.set_corner_radius_all(6)
		var path := HudWidgets.DIR + ("xp_frame.png" if palette == XP_COLORS else "hp_frame.png")
		if ResourceLoader.exists(path):
			_art = StyleBoxTexture.new()
			_art.texture = load(path) as Texture2D
			_art.texture_margin_left = 24
			_art.texture_margin_right = 24
			_art.texture_margin_top = 6
			_art.texture_margin_bottom = 6

	func _draw() -> void:
		draw_style_box(_back, Rect2(Vector2.ZERO, size))
		var frac := clampf(value / max_value, 0.0, 1.0)
		if frac <= 0.0:
			if _art != null:
				draw_style_box(_art, Rect2(Vector2.ZERO, size))
			return
		var inner := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var width := maxf(inner.size.x * frac, 12.0)
		var base: Color = colors[clampi(fill_index, 0, colors.size() - 1)]
		_fill.bg_color = base
		draw_style_box(_fill, Rect2(inner.position, Vector2(width, inner.size.y)))
		# Светлая полоска сверху даёт объём без текстур.
		draw_rect(Rect2(inner.position + Vector2(6, 2), Vector2(maxf(width - 12.0, 0.0), inner.size.y * 0.28)), Color(1, 1, 1, 0.22), true)
		if _art != null:
			draw_style_box(_art, Rect2(Vector2.ZERO, size))


## Портрет в круглой оправе. Лицо — нарисованный портрет того героя, за которого играют; по мере потери
## здоровья подставляются кадры «ему больно» (assets/ui/portraits/hud/<герой>_<0..3>.png, их рисует Астра).
## Пока кадров нет, лицо перекашивается и краснеет кодом.
class DamagePortrait:
	extends Control

	var _batch := PolyBatch.new()

	const HUD_DIR := "res://assets/ui/portraits/hud/"
	const SIDE := 120.0

	var health := 1.0
	var _face: Face
	var _faces: Array[Texture2D] = []
	var _shake := 0.0
	var _clock := 0.0
	var _stage := 0
	## Короткая реакция лица (face_<вид>.png): попадание, ухмылка, гордость за серию, испуг.
	const FACE_DIR := "res://assets/ui/portraits/face/"
	var _hero_id := ""
	var _react_left := 0.0
	var _react_cache := {}
	var _scared_done := false

	func react(kind: String, time: float = 1.4) -> void:
		var key := "%s_%s" % [_hero_id, kind]
		if not _react_cache.has(key):
			var path := FACE_DIR + key + ".png"
			_react_cache[key] = AvatarPicker.portrait_texture(path) if ResourceLoader.exists(path) else null
		var tex: Texture2D = _react_cache[key]
		if tex == null:
			return
		_face.tex = tex
		_face.queue_redraw()
		_react_left = time

	func _init() -> void:
		custom_minimum_size = Vector2(SIDE, SIDE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face = Face.new()
		_face.size = Vector2(SIDE - 18.0, SIDE - 18.0)
		_face.position = Vector2(9, 9)
		_face.pivot_offset = _face.size * 0.5
		add_child(_face)
		add_child(Over.new(self))
		set_process(true)

	## Какой герой сейчас в бою: берём его портрет и кадры повреждений, если они нарисованы.
	func set_character(character: Dictionary) -> void:
		var id := str(character.get("id", ""))
		_hero_id = id
		_react_cache.clear()
		_faces.clear()
		for n in 4:
			var path := "%s%s_%d.png" % [HUD_DIR, id, n]
			_faces.append(AvatarPicker.portrait_texture(path) if ResourceLoader.exists(path) else null)
		if _faces[0] == null:
			var base := str(character.get("hud_portrait", character.get("portrait", "")))
			_faces[0] = AvatarPicker.portrait_texture(base) if not base.is_empty() else null
		_pick_face()

	func _pick_face() -> void:
		var stage := 0 if health > 0.7 else (1 if health > 0.45 else (2 if health > 0.2 else 3))
		_stage = stage
		var tex: Texture2D = _faces[stage] if stage < _faces.size() else null
		if tex == null:
			for i in range(stage, -1, -1):
				if i < _faces.size() and _faces[i] != null:
					tex = _faces[i]
					break
		_face.tex = tex
		_face.queue_redraw()

	## Есть ли нарисованный кадр именно для этой стадии (тогда код не портит лицо сам).
	func has_art(stage: int) -> bool:
		return stage < _faces.size() and _faces[stage] != null

	## fraction — доля здоровья 0..1; пришёл урон — портрет дёргается.
	func set_health(fraction: float) -> void:
		var f := clampf(fraction, 0.0, 1.0)
		if f < health - 0.004:
			_shake = 0.3
		var big_hit := f < health - 0.08
		health = f
		if _react_left <= 0.0:
			_pick_face()
		if f > 0.0 and f < 0.2 and not _scared_done:
			_scared_done = true
			react("scared", 1.8)
		elif big_hit:
			react("hit", 0.9)
		if f > 0.5:
			_scared_done = false
		queue_redraw()

	func damage() -> float:
		return clampf((0.8 - health) / 0.8, 0.0, 1.0)

	func _process(delta: float) -> void:
		_clock += delta
		_shake = maxf(_shake - delta, 0.0)
		if _react_left > 0.0:
			_react_left -= delta
			if _react_left <= 0.0:
				_pick_face()
		var d := damage()
		var painted := has_art(_stage) and _stage > 0
		# Нарисованный кадр сам несёт перекошенное лицо, код добавляет только дрожь.
		var warp := 0.35 if painted else 1.0
		var tilt := -0.2 * d * d * warp
		var jitter := sin(_clock * 38.0) * 0.07 * (_shake / 0.3)
		if health < 0.2 and health > 0.0:
			jitter += sin(_clock * 9.0) * 0.025
		_face.rotation = tilt + jitter
		_face.scale = Vector2(1.0 + 0.05 * d * warp, 1.0 - 0.09 * d * warp)
		_face.modulate = Color.WHITE.lerp(Color(1.0, 0.55, 0.55), d * 0.7 * warp)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		_batch.circle(c, r - 1.0, Color("#1a1917"))
		_batch.circle(c, r - 5.0, Color("#4f4c47"))
		_batch.flush(self)


## Лицо: портрет, вырезанный кругом (полигон с UV).
class Face:
	extends Control

	var tex: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if tex == null:
			return
		MenuWidgets.Avatar.draw_round(self, tex, size * 0.5, minf(size.x, size.y) * 0.5)


## Верхний слой портрета: оправа, трещины, кровь и красная вуаль. Рисуется поверх лица.
class Over:
	extends Control

	var owner_portrait: DamagePortrait
	var _batch := PolyBatch.new()

	func _init(p: DamagePortrait) -> void:
		owner_portrait = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var path := "res://assets/ui/hud/portrait_frame.png"
		if ResourceLoader.exists(path):
			var frame := TextureRect.new()
			frame.texture = load(path) as Texture2D
			frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(frame)
		set_process(true)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var d := owner_portrait.damage()
		var health := owner_portrait.health
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var clock := Time.get_ticks_msec() / 1000.0
		if d > 0.0:
			_batch.circle(c, r - 8.0, Color(0.85, 0.05, 0.12, 0.34 * d))
		# Трещины на «стекле» оправы: появляются по ступеням.
		var cracks := [
			[0.25, [Vector2(0.62, 0.10), Vector2(0.52, 0.30), Vector2(0.58, 0.45), Vector2(0.46, 0.64)]],
			[0.5, [Vector2(0.12, 0.40), Vector2(0.28, 0.48), Vector2(0.22, 0.68)]],
			[0.75, [Vector2(0.9, 0.58), Vector2(0.72, 0.68), Vector2(0.76, 0.9)]],
		]
		for crack in cracks:
			if d < float(crack[0]):
				continue
			var pts := PackedVector2Array()
			for u: Vector2 in crack[1]:
				pts.append(u * size)
			_batch.polyline(pts, Color(0.05, 0.02, 0.08, 0.9), 3.4, true)
			_batch.polyline(pts, Color(1, 0.85, 0.8, 0.5), 1.1, true)
		if d > 0.6:
			for i in 3:
				var x := size.x * (0.3 + 0.22 * i)
				var fall := fmod(clock * (0.5 + 0.15 * i) + i * 0.37, 1.0)
				_batch.circle(Vector2(x, size.y * (0.62 + 0.3 * fall)), 2.6 * (1.0 - fall * 0.5), Color(0.8, 0.05, 0.1, 0.9 * (1.0 - fall)))
		# Оправа.
		var rust := Color("#c9722b").lerp(Color("#8a2a1a"), d * 0.8)
		_batch.arc(c, r - 3.5, 0.0, TAU, 48, Color("#262422"), 8.0, true)
		_batch.arc(c, r - 3.5, 0.0, TAU, 48, rust, 4.5, true)
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			_batch.circle(c + Vector2.from_angle(a) * (r - 3.5), 3.0, Color("#ffe27a").lerp(Color("#5a3a30"), d))
		if health < 0.25 and health > 0.0:
			_batch.arc(c, r - 2.0, 0.0, TAU, 48, Color(1, 0.15, 0.2, 0.35 + 0.35 * sin(clock * 8.0)), 6.0, true)
		_batch.flush(self)
