extends Node
func _ready() -> void:
	Orient.portrait = false
	get_window().content_scale_size = Orient.LANDSCAPE_SIZE
	var u := AppUpdater.new()
	add_child(u)
	await get_tree().process_frame
	u._native = RefCounted.new()
	u._remote = {"code": 46, "bytes": 55 * 1024 * 1024, "sha256": "0".repeat(64)}
	u._show("beta.46", "")
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	print("LOCAL ", AppUpdater.local_code())
	get_tree().quit()
