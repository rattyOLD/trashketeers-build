class_name AvatarPicker
extends GlassPopup
## Выбор портрета: сетка плиток. Открытые выбираются, закрытые подсказывают условие, недоступные ждут обновлений.

signal picked

const COLUMNS := 3
const TILE := 150.0
## path, название, тип условия, значение, подсказка
const ENTRIES := [
	["", "Герой", "open", 0, ""],
	["res://assets/story/portraits/rico.png", "Рико", "open", 0, ""],
	["res://assets/story/portraits/rico_alt.png", "Рико злой", "story", 1, "Пройди миссию 1"],
	["res://assets/story/portraits/nell.png", "Нэлл", "open", 0, ""],
	["res://assets/story/portraits/nell_alt.png", "Нэлл в бешенстве", "story", 1, "Пройди миссию 1"],
	["res://assets/story/portraits/baron.png", "Барон", "stat:k_beer_baron", 1, "Победи Пивного Барона"],
	["res://assets/story/portraits/baron_alt.png", "Барон ржёт", "stat:k_beer_baron", 3, "Победи Барона 3 раза"],
	["res://assets/story/portraits/king.png", "Король Хлама", "shards", 1, "Забери 1 осколок Бочки"],
	["res://assets/story/portraits/king_alt.png", "Король злой", "shards", 6, "Собери все 6 печатей"],
	["res://assets/story/portraits/toxic.png", "Токсик", "stat:k_toxic_rat", 100, "Победи 100 Токсичных крыс"],
	["", "???", "never", 0, "Недоступно"],
	["", "???", "never", 0, "Недоступно"],
]

const CUSTOM := "custom"
const CUSTOM_SIDE := 160
const MAX_PHOTO := 12 * 1024 * 1024

static var _cache: Dictionary = {}
static var _custom_src := ""
static var _custom_tex: ImageTexture = null


## Своё фото игрока: квадрат CUSTOM_SIDE, лежит в сохранении как base64 JPEG.
static func custom_texture() -> Texture2D:
	var raw := str(SaveService.data.get("avatar_custom", ""))
	if raw.is_empty():
		return null
	if raw == _custom_src and _custom_tex != null:
		return _custom_tex
	var image := Image.new()
	if image.load_jpg_from_buffer(Marshalls.base64_to_raw(raw)) != OK:
		return null
	_custom_src = raw
	_custom_tex = ImageTexture.create_from_image(image)
	return _custom_tex


## Файл с телефона → квадратная миниатюра. true — фото принято.
static func store_photo(info: Dictionary) -> bool:
	var bytes := Marshalls.base64_to_raw(str(info.get("data", "")))
	var image := Image.new()
	var type := str(info.get("type", "")).to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	if type.contains("png"):
		err = image.load_png_from_buffer(bytes)
	elif type.contains("webp"):
		err = image.load_webp_from_buffer(bytes)
	else:
		err = image.load_jpg_from_buffer(bytes)
		if err != OK:
			err = image.load_png_from_buffer(bytes)
		if err != OK:
			err = image.load_webp_from_buffer(bytes)
	if err != OK or image.is_empty():
		return false
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	var side := mini(image.get_width(), image.get_height())
	var square := image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	square.resize(CUSTOM_SIDE, CUSTOM_SIDE, Image.INTERPOLATE_LANCZOS)
	SaveService.data["avatar_custom"] = Marshalls.raw_to_base64(square.save_jpg_to_buffer(0.88))
	SaveService.data["avatar"] = CUSTOM
	SaveService.save_data()
	return true



## Портрет как ImageTexture: сжатые текстуры в полигонах с UV на некоторых GPU рисуются белыми.
static func portrait_texture(path: String) -> Texture2D:
	if path == CUSTOM:
		return custom_texture()
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var image := (load(path) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	var texture := ImageTexture.create_from_image(image)
	_cache[path] = texture
	return texture


var _grid: GridContainer
var _hint: Label
var _waiting := false


func _init() -> void:
	super("ПОРТРЕТ")
	_hint = UiStyle.label("", 20, UiStyle.TEXT_DIM, 4)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(panel_width() - 70.0, 0)
	content.add_child(_hint)
	var upload := UiStyle.button("СВОЁ ФОТО С ТЕЛЕФОНА", UiStyle.NEON.darkened(0.45), 28, Vector2(0, 84))
	upload.pressed.connect(func() -> void:
		SoundManager.play(&"ui_click")
		_waiting = true
		_hint.text = "Выбери фото…"
		Platform.pick_file("image/*", MAX_PHOTO))
	content.add_child(upload)
	set_process(true)
	var list := MenuPopups.scroll_list(content)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	list.add_child(_grid)


func _process(_delta: float) -> void:
	if not _waiting:
		return
	var picked_file: Variant = Platform.pick_file_result()
	if picked_file == null:
		return
	_waiting = false
	var info: Dictionary = picked_file
	if info.is_empty():
		_hint.text = "Фото не выбрано."
	elif bool(info.get("too_big", false)):
		_hint.text = "Фото слишком большое (до 12 МБ)."
	elif store_photo(info):
		SoundManager.play(&"ui_confirm", -6.0)
		picked.emit()
		close()
	else:
		_hint.text = "Не получилось прочитать фото. Пришли JPG или PNG."


func _refresh() -> void:
	MenuPopups.clear(_grid)
	_hint.text = "Тап по открытому портрету выбирает его. Остальные открываются по ходу игры."
	var current := str(SaveService.data.get("avatar", ""))
	for entry: Array in ENTRIES:
		var state := _state(entry)
		_grid.add_child(_tile(entry, state, str(entry[0]) == current and state == 0))


## 0 открыт, 1 закрыт, 2 недоступен.
func _state(entry: Array) -> int:
	var kind := str(entry[2])
	var value := int(entry[3])
	if kind == "open":
		return 0
	if kind == "never":
		return 2
	if kind == "story":
		return 0 if SaveService.get_stat("story_missions") >= value else 1
	if kind == "shards":
		return 0 if SaveService.story_shards() >= value else 1
	if kind.begins_with("stat:"):
		return 0 if SaveService.get_stat(kind.substr(5)) >= value else 1
	return 1


func _tile(entry: Array, state: int, selected: bool) -> Control:
	var tile := PortraitTile.new(str(entry[0]), str(entry[1]), state, selected)
	tile.custom_minimum_size = Vector2((panel_width() - 70.0) / float(COLUMNS) - 8.0, TILE + 36.0)
	tile.gui_input.connect(func(event: InputEvent) -> void:
		var tapped := UiStyle.is_tap(event)
		if not tapped:
			return
		if state == 0:
			SaveService.data["avatar"] = str(entry[0])
			SaveService.save_data()
			SoundManager.play(&"ui_confirm", -6.0)
			picked.emit()
			close()
		else:
			_hint.text = "%s: %s" % [entry[1], entry[4]])
	return tile


class PortraitTile:
	extends Control

	var _path: String
	var _title: String
	var _state: int
	var _selected: bool

	func _init(path: String, title: String, state: int, selected: bool) -> void:
		_path = path
		_title = title
		_state = state
		_selected = selected
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var r := minf(size.x, size.y - 30.0) * 0.5 - 4.0
		var c := Vector2(size.x * 0.5, r + 4.0)
		draw_circle(c, r, Color("#22211f"))
		draw_circle(c, r - 3.0, Color("#4f4c47"))
		var tex: Texture2D = null
		if _path.is_empty() and _state == 0:
			tex = MenuWidgets.Avatar.get_texture_for(SaveService.get_character(), SaveService.get_selected_skin())
		elif not _path.is_empty():
			tex = AvatarPicker.portrait_texture(_path)
		if tex != null:
			MenuWidgets.Avatar.draw_round(self, tex, c, r - 4.0)
		if _state != 0:
			draw_circle(c, r - 3.0, Color(0.03, 0.0, 0.08, 0.72 if _state == 1 else 0.88))
			_draw_lock(c)
		var ring := UiStyle.GOLD if _selected else (UiStyle.NEON if _state == 0 else Color(UiStyle.TEXT_DIM, 0.5))
		draw_arc(c, r - 1.5, 0.0, TAU, 48, ring, 5.0 if _selected else 3.0, true)
		var font := ThemeDB.fallback_font
		var color := UiStyle.GOLD if _selected else (UiStyle.TEXT if _state == 0 else Color(UiStyle.TEXT_DIM, 0.7))
		draw_string(font, Vector2(0, size.y - 8.0), _title if _state != 2 else "???", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, color)

	func _draw_lock(c: Vector2) -> void:
		draw_arc(c + Vector2(0, -6), 11.0, PI, TAU, 14, Color("#ffdebb"), 5.0, true)
		var body := Rect2(c + Vector2(-17, -6), Vector2(34, 26))
		draw_rect(body.grow(3.0), Color("#22211f"))
		draw_rect(body, Color("#ffd257") if _state == 1 else Color("#b89c80"))
		draw_circle(c + Vector2(0, 6), 4.0, Color("#22211f"))
