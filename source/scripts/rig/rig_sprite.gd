class_name RigSprite
extends MeshInstance2D
## Персонаж на GPU-риге: сетка поверх текстуры, деформация — в shaders/rig2d.gdshader.
## Позу задают массивы angles / offsets / stretches (по кости), apply_pose() отправляет их в шейдер
## одним вызовом на массив. Вершины сетки — в пикселях текстуры относительно pivot рига, так что
## позиция узла = точка опоры персонажа, а масштаб узла = масштаб спрайта.
## Сетка строится один раз на риг (кэш) и пропускает полностью прозрачные ячейки.
## Покадровый режим (setup_frames): тот же шейдер без костей, сетка — квад текущего кадра атласа
## (FrameDB); перекраска регионов, обводка, вспышка и свет окружения работают так же.

const SHADER_PATH := "res://shaders/rig2d.gdshader"
## Внешность особи (окрас, обводка, свет) — переносится на «труп» того же вида.
const LOOK_PARAMS: Array[StringName] = [&"recolor_enabled", &"regions0", &"regions1", &"grad_dark", &"grad_mid",
	&"grad_light", &"grad_range", &"hue_shift", &"tint", &"outline_px", &"outline_color", &"env_light"]

static var _shader: Shader
static var _meshes: Dictionary = {}

var rig: Dictionary = {}
var angles := PackedFloat32Array()
var offsets := PackedVector2Array()
var stretches := PackedVector2Array()
var shader_material: ShaderMaterial
var frame_sheet: Dictionary = {}
var frame_index := -1
var _frame_margin := 0.0


func _init() -> void:
	angles.resize(RigDB.BONE_COUNT)
	offsets.resize(RigDB.BONE_COUNT)
	stretches.resize(RigDB.BONE_COUNT)
	shader_material = ShaderMaterial.new()
	if _shader == null:
		_shader = load(SHADER_PATH)
	shader_material.shader = _shader
	material = shader_material


## margin — запас сетки за краем текстуры под шейдерную обводку (px текстуры).
## cull — выкидывать прозрачные ячейки (массовые враги); герою с аксессуарами вне силуэта — false.
func setup(rig_id: String, margin: float = 0.0, cull: bool = true) -> bool:
	rig = RigDB.get_rig(rig_id)
	if rig.is_empty():
		return false
	frame_sheet = {}
	frame_index = -1
	texture = rig["texture"]
	mesh = _get_mesh(rig, margin, cull)
	var weights: PackedStringArray = rig["weights"]
	var has_rig := weights.size() >= 3
	shader_material.set_shader_parameter("rig_enabled", has_rig)
	if has_rig:
		for i in 3:
			shader_material.set_shader_parameter("weights%d" % i, RigDB.data_texture(weights[i]))
		shader_material.set_shader_parameter("bone_pivot", rig["bones"])
	var regions: PackedStringArray = rig["regions"]
	if regions.size() >= 2:
		shader_material.set_shader_parameter("regions0", RigDB.data_texture(regions[0]))
		shader_material.set_shader_parameter("regions1", RigDB.data_texture(regions[1]))
	var eyes: Array = rig["eyes"]
	shader_material.set_shader_parameter("eye0", eyes[0])
	shader_material.set_shader_parameter("eye1", eyes[1])
	shader_material.set_shader_parameter("wheel", rig["wheel"])
	var wheel_px: Array = (rig["extra"] as Dictionary).get("wheel_px", [0, 0])
	shader_material.set_shader_parameter("wheel_radii", Vector2(float(wheel_px[0]), float(wheel_px[1])))
	reset_pose()
	apply_pose()
	return true


## Сетка рига строится по альфе текстуры: в вебе get_image() — это чтение из видеопамяти
## (ReadPixels, стоп конвейера). Прогрев на загрузочном экране убирает такие фризы из боя.
static func prewarm(rig_id: String, margin: float, cull: bool = true) -> void:
	var rig_data := RigDB.get_rig(rig_id)
	if rig_data.is_empty():
		return
	_get_mesh(rig_data, margin, cull)
	for path in rig_data["weights"]:
		RigDB.data_texture(path)
	for path in rig_data["regions"]:
		RigDB.data_texture(path)


## Запасной вариант без рига (нет описания в rigs.json): та же сетка и шейдер, кости выключены.
func setup_texture(tex: Texture2D, margin: float = 0.0) -> void:
	rig = {"id": "plain:%d" % tex.get_instance_id(), "texture": tex, "pivot": tex.get_size() * 0.5, "grid": 64,
		"bones": PackedVector2Array(), "bone_index": {}, "eyes": [Vector4(-1, -1, -1, -1), Vector4(-1, -1, -1, -1)],
		"wheel": Vector4(-1, -1, -1, -1), "extra": {}, "weights": PackedStringArray(), "regions": PackedStringArray()}
	(rig["bones"] as PackedVector2Array).resize(RigDB.BONE_COUNT)
	frame_sheet = {}
	frame_index = -1
	texture = tex
	mesh = _get_mesh(rig, margin, false)
	shader_material.set_shader_parameter("rig_enabled", false)
	shader_material.set_shader_parameter("recolor_enabled", false)
	shader_material.set_shader_parameter("eye0", Vector4(-1, -1, -1, -1))
	shader_material.set_shader_parameter("eye1", Vector4(-1, -1, -1, -1))
	shader_material.set_shader_parameter("wheel", Vector4(-1, -1, -1, -1))
	reset_pose()
	apply_pose()


## Покадровый персонаж из data/frames.json. margin — запас квада под обводку (px атласа);
## между кадрами в атласе оставлен зазор больше него, поэтому соседи не просвечивают.
func setup_frames(sheet_id: String, margin: float = 0.0) -> bool:
	frame_sheet = FrameDB.get_sheet(sheet_id)
	if frame_sheet.is_empty():
		return false
	rig = {"id": "frames:" + sheet_id, "bones": PackedVector2Array(), "bone_index": {}}
	(rig["bones"] as PackedVector2Array).resize(RigDB.BONE_COUNT)
	texture = frame_sheet["texture"]
	_frame_margin = margin
	shader_material.set_shader_parameter("rig_enabled", false)
	var regions: PackedStringArray = frame_sheet["regions"]
	if regions.size() >= 2:
		shader_material.set_shader_parameter("regions0", RigDB.data_texture(regions[0]))
		shader_material.set_shader_parameter("regions1", RigDB.data_texture(regions[1]))
	shader_material.set_shader_parameter("eye0", Vector4(-1, -1, -1, -1))
	shader_material.set_shader_parameter("eye1", Vector4(-1, -1, -1, -1))
	shader_material.set_shader_parameter("wheel", Vector4(-1, -1, -1, -1))
	reset_pose()
	apply_pose()
	frame_index = -1
	set_frame(0)
	return true


func set_frame(index: int) -> void:
	if index == frame_index or frame_sheet.is_empty():
		return
	frame_index = index
	mesh = _get_frame_mesh(frame_sheet, index, _frame_margin)


func is_framed() -> bool:
	return not frame_sheet.is_empty()


func copy_look(other: RigSprite) -> void:
	for param in LOOK_PARAMS:
		shader_material.set_shader_parameter(param, other.shader_material.get_shader_parameter(param))


## Трансформ точки, целиком принадлежащей цепочке костей (индексы по возрастанию = от ребёнка
## к родителю) — например, голова∘корпус для аксессуаров на голове.
func chain_transform(bones: Array) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var pivots: PackedVector2Array = rig["bones"]
	for i in bones:
		var index: int = i
		var local := Transform2D(angles[index], Vector2.ONE + stretches[index], 0.0, pivots[index] + offsets[index])
		xf = local * Transform2D(0.0, -pivots[index]) * xf
	return xf


func bone(bone_name: String) -> int:
	return int((rig.get("bone_index", {}) as Dictionary).get(bone_name, -1))


func bone_pivot(index: int) -> Vector2:
	return (rig["bones"] as PackedVector2Array)[index]


func reset_pose() -> void:
	angles.fill(0.0)
	offsets.fill(Vector2.ZERO)
	stretches.fill(Vector2.ZERO)


func apply_pose() -> void:
	shader_material.set_shader_parameter("bone_angle", angles)
	shader_material.set_shader_parameter("bone_offset", offsets)
	shader_material.set_shader_parameter("bone_stretch", stretches)


func set_param(param: StringName, value: Variant) -> void:
	shader_material.set_shader_parameter(param, value)


## Где окажется точка покоя p (px текстуры относительно pivot) после текущей позы — та же
## математика, что в шейдере, но для заданных весов (например, плечо, на 100% в корпусе).
func deform_point(p: Vector2, weights: Dictionary) -> Vector2:
	var pivots: PackedVector2Array = rig["bones"]
	for i in RigDB.BONE_COUNT:
		var w := float(weights.get(i, 0.0))
		if w <= 0.0:
			continue
		var local := (p - pivots[i]) * (Vector2.ONE + stretches[i] * w)
		p = pivots[i] + local.rotated(angles[i] * w) + offsets[i] * w
	return p


static func _get_mesh(rig_data: Dictionary, margin: float, cull: bool) -> ArrayMesh:
	var key := "%s:%d:%s" % [rig_data["id"], int(margin), cull]
	if _meshes.has(key):
		return _meshes[key]
	var tex: Texture2D = rig_data["texture"]
	var size := tex.get_size()
	var pivot: Vector2 = rig_data["pivot"]
	var step := float(rig_data["grid"])
	var image: Image = tex.get_image() if cull else null
	if image != null and image.is_compressed():
		image.decompress()
	var x0 := -margin
	var y0 := -margin
	var cols := int(ceil((size.x + margin * 2.0) / step))
	var rows := int(ceil((size.y + margin * 2.0) / step))
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var index_of: Dictionary = {}
	var indices := PackedInt32Array()
	for row in rows:
		for col in cols:
			var cell := Rect2(x0 + col * step, y0 + row * step, step, step)
			if image != null and _is_empty(image, cell.grow(margin + 3.0)):
				continue
			var corners := [Vector2i(col, row), Vector2i(col + 1, row), Vector2i(col + 1, row + 1), Vector2i(col, row + 1)]
			var ids := PackedInt32Array()
			for c in corners:
				if not index_of.has(c):
					var pos := Vector2(minf(x0 + c.x * step, size.x + margin), minf(y0 + c.y * step, size.y + margin))
					index_of[c] = verts.size()
					verts.append(pos - pivot)
					uvs.append(pos / size)
				ids.append(index_of[c])
			indices.append_array(PackedInt32Array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	_meshes[key] = array_mesh
	return array_mesh


static func _get_frame_mesh(sheet: Dictionary, index: int, margin: float) -> ArrayMesh:
	var key := "frame:%s:%d:%d" % [sheet["id"], index, int(margin)]
	if _meshes.has(key):
		return _meshes[key]
	var rect: Rect2 = (sheet["rects"] as Array)[index]
	var pivot: Vector2 = (sheet["pivots"] as PackedVector2Array)[index]
	var size := (sheet["texture"] as Texture2D).get_size()
	var outer := rect.grow(margin)
	var origin := rect.position + pivot
	var corners := [outer.position, Vector2(outer.end.x, outer.position.y), outer.end, Vector2(outer.position.x, outer.end.y)]
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for c in corners:
		verts.append(c - origin)
		uvs.append(c / size)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	_meshes[key] = array_mesh
	return array_mesh


static func _is_empty(image: Image, area: Rect2) -> bool:
	var rect := Rect2i(area.position.floor(), area.size.ceil()).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return true
	return image.get_region(rect).is_invisible()
