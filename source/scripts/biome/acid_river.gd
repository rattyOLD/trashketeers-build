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
	// COLOR во fragment уже умножен на текстуру — берём чистый цвет вершины.
	COLOR = vec4(rgb * glow, c.a) * tint;
}
"""

var _lights: PackedInt32Array = PackedInt32Array()
var water := false


## points — средняя линия сверху вниз; width — ширина кислоты; bridges — Y мостов; bridge_len — длина настила.
func build(points: PackedVector2Array, width: float, bridges: Array, bridge_len: float) -> void:
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
	for id in _lights:
		EnvLights.remove(id)
	_lights.clear()
