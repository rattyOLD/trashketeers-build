class_name HeroMoodCard
extends PanelContainer
## Карточка героя на экране итогов: портрет в рамке, у каждого героя свой характер движения.
## Победа: бодрый, чуть уставший, на щеке пара капель вражеской крови. Поражение: побитый, злой или грустный
## (синяки, пластырь, трещины, слёзы, звёздочки). Внизу реплика героя и полезная строка итога.

const LINES_PATH := "res://data/hero_lines.json"
const HUD_DIR := "res://assets/ui/portraits/hud/"
const SIDE := 188.0
## win/lose — манера движения, mood — как герой переживает поражение.
const STYLES := {
	"raccoon": {"win": "hop", "lose": "slump", "mood": "sad"},
	"red_panda": {"win": "flex", "lose": "jitter", "mood": "angry"},
	"snow": {"win": "steady", "lose": "slump", "mood": "stoic"},
	"night": {"win": "sway", "lose": "flicker", "mood": "angry"},
	"neon_hopper": {"win": "bounce", "lose": "wobble", "mood": "dizzy"},
	"fluffy_chemist": {"win": "sway", "lose": "cough", "mood": "sad"},
	"pigeon_mafioso": {"win": "nod", "lose": "jitter", "mood": "angry"},
}

static var _lines: Dictionary = {}

var _character: Dictionary
var _win := false
var _style: Dictionary
var _t := 0.0
var _face: TextureRect
var _over: MoodOver


static func lines_for(id: String, win: bool) -> Array:
	if _lines.is_empty():
		_lines = ConfigLoader.load_json(LINES_PATH)
	var entry: Dictionary = _lines.get(id, _lines.get("fallback", {}))
	return entry.get("win" if win else "lose", [])


## Строка «итог» по цифрам забега: темп убийств и сколько не хватило до рекорда.
static func summary_line(summary: Dictionary) -> String:
	var time := float(summary.get("time", 0.0))
	var kills := int(summary.get("kills", 0))
	var parts: PackedStringArray = []
	if time >= 20.0 and kills > 0:
		parts.append("%d врагов в минуту" % roundi(float(kills) / (time / 60.0)))
	var best := int(summary.get("best_wave", 0))
	var wave := int(summary.get("wave", 0))
	if bool(summary.get("record", false)):
		parts.append("новый рекорд: волна %d" % wave)
	elif best > wave:
		parts.append("до рекорда не хватило %d %s" % [best - wave, SaveService.plural(best - wave, "волны", "волн", "волн")])
	return " · ".join(parts)


func _init(character: Dictionary, win: bool, extra_line: String = "") -> void:
	_character = character
	_win = win
	var id := str(character.get("id", "raccoon"))
	_style = STYLES.get(id, STYLES["raccoon"])
	var accent: Color = Color("#7cff6b") if win else Color("#ff5a6e")
	add_theme_stylebox_override("panel", UiStyle.box(accent.darkened(0.78), accent, 4, 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(SIDE, SIDE)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	var back := Panel.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_theme_stylebox_override("panel", UiStyle.box(Color("#0a0d1c"), accent, 3, 18))
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(back)
	_face = TextureRect.new()
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.size = Vector2(SIDE - 8.0, SIDE - 8.0)
	_face.position = Vector2(4, 4)
	_face.pivot_offset = _face.size * 0.5
	_face.texture = _pick_texture(id, win)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_face)
	_over = MoodOver.new(win, str(_style.get("mood", "sad")), str(id).hash())
	_over.size = Vector2(SIDE, SIDE)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_over)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	var name_label := UiStyle.label(str(character.get("title", "Герой")).to_upper(), 22, accent.lightened(0.3), 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name_label)
	var mood_text := ("бодр, но устал" if win else _mood_name(str(_style.get("mood", "sad"))))
	var mood_label := UiStyle.label(mood_text, 17, UiStyle.TEXT_DIM, 4)
	mood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(mood_label)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.25), 2, 14))
	var phrases := lines_for(id, win)
	var phrase := UiStyle.label("«%s»" % str(phrases.pick_random()) if not phrases.is_empty() else "", 20, UiStyle.TEXT, 5)
	phrase.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	phrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phrase.custom_minimum_size = Vector2(150, 0)
	bubble.add_child(phrase)
	column.add_child(bubble)
	if not extra_line.is_empty():
		var extra := UiStyle.label(extra_line, 17, UiStyle.NEON, 4)
		extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		extra.custom_minimum_size = Vector2(150, 0)
		column.add_child(extra)
	set_process(true)


static func _mood_name(mood: String) -> String:
	match mood:
		"angry":
			return "побит и очень зол"
		"dizzy":
			return "побит, голова кругом"
		"stoic":
			return "побит, но держится"
	return "побит и расстроен"


## Победа: самый бодрый кадр. Поражение: кадр «сильно побит»; если нарисован один кадр, остальное дорисует код.
func _pick_texture(id: String, win: bool) -> Texture2D:
	var order := PackedInt32Array([0, 1]) if win else PackedInt32Array([3, 2])
	for n in order:
		var path := "%s%s_%d.png" % [HUD_DIR, id, n]
		if ResourceLoader.exists(path):
			return AvatarPicker.portrait_texture(path)
	var base := str(_character.get("hud_portrait", _character.get("portrait", "")))
	return AvatarPicker.portrait_texture(base) if not base.is_empty() else null


func _process(delta: float) -> void:
	_t += delta
	var intro := clampf(_t / 0.45, 0.0, 1.0)
	var pop := 1.0 + 0.45 * pow(1.0 - intro, 2.0) * -1.0
	var offset := Vector2.ZERO
	var rot := 0.0
	var scale_v := Vector2.ONE
	var alpha := 1.0
	var motion := str(_style.get("win" if _win else "lose", "steady"))
	match motion:
		"hop":
			var k := absf(sin(_t * 3.2))
			offset.y = -k * 16.0
			scale_v = Vector2(1.0 + 0.05 * (1.0 - k), 1.0 - 0.05 * (1.0 - k))
		"flex":
			scale_v = Vector2.ONE * (1.0 + 0.035 * sin(_t * 9.0))
			rot = sin(_t * 7.0) * 0.03
		"steady":
			scale_v = Vector2.ONE * (1.0 + 0.012 * sin(_t * 2.0))
			offset.y = sin(_t * 2.0) * 2.0
		"sway":
			rot = sin(_t * 1.8) * 0.05
			offset.x = sin(_t * 1.8) * 4.0
		"bounce":
			offset.y = -absf(sin(_t * 5.5)) * 22.0
		"nod":
			offset.y = sin(_t * 2.2) * 6.0
			rot = sin(_t * 1.1) * 0.025
		"slump":
			var sink := minf(_t / 1.2, 1.0)
			offset.y = 12.0 * sink + sin(_t * 1.2) * 2.0
			rot = -0.05 * sink
		"jitter":
			offset.x = sin(_t * 43.0) * 2.4 * (0.5 + 0.5 * sin(_t * 2.3))
			scale_v = Vector2.ONE * 1.02
		"flicker":
			alpha = 0.72 + 0.28 * absf(sin(_t * 17.0))
			offset.y = 4.0
		"wobble":
			rot = sin(_t * 3.0) * 0.1
			offset.x = sin(_t * 1.5) * 6.0
		"cough":
			var c := pow(maxf(sin(_t * 1.7), 0.0), 6.0)
			offset.y = -c * 7.0
			scale_v = Vector2(1.0 + 0.03 * c, 1.0 - 0.03 * c)
	_face.position = Vector2(4, 4) + offset
	_face.rotation = rot
	_face.scale = scale_v * (0.6 + 0.4 * intro if intro < 1.0 else 1.0)
	_face.modulate = Color(1, 1, 1, alpha * clampf(intro * 2.0, 0.0, 1.0))
	_over.t = _t
	_over.queue_redraw()


## Лицевые эффекты поверх портрета: рисуются кодом, одинаково работают для любого героя.
class MoodOver:
	extends Control
	var win := false
	var mood := "sad"
	var t := 0.0
	var seed_value := 0

	func _init(is_win: bool, mood_name: String, seed_number: int) -> void:
		win = is_win
		mood = mood_name
		seed_value = seed_number

	func _rand(i: int) -> float:
		return float(absi(hash(seed_value * 31 + i)) % 1000) / 1000.0

	func _draw() -> void:
		var s := size.x
		if win:
			_draw_win(s)
		else:
			_draw_lose(s)

	func _drop(at: Vector2, radius: float, color: Color) -> void:
		draw_circle(at, radius, color)
		draw_circle(at + Vector2(0, radius * 1.1), radius * 0.7, color)
		draw_circle(at + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.3, Color(1, 1, 1, 0.35 * color.a))

	func _blood(s: float, count: int, strength: float) -> void:
		var color := Color(0.72, 0.08, 0.16, 0.88)
		for i in count:
			var at := Vector2(s * (0.22 + 0.56 * _rand(i * 3)), s * (0.55 + 0.3 * _rand(i * 3 + 1)))
			_drop(at, (3.0 + 4.0 * _rand(i * 3 + 2)) * strength, color)
		var run := fmod(t * 7.0, 22.0)
		draw_line(Vector2(s * 0.34, s * 0.62), Vector2(s * 0.34, s * 0.62 + 10.0 + run * 0.4), color, 2.5)

	func _draw_win(s: float) -> void:
		_blood(s, 4, 0.9)
		var sweat_y := s * 0.2 + fmod(t * 14.0, 40.0)
		_drop(Vector2(s * 0.76, sweat_y), 4.0, Color(0.55, 0.85, 1.0, 0.85 * (1.0 - (sweat_y - s * 0.2) / 40.0)))
		for i in 3:
			var phase := fmod(t * 1.3 + _rand(i) * 3.0, 1.0)
			var at := Vector2(s * (0.12 + 0.76 * _rand(i + 9)), s * (0.1 + 0.2 * _rand(i + 12)))
			_star(at, 9.0 * sin(phase * PI), Color(1.0, 0.95, 0.5, sin(phase * PI)))

	func _star(at: Vector2, r: float, color: Color) -> void:
		if r <= 0.5:
			return
		draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), color, 2.0)
		draw_line(at + Vector2(0, -r), at + Vector2(0, r), color, 2.0)
		draw_line(at + Vector2(-r, -r) * 0.55, at + Vector2(r, r) * 0.55, color, 1.5)
		draw_line(at + Vector2(-r, r) * 0.55, at + Vector2(r, -r) * 0.55, color, 1.5)

	func _draw_lose(s: float) -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), Color(0.35, 0.0, 0.06, 0.16))
		for i in 6:
			var inset := float(i) * 5.0
			draw_rect(Rect2(Vector2(inset, inset), Vector2(s - inset * 2.0, s - inset * 2.0)), Color(0.5, 0.0, 0.1, 0.07 * float(6 - i)), false, 5.0)
		# синяк под глазом
		draw_circle(Vector2(s * 0.34, s * 0.5), s * 0.07, Color(0.38, 0.1, 0.5, 0.45))
		# пластырь
		draw_set_transform(Vector2(s * 0.7, s * 0.6), -0.5, Vector2.ONE)
		draw_rect(Rect2(-17, -6, 34, 12), Color("#e8c9a0"))
		draw_rect(Rect2(-17, -6, 34, 12), Color("#180e22"), false, 2.0)
		draw_circle(Vector2(-6, 0), 1.6, Color("#b88e60"))
		draw_circle(Vector2(6, 0), 1.6, Color("#b88e60"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_blood(s, 6, 1.2)
		# трещина «экрана»
		var crack := PackedVector2Array([Vector2(s * 0.02, s * 0.1), Vector2(s * 0.18, s * 0.2), Vector2(s * 0.14, s * 0.34), Vector2(s * 0.3, s * 0.44)])
		draw_polyline(crack, Color(1, 1, 1, 0.55), 2.0)
		draw_line(crack[1], Vector2(s * 0.3, s * 0.12), Color(1, 1, 1, 0.4), 1.5)
		match mood:
			"sad":
				var ty := fmod(t * 38.0, 60.0)
				_drop(Vector2(s * 0.3, s * 0.52 + ty), 4.0, Color(0.55, 0.85, 1.0, 0.85 * (1.0 - ty / 60.0)))
			"angry":
				var pulse := 1.0 + 0.2 * sin(t * 9.0)
				var c := Vector2(s * 0.82, s * 0.16)
				var col := Color(1.0, 0.2, 0.25, 0.95)
				for k in 4:
					var a := PI * 0.5 * float(k) + 0.78
					draw_arc(c + Vector2.from_angle(a) * 9.0 * pulse, 7.0 * pulse, a + 2.4, a + 5.4, 8, col, 3.0)
			"dizzy":
				for k in 4:
					var a := t * 3.0 + TAU * float(k) / 4.0
					_star(Vector2(s * 0.5 + cos(a) * s * 0.3, s * 0.1 + sin(a) * 9.0), 7.0, Color(1.0, 0.9, 0.3, 0.95))
			"stoic":
				for k in 3:
					var x := s * (0.62 + 0.1 * float(k))
					draw_colored_polygon(PackedVector2Array([Vector2(x, s * 0.02), Vector2(x + 7.0, s * 0.02), Vector2(x + 3.5, s * (0.12 + 0.05 * float(k)))]), Color(0.75, 0.92, 1.0, 0.8))
		if mood == "sad" or mood == "angry":
			for k in 2:
				var phase := fmod(t * 0.7 + float(k) * 0.5, 1.0)
				draw_circle(Vector2(s * (0.45 + 0.1 * float(k)), s * 0.1 - phase * 14.0), 4.0 + 4.0 * phase, Color(0.8, 0.8, 0.85, 0.35 * (1.0 - phase)))
