class_name FrameDB
extends RefCounted
## Покадровые листы персонажей (data/frames.json): атлас кадров с концепт-листа, у каждого кадра —
## прямоугольник в атласе и точка опоры (ноги), клипы — списки кадров с частотой.
## Карты регионов (мех / одежда / акцент / кожа / металл / радужка) в той же раскладке, что атлас,
## поэтому перекраска рига (градиентные карты) работает и на кадрах без изменений шейдера.

const CONFIG_PATH := "res://data/frames.json"

static var _sheets: Dictionary = {}
static var _loaded := false


static func has_sheet(sheet_id: String) -> bool:
	_load()
	return _sheets.has(sheet_id)


static func release_textures() -> void:
	for sheet: Dictionary in _sheets.values():
		sheet["texture"] = null


static func get_sheet(sheet_id: String) -> Dictionary:
	_load()
	var sheet: Dictionary = _sheets.get(sheet_id, {})
	if not sheet.is_empty() and sheet["texture"] == null:
		sheet["texture"] = load(sheet["texture_path"])
	return sheet


## Кадр клипа по «фазе» (накопленные кадры). Незацикленный клип замирает на последнем кадре.
static func clip_frame(sheet: Dictionary, clip_name: String, phase: float) -> int:
	var clip: Dictionary = (sheet["clips"] as Dictionary).get(clip_name, {})
	if clip.is_empty():
		return 0
	var frames: PackedInt32Array = clip["frames"]
	var step := int(floor(maxf(phase, 0.0)))
	if clip["loop"]:
		return frames[step % frames.size()]
	return frames[mini(step, frames.size() - 1)]


static func clip_length(sheet: Dictionary, clip_name: String) -> int:
	var clip: Dictionary = (sheet["clips"] as Dictionary).get(clip_name, {})
	return (clip["frames"] as PackedInt32Array).size() if not clip.is_empty() else 0


static func clip_fps(sheet: Dictionary, clip_name: String) -> float:
	var clip: Dictionary = (sheet["clips"] as Dictionary).get(clip_name, {})
	return float(clip.get("fps", 8.0))


static func has_clip(sheet: Dictionary, clip_name: String) -> bool:
	return (sheet["clips"] as Dictionary).has(clip_name)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var root := ConfigLoader.load_json(CONFIG_PATH)
	var sheets: Dictionary = root.get("sheets", {})
	for sheet_id in sheets:
		var parsed := _parse(str(sheet_id), sheets[sheet_id])
		if not parsed.is_empty():
			_sheets[str(sheet_id)] = parsed


static func _parse(sheet_id: String, raw: Dictionary) -> Dictionary:
	var texture_path := str(raw.get("texture", ""))
	if not ResourceLoader.exists(texture_path):
		push_warning("FrameDB: нет атласа %s" % texture_path)
		return {}
	var rects: Array[Rect2] = []
	var pivots := PackedVector2Array()
	for f in raw.get("frames", []):
		rects.append(Rect2(float(f[0]), float(f[1]), float(f[2]), float(f[3])))
		pivots.append(Vector2(float(f[4]), float(f[5])))
	if rects.is_empty():
		return {}
	var clips: Dictionary = {}
	var raw_clips: Dictionary = raw.get("clips", {})
	for clip_name in raw_clips:
		var c: Dictionary = raw_clips[clip_name]
		var frames := PackedInt32Array()
		for index in c.get("frames", []):
			frames.append(clampi(int(index), 0, rects.size() - 1))
		if frames.is_empty():
			continue
		clips[str(clip_name)] = {"frames": frames, "fps": float(c.get("fps", 8.0)), "loop": bool(c.get("loop", true))}
	var ranges: Dictionary = {}
	var raw_ranges: Dictionary = raw.get("region_ranges", {})
	for region in raw_ranges:
		var r: Array = raw_ranges[region]
		ranges[str(region)] = Vector2(float(r[0]), float(r[1]))
	var regions := PackedStringArray()
	for p in raw.get("regions", []):
		regions.append(str(p))
	return {
		"id": sheet_id,
		"texture": null,
		"texture_path": texture_path,
		"regions": regions,
		"region_ranges": ranges,
		"rects": rects,
		"pivots": pivots,
		"clips": clips,
		"faces_right": bool(raw.get("faces_right", true)),
	}
