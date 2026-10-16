class_name MenuBackdrop
extends Control
## Цельная панорама базы без персонажей. Изображение заполняет экран без плитки,
## сохраняет пропорции и автоматически подстраивается под размер окна.
var _panorama: TextureRect

func build(_view_size: Vector2) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid(_panorama):
		return
	var panorama := TextureRect.new()
	_panorama = panorama
	panorama.texture = load("res://assets/ui/hub/menu_backdrop.png")
	panorama.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panorama.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	panorama.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panorama.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panorama.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panorama)
	_build_fx()


## Живой фон (слои Астры, бриф v33): мигает световой короб, поднимается пар, «дышат» тёплые окна.
## Слои лежат в координатах исходной панорамы 1536×1024 и повторяют её масштаб и кадрирование (cover).
const FX_DIR := "res://assets/ui/hub/backdrop_fx/"
const SOURCE_SIZE := Vector2(1536, 1024)
const SIGN_RECT := Rect2(1288, 76, 80, 64)
const WINDOWS_RECT := Rect2(46, 258, 1162, 231)
const SMOKE_RECTS: Array[Rect2] = [Rect2(440, 415, 256, 256), Rect2(1015, 440, 160, 192)]
const SMOKE_ALPHA := Vector2(0.12, 0.3)
const WINDOWS_ALPHA := Vector2(0.08, 0.2)
const SMOKE_SPEED := 0.06

var _mix_layer: Control
var _add_layer: Control
var _sign_on: Texture2D
var _sign_off: Texture2D
var _smoke: Texture2D
var _windows: Texture2D
var _clock := 0.0


func _build_fx() -> void:
	if not ResourceLoader.exists(FX_DIR + "smoke.png"):
		return
	_sign_on = load(FX_DIR + "sign_on.png") as Texture2D
	_sign_off = load(FX_DIR + "sign_off.png") as Texture2D
	_smoke = load(FX_DIR + "smoke.png") as Texture2D
	_windows = load(FX_DIR + "window_glow.png") as Texture2D
	_add_layer = _fx_layer(CanvasItemMaterial.BLEND_MODE_ADD)
	_add_layer.draw.connect(_draw_windows)
	_mix_layer = _fx_layer(CanvasItemMaterial.BLEND_MODE_MIX)
	_mix_layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_mix_layer.draw.connect(_draw_mix)
	set_process(true)


func _fx_layer(blend: CanvasItemMaterial.BlendMode) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = blend
	layer.material = mat
	# Слои — внутри панорамы: у фона по-прежнему один ребёнок, ресайз ничего не дублирует.
	_panorama.add_child(layer)
	return layer


func _process(delta: float) -> void:
	if _mix_layer == null or not is_visible_in_tree():
		return
	_clock += delta
	_mix_layer.queue_redraw()
	_add_layer.queue_redraw()


## Та же раскладка, что у панорамы: STRETCH_KEEP_ASPECT_COVERED по центру.
func _map(rect: Rect2) -> Rect2:
	var k := maxf(size.x / SOURCE_SIZE.x, size.y / SOURCE_SIZE.y)
	var origin := (size - SOURCE_SIZE * k) * 0.5
	return Rect2(origin + rect.position * k, rect.size * k)


func _draw_windows() -> void:
	var breath := 0.5 + 0.5 * sin(_clock * 0.9)
	_add_layer.draw_texture_rect(_windows, _map(WINDOWS_RECT), false, Color(1, 1, 1, lerpf(WINDOWS_ALPHA.x, WINDOWS_ALPHA.y, breath)))


func _draw_mix() -> void:
	for i in SMOKE_RECTS.size():
		var drift := 0.5 + 0.5 * sin(_clock * 0.5 + i * 2.0)
		var scroll := fmod(_clock * SMOKE_SPEED + i * 0.37, 1.0) * float(_smoke.get_height())
		_mix_layer.draw_texture_rect_region(_smoke, _map(SMOKE_RECTS[i]), Rect2(0, scroll, _smoke.get_width(), _smoke.get_height()), Color(1, 1, 1, lerpf(SMOKE_ALPHA.x, SMOKE_ALPHA.y, drift)))
	_mix_layer.draw_texture_rect(_sign_on if _sign_lit() else _sign_off, _map(SIGN_RECT), false)


## Короб горит почти всегда; раз в несколько секунд — короткое двойное мигание, как у старой лампы.
func _sign_lit() -> bool:
	var t := fmod(_clock, 6.5)
	return not (t > 5.6 and t < 5.75 or t > 5.9 and t < 6.0)
