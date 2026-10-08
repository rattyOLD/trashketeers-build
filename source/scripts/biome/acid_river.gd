class_name AcidRiver
extends Node2D
## Кислотная протока через выживание на Свалке (в Банке — голубой пруд-канал, water = true): течёт из-под верхнего забора под нижний, извиваясь;
## через неё 2–3 моста — естественные «горлышки» для толпы. Кислота (тайл Астры, течёт), по краям —
## ржавые уступы, на мостах — настилы Астры с огнями. Коллизию (слой TERRAIN: держит пеших, пули
## пролетают) и клетки сетки ставит LevelSpawner; здесь только картинка и зелёный свет.

const ACID := "res://assets/terrain/acid_01.png"
const LEDGE := "res://assets/terrain/ledge_scrap.png"
const BRIDGES := ["res://assets/terrain/bridge_scrap.png", "res://assets/terrain/bridge_steel.png", "res://assets/terrain/bridge_wood.png"]
const BANK_WIDTH := 30.0
const SHADER := """
shader_type canvas_item;
uniform float flow = 0.06;
uniform float water = 0.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec2 uv = UV + vec2(TIME * flow, sin(TIME * 0.7 + UV.x * 3.0) * 0.015);
	vec4 c = texture(TEXTURE, uv);
	float glow = 0.85 + 0.15 * sin(TIME * 2.0 + UV.x * 6.0);
	vec3 rgb = c.rgb;
	if (water > 0.5) {
		// Та же текстура, перекрашенная по яркости в бирюзу бассейна: блики светлые, глубина синяя.
		float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
		rgb = mix(vec3(0.05, 0.32, 0.62), vec3(0.75, 0.97, 1.0), smoothstep(0.35, 0.95, l));
	}
	// Блики: редкие бегущие светлые искры по поверхности — жидкость, а не ковёр.
	float spec = pow(max(0.0, sin(UV.x * 9.0 + TIME * 1.7) * sin(UV.y * 6.0 - TIME * 1.1 + UV.x * 2.0)), 14.0);
	rgb += vec3(spec * (water > 0.5 ? 0.55 : 0.35));
	// COLOR во fragment уже умножен на текстуру — берём чистый цвет вершины.
	COLOR = vec4(rgb * glow, c.a) * tint;
}
"""

var _lights: PackedInt32Array = PackedInt32Array()
var water := false
## Герой (только у протоки на арене; у истока/устья за забором — null): вброд, звук, фон.
var player: Player
const WADE_SLOW_ACID := 0.55
const WADE_SLOW_WATER := 0.65
## Кислота жжёт сильно: перейти вброд можно (короткий путь от толпы), но это дорого — около 25 HP в секунду.
const ACID_DAMAGE := 16.0
const ACID_TICK := 0.45
const AMBIENT_RANGE := 900.0
var _points := PackedVector2Array()
var _width := 0.0
var _bridges: Array = []
var _bridge_len := 0.0
var _inside := false
var _burn := 0.0
var _check := 0.0
var _loop := -1


## points — средняя линия сверху вниз; width — ширина кислоты; bridges — Y мостов; bridge_len — длина настила.
func build(points: PackedVector2Array, width: float, bridges: Array, bridge_len: float) -> void:
	_points = points
	_width = width
	_bridge_len = bridge_len
	set_process(false)
	# Мокрая тёмная кайма — протока врезана в землю.
	_line(points, width + BANK_WIDTH * 2.6, null, Color(0.02, 0.05, 0.02, 0.45) if not water else Color(0.1, 0.2, 0.1, 0.35))
	var acid := _line(points, width, load(ACID) as Texture2D, Color(0.92, 1.0, 0.86))
	# Вода всегда через шейдер (перекраска); кислота на качестве 0 — без течения.
	if acid != null and (water or SaveService.get_quality() > 0):
		var shader := Shader.new()
		shader.code = SHADER
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("water", 1.0 if water else 0.0)
		mat.set_shader_parameter("flow", 0.06 if not water else 0.025)
		acid.material = mat
	var ledge := load(LEDGE if not water else "res://assets/terrain/ledge_concrete.png") as Texture2D
	for side in [-1.0, 1.0]:
		_line(_offset(points, side * (width * 0.5 + BANK_WIDTH * 0.35)), BANK_WIDTH, ledge, Color.WHITE)
	for i in bridges.size():
		var y: float = bridges[i]
		var kinds := BRIDGES if not water else ["res://assets/terrain/bridge_wood.png", "res://assets/terrain/bridge_steel.png"]
		var tex := load(kinds[i % kinds.size()]) as Texture2D
		if tex == null:
			continue
		var path: String = kinds[i % kinds.size()]
		_bridges.append([y, &"metal" if path.contains("steel") else &"wood"])
		var deck := Sprite2D.new()
		deck.texture = tex
		deck.scale = Vector2.ONE * bridge_len / tex.get_width()
		deck.position = Vector2(_x_at(points, y), y)
		add_child(deck)
	var step := 340.0
	var travelled := 0.0
	for k in range(1, points.size()):
		travelled += points[k].distance_to(points[k - 1])
		if travelled >= step:
			travelled = 0.0
			_lights.append(EnvLights.add(points[k], Color("#7dff4a") if not water else Color("#6fd8ff"), 260.0, 0.45 if not water else 0.3))


## Водосток в линии забора: бетонный оголовок поперёк русла и тёмный зев трубы — протока выходит
## из-под забора (top) или уходит под него, а не начинается из ниоткуда.
func add_culvert(x: float, y: float, top: bool) -> void:
	var span := _width + 120.0
	var mouth := Polygon2D.new()
	var depth := 70.0 if top else -70.0
	mouth.polygon = PackedVector2Array([Vector2(x - _width * 0.5, y), Vector2(x + _width * 0.5, y),
		Vector2(x + _width * 0.42, y - depth), Vector2(x - _width * 0.42, y - depth)])
	mouth.vertex_colors = PackedColorArray([Color(0.02, 0.03, 0.02, 0.0), Color(0.02, 0.03, 0.02, 0.0), Color(0.01, 0.02, 0.01, 0.9), Color(0.01, 0.02, 0.01, 0.9)])
	add_child(mouth)
	var wall := Sprite2D.new()
	wall.texture = load("res://assets/terrain/ledge_concrete.png") as Texture2D
	if wall.texture == null:
		return
	wall.scale = Vector2(span / wall.texture.get_width(), 0.9)
	wall.position = Vector2(x, y - (24.0 if top else -6.0))
	add_child(wall)
	# Пена/брызги у выхода из трубы: стоячая светлая полоса.
	var foam := Line2D.new()
	foam.points = PackedVector2Array([Vector2(x - _width * 0.45, y + (14.0 if top else -14.0)), Vector2(x + _width * 0.45, y + (14.0 if top else -14.0))])
	foam.width = 10.0
	foam.default_color = Color(0.8, 1.0, 0.6, 0.35) if not water else Color(0.85, 0.97, 1.0, 0.45)
	add_child(foam)


## Подключить героя: вброд, звуки и фон протоки.
func attach(target: Player) -> void:
	player = target
	set_process(player != null)


## Поверхность под точкой: мост (wood/metal), протока (acid/water) или &"" — не протока.
func surface_at(p: Vector2) -> StringName:
	if _points.is_empty() or p.y < _points[0].y or p.y > _points[_points.size() - 1].y:
		return &""
	var dx := absf(p.x - _x_at(_points, p.y))
	for b: Array in _bridges:
		if absf(p.y - float(b[0])) < 46.0 and dx < _bridge_len * 0.5:
			return b[1]
	if dx < _width * 0.5:
		return &"water" if water else &"acid"
	return &""


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.1
	var p := player.global_position
	var surface := surface_at(p)
	var wading := surface == &"acid" or surface == &"water"
	if wading and not player.is_dead:
		if not _inside:
			_inside = true
			_burn = 0.0
			SoundManager.play(&"enter_water" if water else &"enter_acid", 0.0, true)
		player.terrain_slow = WADE_SLOW_WATER if water else WADE_SLOW_ACID
		if not water:
			_burn -= 0.1
			if _burn <= 0.0:
				_burn = ACID_TICK
				Player.last_source = &"acid"
				player.take_damage(ACID_DAMAGE, Vector2.ZERO)
	elif _inside:
		_inside = false
		player.terrain_slow = 1.0
	# Фон протоки: громче у берега, тише вдали.
	var dist := absf(p.x - _x_at(_points, clampf(p.y, _points[0].y, _points[_points.size() - 1].y)))
	if _loop == -1 and dist < AMBIENT_RANGE:
		_loop = SoundManager.play_loop(&"amb_water" if water else &"amb_acid")
	if _loop != -1:
		var base: float = SoundManager.SFX[&"amb_water" if water else &"amb_acid"][0]
		SoundManager.set_loop_volume(_loop, base - 22.0 * clampf(dist / AMBIENT_RANGE, 0.0, 1.0) - (40.0 if dist >= AMBIENT_RANGE else 0.0))


static func _x_at(points: PackedVector2Array, y: float) -> float:
	for k in range(1, points.size()):
		if points[k].y >= y:
			var t := inverse_lerp(points[k - 1].y, points[k].y, y)
			return lerpf(points[k - 1].x, points[k].x, t)
	return points[points.size() - 1].x


static func _offset(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points.size():
		var a := points[maxi(k - 1, 0)]
		var b := points[mini(k + 1, points.size() - 1)]
		out.append(points[k] + (b - a).normalized().orthogonal() * distance)
	return out


func _line(points: PackedVector2Array, width: float, texture: Texture2D, color: Color) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	if texture != null:
		line.texture = texture
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.light_mask = BiomeLayers.LIGHT_MASK_FLOOR
	add_child(line)
	return line


func _exit_tree() -> void:
	if _loop != -1:
		SoundManager.stop_loop(_loop)
		_loop = -1
	if _inside and player != null and is_instance_valid(player):
		player.terrain_slow = 1.0
	for id in _lights:
		EnvLights.remove(id)
	_lights.clear()
