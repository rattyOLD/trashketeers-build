class_name AmbientLife
extends Node
## Живой фон арен: жители, костры, вороны. Нарезка листов Астры лежит в data/npc_frames.json ([x, y, w, h] на кадр),
## сами листы — assets/npc/. Актёры без коллизий, сортируются по Y вместе с миром. Режимы: loop (цикл кадров),
## idle (две позы по очереди), wander (бродит у дома), crow (улетает от взрывов и возвращается), prop (статика).
## Взрыв рядом пугает всех, кроме огня и статики: житель отбегает и возвращается.

const FRAMES_PATH := "res://data/npc_frames.json"
const SHEET_DIR := "res://assets/npc/"
const SCARE_MARGIN := 260.0

## Режим и масштаб по умолчанию для каждого листа.
const DEFS := {
	"npc_rat_worker": {"mode": "idle", "scale": 0.58},
	"npc_rat_grandma": {"mode": "wander", "scale": 0.56},
	"npc_pig_guard": {"mode": "idle", "scale": 0.6},
	"npc_pig_mechanic": {"mode": "idle", "scale": 0.6},
	"npc_pigeon_postman": {"mode": "wander", "scale": 0.56},
	"npc_cat_stray": {"mode": "idle", "scale": 0.6},
	"npc_raccoon_fisher": {"mode": "idle", "scale": 0.6},
	"npc_robot_cleaner": {"mode": "wander", "scale": 0.56},
	"npc_barrel_fire": {"mode": "loop", "scale": 0.9, "fps": 7.0},
	"npc_crow_lamp": {"mode": "crow", "scale": 0.9},
	"npc_dumpster_cat": {"mode": "prop", "scale": 0.85},
	"npc_raccoon_sign": {"mode": "prop", "scale": 0.8},
	"npc_equipment_sled": {"mode": "prop", "scale": 0.9},
	"npc_ice_fishers": {"mode": "idle", "scale": 0.62},
	"npc_ice_fish_crate": {"mode": "prop", "scale": 0.8},
	"npc_frozen_fish": {"mode": "prop", "scale": 0.7},
	"npc_fish_under_ice": {"mode": "loop", "scale": 1.0, "fps": 2.5},
}

static var _frames: Dictionary = {}
static var _textures: Dictionary = {}
static var _shadow: Texture2D

var actors: Array[Actor] = []
var _walkable: Callable


func setup(walkable: Callable = Callable()) -> void:
	_walkable = walkable
	if not BulletPool.exploded.is_connected(_on_explosion):
		BulletPool.exploded.connect(_on_explosion)


## Создаёт актёра и кладёт его в parent. frame_pick >= 0 фиксирует один кадр (статика).
func spawn(sheet: String, at: Vector2, parent: Node, mode: String = "", frame_pick: int = -1, scale_mult: float = 1.0) -> Actor:
	var frames := frames_of(sheet)
	if frames.is_empty():
		return null
	var def: Dictionary = DEFS.get(sheet, {"mode": "prop", "scale": 0.6})
	var actor := Actor.new()
	actor.setup(texture_of(sheet), frames, mode if not mode.is_empty() else str(def["mode"]), float(def["scale"]) * scale_mult, float(def.get("fps", 2.0)), frame_pick, _walkable)
	actor.position = at
	actor.set_meta("sheet", sheet)
	parent.add_child(actor)
	actors.append(actor)
	return actor


static func frames_of(sheet: String) -> Array:
	if _frames.is_empty():
		_frames = ConfigLoader.load_json(FRAMES_PATH)
	return _frames.get(sheet, [])


static func texture_of(sheet: String) -> Texture2D:
	if not _textures.has(sheet):
		var path := SHEET_DIR + sheet + ".png"
		_textures[sheet] = load(path) if ResourceLoader.exists(path) else null
	return _textures[sheet]


static func shadow_texture() -> Texture2D:
	if _shadow == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 96
		tex.height = 96
		_shadow = tex
	return _shadow


func _on_explosion(at: Vector2, radius: float, _color: Color, _team: int) -> void:
	for actor in actors:
		if is_instance_valid(actor):
			actor.scare(at, radius + SCARE_MARGIN)


class Actor:
	extends Sprite2D

	var frames: Array[AtlasTexture] = []
	var offsets: Array[Vector2] = []
	var mode := "prop"
	var fps := 2.0
	var home := Vector2.ZERO
	var base_scale := 0.6
	var _time := randf() * 10.0
	var _frame := 0
	var _hold := randf_range(0.5, 2.5)
	var _target := Vector2.INF
	var _walk_cd := 0.0
	var _flee_left := 0.0
	var _flee_dir := Vector2.ZERO
	var _away := 0.0
	var _walkable: Callable
	var _fixed := false
	## Прохожий: идёт по улице (route) туда-обратно, у концов стоит, на пути иногда останавливается поглазеть.
	var route := PackedVector2Array()
	var _leg := 0
	var _dir := 1
	var _pause := 0.0
	var speed := 34.0
	var _shadow_node: Sprite2D

	func setup(sheet: Texture2D, cells: Array, new_mode: String, scale_value: float, new_fps: float, pick: int, walkable: Callable) -> void:
		mode = new_mode
		fps = new_fps
		base_scale = scale_value
		_walkable = walkable
		centered = true
		for cell in cells:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(cell[0], cell[1], cell[2], cell[3])
			frames.append(atlas)
			offsets.append(Vector2(0, -float(cell[3]) * 0.5))
		if pick >= 0 and pick < frames.size():
			_frame = pick
			_fixed = true
			mode = "prop"
		scale = Vector2.ONE * base_scale
		# Жители — фон, а не цель: приглушены в холодный тон пола, чтобы в бою глаз не путал их с врагами
		# (тестеры: «НПС отвлекают»). Огонь в бочке и прочие «loop»-пропы остаются яркими.
		if new_mode != "loop" and new_mode != "prop":
			self_modulate = Color(0.55, 0.53, 0.7, 0.85)
		_shadow_node = Sprite2D.new()
		_shadow_node.texture = AmbientLife.shadow_texture()
		_shadow_node.show_behind_parent = true
		_shadow_node.position = Vector2(0, -2)
		_shadow_node.scale = Vector2(1.6, 0.6)
		add_child(_shadow_node)
		_apply_frame()

	func _ready() -> void:
		home = position

	func _apply_frame() -> void:
		texture = frames[_frame]
		offset = offsets[_frame]
		_shadow_node.scale = Vector2(float(frames[_frame].region.size.x) / 96.0 * 0.9, 0.55) / maxf(base_scale, 0.01) * 1.0

	func scare(from: Vector2, radius: float) -> void:
		if mode == "loop" or mode == "prop" or _flee_left > 0.0:
			return
		if global_position.distance_to(from) > radius:
			return
		if mode == "crow":
			_flee_left = 22.0
			_flee_dir = Vector2(randf_range(0.3, 1.0), -1.0).normalized()
			_frame = mini(1, frames.size() - 1)
			_apply_frame()
			return
		_flee_left = 1.6
		_flee_dir = (global_position - from).normalized()
		if _flee_dir == Vector2.ZERO:
			_flee_dir = Vector2.RIGHT

	func _process(delta: float) -> void:
		_time += delta
		if _flee_left > 0.0:
			_run_away(delta)
			return
		match mode:
			"loop":
				_frame = int(_time * fps) % frames.size()
				_apply_frame()
			"idle":
				_hold -= delta
				if _hold <= 0.0 and frames.size() > 1:
					_hold = randf_range(1.4, 3.6)
					_frame = 1 - _frame
					_apply_frame()
				scale = Vector2(base_scale, base_scale * (1.0 + 0.018 * sin(_time * 2.2)))
			"wander":
				_wander(delta)
			"walker":
				_walk_route(delta)
			"crow":
				modulate.a = minf(modulate.a + delta * 0.8, 1.0)

	func _wander(delta: float) -> void:
		if _target == Vector2.INF:
			_walk_cd -= delta
			if _frame != 0:
				_frame = 0
				_apply_frame()
			if _walk_cd <= 0.0:
				_pick_target()
			return
		var to := _target - position
		if to.length() < 4.0:
			_target = Vector2.INF
			_walk_cd = randf_range(1.5, 4.0)
			return
		position += to.normalized() * 28.0 * delta
		scale.x = base_scale * (1.0 if to.x >= 0.0 else -1.0)
		var step := int(_time * 3.0) % 2
		if step != _frame:
			_frame = mini(step, frames.size() - 1)
			_apply_frame()

	func set_route(points: PackedVector2Array, start: int) -> void:
		route = points
		_leg = clampi(start, 0, points.size() - 1)
		_dir = 1 if randf() < 0.5 else -1
		position = points[_leg]
		home = position

	func _walk_route(delta: float) -> void:
		if route.size() < 2:
			return
		if _pause > 0.0:
			_pause -= delta
			if _frame != 0:
				_frame = 0
				_apply_frame()
			return
		var target := route[_leg]
		var to := target - position
		var step := speed * delta
		if to.length() <= step:
			position = target
			_leg += _dir
			if _leg < 0 or _leg >= route.size():
				# Дошёл до конца улицы — постоял и пошёл обратно.
				_dir = -_dir
				_leg = clampi(_leg + _dir * 2, 0, route.size() - 1)
				_pause = randf_range(2.0, 5.0)
			elif randf() < 0.04:
				_pause = randf_range(1.0, 2.5)
			return
		position += to / to.length() * step
		scale.x = base_scale * (1.0 if to.x >= 0.0 else -1.0)
		# Шаг: смена кадра и лёгкое покачивание вверх-вниз.
		var phase := _time * 5.0
		var alt := int(phase) % 2
		if alt != _frame:
			_frame = mini(alt, frames.size() - 1)
			_apply_frame()
		offset.y = offsets[_frame].y - absf(sin(phase * PI)) * 3.0

	func _pick_target() -> void:
		for attempt in 6:
			var p := home + Vector2.from_angle(randf() * TAU) * randf_range(50.0, 150.0)
			if not _walkable.is_valid() or _walkable.call(p):
				_target = p
				return
		_walk_cd = 2.0

	func _run_away(delta: float) -> void:
		_flee_left -= delta
		if mode == "crow":
			position += _flee_dir * 260.0 * delta
			modulate.a = maxf(modulate.a - delta * 0.6, 0.0)
			if _flee_left <= 0.0:
				position = home
				_frame = 0
				modulate.a = 0.0
				_apply_frame()
			return
		var step := position + _flee_dir * 150.0 * delta
		if not _walkable.is_valid() or _walkable.call(step):
			position = step
		scale.x = base_scale * (1.0 if _flee_dir.x >= 0.0 else -1.0)
		var alt := int(_time * 8.0) % 2
		_frame = mini(alt, frames.size() - 1)
		_apply_frame()
		if _flee_left <= 0.0:
			_target = home
			_walk_cd = 0.0
			mode = "wander" if mode == "wander" else mode
			position = position.move_toward(home, 0.0)
			if mode != "wander" and mode != "walker":
				position = home
