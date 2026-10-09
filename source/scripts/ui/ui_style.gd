class_name UiStyle
extends RefCounted
## Фабрики стилизованных контролов: жирный тёмный контур, скруглённые плашки, неон.
## Всё строится кодом, чтобы UI не зависел от .tres-тем и легко правился в одном месте.

const OUTLINE := Color("#0d0f0e")
const PANEL := Color("#221d19")
const PANEL_LIGHT := Color("#302823")
const NEON := Color("#ff8a1f")
const HOT := Color("#ff5a1f")
const GOLD := Color("#f5c04a")
const DANGER := Color("#e8412f")
const TEXT := Color("#f1efe6")
const TEXT_DIM := Color("#aaa898")


static func box(bg: Color, border: Color = OUTLINE, border_width: int = 4, radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


static func label(text: String, font_size: int, color: Color = TEXT, outline: int = 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


const KIT_ON := true
const KIT_DIR := "res://assets/ui/kit/"
static var _kit_cache: Dictionary = {}


## Единая палитра карточек окон (под набор Астры: ржавчина, золото, бирюза): тёмная тёплая плашка, янтарная рамка.
const CARD_BG := Color("#25201c")
const CARD_BORDER := Color("#b07a30")
const CARD_TEAL := Color("#3fc8d8")


static func card_box(accent: Color = CARD_BORDER, width: int = 3) -> StyleBoxFlat:
	return box(CARD_BG, accent, width, 14)


## Шрифт кнопки уменьшается (не меньше 11), пока надпись не влезет в max_width: текст не вылезает из плашки.
static func fit_button_font(button: Button, base: int, max_width: float) -> void:
	var font := button.get_theme_font("font")
	var size := base
	while size > 11 and font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > max_width:
		size -= 1
	button.add_theme_font_size_override("font_size", size)


## Текстура из набора интерфейса Астры (assets/ui/kit/<имя>) или null, если набор выключен или файла нет.
static func kit_texture(file: String) -> Texture2D:
	if not KIT_ON:
		return null
	var key := "tex:" + file
	if not _kit_cache.has(key):
		_kit_cache[key] = load(KIT_DIR + file) if ResourceLoader.exists(KIT_DIR + file) else null
	return _kit_cache[key]


## Какой из четырёх нарисованных цветов кнопки ближе к заказанному оттенку. Серые и тёмные кнопки: фиолетовая «стальная».
static func _kit_family(color: Color) -> String:
	if color.s < 0.3 or color.v < 0.4:
		return "teal"
	var h := color.h
	if h < 0.04 or h > 0.93:
		return "red"
	if h < 0.2:
		return "gold"
	if h < 0.46:
		return "green"
	# Фиолетовые (премиум, неонит) — своя плашка, а не серая нейтральная.
	if h > 0.68 and h < 0.93:
		return "purple"
	return "teal"


## Кнопка из рисованной плашки: девять частей, углы с заклёпками не растягиваются.
## Для низких кнопок берётся уменьшенная вдвое копия, чтобы рамка не съедала всю высоту.
static func kit_box(family: String, state: String, small: bool, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var key := "%s_%s_%s_%s" % [family, state, small, tint.to_html()]
	if _kit_cache.has(key):
		return _kit_cache[key]
	var sb := StyleBoxTexture.new()
	sb.texture = load("%sbtn_%s_%s%s.png" % [KIT_DIR, family, state, "_s" if small else ""]) as Texture2D
	var m := 15.0 if small else 30.0
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = m + 4.0
	sb.content_margin_right = m + 4.0
	sb.content_margin_top = m * 0.35
	sb.content_margin_bottom = m * 0.35 + (2.0 if state == "pressed" else 0.0)
	sb.modulate_color = tint
	_kit_cache[key] = sb
	return sb


## Тап по плитке-панели: на отпускании и только если палец почти не двигался (иначе это прокрутка списка).
static func is_tap(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed and not Platform.touch_moved()
	if event is InputEventMouseButton and not Platform.is_touch():
		var mouse := event as InputEventMouseButton
		return mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed
	return false


static func button(text: String, color: Color, font_size: int = 30, min_size: Vector2 = Vector2(0, 84)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_hover_pressed_color", TEXT)
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_disabled_color", Color(TEXT, 0.55))
	var small := min_size.y < 100.0 or font_size <= 30
	var family := _kit_family(color)
	if KIT_ON and ResourceLoader.exists(KIT_DIR + "btn_%s_normal.png" % family):
		b.add_theme_stylebox_override("normal", kit_box(family, "normal", small))
		b.add_theme_stylebox_override("hover", kit_box(family, "normal", small, Color(1.12, 1.12, 1.12)))
		b.add_theme_stylebox_override("pressed", kit_box(family, "pressed", small))
		b.add_theme_stylebox_override("hover_pressed", kit_box(family, "pressed", small))
		b.add_theme_stylebox_override("disabled", kit_box(family, "disabled", small))
	else:
		b.add_theme_stylebox_override("normal", button_box(color, false))
		b.add_theme_stylebox_override("hover", button_box(color.lightened(0.06), false))
		b.add_theme_stylebox_override("pressed", button_box(color.lightened(0.1), true))
		b.add_theme_stylebox_override("hover_pressed", button_box(color.lightened(0.1), true))
		b.add_theme_stylebox_override("disabled", button_box(color.darkened(0.45).lerp(Color("#4a4742"), 0.5), false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: SoundManager.play(&"ui_click"))
	press_feedback(b)
	# Надпись всегда внутри плашки: при смене размера или текста шрифт ужимается под ширину без болтов и иконки.
	var fit := func() -> void: _fit_inside(b, font_size)
	b.resized.connect(fit)
	b.ready.connect(fit)
	return b


static func _fit_inside(b: Button, base: int) -> void:
	if not is_instance_valid(b) or b.size.x < 8.0 or b.text.is_empty() or b.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return
	var sb := b.get_theme_stylebox("normal")
	# Ровно то место, что Godot отдаёт тексту: без запаса, иначе кнопка, подстроенная под текст, ужималась по кругу.
	var avail := b.size.x - (sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb != null else 0.0)
	if b.icon != null:
		var icon_w := float(b.get_theme_constant("icon_max_width")) if b.get_theme_constant("icon_max_width") > 0 else float(b.icon.get_width())
		avail -= icon_w + float(b.get_theme_constant("h_separation"))
	var font := b.get_theme_font("font")
	var size := base
	var widest := 0.0
	for line in b.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	while size > 11 and widest > avail + 0.5:
		size -= 1
		widest = 0.0
		for line in b.text.split("\n"):
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	if size != b.get_theme_font_size("font_size"):
		b.add_theme_font_size_override("font_size", size)


## Кнопка «прожимается»: под пальцем чуть утапливается, отпустил — пружинит обратно, плюс короткий отклик вибрацией.
static func press_feedback(b: BaseButton) -> void:
	b.button_down.connect(func() -> void:
		if b.disabled:
			return
		b.pivot_offset = b.size * 0.5
		var tween := b.create_tween()
		tween.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06)
		b.set_meta(&"press_tween", tween)
		Platform.haptic("light"))
	b.button_up.connect(func() -> void:
		var old: Variant = b.get_meta(&"press_tween") if b.has_meta(&"press_tween") else null
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		b.pivot_offset = b.size * 0.5
		var tween := b.create_tween()
		tween.tween_property(b, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Кнопка без плашки: видна только иконка внутри (у неё уже своя рамка). Нажатие — лёгкое затемнение.
static func flat_button(min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: SoundManager.play(&"ui_click"))
	press_feedback(b)
	return b


## Единый стиль кнопок: плашка с тёмным ободком того же оттенка и толстой «губой» снизу;
## при нажатии губа уходит, текст опускается — кнопка «продавливается».
static func button_box(color: Color, pressed: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.darkened(0.6).lerp(OUTLINE, 0.35)
	s.set_border_width_all(4)
	s.border_width_bottom = 5 if pressed else 11
	s.set_corner_radius_all(20)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 16 if pressed else 10
	s.content_margin_bottom = 8 if pressed else 14
	s.expand_margin_top = -6.0 if pressed else 0.0
	s.anti_aliasing = true
	return s


static func progress_bar(fill: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", box(Color("#21201e"), OUTLINE, 4, 10))
	var fill_box := box(fill, OUTLINE, 4, 10)
	fill_box.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill", fill_box)
	return bar


## Якорь в точке anchor (0..1 от родителя) и прямоугольник относительно неё.
## Задаём offsets напрямую: position у заякоренного контрола зависит от текущего размера родителя.
static func anchor(control: Control, anchor_point: Vector2, rect: Rect2) -> void:
	control.anchor_left = anchor_point.x
	control.anchor_right = anchor_point.x
	control.anchor_top = anchor_point.y
	control.anchor_bottom = anchor_point.y
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


static func keep_pivot_centered(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	if control.has_meta(&"pivot_bound"):
		return
	control.set_meta(&"pivot_bound", true)
	control.resized.connect(func() -> void: control.pivot_offset = control.size * 0.5)


## Пружинящее появление (Elastic по ТЗ).
static func pop_in(control: Control, duration: float = 0.6) -> void:
	keep_pivot_centered(control)
	var user_scale: float = float(control.get_meta(&"ui_scale", 1.0))
	var user_alpha: float = float(control.get_meta(&"ui_alpha", 1.0))
	control.scale = Vector2(0.55, 0.55) * user_scale
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE * user_scale, duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", user_alpha, duration * 0.3)


static func pulse(control: Control, amount: float = 0.06, period: float = 0.9) -> void:
	keep_pivot_centered(control)
	var tween := control.create_tween().set_loops()
	tween.tween_property(control, "scale", Vector2.ONE * (1.0 + amount), period * 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE)


## Телефон уменьшает холст 1280×720 (или 720×1280) вдвое: мелкие подписи HUD становятся нечитаемыми.
## Поднимаем размер и контур у небольших Label внутри переданных узлов; крупные баннеры не трогаем.
static func boost_labels(node: Node, factor: float, max_size: int = 30) -> void:
	if node is Label:
		var label := node as Label
		var current := label.get_theme_font_size("font_size")
		if current > 0 and current <= max_size:
			label.add_theme_font_size_override("font_size", roundi(current * factor))
			label.add_theme_constant_override("outline_size", label.get_theme_constant("outline_size") + 2)
	for child in node.get_children():
		boost_labels(child, factor, max_size)
