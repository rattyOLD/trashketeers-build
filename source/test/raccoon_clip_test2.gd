extends Node
func _ready() -> void:
	var sub := SubViewport.new(); sub.size = Vector2i(720, 1280); add_child(sub)
	var v := RaccoonVisual.new(); sub.add_child(v)
	v.apply_look(CharacterDB.get_character("raccoon"), {})
	await get_tree().process_frame
	var fails := 0
	v.dashing = true
	var seen := {}
	for i in 12:
		v.update_motion(Vector2(300, 0), Vector2(1, 0), 0.016); seen[v.hero.texture.region.position] = true
	print("dash frames ", seen.size()); if seen.size() < 5: fails += 1
	v.dashing = false
	v.flash(); v.update_motion(Vector2.ZERO, Vector2(1, 0), 0.02)
	var hit_pos: Vector2 = v.hero.texture.region.position
	var hit_tex = v.hero.texture.atlas
	v.play_death()
	await get_tree().create_timer(1.1).timeout
	v.update_motion(Vector2.ZERO, Vector2(1, 0), 0.02)
	print("death last: ", v.hero.texture.region.position, " atlas differs ", v.hero.texture.atlas != hit_tex, " sway ", v._sway)
	if v.hero.texture.atlas == hit_tex or v._sway != 0.0: fails += 1
	v.revive()
	await get_tree().create_timer(0.2).timeout
	v.update_motion(Vector2.ZERO, Vector2(1, 0), 0.02)
	await get_tree().create_timer(0.5).timeout
	v.update_motion(Vector2.ZERO, Vector2(1, 0), 0.02)
	print("after revive dead=", v._dead, " reviving=", v._reviving)
	if v._dead or v._reviving: fails += 1
	print("RACCOON_CLIP2 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	get_tree().quit()
