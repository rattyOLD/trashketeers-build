class_name Minimap
extends Control
## Мини-карта арены главы в углу HUD. Фон — картинка grid_size из сетки LevelSpawner
## (стены, укрытия, зоны), пересобирается при смене главы (rebuild). Поверх 5 раз в секунду
## рисуются точки: Енот, враги, босс, ящики с оружием, портал.

const REFRESH := 0.05
const FRAME := Color("#ff8200")
const RUST := Color("#c9722b")
const RUST_DARK := Color("#5a2f14")
const INSET := 9.0
const WALL := Color("#7a4a30")
const COVER := Color("#d0812f")
const PORTAL := Color("#b46bff")

signal tapped(overview: bool)
signal enlarge_toggled(enlarged: bool)

const RAIL_W := 10.0
const TITLE_H := 18.0
const ZONE_TINTS: Array[Color] = [Color("#c97926"), Color("#8a4fd6"), Color("#c9722b"), Color("#d63a4f")]

var story: StoryRun
var overview := false
var enlarged := false
var _last_tap_ms := 0
var _stretch := 1.0
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
var _batch := PolyBatch.new()


func setup(level: LevelSpawner, player: Player, enemies: EnemyManager, director: WaveDirector) -> void:
	_level = level
	_player = player
	_enemies = enemies
	_director = director
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_panel = UiStyle.box(Color(0.092, 0.088, 0.083, 0.86), RUST, 4, 16)
	_panel.shadow_color = Color(0, 0, 0, 0.45)
	_panel.shadow_size = 6
	_inner = UiStyle.box(Color(0, 0, 0, 0), Color(FRAME, 0.55), 2, 10)
	rebuild()


func set_story(run: StoryRun) -> void:
	story = run
	_panel.bg_color = Color(0.092, 0.088, 0.083, 0.5)
	_panel.border_color = Color(RUST, 0.7)
	_panel.shadow_size = 0
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _gui_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not pressed:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < 250:
		return
	_last_tap_ms = now
	if story == null:
		enlarged = not enlarged
		enlarge_toggled.emit(enlarged)
		accept_event()
		return
	overview = not overview
	queue_redraw()
	tapped.emit(overview)


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
			return Color("#23221f")
		LevelSpawner.Zone.LANE:
			return Color("#5a4a2a") if bank else Color("#4a4742")
		LevelSpawner.Zone.LAWN:
			return Color("#33502f") if bank else Color("#3f3c38")
		LevelSpawner.Zone.BOSS:
			return Color("#6b3a22") if bank else Color("#4a2440")
		LevelSpawner.Zone.GATE:
			return Color("#5a5751")
	return Color("#3d3424") if bank else Color("#32302d")


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
	_stretch = 1.0
	if story != null:
		_draw_story()
		return
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	var field := Rect2(Vector2.ONE * INSET, size - Vector2.ONE * INSET * 2.0)
	var grid := Vector2(_level.grid_size)
	var scale := minf(field.size.x / grid.x, field.size.y / grid.y)
	var origin := field.position + (field.size - grid * scale) * 0.5
	draw_rect(field, Color(0.055, 0.053, 0.050, 0.9))
	draw_texture_rect(_texture, Rect2(origin, grid * scale), false, Color(1, 1, 1, 0.95))
	var y := origin.y
	while y < origin.y + grid.y * scale:
		_batch.line(Vector2(origin.x, y), Vector2(origin.x + grid.x * scale, y), Color(0, 0, 0, 0.16), 1.0)
		y += 3.0
	var sweep := fposmod(_time * 0.35, 1.0)
	var sx := origin.x + grid.x * scale * sweep
	_batch.rect(Rect2(sx - 5.0, origin.y, 10.0, grid.y * scale), Color(FRAME, 0.05))
	_batch.line(Vector2(sx, origin.y), Vector2(sx, origin.y + grid.y * scale), Color(FRAME, 0.28), 1.5)
	if pickups != null:
		for i in pickups.get_count():
			var at := pickups.position_at(i)
			if pickups.is_gold_at(i):
				_diamond(origin, scale, at, 3.6, Color("#ff9a1f"))
			elif pickups.is_xp_at(i):
				_diamond(origin, scale, at, 2.2, Color("#ffab53"))
			else:
				_dot(origin, scale, at, 1.7, Color("#ffd23f"), false)
	if events != null:
		for pool in events.pools:
			if pool.visible:
				var c := _to_map(origin, scale, pool.global_position)
				var r := maxf(6.0 * pool.scale.x / 2.0, 4.0)
				_batch.circle(c, r, Color(0.48, 1.0, 0.24, 0.28))
				_batch.arc(c, r, 0.0, TAU, 20, Color(0.48, 1.0, 0.24, 0.8), 1.5, true)
	var radar := SaveService.get_perk_level("radar")
	for object in _level.destructibles:
		if object.kind == DestructibleObject.Kind.WEAPON_CRATE and object.is_intact() and (object.visible or radar > 0):
			var p := _to_map(origin, scale, object.global_position).clamp(field.position + Vector2.ONE * 4.0, field.end - Vector2.ONE * 4.0)
			_batch.rect(Rect2(p - Vector2.ONE * 4.5, Vector2.ONE * 9.0), Color(0, 0, 0, 0.7))
			_batch.rect(Rect2(p - Vector2.ONE * 3.0, Vector2.ONE * 6.0), object.get_rarity_color())
	if events != null and events.marauder != null and events.marauder.is_alive():
		var m := _to_map(origin, scale, events.marauder.global_position)
		var pulse := 6.0 + 2.5 * sin(_time * 9.0)
		_batch.arc(m, pulse, 0.0, TAU, 20, Color("#ffd23f"), 2.0, true)
		_batch.circle(m, 3.5, Color("#ffd23f"))
	for enemy in _enemies.get_active():
		if enemy.is_alive() and enemy != _director.boss and enemy != (events.marauder if events != null else null):
			_dot(origin, scale, enemy.global_position, 2.0, Color("#ff4d6d"), true)
			if radar > 0 and enemy.data.max_hp >= 120.0:
				var ep := _to_map(origin, scale, enemy.global_position)
				_batch.arc(ep, 5.5 + sin(_time * 7.0), 0.0, TAU, 14, Color("#ffd23f"), 1.5, true)
	if _director.boss != null and _director.boss.is_alive():
		_diamond(origin, scale, _director.boss.global_position, 7.0 + sin(_time * 6.0), Color("#ffd23f"))
	# Выживание 2.0: вышки (голубые, пока не заряжены) и закрытые сейфы (золотые квадраты).
	for tower in _level.towers:
		if is_instance_valid(tower) and not tower.used:
			_dot(origin, scale, tower.global_position, 3.5, Color("#6adcff"), true)
	for safe in _level.safes:
		if is_instance_valid(safe) and not safe.opened:
			var sp := _to_map(origin, scale, safe.global_position)
			_batch.rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), Color("#ffd23f"))
	var portal := _level.get_portal()
	if portal != null and portal.visible:
		var pp := _to_map(origin, scale, portal.global_position)
		var pr := 6.0 + sin(_time * 8.0) * 1.5
		_batch.arc(pp, pr + 3.0, 0.0, TAU, 24, Color(PORTAL, 0.6), 2.0, true)
		_batch.circle(pp, pr, PORTAL)
	var me := _to_map(origin, scale, _player.global_position)
	var aim := _player.visual.aim_direction.normalized() if _player.visual.aim_direction.length_squared() > 0.0 else Vector2.UP
	_batch.arc(me, 9.0 + sin(_time * 5.0) * 1.2, 0.0, TAU, 20, Color(FRAME, 0.55), 1.5, true)
	var tip := me + aim * 8.0
	var left := me + aim.rotated(2.5) * 6.0
	var right := me + aim.rotated(-2.5) * 6.0
	_batch.polygon(PackedVector2Array([tip, left, right]), Color(0, 0, 0, 0.75))
	_batch.polygon(PackedVector2Array([me + aim * 6.5, me + aim.rotated(2.5) * 4.2, me + aim.rotated(-2.5) * 4.2]), FRAME)
	_batch.flush(self)
	draw_style_box(_inner, Rect2(Vector2.ONE * (INSET - 3.0), size - Vector2.ONE * (INSET - 3.0) * 2.0))
	for corner in [Vector2(9, 9), Vector2(size.x - 9, 9), Vector2(9, size.y - 9), Vector2(size.x - 9, size.y - 9)]:
		_batch.circle(corner, 3.5, RUST_DARK)
		_batch.circle(corner, 2.2, Color("#f0b060"))
	_batch.flush(self)


func _to_map(origin: Vector2, scale: float, world: Vector2) -> Vector2:
	var cells := (world - _level.bounds.position) / LevelSpawner.CELL
	return origin + Vector2(cells.x, cells.y * _stretch) * scale


func _dot(origin: Vector2, scale: float, world: Vector2, radius: float, color: Color, outline: bool) -> void:
	var p := _to_map(origin, scale, world).clamp(Vector2.ONE * (INSET + radius), size - Vector2.ONE * (INSET + radius))
	if outline:
		_batch.circle(p, radius + 1.0, Color(0, 0, 0, 0.6))
	_batch.circle(p, radius, color)


func _diamond(origin: Vector2, scale: float, world: Vector2, radius: float, color: Color) -> void:
	var p := _to_map(origin, scale, world).clamp(Vector2.ONE * (INSET + radius), size - Vector2.ONE * (INSET + radius))
	var pts := PackedVector2Array([p + Vector2(0, -radius - 1.0), p + Vector2(radius + 1.0, 0), p + Vector2(0, radius + 1.0), p + Vector2(-radius - 1.0, 0)])
	_batch.polygon(pts, Color(0, 0, 0, 0.65))
	_batch.polygon(PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, 0), p + Vector2(0, radius), p + Vector2(-radius, 0)]), color)


# --- Сюжетная карта: крупный план вокруг игрока и рельса всей миссии справа ---------------------

func _draw_story() -> void:
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var grid := Vector2(_level.grid_size)
	var field := Rect2(INSET, INSET + TITLE_H, size.x - INSET * 2.0 - RAIL_W - 6.0, size.y - INSET * 2.0 - TITLE_H)
	draw_string(font, Vector2(INSET + 2.0, INSET + 11.0), story.zone_name(), HORIZONTAL_ALIGNMENT_LEFT, size.x - INSET * 2.0, 11, Color("#ffd257"))
	draw_rect(field, Color(0.055, 0.053, 0.050, 0.5))
	var scale := field.size.x / grid.x
	_stretch = (field.size.y / grid.y) / scale if overview else 1.0
	var top := 0.0
	var rows := minf(field.size.y / scale, grid.y)
	if not overview:
		var py := (_player.global_position.y - _level.bounds.position.y) / LevelSpawner.CELL
		top = clampf(py - rows * 0.5, 0.0, maxf(grid.y - rows, 0.0))
	var origin := field.position - Vector2(0.0, top * scale)
	if overview:
		origin = field.position
		rows = grid.y
	var src := Rect2(0.0, top, grid.x, minf(rows, grid.y - top))
	draw_texture_rect_region(_texture, Rect2(origin + Vector2(0.0, top * scale), Vector2(src.size.x * scale, src.size.y * scale * _stretch)), src, Color(1, 1, 1, 0.72))
	var inner := field.grow(-3.0)
	if pickups != null:
		for i in pickups.get_count():
			if pickups.is_gold_at(i):
				var g := _to_map(origin, scale, pickups.position_at(i))
				if inner.has_point(g):
					_batch.circle(g, 2.4, Color("#ff9a1f"))
	for object in _level.destructibles:
		if object.kind == DestructibleObject.Kind.WEAPON_CRATE and object.is_intact() and object.visible:
			var c := _to_map(origin, scale, object.global_position)
			if inner.has_point(c):
				_batch.rect(Rect2(c - Vector2.ONE * 4.5, Vector2.ONE * 9.0), Color(0, 0, 0, 0.75))
				_batch.rect(Rect2(c - Vector2.ONE * 3.0, Vector2.ONE * 6.0), object.get_rarity_color())
	var blink := 0.6 + 0.4 * sin(_time * 6.0)
	for key: Variant in _level.story_gates:
		var gate := _level.story_gates[key] as StoryGate
		var a := _to_map(origin, scale, gate.rect.position)
		var b := _to_map(origin, scale, gate.rect.end)
		var bar := Rect2(a, Vector2(maxf(b.x - a.x, 6.0), maxf(b.y - a.y, 4.0)))
		if inner.intersects(bar):
			var color := Color("#7cff6b") if gate.is_open else Color("#ff3b5c").lerp(Color.WHITE, (1.0 - blink) * 0.5)
			_batch.rect(bar, Color(color, 0.85 if not gate.is_open else 0.5))
	for node in get_tree().get_nodes_in_group(&"story_captive"):
		var p := _to_map(origin, scale, (node as Node2D).global_position)
		if inner.has_point(p):
			_batch.arc(p, 6.0 + blink, 0.0, TAU, 16, Color("#ffac56"), 2.0, true)
			_batch.circle(p, 2.5, Color("#ffac56"))
	for enemy in _enemies.get_active():
		if enemy.is_alive() and enemy != _director.boss:
			var e := _to_map(origin, scale, enemy.global_position)
			if inner.has_point(e):
				_batch.circle(e, 3.0, Color(0, 0, 0, 0.6))
				_batch.circle(e, 2.2, Color("#ff4d6d"))
	if _director.boss != null and _director.boss.is_alive():
		var bp := _to_map(origin, scale, _director.boss.global_position)
		if inner.has_point(bp):
			_diamond(origin, scale, _director.boss.global_position, 7.0 + sin(_time * 6.0), Color("#ffd23f"))
	var me := _to_map(origin, scale, _player.global_position)
	var aim := _player.visual.aim_direction.normalized() if _player.visual.aim_direction.length_squared() > 0.0 else Vector2.UP
	_batch.arc(me, 8.0 + sin(_time * 5.0) * 1.2, 0.0, TAU, 20, Color(FRAME, 0.6), 1.5, true)
	_batch.polygon(PackedVector2Array([me + aim * 8.0, me + aim.rotated(2.5) * 6.0, me + aim.rotated(-2.5) * 6.0]), Color(0, 0, 0, 0.75))
	_batch.polygon(PackedVector2Array([me + aim * 6.5, me + aim.rotated(2.5) * 4.2, me + aim.rotated(-2.5) * 4.2]), FRAME)
	if not overview and top > 0.5:
		_edge_arrow(field, true)
	if not overview and top + rows < grid.y - 0.5:
		_edge_arrow(field, false)
	_batch.flush(self)
	draw_style_box(_inner, field.grow(3.0))
	_draw_rail(field)


func _edge_arrow(field: Rect2, up: bool) -> void:
	var x := field.get_center().x
	var y := field.position.y + 7.0 if up else field.end.y - 7.0
	var dir := -1.0 if up else 1.0
	_batch.polygon(PackedVector2Array([Vector2(x, y + 5.0 * dir), Vector2(x - 7.0, y - 3.0 * dir), Vector2(x + 7.0, y - 3.0 * dir)]), Color(FRAME, 0.7))


## Рельса всей миссии: зоны цветными полосами, засады и пленники засечками, босс наверху, Енот — стрелкой.
func _draw_rail(field: Rect2) -> void:
	var x0 := size.x - INSET - RAIL_W
	var y0 := field.position.y
	var h := field.size.y
	var zones: Array = story.mission.get("zones", [])
	for i in zones.size():
		var from := float(zones[i]["from"])
		var to := float(zones[i + 1]["from"]) if i + 1 < zones.size() else 1.0
		var band := Rect2(x0, y0 + h * (1.0 - to), RAIL_W, h * (to - from))
		draw_rect(band, Color(ZONE_TINTS[i % ZONE_TINTS.size()], 0.55))
		draw_rect(band, Color(0, 0, 0, 0.55), false, 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(x0, band.get_center().y + 5.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, RAIL_W, 10, Color(1, 1, 1, 0.9))
	for i in story.encounter_total():
		var at := story.encounter_mark(i)
		var y := y0 + h * (1.0 - at)
		var done := i < story.encounters_done()
		draw_line(Vector2(x0 - 2.0, y), Vector2(x0 + RAIL_W + 2.0, y), Color("#7cff6b") if done else Color("#ff3b5c"), 2.0)
	for i in range(story.captives_spawned(), story.captive_total()):
		var y := y0 + h * (1.0 - story.captive_mark(i))
		draw_circle(Vector2(x0 + RAIL_W * 0.5, y), 2.6, Color("#ffac56"))
	var boss := Vector2(x0 + RAIL_W * 0.5, y0 + 4.0)
	draw_colored_polygon(PackedVector2Array([boss + Vector2(0, -6), boss + Vector2(6, 0), boss + Vector2(0, 6), boss + Vector2(-6, 0)]), Color("#ffd23f"))
	var py := y0 + h * (1.0 - story.progress)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 - 1.0, py), Vector2(x0 - 9.0, py - 6.0), Vector2(x0 - 9.0, py + 6.0)]), FRAME)
