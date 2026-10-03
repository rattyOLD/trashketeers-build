extends Node
func _ready() -> void:
	Orient.portrait = true
	get_window().content_scale_size = Orient.PORTRAIT_SIZE
	var u := AppUpdater.new()
	add_child(u)
	await get_tree().process_frame
	u._show("beta.25", "Карты выживания: карта +50%, районы во всех главах")
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	print("LOCAL ", AppUpdater.local_code())
	get_tree().quit()
