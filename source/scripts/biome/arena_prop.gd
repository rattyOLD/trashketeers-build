class_name ArenaProp
extends StaticBody2D
## Проп арены с концепт-листа (data/props.json): спрайт, коллизия-основание, свет, дымок.
## Y-Sort: origin — середина переднего края основания, спрайт рисуется вверх от него, коллизия —
## прямоугольник footprint над origin (глубина основания). «Плоские» пропы (flat) — на слое
## декалей без коллизии. Свет — PointLight2D только на пол (как у неона) + запись в EnvLights,
## чтобы персонажи рядом подкрашивались; мерцание и дым считаются только на экране.

const SMOKE_PUFFS := 6
const SMOKE_LIFE := 2.4

static var _defs: Dictionary = {}
static var _textures: Dictionary = {}

var def_id := ""
var def: Dictionary = {}
var sprite: Sprite2D

var _light: PointLight2D
var _light_energy := 0.0
var _flicker := 0.0
var _light_id := -1
var _time := 0.0
var _smoke_at := Vector2.INF
var _smoke: PackedVector3Array = PackedVector3Array()


## Растения качаются на ветру: верх спрайта гуляет по синусу, фаза — от положения в мире (не в унисон).
## Один общий материал на все растения — отрисовка не дробится.
const SWAY_IDS := ["spruce", "bush", "bush_low", "planter"]
const SWAY_SHADER := """
shader_type canvas_item;
uniform float amount = 5.0;
void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float top = 1.0 - UV.y;
	float gust = 0.7 + 0.3 * sin(TIME * 0.37 + world.y * 0.002);
	VERTEX.x += sin(TIME * 1.7 + world.x * 0.013 + world.y * 0.007) * amount * top * top * gust;
}
"""
static var _sway: ShaderMaterial


## Попадание в куст/дерево: короткое покачивание (от основания) — растение «отзывается».
func rustle() -> void:
	if sprite == null or (has_meta("rustling") and bool(get_meta("rustling"))):
		return
	set_meta("rustling", true)
	var tween := create_tween()
	tween.tween_property(sprite, "rotation", 0.07, 0.07)
	tween.tween_property(sprite, "rotation", -0.05, 0.1)
	tween.tween_property(sprite, "rotation", 0.0, 0.12)
	tween.tween_callback(func() -> void: set_meta("rustling", false))


static func sway_material() -> ShaderMaterial:
	if _sway == null:
		var shader := Shader.new()
		shader.code = SWAY_SHADER
		_sway = ShaderMaterial.new()
		_sway.shader = shader
	return _sway


static func get_def(prop_id: String) -> Dictionary:
	if _defs.is_empty():
		var root := ConfigLoader.load_json("res://data/props.json")
		_defs = root.get("props", {})
	return _defs.get(prop_id, {})


static func texture_of(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


static func is_flat(prop_id: String) -> bool:
	return bool(get_def(prop_id).get("flat", false))


static func footprint(prop_id: String) -> Vector2:
	var f: Array = get_def(prop_id).get("footprint", [0, 0])
	return Vector2(float(f[0]), float(f[1])) if f.size() >= 2 else Vector2.ZERO


## Форма коллизии и её центр относительно origin (генератор проверяет по ним наложения).
static func make_shape(prop_id: String) -> RectangleShape2D:
	var shape := RectangleShape2D.new()
	shape.size = footprint(prop_id).max(Vector2.ONE)
	return shape


static func shape_offset(prop_id: String) -> Vector2:
	return Vector2(0, -footprint(prop_id).y * 0.5)


## Экранный размер спрайта в мире (для раскладки бордюра).
static func visual_size(prop_id: String) -> Vector2:
	var d := get_def(prop_id)
	var tex := texture_of(str(d.get("texture", "")))
	if tex == null:
		return Vector2(64, 64)
	var s := float(d.get("width", tex.get_width())) / tex.get_width()
	return tex.get_size() * s


func setup(prop_id: String, solid: bool = true, flip: int = 0) -> void:
	def_id = prop_id
	def = get_def(prop_id)
	collision_layer = PhysicsLayers.OBSTACLE if solid and not def.get("flat", false) else 0
	collision_mask = 0
	sprite = make_sprite(str(def.get("texture", "")), float(def.get("width", 0.0)))
	if def.get("flip", false):
		sprite.flip_h = (flip > 0) if flip != 0 else randf() < 0.5
	if SWAY_IDS.has(prop_id) and SaveService.get_quality() > 0:
		sprite.material = sway_material()
	add_child(sprite)
	if collision_layer != 0:
		var collision := CollisionShape2D.new()
		collision.shape = make_shape(prop_id)
		collision.position = shape_offset(prop_id)
		add_child(collision)
	if def.has("light") and SaveService.are_prop_lights_enabled():
		_build_light(def["light"])
	elif def.has("light"):
		_register_plain_light.call_deferred(def["light"])
	if def.has("smoke"):
		var s: Array = def["smoke"]
		_smoke_at = Vector2(float(s[0]) * (-1.0 if sprite.flip_h else 1.0), float(s[1]))
		for i in SMOKE_PUFFS:
			_smoke.append(Vector3(0, 0, -float(i) / SMOKE_PUFFS * SMOKE_LIFE))
	var animated := _light != null and _flicker > 0.0 or _smoke_at != Vector2.INF
	set_process(animated)
	if animated:
		var enabler := VisibleOnScreenEnabler2D.new()
		enabler.rect = Rect2(-200, -320, 400, 420)
		enabler.enable_node_path = NodePath("..")
		add_child(enabler)


## Спрайт с опорой в середине низа: так origin пропа = точка касания пола.
static func make_sprite(path: String, width: float) -> Sprite2D:
	var s := Sprite2D.new()
	var tex := texture_of(path)
	s.texture = tex
	if tex == null:
		return s
	var k := width / tex.get_width() if width > 0.0 else 1.0
	s.scale = Vector2.ONE * k
	s.centered = true
	s.offset = Vector2(0, -tex.get_height() * 0.5 + tex.get_height() * 0.03)
	return s


func _build_light(cfg: Dictionary) -> void:
	var color := Color(str(cfg.get("color", "#ffffff")))
	var radius := float(cfg.get("radius", 200.0))
	_light_energy = float(cfg.get("energy", 0.5))
	_flicker = float(cfg.get("flicker", 0.0))
	var offset: Array = cfg.get("offset", [0, 0])
	var cast: Array = cfg.get("cast", [0, 0])
	_light = PointLight2D.new()
	_light.texture = NeonSign.get_light_texture()
	_light.texture_scale = radius / 64.0
	_light.color = color
	_light.energy = _light_energy
	_light.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
	_light.position = Vector2(float(cast[0]), float(cast[1]) * 0.5 + 10.0)
	add_child(_light)
	var glow_at := Vector2(float(offset[0]), float(offset[1]))
	_register_light.call_deferred(color, radius, glow_at)


func _register_light(color: Color, radius: float, _glow_at: Vector2) -> void:
	if is_inside_tree():
		_light_id = EnvLights.add(_light.global_position, color, radius * 0.9, 0.6, _light)


## Без PointLight2D (качество «Эконом»): источник только в EnvLights — для карты освещения и подсветки персонажей.
func _register_plain_light(cfg: Dictionary) -> void:
	if not is_inside_tree():
		return
	var cast: Array = cfg.get("cast", [0, 0])
	var at := global_position + Vector2(float(cast[0]), float(cast[1]) * 0.5 + 10.0)
	_light_id = EnvLights.add(at, Color(str(cfg.get("color", "#ffffff"))), float(cfg.get("radius", 200.0)) * 0.9, 0.6)


func _exit_tree() -> void:
	EnvLights.remove(_light_id)
	_light_id = -1


func _process(delta: float) -> void:
	_time += delta
	if _light != null and _flicker > 0.0:
		var n := sin(_time * 13.0) * 0.5 + sin(_time * 29.0 + 1.3) * 0.3 + sin(_time * 3.1) * 0.2
		_light.energy = _light_energy * (1.0 + n * _flicker)
	if _smoke_at != Vector2.INF:
		for i in _smoke.size():
			var p := _smoke[i]
			p.z += delta
			if p.z > SMOKE_LIFE:
				p = Vector3(randf_range(-4, 4), 0, 0.0)
			_smoke[i] = p
		queue_redraw()


func _draw() -> void:
	if _smoke_at == Vector2.INF:
		return
	for p in _smoke:
		if p.z < 0.0:
			continue
		var t := p.z / SMOKE_LIFE
		var at := _smoke_at + Vector2(p.x + sin(t * 5.0 + p.x) * 6.0, -t * 70.0)
		draw_circle(at, 7.0 + t * 16.0, Color(0.75, 0.75, 0.85, 0.28 * (1.0 - t)))
