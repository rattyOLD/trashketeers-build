extends Node

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("BRIEF_COMPLETION FAIL: " + label)


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	for id in ["sniper_f", "medic_f"]:
		var hero: Dictionary = CharacterDB.get_character(id)
		_check(not hero.get("coming_soon", true) and hero.has("skill"), id + " available with skill")
		var portrait := HudWidgets.DamagePortrait.new()
		portrait.set_character(hero)
		for stage in 4:
			_check(portrait.has_art(stage), id + " damage portrait " + str(stage))
		portrait.free()
		for clip in ["idle", "run", "shoot", "hit", "dash", "death", "revive", "fidget"]:
			_check(ResourceLoader.exists("res://assets/heroes/tactical/" + id + "_" + clip + ".png"), id + " clip " + clip)
	SaveService.add_stat("scars", 5, false)
	var scar_face := HudWidgets.DamagePortrait.new()
	scar_face.set_character(CharacterDB.get_character("raccoon"))
	_check(scar_face._face.scars.size() == 5 and scar_face._face.scars_visible, "Rico scars align only to healthy base")
	scar_face.health = 0.4
	scar_face._pick_face()
	_check(not scar_face._face.scars_visible, "scar overlays hidden on differently framed damage portraits")
	scar_face.free()
	for id in ["raccoon", "red_panda", "snow", "night", "maloy"]:
		var tex := MenuWidgets.Avatar.get_texture_for(CharacterDB.get_character(id), "default")
		_check(tex != null and tex.get_width() <= 160, "small avatar " + id)
		var image := tex.get_image()
		_check(image.get_used_rect().has_area(), "visible avatar " + id)
	var visual := RaccoonVisual.new()
	add_child(visual)
	visual.apply_look(CharacterDB.get_character("night"), {})
	_check(visual.uses_clips(), "night uses new animation sheets")
	for clip in ["idle", "run", "shoot"]:
		var frames: Array = visual._clip_frames[clip]
		var points: Array = visual._clip_grip[clip]
		_check(frames.size() == int(RaccoonVisual.CLIP_COUNTS[clip]) and frames.size() == points.size(), "matching hand/grip frames " + clip)
		for point: Array in points:
			_check(point.size() == 4 and float(point[0]) >= 0 and float(point[0]) < 300 and float(point[2]) >= 0 and float(point[2]) < 300, "grips inside cell " + clip)
	_check(not visual._clip_frames.has("death"), "death remains lazy")
	_check(visual.play_fidget(), "night fidget")
	visual.play_death()
	visual.update_motion(Vector2.ZERO, Vector2.RIGHT, 0.016)
	_check(visual._clip_frames.has("death"), "death loads when needed")
	var face := HudWidgets.DamagePortrait.new()
	face.size = face.custom_minimum_size
	face.set_character(CharacterDB.get_character("night"))
	add_child(face)
	for stage in 4:
		_check(face.has_art(stage), "night damage portrait " + str(stage))
	for kind in ["hit", "angry", "grin", "proud", "scared", "tired"]:
		face.react(kind)
		_check(face._face.tex != null and face._face.tex.get_image().get_used_rect().has_area(), "visible face " + kind)
	face.hide()
	for win in [true, false]:
		var mood := HeroMoodCard.new(CharacterDB.get_character("night"), win)
		_check(mood._posed, "drawn result pose")
		mood.free()
	_check(not BestiaryPopup.discovered("rat_punk"), "new player has locked cards")
	SaveService.add_stat("k_rat_punk", 1, false)
	_check(BestiaryPopup.discovered("rat_punk"), "old kill statistics unlock existing players")
	SaveService.add_stat("seen_bomb_rat", 1, false)
	_check(BestiaryPopup.discovered("bomb_rat"), "encounter unlocks without kill")
	var popup := BestiaryPopup.new()
	add_child(popup)
	popup.open()
	_check(popup._entries.size() == ContentDB.get_enemy_ids().size() + 1, "all enemies and raid dragon")
	_check(popup._grid.get_child_count() == popup._entries.size(), "all cards displayed")
	popup._select_filter("boss")
	var bosses := 1
	for id in ContentDB.get_enemy_ids():
		bosses += int(ContentDB.get_enemy(id).is_boss())
	_check(popup._grid.get_child_count() == bosses, "boss filter includes all bosses")
	popup._select_filter("bomber")
	var bombers := 0
	for id in ContentDB.get_enemy_ids():
		var kind: String = str(EnemyData.Behavior.keys()[ContentDB.get_enemy(id).behavior]).to_lower()
		bombers += int(kind == "bomber" or kind == "exploder")
	# Считаем по данным: с картами Выживания у голубей-бомбардиров появился фирменный собрат.
	_check(bombers >= 3 and popup._grid.get_child_count() == bombers, "bomb filter includes explosive rat and bombers")
	popup._select_filter("")
	await get_tree().create_timer(0.8).timeout
	if DisplayServer.get_name() != "headless":
		var box: Control = popup._panel
		var xf := box.get_global_transform()
		var rect := Rect2(xf.origin, box.size * xf.get_scale())
		_check(get_viewport().get_visible_rect().encloses(rect), "catalog fits viewport")
		var out := OS.get_environment("BRIEF_OUT")
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out)
			get_viewport().get_texture().get_image().save_png(out.path_join("bestiary.png"))
	popup.close()
	await get_tree().create_timer(0.25).timeout
	_check(not popup.visible, "catalog closes")
	var loading := LoadingScreen.new()
	add_child(loading)
	for mission in ["m1", "m2"]:
		_check(ResourceLoader.exists("res://assets/story/chapter_cards/chapter_%s.png" % mission.trim_prefix("m")), "chapter title " + mission)
	loading.show_chapter("m1")
	_check(not loading._title.visible, "drawn chapter title replaces rotating text")
	_check(ResourceLoader.exists("res://assets/story/gates/aquilon_sign.png"), "checkpoint sign")
	await get_tree().create_timer(0.3).timeout
	var out := OS.get_environment("BRIEF_OUT")
	if not out.is_empty() and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(out.path_join("chapter_loading.png"))
	print("BRIEF_COMPLETION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
