extends Node
## Снимок главного меню (нужен виртуальный экран, не headless).

func _ready() -> void:
	Orient.portrait = true
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var main := scene.instantiate()
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/anim/menu.png")
	get_tree().quit()
