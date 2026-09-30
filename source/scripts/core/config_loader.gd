class_name ConfigLoader
extends RefCounted
## Общие утилиты data-driven конфигов. Формат файла: {"version": N, "<list_key>": [ {...}, ... ]}.
## Все *DB-автолоады используют эти функции, чтобы валидация была одинаково строгой.

const FALLBACK_TEXTURE_SIZE := 32

static var _fallback_texture: GradientTexture2D
static var _tracer_texture: ImageTexture


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: файл не найден: %s" % path)
		return ""
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ConfigLoader: не удалось прочитать %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	return text


## Возвращает корневой объект или пустой словарь, если JSON битый, версия не та
## или нет обязательных массивов.
## Произвольный JSON-объект (платформенные настройки и т.п.); ошибка → пустой словарь.
static func load_json(path: String) -> Dictionary:
	var text := read_text(path)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func parse_root(json_text: String, source: String, supported_version: int, required_arrays: PackedStringArray) -> Dictionary:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("ConfigLoader: JSON-ошибка в %s, строка %d: %s"
				% [source, json.get_error_line(), json.get_error_message()])
		return {}

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ConfigLoader: корень %s должен быть объектом" % source)
		return {}

	var version := int(data.get("version", 0))
	if version != supported_version:
		push_error("ConfigLoader: версия %s = %d не поддерживается (ожидается %d)" % [source, version, supported_version])
		return {}

	for key in required_arrays:
		if typeof(data.get(key)) != TYPE_ARRAY:
			push_error("ConfigLoader: в %s нет массива '%s'" % [source, key])
			return {}

	return data


## Накладывает raw на defaults со строгой проверкой типов. Неизвестные поля и поля
## неверного типа не попадают в результат, а логируются.
static func sanitize(raw: Dictionary, defaults: Dictionary, label: String, skip_keys: PackedStringArray = PackedStringArray()) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	for key in raw:
		if skip_keys.has(key):
			continue
		if not defaults.has(key):
			push_warning("%s: неизвестное поле '%s' (опечатка?)" % [label, key])
			continue
		var value = raw[key]
		if not type_matches(value, defaults[key]):
			push_error("%s: поле '%s' имеет неверный тип (%s), взято значение по умолчанию"
					% [label, key, type_string(typeof(value))])
			continue
		result[key] = value
	return result


static func type_matches(value: Variant, reference: Variant) -> bool:
	var ref_type := typeof(reference)
	var val_type := typeof(value)
	if ref_type == TYPE_FLOAT or ref_type == TYPE_INT:
		return val_type == TYPE_FLOAT or val_type == TYPE_INT
	return val_type == ref_type


## Для обязательных строковых id: пустая строка = запись отбрасывается.
static func require_id(raw: Dictionary, key: String, label: String) -> String:
	var value := str(raw.get(key, "")).strip_edges()
	if value.is_empty():
		push_error("%s: запись без '%s' пропущена: %s" % [label, key, raw])
	return value


static func parse_color(value: String, label: String, fallback: Color = Color.WHITE) -> Color:
	if not Color.html_is_valid(value):
		push_warning("%s: некорректный цвет '%s'" % [label, value])
		return fallback
	return Color.html(value)


## Кэширует и отсутствующие текстуры (как null), чтобы предупреждение выводилось один раз.
static func load_texture(path: String, cache: Dictionary) -> Texture2D:
	if path.is_empty():
		return null
	if cache.has(path):
		return cache[path]

	var texture: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	if texture == null:
		push_warning("ConfigLoader: текстура '%s' не найдена, используется процедурная" % path)

	cache[path] = texture
	return texture


static func get_fallback_texture() -> GradientTexture2D:
	if _fallback_texture != null:
		return _fallback_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.75, Color.WHITE)
	_fallback_texture = GradientTexture2D.new()
	_fallback_texture.gradient = gradient
	_fallback_texture.fill = GradientTexture2D.FILL_RADIAL
	_fallback_texture.fill_from = Vector2(0.5, 0.5)
	_fallback_texture.fill_to = Vector2(1.0, 0.5)
	_fallback_texture.width = FALLBACK_TEXTURE_SIZE
	_fallback_texture.height = FALLBACK_TEXTURE_SIZE
	return _fallback_texture


## Трассер огнестрельной пули 36×12: белое ядро-капсула и мягкий ореол; хвост сзади
## прозрачнее, поэтому пуля читается как летящая даже без шлейфа.
static func get_tracer_texture() -> ImageTexture:
	if _tracer_texture != null:
		return _tracer_texture
	var w := 36
	var h := 12
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var half_h := h * 0.5
	for y in h:
		for x in w:
			var t := float(x) / float(w - 1)
			var core_half := lerpf(1.2, 3.2, t)
			var glow_half := lerpf(2.4, 5.8, t)
			var dy := absf(y + 0.5 - half_h)
			var tail := clampf(t * 1.6, 0.0, 1.0)
			var cap := clampf((w - 1 - x) / 3.0, 0.0, 1.0)
			var alpha := 0.0
			var bright := 0.0
			if dy <= core_half:
				alpha = tail * cap
				bright = 1.0
			elif dy <= glow_half:
				alpha = (1.0 - (dy - core_half) / (glow_half - core_half)) * 0.55 * tail * cap
				bright = 0.8
			image.set_pixel(x, y, Color(bright, bright, bright, alpha))
	_tracer_texture = ImageTexture.create_from_image(image)
	return _tracer_texture
