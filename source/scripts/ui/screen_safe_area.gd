class_name ScreenSafeArea
extends RefCounted

## Тестовые сцены подменяют вырез экрана (слева, сверху, справа, снизу в пикселях холста).
static var test_insets := Vector4.ZERO


static func rect(view: Vector2) -> Rect2:
	var insets := Vector4.ZERO
	if test_insets != Vector4.ZERO:
		insets = test_insets
		return Rect2(Vector2(insets.x, insets.y), Vector2(maxf(view.x - insets.x - insets.z, 1.0), maxf(view.y - insets.y - insets.w, 1.0)))
	if OS.has_feature("web"):
		var raw := str(JavaScriptBridge.eval("JSON.stringify(window.trashSafeInsets ? window.trashSafeInsets() : [0,0,0,0])"))
		var values: Variant = JSON.parse_string(raw)
		if values is Array and values.size() == 4:
			var width := maxf(float(JavaScriptBridge.eval("window.innerWidth")), 1.0)
			var height := maxf(float(JavaScriptBridge.eval("window.innerHeight")), 1.0)
			insets = Vector4(float(values[0]) * view.x / width, float(values[1]) * view.y / height, float(values[2]) * view.x / width, float(values[3]) * view.y / height)
	elif OS.has_feature("mobile"):
		var window := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if window.x > 0.0 and window.y > 0.0 and safe.has_area():
			insets = Vector4(maxf(safe.position.x, 0.0) * view.x / window.x, maxf(safe.position.y, 0.0) * view.y / window.y, maxf(window.x - safe.end.x, 0.0) * view.x / window.x, maxf(window.y - safe.end.y, 0.0) * view.y / window.y)
	return Rect2(Vector2(insets.x, insets.y), Vector2(maxf(view.x - insets.x - insets.z, 1.0), maxf(view.y - insets.y - insets.w, 1.0)))


static func fit(control: Control, view: Vector2, padding: float = 0.0) -> void:
	var safe := rect(view).grow(-padding)
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = safe.position.x
	control.offset_top = safe.position.y
	control.offset_right = safe.end.x - view.x
	control.offset_bottom = safe.end.y - view.y
