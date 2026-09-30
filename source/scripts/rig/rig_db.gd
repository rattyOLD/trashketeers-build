class_name RigDB
extends RefCounted
## Описания ригов персонажей (data/rigs.json) и их служебные текстуры.
## Карты весов и регионов — данные, а не картинки: они лежат в проекте как «keep»-файлы
## (без импорта), читаются байтами и превращаются в ImageTexture как есть. Импорт Godot
## «чинил» бы RGB под нулевой альфой и сжимал каналы — веса костей бы поплыли.

const CONFIG_PATH := "res://data/rigs.json"
const BONE_COUNT := 12

static var _rigs: Dictionary = {}
static var _loaded := false
static var _data_textures: Dictionary = {}


static func get_rig(rig_id: String) -> Dictionary:
	_load()
	var rig: Dictionary = _rigs.get(rig_id, {})
	if not rig.is_empty() and rig["texture"] == null:
		rig["texture"] = load(rig["texture_path"])
	return rig


static func has_rig(rig_id: String) -> bool:
	_load()
	return _rigs.has(rig_id)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var root := ConfigLoader.load_json(CONFIG_PATH)
	for raw in root.get("rigs", []):
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("id"):
			continue
		var rig := _parse(raw)
		if not rig.is_empty():
			_rigs[str(raw["id"])] = rig


static func _parse(raw: Dictionary) -> Dictionary:
	var texture_path := str(raw.get("texture", ""))
	if not ResourceLoader.exists(texture_path):
		push_warning("RigDB: нет текстуры %s" % texture_path)
		return {}
	var bones := PackedVector2Array()
	for p in raw.get("bones", []):
		bones.append(Vector2(float(p[0]), float(p[1])))
	bones.resize(BONE_COUNT)
	var eyes: Array[Vector4] = []
	for e in raw.get("eyes", []):
		eyes.append(Vector4(float(e[0]), float(e[1]), float(e[2]), float(e[3])))
	while eyes.size() < 2:
		eyes.append(Vector4(-1, -1, -1, -1))
	var wheel := Vector4(-1, -1, -1, -1)
	if raw.get("wheel") is Array:
		var w: Array = raw["wheel"]
		wheel = Vector4(float(w[0]), float(w[1]), float(w[2]), float(w[3]))
	var names: Dictionary = {}
	var list: Array = raw.get("bone_names", [])
	for i in list.size():
		names[str(list[i])] = i
	return {
		"id": str(raw["id"]),
		"texture": null,
		"texture_path": texture_path,
		"weights": _paths(raw.get("weights", [])),
		"regions": _paths(raw.get("regions", [])),
		"pivot": Vector2(float(raw["pivot"][0]), float(raw["pivot"][1])),
		"grid": int(raw.get("grid", 12)),
		"bones": bones,
		"bone_index": names,
		"eyes": eyes,
		"wheel": wheel,
		"extra": raw.get("extra", {}),
	}


static func _paths(list: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p in list:
		out.append(str(p))
	return out


## Текстура-данные без импорта (кэш по пути). null, если файла нет.
static func data_texture(path: String) -> Texture2D:
	if _data_textures.has(path):
		return _data_textures[path]
	var texture: Texture2D = null
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		push_warning("RigDB: не удалось прочитать %s" % path)
	_data_textures[path] = texture
	return texture
