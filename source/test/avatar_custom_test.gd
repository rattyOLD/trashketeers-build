extends Node
func _ready() -> void:
	var im := Image.create(300, 200, false, Image.FORMAT_RGB8)
	im.fill(Color(0.9, 0.2, 0.1))
	var info := {"type": "image/png", "data": Marshalls.raw_to_base64(im.save_png_to_buffer())}
	var ok := AvatarPicker.store_photo(info)
	var tex := AvatarPicker.portrait_texture(str(SaveService.data.get("avatar", "")))
	var good := ok and tex != null and tex.get_width() == AvatarPicker.CUSTOM_SIDE
	var bad := AvatarPicker.store_photo({"type": "image/png", "data": "AAAA"})
	print("AVATAR_CUSTOM ", "PASS" if good and not bad else "FAIL %s %s %s" % [ok, tex, bad])
	get_tree().quit()
