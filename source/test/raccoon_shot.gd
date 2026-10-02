extends Node
## Снимок: енот на фоне, три позы с оружием — для проверки глазами.

func _ready() -> void:
	var root := Node2D.new()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("#2a2540")
	bg.size = Vector2(720, 400)
	add_child(bg)
	var poses := [[Vector2.ZERO, Vector2(1, 0), "rifle"], [Vector2.ZERO, Vector2(1, -0.9), "rifle"], [Vector2.ZERO, Vector2(1, 0.9), "rifle"], [Vector2(230, 0), Vector2(-1, -0.2), "pistol"]]
	for i in poses.size():
		var v := RaccoonVisual.new()
		v.position = Vector2(90 + i * 170, 250)
		v.weapon_icon = StringName(poses[i][2])
		add_child(v)
		v.apply_look(CharacterDB.get_character("raccoon"), {})
		for k in 40:
			v.update_motion(poses[i][0], poses[i][1], 0.03)
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/anim/shot.png")
	get_tree().quit()
