extends Node2D
## Every tactical hero holds short/long guns at all aim angles and animation frames.
var failures := 0
var actors: Array[RaccoonVisual] = []
const IDS := ["raccoon", "red_panda", "snow", "night", "neon_hopper", "fluffy_chemist", "pigeon_mafioso"]


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		if failures < 12:
			push_error("HAND_GRIP FAIL " + message)


func _run() -> void:
	var configs: Array = ConfigLoader.load_json("res://data/characters.json").get("characters", [])
	for id in IDS:
		var character: Dictionary = {}
		for cfg: Dictionary in configs:
			if str(cfg["id"]) == id:
				character = cfg
		var actor := RaccoonVisual.new()
		add_child(actor)
		actor.apply_look(character, {})
		actors.append(actor)
		_check(actor._clip_has_arm_rig(), id + " separate arm layers loaded")
		for clip: String in ["idle", "run", "shoot"]:
			for frame in int(RaccoonVisual.CLIP_COUNTS[clip]):
				actor._clip_cur = clip
				actor._clip_idx = frame
				var point: Array = actor._clip_grip[clip][frame]
				actor._clip_grip_px = Vector2(float(point[0]), float(point[1]))
				for weapon: StringName in [&"pistol", &"revolver", &"shotgun", &"rifle", &"sniper", &"minigun"]:
					actor.weapon_icon = weapon
					for angle_index in 8:
						var dir := Vector2.from_angle(angle_index * TAU / 8.0)
						actor._facing = -1.0 if dir.x < 0 else 1.0
						actor._sway = 0.0
						actor._gun_angle = atan2(dir.y,dir.x*actor._facing)
						actor._kick = 3.0
						var center := actor._gun_center(actor._paw_at(0.0), dir, 3.0)
						for which: String in ["right", "left"]:
							var shoulder := actor._clip_source_joint(which,"shoulder")
							var elbow := actor._clip_source_joint(which,"elbow")
							var palm := actor._clip_source_joint(which,"palm")
							var target := actor._clip_hand_target(which,center,dir)
							var upper := actor._clip_segment_transform(which,"upper",target)
							var fore := actor._clip_segment_transform(which,"fore",target)
							_check((fore*palm).distance_to(target) < 0.25, "%s %s %s %d %s angle=%d miss=%.3f" % [id,which,clip,frame,weapon,angle_index,(fore*palm).distance_to(target)])
							_check((upper*shoulder).distance_to(actor._clip_shoulder(which)) < 0.02, "arm begins at its own shoulder")
							if actor._clip_baked_upper(which):
								_check((fore*elbow).distance_to(actor._clip_body_elbow(which)) < 0.02, "forearm begins at the existing sleeve end")
							else:
								_check((upper*elbow).distance_to(fore*elbow) < 0.02, "continuous elbow joint")
							var original_scale := actor._sprite_xform().get_scale()
							_check(absf(absf(upper.get_scale().x)-absf(original_scale.x)) < 0.001, "upper arm stays original size")
							_check(absf(absf(fore.get_scale().x)-absf(original_scale.x)) < 0.001, "forearm and hand stay original size")

		actor.scale = Vector2.ONE * 2.0
		var index := actors.size()-1
		actor.position = Vector2(200 + index%4*390, 480 + index/4*460)
		var label := Label.new()
		label.text = id
		label.position = actor.position + Vector2(-110, 25)
		label.add_theme_font_size_override("font_size", 20)
		add_child(label)
	var output := OS.get_environment("HAND_GRIP_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		get_window().size = Vector2i(1600, 1000)
		get_window().content_scale_size = Vector2i(1600, 1000)
		var focus := OS.get_environment("HAND_GRIP_FOCUS").split(",",false)
		if not focus.is_empty():
			get_window().size = Vector2i(focus.size()*600, 760)
			get_window().content_scale_size = get_window().size
			for child in get_children():
				if child is Label:
					child.hide()
			for index in actors.size():
				var slot := focus.find(IDS[index])
				actors[index].position = Vector2(290+slot*600,620) if slot >= 0 else Vector2(5000,5000)
				actors[index].scale = Vector2.ONE*3.8
				if slot >= 0:
					var label := Label.new()
					label.text = {"raccoon":"Рико","red_panda":"Фитиль","snow":"Снег","night":"Найт","pigeon_mafioso":"Дон"}.get(IDS[index],IDS[index])
					label.position = actors[index].position+Vector2(-120,35)
					label.add_theme_font_size_override("font_size",28)
					add_child(label)
		for sample in [
			{"name":"arms", "weapon":&"pistol", "dir":Vector2.RIGHT, "show_weapon":false},
			{"name":"pistol", "weapon":&"pistol", "dir":Vector2.RIGHT},
			{"name":"shotgun", "weapon":&"shotgun", "dir":Vector2.RIGHT},
			{"name":"up", "weapon":&"rifle", "dir":Vector2.UP},
			{"name":"left", "weapon":&"pistol", "dir":Vector2.LEFT},
			{"name":"run_shotgun", "weapon":&"shotgun", "dir":Vector2.RIGHT, "velocity":Vector2(160,0)},
			{"name":"left_shotgun", "weapon":&"shotgun", "dir":Vector2.LEFT},
			{"name":"diagonal", "weapon":&"rifle", "dir":Vector2(1,-1).normalized()},
		]:
			for actor in actors:
				actor.show_held_weapon = sample.get("show_weapon",true)
				actor.weapon_icon = sample["weapon"]
				actor._run = 0.0
				actor._shoot_t = 0.0
				actor._fidget_t = 0.0
				actor.update_motion(sample.get("velocity",Vector2.ZERO), sample["dir"], 1.0)
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join(sample["name"] + ".png"))
	print("HAND_GRIP failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
