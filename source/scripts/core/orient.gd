class_name Orient
extends RefCounted
## Ориентация экрана. На телефонах игра только вертикальная (720×1280), горизонтальная раскладка 1280×720
## доступна только на ПК. Окна и панели выбирают раскладку по Orient.portrait.

const LANDSCAPE_SIZE := Vector2i(1280, 720)
const PORTRAIT_SIZE := Vector2i(720, 1280)

static var portrait := false
static var desktop := true
static var _probed := false


static func _probe() -> void:
	if _probed:
		return
	_probed = true
	if OS.has_feature("web"):
		desktop = not bool(JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches"))
	else:
		desktop = OS.has_feature("pc")


## Нужна ли вертикальная раскладка для окна такого размера.
static func wants_portrait(width: float, height: float) -> bool:
	_probe()
	return height > width or not desktop


## Возвращает true, если ориентация сменилась.
static func refresh(window: Window) -> bool:
	var size := Vector2(DisplayServer.window_get_size())
	if OS.has_feature("web"):
		size = Vector2(float(JavaScriptBridge.eval("window.innerWidth")), float(JavaScriptBridge.eval("window.innerHeight")))
	var want := wants_portrait(size.x, size.y)
	var changed := want != portrait
	portrait = want
	window.content_scale_size = PORTRAIT_SIZE if want else LANDSCAPE_SIZE
	return changed
