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

var ambient := Color(0.7, 0.68, 0.78)
## Тон по типу главы: Свалка (М1–М3) — темнее, Банк (М4–М6) — светлее. Не хоррор: свет только мягче/ярче.
const LAYOUT_AMBIENT := {
	"junkyard": Color(0.62, 0.6, 0.71),
	"bank": Color(0.84, 0.81, 0.86),
}


func set_layout(layout: String) -> void:
	ambient = LAYOUT_AMBIENT.get(layout, ambient)
var player: Node2D

var _viewport: SubViewport
var _ambient: ColorRect
var _lights: LightDraw
var _overlay: TextureRect


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


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
	_lights.queue_redraw()


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
	var _pos := PackedVector2Array()
	var _color := PackedColorArray()
	var _radius := PackedFloat32Array()

	func _draw() -> void:
		var tex := LightMap.light_texture()
		EnvLights.collect(view, _pos, _color, _radius)
		if owner_map.player != null and is_instance_valid(owner_map.player):
			_pos.append(owner_map.player.global_position)
			_color.append(LightMap.HERO_COLOR * LightMap.HERO_STRENGTH)
			_radius.append(LightMap.HERO_RADIUS)
		for i in _pos.size():
			var r := _radius[i]
			var c := _color[i] * LightMap.LIGHT_GAIN
			c.a = 1.0
			draw_texture_rect(tex, Rect2(_pos[i] - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
