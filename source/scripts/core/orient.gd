class_name Orient
extends RefCounted
## Ориентация экрана. База холста подстраивается под телефон: 1280×720 в альбомной и 720×1280 в портретной,
## а окна и панели выбирают раскладку по Orient.portrait.

const LANDSCAPE_SIZE := Vector2i(1280, 720)
const PORTRAIT_SIZE := Vector2i(720, 1280)

static var portrait := false


## Возвращает true, если ориентация сменилась.
static func refresh(window: Window) -> bool:
	var size := DisplayServer.window_get_size()
	var want := size.y > size.x
	var changed := want != portrait
	portrait = want
	window.content_scale_size = PORTRAIT_SIZE if want else LANDSCAPE_SIZE
	return changed
