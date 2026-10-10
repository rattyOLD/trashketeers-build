class_name LightMap
extends Node
## Карта освещения боя: мир затемнён до ambient, а источники света (герой, огонь, неон, вспышки
## выстрелов и взрывов из EnvLights) «проявляют» его мягкими пятнами. Свет рисуется в маленький
## SubViewport (1/DIVIDER разрешения) аддитивно поверх ambient и ложится на мир умножением
## (CanvasItemMaterial MUL) — один дешёвый проход вместо PointLight2D, который в Compatibility
## перерисовывает освещённые узлы на каждый источник.

const DIVIDER := 4
const TEXTURE_SIZE := 64
const HERO_RADIUS := 420.0
const HERO_COLOR := Color(1.0, 0.86, 0.66)
const HERO_STRENGTH := 0.42
const LIGHT_GAIN := 0.9

static var _texture: ImageTexture
static var _vignette: ImageTexture
static var _mottle: ImageTexture
## Неровность света: мягкая полутень по краям экрана и медленно плывущие пятна по полу —
## два дешёвых умножения в маленьком вьюпорте, убирают «плоский» ровный свет.
const VIGNETTE_EDGE := 0.68
const MOTTLE_DEPTH := 0.28
const MOTTLE_SCALE := 9.0
const MOTTLE_DRIFT := Vector2(14.0, 6.0)

var ambient := Color(0.7, 0.68, 0.78)
## Тон по типу главы: Свалка (М1–М3) — темнее, Банк (М4–М6) — светлее. Не хоррор: свет только мягче/ярче.
const LAYOUT_AMBIENT := {
	"junkyard": Color(0.66, 0.64, 0.74),
	"bank": Color(0.84, 0.81, 0.86),
}


func set_layout(layout: String) -> void:
	ambient = LAYOUT_AMBIENT.get(layout, ambient)
var player: Node2D

var _viewport: SubViewport
var _ambient: ColorRect
var _lights: LightDraw
var _overlay: TextureRect
var _mottle_rect: Sprite2D
var _clock := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	_clock += delta


func build(parent: Node, layer: int) -> void:
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_viewport)
	var screen := CanvasLayer.new()
	screen.layer = -1
	_viewport.add_child(screen)
	_ambient = ColorRect.new()
	_ambient.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(_ambient)
	var multiply_in := CanvasItemMaterial.new()
	multiply_in.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_mottle_rect = Sprite2D.new()
	_mottle_rect.texture = mottle_texture()
	_mottle_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_mottle_rect.region_enabled = true
	_mottle_rect.material = multiply_in
	_mottle_rect.centered = false
	_viewport.add_child(_mottle_rect)
	var vignette := TextureRect.new()
	vignette.texture = vignette_texture()
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.material = multiply_in
	screen.add_child(vignette)
	_lights = LightDraw.new()
	_lights.owner_map = self
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = additive
	_viewport.add_child(_lights)

	var top := CanvasLayer.new()
	top.layer = layer
	parent.add_child(top)
	_overlay = TextureRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overlay.texture = _viewport.get_texture()
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_overlay.material = multiply
	top.add_child(_overlay)
	RenderingServer.frame_pre_draw.connect(_sync)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)


## Перед отрисовкой кадра: размер и камера карты повторяют основной вьюпорт (с интерполяцией камеры).
func _sync() -> void:
	if not is_inside_tree():
		return
	var main := get_viewport()
	var size := Vector2i((main.get_visible_rect().size / DIVIDER).ceil())
	if _viewport.size != size:
		_viewport.size = size
	_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE / DIVIDER) * main.canvas_transform
	_ambient.color = ambient
	_lights.view = main.canvas_transform.affine_inverse() * main.get_visible_rect()
	# Пятна лежат в мире (ползут медленно), покрывают видимую область с запасом.
	var tile := float(TEXTURE_SIZE) * MOTTLE_SCALE
	var area := _lights.view.grow(tile)
	var origin := (area.position / tile).floor() * tile
	_mottle_rect.position = origin
	_mottle_rect.scale = Vector2.ONE * MOTTLE_SCALE
	_mottle_rect.region_rect = Rect2(MOTTLE_DRIFT * _clock / MOTTLE_SCALE, (area.end - origin) / MOTTLE_SCALE)
	_lights.queue_redraw()


## Края экрана темнее центра (круг под портрет/альбом растягивается вместе с экраном).
static func vignette_texture() -> ImageTexture:
	if _vignette == null:
		var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		var half := TEXTURE_SIZE * 0.5
		for y in TEXTURE_SIZE:
			for x in TEXTURE_SIZE:
				var d := clampf(Vector2(x + 0.5 - half, y + 0.5 - half).length() / (half * 1.41), 0.0, 1.0)
				var f := lerpf(1.0, VIGNETTE_EDGE, smoothstep(0.45, 1.0, d))
				img.set_pixel(x, y, Color(f, f, f, 1.0))
		_vignette = ImageTexture.create_from_image(img)
	return _vignette


## Бесшовный шум полутени: 1 — свет, 1 − MOTTLE_DEPTH — самые тёмные пятна.
static func mottle_texture() -> ImageTexture:
	if _mottle == null:
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.045
		noise.fractal_octaves = 2
		var img := noise.get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
		img.convert(Image.FORMAT_RGBA8)
		for y in TEXTURE_SIZE:
			for x in TEXTURE_SIZE:
				var v := img.get_pixel(x, y).r
				var f := 1.0 - MOTTLE_DEPTH * smoothstep(0.45, 0.8, v)
				img.set_pixel(x, y, Color(f, f, f, 1.0))
		_mottle = ImageTexture.create_from_image(img)
	return _mottle


static func light_texture() -> ImageTexture:
	if _texture == null:
		var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		var half := TEXTURE_SIZE * 0.5
		for y in TEXTURE_SIZE:
			for x in TEXTURE_SIZE:
				var d := clampf(Vector2(x + 0.5 - half, y + 0.5 - half).length() / half, 0.0, 1.0)
				var f := (1.0 - d) * (1.0 - d)
				img.set_pixel(x, y, Color(f, f, f, 1.0))
		_texture = ImageTexture.create_from_image(img)
	return _texture


class LightDraw:
	extends Node2D
	var owner_map: LightMap
	var view := Rect2()
	var _buffer := EnvLights.LightBuffer.new()

	func _draw() -> void:
		var tex := LightMap.light_texture()
		EnvLights.collect(view, _buffer)
		if owner_map.player != null and is_instance_valid(owner_map.player):
			_buffer.positions.append(owner_map.player.global_position)
			_buffer.colors.append(LightMap.HERO_COLOR * LightMap.HERO_STRENGTH)
			_buffer.radii.append(LightMap.HERO_RADIUS)
		for i in _buffer.positions.size():
			var r := _buffer.radii[i]
			var c := _buffer.colors[i] * LightMap.LIGHT_GAIN
			c.a = 1.0
			draw_texture_rect(tex, Rect2(_buffer.positions[i] - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
