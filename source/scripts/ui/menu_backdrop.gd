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
