extends Node
## Покадровый енот: листы загружены, кадр выбирается по состоянию, точка хвата меняется, рука с оружием в рамках.

func _ready() -> void:
	var fails := 0
	var sub := SubViewport.new()
	sub.size = Vector2i(720, 1280)
	add_child(sub)
	var v := RaccoonVisual.new()
	sub.add_child(v)
	v.apply_look(CharacterDB.get_character("raccoon"), {})
	await get_tree().process_frame
	if not v._clip_mode:
		fails += 1
		print("FAIL clip mode off")
	var seen: Dictionary = {}
	for i in 90:
		v.update_motion(Vector2.ZERO, Vector2(1, 0), 0.05)
		seen[v.hero.texture] = true
	print("idle frames seen ", seen.size())
	if seen.size() < 6:
		fails += 1
	var run_seen: Dictionary = {}
	for i in 60:
		v.update_motion(Vector2(220, 0), Vector2(1, 0), 0.03)
		run_seen[v.hero.texture] = true
	print("run frames seen ", run_seen.size())
	if run_seen.size() < 6:
		fails += 1
	var paw_a := v._paw_at(0.0)
	v.update_motion(Vector2(220, 0), Vector2(1, 0), 0.07)
	var paw_b := v._paw_at(0.0)
	print("paw ", paw_a, paw_b)
	if paw_a.length() > 200.0 or paw_a.length() < 5.0:
		fails += 1
		print("FAIL paw out of range")
	v.kick(Vector2.RIGHT, 1.0)
	for i in 4:
		v.update_motion(Vector2.ZERO, Vector2(1, 0), 0.05)
	print("RACCOON_CLIP_TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
