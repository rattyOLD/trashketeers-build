extends Node
func _ready() -> void:
	Orient.portrait = true
	Platform.storage_set(SaveService.BADGE_KEY, "0")
	SaveService.data["frame"] = "frame:tin"
	var own: Array = SaveService.data.get("cosmetics", [])
	own.append("frame:tin")
	SaveService.data["cosmetics"] = own
	var bg := ColorRect.new(); bg.color = Color(0.2,0.15,0.3); bg.size = Vector2(720,400); add_child(bg)
	var a := MenuWidgets.Avatar.new()
	a.custom_minimum_size = Vector2(240,240); a.position = Vector2(40,40); a.size = Vector2(240,240)
	add_child(a)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/anim/avatar.png")
	get_tree().quit()
