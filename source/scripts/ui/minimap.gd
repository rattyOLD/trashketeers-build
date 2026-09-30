class_name Minimap
extends Control
## Мини-карта арены главы в углу HUD. Фон — картинка grid_size из сетки LevelSpawner
## (стены, укрытия, зоны), пересобирается при смене главы (rebuild). Поверх 5 раз в секунду
## рисуются точки: Енот, враги, босс, ящики с оружием, портал.

const REFRESH := 0.05
const FRAME := Color("#00e5ff")
const RUST := Color("#c9722b")
const RUST_DARK := Color("#5a2f14")
const INSET := 9.0
const WALL := Color("#7a4a30")
const COVER := Color("#d0812f")
const PORTAL := Color("#b46bff")

var events: MapEvents
var pickups: PickupManager
var _level: LevelSpawner
var _player: Player
var _enemies: EnemyManager
var _director: WaveDirector
var _texture: ImageTexture
var _timer := 0.0
var _time := 0.0
var _panel: StyleBoxFlat
var _inner: StyleBoxFlat


func setup(level: LevelSpawner, player: Player, enemies: EnemyManager, director: WaveDirector) -> void:
	_level = level
	_player = player
	_enemies = enemies
	_director = director
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_panel = UiStyle.box(Color(0.05, 0.04, 0.1, 0.86), RUST, 4, 16)
	_panel.shadow_color = Color(0, 0, 0, 0.45)
	_panel.shadow_size = 6
	_inner = UiStyle.box(Color(0, 0, 0, 0), Color(FRAME, 0.55), 2, 10)
	rebuild()


func rebuild() -> void:
	if _level == null or _level.cells.is_empty():
		return
	var image := _build_image()
	if _texture != null and Vector2i(_texture.get_size()) == image.get_size():
		_texture.update(image)
	else:
		_texture = ImageTexture.create_from_image(image)
	queue_redraw()


func _zone_color(zone: int) -> Color:
	var bank := _level.layout == "bank"
	match zone:
		LevelSpawner.Zone.EDGE:
			return Color("#141226")
		LevelSpawner.Zone.LANE:
			return Color("#5a4a2a") if bank else Color("#2b3350")
		LevelSpawner.Zone.LAWN:
			return Color("#33502f") if bank else Color("#1f3a44")
		LevelSpawner.Zone.BOSS:
			return Color("#6b3a22") if bank else Color("#4a2440")
		LevelSpawner.Zone.GATE:
			return Color("#1d5a62")
	return Color("#3d3424") if bank else Color("#1c1b36")


func _build_image() -> Image:
	var grid := _level.grid_size
	var image := Image.create(grid.x, grid.y, false, Image.FORMAT_RGBA8)
	for y in grid.y:
		for x in grid.x:
			var index := y * grid.x + x
			var color := _zone_color(_level.zones[index])
			match _level.cells[index]:
				LevelSpawner.CellType.WALL:
					color = WALL
				LevelSpawner.CellType.COVER, LevelSpawner.CellType.DESTRUCTIBLE:
					color = COVER
			image.set_pixel(x, y, color)
	return image


func _process(delta: float) -> void:
	_time += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		queue_redraw()


func _draw() -> void:
	if _level == null or _player == null or _texture == null or size.x < 20.0:
		return
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	var field := Rect2(Vector2.ONE * INSET, size - Vector2.ONE * INSET * 2.0)
	var grid := Vector2(_level.grid_size)
	var scale := minf(field.size.x / grid.x, field.size.y / grid.y)
	var origin := field.position + (field.size - grid * scale) * 0.5
	draw_rect(field, Color(0.02, 0.02, 0.06, 0.9))
	draw_texture_rect(_texture, Rect2(origin, grid * scale), false, Color(1, 1, 1, 0.95))
	var y := origin.y
	while y < origin.y + grid.y * scale:
		draw_line(Vector2(origin.x, y), Vector2(origin.x + grid.x * scale, y), Color(0, 0, 0, 0.16), 1.0)
		y += 3.0
	var sweep := fposmod(_time * 0.35, 1.0)
	var sx := origin.x + grid.x * scale * sweep
	draw_rect(Rect2(sx - 5.0, origin.y, 10.0, grid.y * scale), Color(FRAME, 0.05))
	draw_line(Vector2(sx, origin.y), Vector2(sx, origin.y + grid.y * scale), Color(FRAME, 0.28), 1.5)
	if pickups != null:
		for i in pickups.get_count():
			var at := pickups.position_at(i)
			if pickups.is_gold_at(i):
				_diamond(origin, scale, at, 3.6, Color("#ff9a1f"))
			elif pickups.is_xp_at(i):
				_diamond(origin, scale, at, 2.2, Color("#5cf3ff"))
			else:
				_dot(origin, scale, at, 1.7, Color("#ffd23f"), false)
	if events != null:
		for pool in events.pools:
			if pool.visible:
				var c := _to_map(origin, scale, pool.global_position)
				var r := maxf(6.0 * pool.scale.x / 2.0, 4.0)
				draw_circle(c, r, Color(0.48, 1.0, 0.24, 0.28))
				draw_arc(c, r, 0.0, TAU, 20, Color(0.48, 1.0, 0.24, 0.8), 1.5, true)
	for object in _level.destructibles:
		if object.kind == DestructibleObject.Kind.WEAPON_CRATE and object.is_intact() and object.visible:
			var p := _to_map(origin, scale, object.global_position).clamp(field.position + Vector2.ONE * 4.0, field.end - Vector2.ONE * 4.0)
			draw_rect(Rect2(p - Vector2.ONE * 4.5, Vector2.ONE * 9.0), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(p - Vector2.ONE * 3.0, Vector2.ONE * 6.0), object.get_rarity_color())
	if events != null and events.marauder != null and events.marauder.is_alive():
		var m := _to_map(origin, scale, events.marauder.global_position)
		var pulse := 6.0 + 2.5 * sin(_time * 9.0)
		draw_arc(m, pulse, 0.0, TAU, 20, Color("#ffd23f"), 2.0, true)
		draw_circle(m, 3.5, Color("#ffd23f"))
	for enemy in _enemies.get_active():
		if enemy.is_alive() and enemy != _director.boss and enemy != (events.marauder if events != null else null):
			_dot(origin, scale, enemy.global_position, 2.0, Color("#ff4d6d"), true)
	if _director.boss != null and _director.boss.is_alive():
		_diamond(origin, scale, _director.boss.global_position, 7.0 + sin(_time * 6.0), Color("#ffd23f"))
	var portal := _level.get_portal()
	if portal != null and portal.visible:
		var pp := _to_map(origin, scale, portal.global_position)
		var pr := 6.0 + sin(_time * 8.0) * 1.5
		draw_arc(pp, pr + 3.0, 0.0, TAU, 24, Color(PORTAL, 0.6), 2.0, true)
		draw_circle(pp, pr, PORTAL)
	var me := _to_map(origin, scale, _player.global_position)
	var aim := _player.visual.aim_direction.normalized() if _player.visual.aim_direction.length_squared() > 0.0 else Vector2.UP
	draw_arc(me, 9.0 + sin(_time * 5.0) * 1.2, 0.0, TAU, 20, Color(FRAME, 0.55), 1.5, true)
	var tip := me + aim * 8.0
	var left := me + aim.rotated(2.5) * 6.0
	var right := me + aim.rotated(-2.5) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0, 0, 0, 0.75))
	draw_colored_polygon(PackedVector2Array([me + aim * 6.5, me + aim.rotated(2.5) * 4.2, me + aim.rotated(-2.5) * 4.2]), FRAME)
	draw_style_box(_inner, Rect2(Vector2.ONE * (INSET - 3.0), size - Vector2.ONE * (INSET - 3.0) * 2.0))
	for corner in [Vector2(9, 9), Vector2(size.x - 9, 9), Vector2(9, size.y - 9), Vector2(size.x - 9, size.y - 9)]:
		draw_circle(corner, 3.5, RUST_DARK)
		draw_circle(corner, 2.2, Color("#f0b060"))


func _to_map(origin: Vector2, scale: float, world: Vector2) -> Vector2:
	return origin + (world - _level.bounds.position) / LevelSpawner.CELL * scale


func _dot(origin: Vector2, scale: float, world: Vector2, radius: float, color: Color, outline: bool) -> void:
	var p := _to_map(origin, scale, world).clamp(Vector2.ONE * (INSET + radius), size - Vector2.ONE * (INSET + radius))
	if outline:
		draw_circle(p, radius + 1.0, Color(0, 0, 0, 0.6))
	draw_circle(p, radius, color)


func _diamond(origin: Vector2, scale: float, world: Vector2, radius: float, color: Color) -> void:
	var p := _to_map(origin, scale, world).clamp(Vector2.ONE * (INSET + radius), size - Vector2.ONE * (INSET + radius))
	var pts := PackedVector2Array([p + Vector2(0, -radius - 1.0), p + Vector2(radius + 1.0, 0), p + Vector2(0, radius + 1.0), p + Vector2(-radius - 1.0, 0)])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, 0), p + Vector2(0, radius), p + Vector2(-radius, 0)]), color)
