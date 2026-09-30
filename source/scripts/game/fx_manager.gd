class_name FxManager
extends Node2D
## Все «сочные» эффекты боя. Каждый вид — пул данных фиксированного размера в Packed-массивах
## (кольцевой буфер: при переполнении новая частица перезаписывает самую старую), рисуется
## одним _draw своего слоя. Нода на частицу не создаётся никогда.
##   Слой FX (над миром): искры (Add), вспышки дула (Add), кольца, конфетти, цифры урона, тексты.
##   Слой земли (attach_ground → декали): кляксы, падающие трупы, обломки, пыль, послеобразы рывка.
##   Покадровые трупы — единственное исключение: пул RigSprite (кадры смерти с концепт-листа
##   с тем же окрасом особи, что был при жизни), создаётся один раз и переиспользуется по кругу.
## Искры аддитивны — дешёвый неон без glow-постобработки.

const SPARK_CAPACITY := 420
const RING_CAPACITY := 28
const TEXT_CAPACITY := 56
const CHUNK_CAPACITY := 160
const SPLAT_CAPACITY := 72
const CORPSE_CAPACITY := 28
const GHOST_CAPACITY := 18
const PUFF_CAPACITY := 64
const FLASH_CAPACITY := 12
const TEXT_LIFE := 0.8
const TEXT_RISE := 80.0
const SPLAT_LIFE := 7.0
const CORPSE_LIFE := 0.9
const GHOST_LIFE := 0.28
const PUFF_LIFE := 0.45
const FLASH_LIFE := 0.06
const CHUNK_GRAVITY := 900.0
const DAMAGE_COLOR := Color("#fff4c2")
const CRIT_COLOR := Color("#ff4d2e")
const OUTLINE := Color("#140a1e")
const CONFETTI: Array[Color] = [Color("#ff2ea6"), Color("#00f5ff"), Color("#ffe14d"), Color("#7cff6b"), Color("#b84dff")]

var _sparks: DrawLayer
var _texts: DrawLayer
var _ground: DrawLayer

var _sp_pos := PackedVector2Array()
var _sp_vel := PackedVector2Array()
var _sp_life := PackedFloat32Array()
var _sp_max := PackedFloat32Array()
var _sp_size := PackedFloat32Array()
var _sp_color := PackedColorArray()
var _sp_next := 0

var _ring_pos := PackedVector2Array()
var _ring_life := PackedFloat32Array()
var _ring_radius := PackedFloat32Array()
var _ring_color := PackedColorArray()
var _ring_next := 0

var _tx_pos := PackedVector2Array()
var _tx_origin := PackedVector2Array()
var _tx_life := PackedFloat32Array()
var _tx_text := PackedStringArray()
var _tx_color := PackedColorArray()
var _tx_size := PackedFloat32Array()
var _tx_next := 0

## Обломки и конфетти: позиция на земле + «высота» z с гравитацией и отскоком.
var _ch_pos := PackedVector2Array()
var _ch_vel := PackedVector2Array()
var _ch_z := PackedFloat32Array()
var _ch_vz := PackedFloat32Array()
var _ch_life := PackedFloat32Array()
var _ch_size := PackedFloat32Array()
var _ch_color := PackedColorArray()
var _ch_spin := PackedFloat32Array()
var _ch_next := 0

var _spl_pos := PackedVector2Array()
var _spl_life := PackedFloat32Array()
var _spl_radius := PackedFloat32Array()
var _spl_color := PackedColorArray()
var _spl_seed := PackedFloat32Array()
var _spl_next := 0

var _co_tex: Array[Texture2D] = []
var _co_pos := PackedVector2Array()
var _co_scale := PackedVector2Array()
var _co_life := PackedFloat32Array()
var _co_dir := PackedFloat32Array()
var _co_color := PackedColorArray()
var _co_next := 0

var _gh_tex: Array[Texture2D] = []
var _gh_pos := PackedVector2Array()
var _gh_scale := PackedVector2Array()
var _gh_life := PackedFloat32Array()
var _gh_color := PackedColorArray()
var _gh_next := 0

var _pf_pos := PackedVector2Array()
var _pf_vel := PackedVector2Array()
var _pf_life := PackedFloat32Array()
var _pf_size := PackedFloat32Array()
var _pf_next := 0

var _fl_pos := PackedVector2Array()
var _fl_angle := PackedFloat32Array()
var _fl_life := PackedFloat32Array()
var _fl_size := PackedFloat32Array()
var _fl_color := PackedColorArray()
var _fl_next := 0

const BOLT_CAPACITY := 16
const BOLT_LIFE := 0.18
var _bo_a := PackedVector2Array()
var _bo_b := PackedVector2Array()
var _bo_life := PackedFloat32Array()
var _bo_color := PackedColorArray()
var _bo_seed := PackedFloat32Array()
var _bo_next := 0

var _font: Font


class DrawLayer:
	extends Node2D
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


const LIGHT_POOL := 4
const FRAME_CORPSE_POOL := 14
const FRAME_CORPSE_LIFE := 2.4
const FRAME_CORPSE_FADE := 0.6
var _fc_root: Node2D
var _fc_nodes: Array[RigSprite] = []
var _fc_life := PackedFloat32Array()
var _fc_tint := PackedColorArray()
var _fc_next := 0
## Вспышки-спрайты (взрыв бочки, брызги шампанского): растут и тают.
const SPRITE_FLASH_POOL := 22
var _sf_nodes: Array[Sprite2D] = []
var _sf_life := PackedFloat32Array()
var _sf_total := PackedFloat32Array()
var _sf_base := PackedFloat32Array()
var _sf_flip := PackedFloat32Array()
var _sf_next := 0
var _lights: Array[PointLight2D] = []
var _light_life := PackedFloat32Array()
var _light_total := PackedFloat32Array()
var _light_energy := PackedFloat32Array()
var _light_next := 0


func _init() -> void:
	_resize_all()
	_bo_a.resize(BOLT_CAPACITY)
	_bo_b.resize(BOLT_CAPACITY)
	_bo_life.resize(BOLT_CAPACITY)
	_bo_color.resize(BOLT_CAPACITY)
	_bo_seed.resize(BOLT_CAPACITY)
	_font = ThemeDB.fallback_font
	EnvLights.clear()
	# Пул вспышек света на полу (выстрелы, взрывы): PointLight2D только на слой пола —
	# в Compatibility каждый свет перерисовывает освещённые узлы, пол дешевле всего.
	_light_life.resize(LIGHT_POOL)
	_light_total.resize(LIGHT_POOL)
	_light_energy.resize(LIGHT_POOL)
	for i in LIGHT_POOL:
		var light := PointLight2D.new()
		light.texture = NeonSign.get_light_texture()
		light.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
		light.enabled = false
		add_child(light)
		_lights.append(light)

	_ground = DrawLayer.new()
	_ground.painter = _draw_ground
	add_child(_ground)

	_fc_root = Node2D.new()
	add_child(_fc_root)
	_fc_life.resize(FRAME_CORPSE_POOL)
	_fc_tint.resize(FRAME_CORPSE_POOL)
	for i in FRAME_CORPSE_POOL:
		var corpse_sprite := RigSprite.new()
		corpse_sprite.visible = false
		_fc_root.add_child(corpse_sprite)
		_fc_nodes.append(corpse_sprite)

	_sf_life.resize(SPRITE_FLASH_POOL)
	_sf_total.resize(SPRITE_FLASH_POOL)
	_sf_base.resize(SPRITE_FLASH_POOL)
	_sf_flip.resize(SPRITE_FLASH_POOL)
	for i in SPRITE_FLASH_POOL:
		var flash_sprite := Sprite2D.new()
		flash_sprite.visible = false
		add_child(flash_sprite)
		_sf_nodes.append(flash_sprite)

	_sparks = DrawLayer.new()
	_sparks.painter = _draw_sparks
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = additive
	add_child(_sparks)

	_texts = DrawLayer.new()
	_texts.painter = _draw_texts
	add_child(_texts)


## Переносит «земляные» эффекты (кляксы, трупы, обломки) в слой декалей: под персонажей.
func attach_ground(decals_layer: Node2D) -> void:
	_ground.reparent(decals_layer, false)
	_fc_root.reparent(decals_layer, false)


## Смерть покадрового врага: кадры клипа death поверх земли, окрас и обводка — как у живой особи.
func frame_corpse(source: RigSprite, at: Vector2, sprite_scale: Vector2) -> void:
	if not source.is_framed() or not FrameDB.has_clip(source.frame_sheet, "death"):
		return
	var k := _fc_next
	_fc_next = (_fc_next + 1) % FRAME_CORPSE_POOL
	var node := _fc_nodes[k]
	var sheet_id: String = source.frame_sheet["id"]
	if not node.is_framed() or node.frame_sheet["id"] != sheet_id:
		node.setup_frames(sheet_id, 6.0)
	node.copy_look(source)
	_fc_tint[k] = source.shader_material.get_shader_parameter("tint")
	node.position = at
	node.scale = sprite_scale
	node.rotation = 0.0
	node.set_frame(FrameDB.clip_frame(node.frame_sheet, "death", 0.0))
	node.set_param("flash", 0.7)
	node.set_param("alpha", 1.0)
	node.visible = true
	_fc_life[k] = FRAME_CORPSE_LIFE


## Вспышка-картинка (взрыв с концепт-листа): width — ширина в мире, растёт на 25% и гаснет.
## angle задан — спрайт повёрнут точно (дульная вспышка), pivot — точка привязки в долях текстуры.
func sprite_flash(texture: Texture2D, at: Vector2, width: float, life: float, angle: float = NAN, pivot: Vector2 = Vector2(0.5, 0.5), flip: float = 1.0) -> void:
	if texture == null:
		return
	var k := _sf_next
	_sf_next = (_sf_next + 1) % SPRITE_FLASH_POOL
	var node := _sf_nodes[k]
	var size := texture.get_size()
	node.texture = texture
	node.global_position = at
	node.rotation = randf_range(-0.2, 0.2) if is_nan(angle) else angle
	node.offset = (Vector2(0.5, 0.5) - pivot) * size
	_sf_base[k] = width / maxf(size.x, 1.0)
	_sf_flip[k] = flip
	node.scale = Vector2(1.0, flip) * _sf_base[k] * 0.7
	node.modulate = Color.WHITE
	node.visible = true
	_sf_life[k] = life
	_sf_total[k] = life


func burst(at: Vector2, color: Color, count: int, speed: float = 240.0, size: float = 3.5) -> void:
	for i in count:
		_spark(at, Vector2.from_angle(randf() * TAU) * speed * randf_range(0.35, 1.0), color, size)


## Искры конусом по направлению удара (попадание пули, выстрел).
func burst_dir(at: Vector2, direction: Vector2, color: Color, count: int, spread: float = 0.7, speed: float = 320.0, size: float = 3.0) -> void:
	var base := direction.angle()
	for i in count:
		var angle := base + randf_range(-spread, spread)
		_spark(at, Vector2.from_angle(angle) * speed * randf_range(0.4, 1.0), color, size)


## Цепная молния: ломаная между двумя точками, гаснет за BOLT_LIFE.
func bolt(from: Vector2, to: Vector2, color: Color) -> void:
	var k := _bo_next
	_bo_next = (_bo_next + 1) % BOLT_CAPACITY
	_bo_a[k] = from
	_bo_b[k] = to
	_bo_life[k] = BOLT_LIFE
	_bo_color[k] = color
	_bo_seed[k] = randf() * 100.0


## Мелкая цифра статуса (яд, кровь) — цветом эффекта и без «попа» крита.
func status_number(at: Vector2, value: float, color: Color) -> void:
	_text(at + Vector2(randf_range(-16, 16), -12), str(maxi(int(round(value)), 1)), color, 22.0)


func ring(at: Vector2, color: Color, radius: float) -> void:
	var k := _ring_next
	_ring_next = (_ring_next + 1) % RING_CAPACITY
	_ring_pos[k] = at
	_ring_life[k] = 0.35
	_ring_radius[k] = radius
	_ring_color[k] = color


## Цифра урона: обычная — светлая, крит — крупнее, красно-оранжевая, с «!».
func number(at: Vector2, value: float, color: Color = DAMAGE_COLOR, is_crit: bool = false) -> void:
	var text := str(int(round(value)))
	if is_crit:
		_text(at + Vector2(randf_range(-14, 14), -26), text + "!", CRIT_COLOR, 40.0)
	else:
		_text(at + Vector2(randf_range(-12, 12), -20), text, color, 28.0)


func popup(at: Vector2, text: String, color: Color, font_size: float = 34.0) -> void:
	_text(at, text, color, font_size)


## Разлёт обломков (мех, слизь, осколки) с гравитацией и отскоком от земли.
func chunks(at: Vector2, color: Color, count: int, speed: float = 220.0, size: float = 5.0) -> void:
	for i in count:
		var k := _ch_next
		_ch_next = (_ch_next + 1) % CHUNK_CAPACITY
		_ch_pos[k] = at
		_ch_vel[k] = Vector2.from_angle(randf() * TAU) * speed * randf_range(0.3, 1.0)
		_ch_z[k] = randf_range(6.0, 20.0)
		_ch_vz[k] = randf_range(160.0, 380.0)
		_ch_life[k] = randf_range(0.7, 1.2)
		_ch_size[k] = size * randf_range(0.6, 1.3)
		_ch_color[k] = color.lerp(color.darkened(0.4), randf() * 0.6)
		_ch_spin[k] = randf() * TAU


func confetti(at: Vector2, count: int = 60) -> void:
	for i in count:
		var k := _ch_next
		_ch_next = (_ch_next + 1) % CHUNK_CAPACITY
		_ch_pos[k] = at + Vector2(randf_range(-40, 40), randf_range(-20, 20))
		_ch_vel[k] = Vector2.from_angle(randf() * TAU) * randf_range(80.0, 420.0)
		_ch_z[k] = randf_range(20.0, 60.0)
		_ch_vz[k] = randf_range(300.0, 620.0)
		_ch_life[k] = randf_range(1.2, 1.9)
		_ch_size[k] = randf_range(5.0, 9.0)
		_ch_color[k] = CONFETTI.pick_random()
		_ch_spin[k] = randf() * TAU


func splat(at: Vector2, color: Color, radius: float) -> void:
	var k := _spl_next
	_spl_next = (_spl_next + 1) % SPLAT_CAPACITY
	_spl_pos[k] = at
	_spl_life[k] = SPLAT_LIFE
	_spl_radius[k] = radius
	_spl_color[k] = color
	_spl_seed[k] = randf() * 100.0


## Короткая анимация падения вместо исчезновения: спрайт заваливается набок, плющится и гаснет.
func corpse(texture: Texture2D, at: Vector2, sprite_scale: Vector2, knock_dir: float, tint: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var k := _co_next
	_co_next = (_co_next + 1) % CORPSE_CAPACITY
	_co_tex[k] = texture
	_co_pos[k] = at
	_co_scale[k] = sprite_scale
	_co_life[k] = CORPSE_LIFE
	_co_dir[k] = knock_dir
	_co_color[k] = tint


## Послеобраз рывка.
func ghost(texture: Texture2D, at: Vector2, sprite_scale: Vector2, color: Color) -> void:
	if texture == null:
		return
	var k := _gh_next
	_gh_next = (_gh_next + 1) % GHOST_CAPACITY
	_gh_tex[k] = texture
	_gh_pos[k] = at
	_gh_scale[k] = sprite_scale
	_gh_life[k] = GHOST_LIFE
	_gh_color[k] = color


func dust(at: Vector2, count: int = 3, spread: float = 30.0) -> void:
	for i in count:
		var k := _pf_next
		_pf_next = (_pf_next + 1) % PUFF_CAPACITY
		_pf_pos[k] = at + Vector2(randf_range(-spread, spread) * 0.5, randf_range(-4, 4))
		_pf_vel[k] = Vector2(randf_range(-spread, spread), randf_range(-26, -6))
		_pf_life[k] = PUFF_LIFE * randf_range(0.7, 1.1)
		_pf_size[k] = randf_range(6.0, 11.0)


## Вспышка света: пол (пул PointLight2D) + персонажи рядом (EnvLights).
func light_flash(at: Vector2, color: Color, energy: float, radius: float, life: float) -> void:
	var k := _light_next
	_light_next = (_light_next + 1) % LIGHT_POOL
	var light := _lights[k]
	light.global_position = at
	light.color = color
	light.texture_scale = radius / 64.0
	light.energy = energy
	light.enabled = true
	_light_life[k] = life
	_light_total[k] = life
	_light_energy[k] = energy
	EnvLights.flash(at, color, radius, minf(energy, 1.4), life)


func muzzle_flash(at: Vector2, angle: float, color: Color, size: float = 1.0) -> void:
	light_flash(at, color.lerp(Color("#fff2c0"), 0.4), 0.9 * size, 150.0 * size, 0.08)
	var k := _fl_next
	_fl_next = (_fl_next + 1) % FLASH_CAPACITY
	_fl_pos[k] = at
	_fl_angle[k] = angle
	_fl_life[k] = FLASH_LIFE
	_fl_size[k] = size
	_fl_color[k] = color


func clear() -> void:
	_resize_all()


func _tick_frame_corpses(delta: float) -> void:
	for i in FRAME_CORPSE_POOL:
		if _fc_life[i] <= 0.0:
			continue
		var node := _fc_nodes[i]
		_fc_life[i] -= delta
		if _fc_life[i] <= 0.0:
			node.visible = false
			continue
		var age := FRAME_CORPSE_LIFE - _fc_life[i]
		var sheet := node.frame_sheet
		node.set_frame(FrameDB.clip_frame(sheet, "death", age * FrameDB.clip_fps(sheet, "death")))
		node.set_param("flash", maxf(0.7 - age * 5.0, 0.0))
		node.set_param("alpha", clampf(_fc_life[i] / FRAME_CORPSE_FADE, 0.0, 1.0))
		var base: Color = _fc_tint[i]
		node.set_param("tint", base.darkened(0.3 * clampf(age / 0.8, 0.0, 1.0)))


func _spark(at: Vector2, velocity: Vector2, color: Color, size: float) -> void:
	var k := _sp_next
	_sp_next = (_sp_next + 1) % SPARK_CAPACITY
	_sp_pos[k] = at
	_sp_vel[k] = velocity
	var life := randf_range(0.18, 0.4)
	_sp_life[k] = life
	_sp_max[k] = life
	_sp_size[k] = size * randf_range(0.7, 1.3)
	_sp_color[k] = color


func _text(at: Vector2, text: String, color: Color, font_size: float) -> void:
	var k := _tx_next
	_tx_next = (_tx_next + 1) % TEXT_CAPACITY
	_tx_origin[k] = at
	_tx_pos[k] = at
	_tx_life[k] = TEXT_LIFE
	_tx_text[k] = text
	_tx_color[k] = color
	_tx_size[k] = font_size


func _process(delta: float) -> void:
	EnvLights.tick(delta)
	_tick_frame_corpses(delta)
	for i in SPRITE_FLASH_POOL:
		if _sf_life[i] <= 0.0:
			continue
		_sf_life[i] -= delta
		var node := _sf_nodes[i]
		if _sf_life[i] <= 0.0:
			node.visible = false
			continue
		var t := 1.0 - _sf_life[i] / _sf_total[i]
		node.scale = Vector2(1.0, _sf_flip[i]) * _sf_base[i] * (0.7 + 0.55 * (1.0 - pow(1.0 - t, 3.0)))
		node.modulate.a = clampf((1.0 - t) * 1.6, 0.0, 1.0)
	for i in LIGHT_POOL:
		if _light_life[i] > 0.0:
			_light_life[i] = maxf(_light_life[i] - delta, 0.0)
			var t := _light_life[i] / maxf(_light_total[i], 0.001)
			_lights[i].energy = _light_energy[i] * t
			_lights[i].enabled = _light_life[i] > 0.0
	for i in SPARK_CAPACITY:
		if _sp_life[i] > 0.0:
			_sp_life[i] -= delta
			_sp_pos[i] += _sp_vel[i] * delta
			_sp_vel[i] *= 0.9
	for i in RING_CAPACITY:
		if _ring_life[i] > 0.0:
			_ring_life[i] -= delta
	for i in BOLT_CAPACITY:
		if _bo_life[i] > 0.0:
			_bo_life[i] -= delta
	for i in TEXT_CAPACITY:
		if _tx_life[i] > 0.0:
			_tx_life[i] -= delta
			var t := 1.0 - _tx_life[i] / TEXT_LIFE
			_tx_pos[i] = _tx_origin[i] + Vector2(0.0, -TEXT_RISE * (1.0 - (1.0 - t) * (1.0 - t)))
	for i in CHUNK_CAPACITY:
		if _ch_life[i] > 0.0:
			_ch_life[i] -= delta
			_ch_vz[i] -= CHUNK_GRAVITY * delta
			_ch_z[i] += _ch_vz[i] * delta
			if _ch_z[i] <= 0.0:
				_ch_z[i] = 0.0
				_ch_vz[i] = -_ch_vz[i] * 0.35
				_ch_vel[i] *= 0.55
			_ch_pos[i] += _ch_vel[i] * delta
			_ch_spin[i] += delta * 9.0
	for i in SPLAT_CAPACITY:
		if _spl_life[i] > 0.0:
			_spl_life[i] -= delta
	for i in CORPSE_CAPACITY:
		if _co_life[i] > 0.0:
			_co_life[i] -= delta
	for i in GHOST_CAPACITY:
		if _gh_life[i] > 0.0:
			_gh_life[i] -= delta
	for i in PUFF_CAPACITY:
		if _pf_life[i] > 0.0:
			_pf_life[i] -= delta
			_pf_pos[i] += _pf_vel[i] * delta
	for i in FLASH_CAPACITY:
		if _fl_life[i] > 0.0:
			_fl_life[i] -= delta
	_sparks.queue_redraw()
	_texts.queue_redraw()
	_ground.queue_redraw()


func _draw_sparks(canvas: CanvasItem) -> void:
	for i in SPARK_CAPACITY:
		var life := _sp_life[i]
		if life <= 0.0:
			continue
		var t := life / _sp_max[i]
		var c := _sp_color[i]
		var tail := _sp_vel[i] * 0.03
		canvas.draw_line(_sp_pos[i] - tail, _sp_pos[i], Color(c, 0.5 * t), _sp_size[i] * 1.4 * t)
		canvas.draw_circle(_sp_pos[i], _sp_size[i] * 2.0 * t, Color(c, 0.22 * t))
		canvas.draw_circle(_sp_pos[i], _sp_size[i] * t, Color(c.lightened(0.45), t))
	for i in FLASH_CAPACITY:
		var life := _fl_life[i]
		if life <= 0.0:
			continue
		var t := life / FLASH_LIFE
		var s := _fl_size[i] * (0.8 + 0.4 * t)
		var fwd := Vector2.from_angle(_fl_angle[i])
		var side := fwd.orthogonal()
		var p := _fl_pos[i]
		var star := PackedVector2Array([p + fwd * 30.0 * s, p + side * 7.0 * s, p - fwd * 6.0 * s, p - side * 7.0 * s])
		canvas.draw_colored_polygon(star, Color(_fl_color[i], 0.85 * t))
		canvas.draw_circle(p + fwd * 6.0 * s, 9.0 * s, Color(1, 1, 1, 0.8 * t))
	for i in BOLT_CAPACITY:
		var life := _bo_life[i]
		if life <= 0.0:
			continue
		var a := _bo_a[i]
		var b := _bo_b[i]
		var dir := b - a
		var normal := dir.orthogonal().normalized()
		var points := PackedVector2Array([a])
		var segments := clampi(int(dir.length() / 26.0), 3, 9)
		for j in range(1, segments):
			var f := float(j) / segments
			points.append(a.lerp(b, f) + normal * sin(_bo_seed[i] + j * 7.3 + life * 60.0) * 14.0)
		points.append(b)
		var fade := life / BOLT_LIFE
		canvas.draw_polyline(points, Color(_bo_color[i], 0.55 * fade), 9.0 * fade + 2.0)
		canvas.draw_polyline(points, Color(1, 1, 1, fade), 3.0)
	for i in RING_CAPACITY:
		var life := _ring_life[i]
		if life <= 0.0:
			continue
		var t := 1.0 - life / 0.35
		canvas.draw_arc(_ring_pos[i], _ring_radius[i] * (0.4 + t), 0.0, TAU, 40, Color(_ring_color[i], 1.0 - t), 6.0 * (1.0 - t) + 1.0)


func _draw_texts(canvas: CanvasItem) -> void:
	for i in CHUNK_CAPACITY:
		var life := _ch_life[i]
		if life <= 0.0 or _ch_z[i] <= 0.5:
			continue
		_draw_chunk(canvas, i, minf(life * 3.0, 1.0))
	for i in TEXT_CAPACITY:
		var life := _tx_life[i]
		if life <= 0.0:
			continue
		var t := 1.0 - life / TEXT_LIFE
		var alpha := clampf(life / TEXT_LIFE * 1.8, 0.0, 1.0)
		# «Поп»: цифра выпрыгивает крупнее и за 0.12 с садится в обычный размер.
		var pop := 1.0 + maxf(0.0, 0.12 - t * TEXT_LIFE) / 0.12 * 0.6
		var size := int(_tx_size[i] * pop)
		var p := _tx_pos[i] - Vector2(80, 0)
		canvas.draw_string_outline(_font, p, _tx_text[i], HORIZONTAL_ALIGNMENT_CENTER, 160, size, maxi(int(size * 0.42), 6), Color(OUTLINE, alpha))
		canvas.draw_string(_font, p, _tx_text[i], HORIZONTAL_ALIGNMENT_CENTER, 160, size, Color(_tx_color[i], alpha))


func _draw_ground(canvas: CanvasItem) -> void:
	for i in SPLAT_CAPACITY:
		var life := _spl_life[i]
		if life <= 0.0:
			continue
		var fade := clampf(life / 1.5, 0.0, 1.0)
		var c := _spl_color[i]
		var r := _spl_radius[i]
		var p := _spl_pos[i]
		var seed := _spl_seed[i]
		canvas.draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
		canvas.draw_circle(Vector2.ZERO, r, Color(c.darkened(0.35), 0.45 * fade))
		for k in 5:
			var a := seed + k * 1.37
			canvas.draw_circle(Vector2.from_angle(a) * r * 0.95, r * (0.22 + 0.08 * sin(seed + k)), Color(c.darkened(0.35), 0.45 * fade))
		canvas.draw_circle(Vector2(-r * 0.25, -r * 0.2), r * 0.28, Color(c.lightened(0.3), 0.25 * fade))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i in PUFF_CAPACITY:
		var life := _pf_life[i]
		if life <= 0.0:
			continue
		var t := life / PUFF_LIFE
		canvas.draw_circle(_pf_pos[i], _pf_size[i] * (1.6 - t * 0.6), Color(0.78, 0.74, 0.86, 0.32 * t))

	for i in CHUNK_CAPACITY:
		var life := _ch_life[i]
		if life <= 0.0 or _ch_z[i] > 0.5:
			continue
		_draw_chunk(canvas, i, minf(life * 3.0, 1.0))

	for i in CORPSE_CAPACITY:
		var life := _co_life[i]
		if life <= 0.0:
			continue
		var t := 1.0 - life / CORPSE_LIFE
		var fall := minf(t / 0.35, 1.0)
		var angle := _co_dir[i] * (PI * 0.5) * (1.0 - pow(1.0 - fall, 3.0))
		var squash := 1.0 - 0.25 * fall
		var scale := _co_scale[i] * Vector2(1.0 + 0.1 * fall, squash)
		var alpha := clampf((1.0 - t) / 0.45, 0.0, 1.0)
		var tex := _co_tex[i]
		canvas.draw_set_transform(_co_pos[i] + Vector2(0, -8.0 * (1.0 - fall)), angle, scale)
		var tint := _co_color[i].darkened(0.35 * fall)
		tint.a = alpha
		canvas.draw_texture(tex, -tex.get_size() * 0.5, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i in GHOST_CAPACITY:
		var life := _gh_life[i]
		if life <= 0.0:
			continue
		var tex := _gh_tex[i]
		var c := _gh_color[i]
		c.a = 0.55 * life / GHOST_LIFE
		canvas.draw_set_transform(_gh_pos[i], 0.0, _gh_scale[i])
		canvas.draw_texture(tex, -tex.get_size() * 0.5, c)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_chunk(canvas: CanvasItem, i: int, alpha: float) -> void:
	var p := _ch_pos[i]
	var s := _ch_size[i]
	var z := _ch_z[i]
	if z > 0.5:
		canvas.draw_circle(p + Vector2(0, 3), s * 0.6, Color(0, 0, 0, 0.25 * alpha))
	var top := p - Vector2(0, z)
	var dir := Vector2.from_angle(_ch_spin[i]) * s * 0.6
	var side := dir.orthogonal() * 0.6
	var quad := PackedVector2Array([top - dir - side, top + dir - side, top + dir + side, top - dir + side])
	canvas.draw_colored_polygon(quad, Color(_ch_color[i], alpha))


func _resize_all() -> void:
	# Новые Packed-массивы заполняются нулями: life = 0 означает «частица мертва».
	_sp_pos = PackedVector2Array(); _sp_pos.resize(SPARK_CAPACITY)
	_sp_vel = PackedVector2Array(); _sp_vel.resize(SPARK_CAPACITY)
	_sp_life = PackedFloat32Array(); _sp_life.resize(SPARK_CAPACITY)
	_sp_max = PackedFloat32Array(); _sp_max.resize(SPARK_CAPACITY)
	_sp_size = PackedFloat32Array(); _sp_size.resize(SPARK_CAPACITY)
	_sp_color = PackedColorArray(); _sp_color.resize(SPARK_CAPACITY)
	_ring_pos = PackedVector2Array(); _ring_pos.resize(RING_CAPACITY)
	_ring_life = PackedFloat32Array(); _ring_life.resize(RING_CAPACITY)
	_ring_radius = PackedFloat32Array(); _ring_radius.resize(RING_CAPACITY)
	_ring_color = PackedColorArray(); _ring_color.resize(RING_CAPACITY)
	_tx_pos = PackedVector2Array(); _tx_pos.resize(TEXT_CAPACITY)
	_tx_origin = PackedVector2Array(); _tx_origin.resize(TEXT_CAPACITY)
	_tx_life = PackedFloat32Array(); _tx_life.resize(TEXT_CAPACITY)
	_tx_text = PackedStringArray(); _tx_text.resize(TEXT_CAPACITY)
	_tx_color = PackedColorArray(); _tx_color.resize(TEXT_CAPACITY)
	_tx_size = PackedFloat32Array(); _tx_size.resize(TEXT_CAPACITY)
	_ch_pos = PackedVector2Array(); _ch_pos.resize(CHUNK_CAPACITY)
	_ch_vel = PackedVector2Array(); _ch_vel.resize(CHUNK_CAPACITY)
	_ch_z = PackedFloat32Array(); _ch_z.resize(CHUNK_CAPACITY)
	_ch_vz = PackedFloat32Array(); _ch_vz.resize(CHUNK_CAPACITY)
	_ch_life = PackedFloat32Array(); _ch_life.resize(CHUNK_CAPACITY)
	_ch_size = PackedFloat32Array(); _ch_size.resize(CHUNK_CAPACITY)
	_ch_color = PackedColorArray(); _ch_color.resize(CHUNK_CAPACITY)
	_ch_spin = PackedFloat32Array(); _ch_spin.resize(CHUNK_CAPACITY)
	_spl_pos = PackedVector2Array(); _spl_pos.resize(SPLAT_CAPACITY)
	_spl_life = PackedFloat32Array(); _spl_life.resize(SPLAT_CAPACITY)
	_spl_radius = PackedFloat32Array(); _spl_radius.resize(SPLAT_CAPACITY)
	_spl_color = PackedColorArray(); _spl_color.resize(SPLAT_CAPACITY)
	_spl_seed = PackedFloat32Array(); _spl_seed.resize(SPLAT_CAPACITY)
	_co_tex.resize(CORPSE_CAPACITY)
	_co_pos = PackedVector2Array(); _co_pos.resize(CORPSE_CAPACITY)
	_co_scale = PackedVector2Array(); _co_scale.resize(CORPSE_CAPACITY)
	_co_life = PackedFloat32Array(); _co_life.resize(CORPSE_CAPACITY)
	_co_dir = PackedFloat32Array(); _co_dir.resize(CORPSE_CAPACITY)
	_co_color = PackedColorArray(); _co_color.resize(CORPSE_CAPACITY)
	_gh_tex.resize(GHOST_CAPACITY)
	_gh_pos = PackedVector2Array(); _gh_pos.resize(GHOST_CAPACITY)
	_gh_scale = PackedVector2Array(); _gh_scale.resize(GHOST_CAPACITY)
	_gh_life = PackedFloat32Array(); _gh_life.resize(GHOST_CAPACITY)
	_gh_color = PackedColorArray(); _gh_color.resize(GHOST_CAPACITY)
	_pf_pos = PackedVector2Array(); _pf_pos.resize(PUFF_CAPACITY)
	_pf_vel = PackedVector2Array(); _pf_vel.resize(PUFF_CAPACITY)
	_pf_life = PackedFloat32Array(); _pf_life.resize(PUFF_CAPACITY)
	_pf_size = PackedFloat32Array(); _pf_size.resize(PUFF_CAPACITY)
	_fl_pos = PackedVector2Array(); _fl_pos.resize(FLASH_CAPACITY)
	_fl_angle = PackedFloat32Array(); _fl_angle.resize(FLASH_CAPACITY)
	_fl_life = PackedFloat32Array(); _fl_life.resize(FLASH_CAPACITY)
	_fl_size = PackedFloat32Array(); _fl_size.resize(FLASH_CAPACITY)
	_fl_color = PackedColorArray(); _fl_color.resize(FLASH_CAPACITY)
