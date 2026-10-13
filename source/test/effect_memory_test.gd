extends Node

var failures := 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("EFFECT_MEMORY: " + message)

func _texture() -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func _populate(fx: FxManager) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	var texture := _texture()
	refs.append(weakref(texture))
	fx.corpse(texture, Vector2.ZERO, Vector2.ONE, 0.0)
	texture = _texture()
	refs.append(weakref(texture))
	fx.ghost(texture, Vector2.ZERO, Vector2.ONE, Color.WHITE)
	texture = _texture()
	refs.append(weakref(texture))
	fx.flipbook(texture, Vector2.ZERO, 2, 10.0, 20.0)
	texture = _texture()
	refs.append(weakref(texture))
	fx.sprite_flash(texture, Vector2.ZERO, 20.0, 0.2)
	texture = _texture()
	refs.append(weakref(texture))
	fx.slash_sweep(texture, Vector2.ZERO, Vector2.RIGHT, 20.0, 0.2, 1.0, 0.6)
	return refs

func _frame_corpse(fx: FxManager) -> Array[WeakRef]:
	FrameDB.has_sheet("memory_fixture")
	var texture := _texture()
	var regions := _texture()
	var refs: Array[WeakRef] = [weakref(texture), weakref(regions)]
	RigDB._data_textures["memory_regions"] = regions
	FrameDB._sheets["memory_fixture"] = {
		"id": "memory_fixture", "texture": texture, "texture_path": "",
		"density": 1.0, "regions": PackedStringArray(["memory_regions", "memory_regions"]),
		"rects": [Rect2(0, 0, 8, 8)], "pivots": PackedVector2Array([Vector2(4, 8)]),
		"clips": {"death": {"frames": PackedInt32Array([0]), "loop": false, "fps": 8.0}},
	}
	var source := RigSprite.new()
	add_child(source)
	source.setup_frames("memory_fixture")
	source.set_param("tint", Color.WHITE)
	fx.frame_corpse(source, Vector2.ZERO, Vector2.ONE)
	source.free()
	FrameDB.release_textures()
	RigDB._data_textures.erase("memory_regions")
	return refs

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame

func _enemy_resources(enemy: Enemy) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for key in ["weights0", "weights1", "weights2", "regions0", "regions1"]:
		var texture := _texture()
		refs.append(weakref(texture))
		enemy._sprite.set_param(key, texture)
	var texture := _texture()
	refs.append(weakref(texture))
	enemy._alt.texture = texture
	texture = _texture()
	refs.append(weakref(texture))
	ArenaProp._textures["memory_part"] = texture
	enemy._parts.setup([{"texture": "memory_part"}])
	ArenaProp._textures.erase("memory_part")
	return refs

func _chapter_resources() -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	var texture := _texture()
	refs.append(weakref(texture))
	RigDB._data_textures["memory_chapter"] = texture
	texture = _texture()
	refs.append(weakref(texture))
	RigDB._rigs["memory_chapter"] = {"texture": texture}
	return refs

func _chapters() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	SaveService._sanitize_arsenal()
	SaveService.data["tester"]["god"] = true
	SaveService.data["tips_off"] = true
	var game := Game.new()
	add_child(game)
	game.start()
	game.director.set_physics_process(false)
	game.player.weapon_controller.set_physics_process(false)
	for chapter_index in range(1, 6):
		game.enemies.release_all()
		var enemy := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(200, 0))
		var refs := _enemy_resources(enemy)
		refs.append_array(_chapter_resources())
		refs.append_array(_populate(game.fx))
		var hero_texture := game.player.visual.get_ghost_texture()
		game._switch_chapter(chapter_index)
		await _settle()
		for reference in refs:
			_check(reference.get_ref() == null, "chapter transition releases old resource")
		_check(game.player.visual.get_ghost_texture() == hero_texture, "chapter transition preserves hero art")
		_check(game.enemies.get_active_count() == 0, "old enemies released")
		var next := game.enemies.spawn(ContentDB.get_enemy(&"rat_punk"), game.player.global_position + Vector2(200, 0))
		_check(next != null and next.get_texture() != null, "enemy pool loads art again")
		print("MEMORY_CHAPTER index=%d vram=%.1fMB nodes=%d" % [chapter_index, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	game.free()
	BattleMemory.release()
	RigDB._rigs.erase("memory_chapter")
	await _settle()
	SoundManager.stop_all_loops()
	SoundManager.stop_ambient()
	SoundManager.stop_music()
	await get_tree().create_timer(SoundManager.MUSIC_FADE + 0.2).timeout
	SoundManager._music.stream = null
	await _settle()

func _ready() -> void:
	Controls.apply_keys()
	for use_clear in [false, true]:
		var fx := FxManager.new()
		add_child(fx)
		fx.set_process(false)
		var refs := _populate(fx)
		refs.append_array(_frame_corpse(fx))
		for reference in refs:
			_check(reference.get_ref() != null, "live effect retains its art")
		fx.light_flash(Vector2.ZERO, Color.WHITE, 1.0, 60.0, 0.2)
		if use_clear:
			fx.clear()
		else:
			fx._process(10.0)
		await _settle()
		for i in refs.size():
			_check(refs[i].get_ref() == null, "%s releases texture %d" % ["clear" if use_clear else "expiry", i])
		for node in fx._fc_nodes:
			_check(not node.visible, "finished frame corpse is hidden")
		_check(not fx._fb_nodes[0].visible and not fx._sf_nodes[0].visible and not fx._sw_nodes[0].visible, "finished sprites are hidden")
		_check(not fx._lights[0].enabled, "finished light disabled")
		var next_refs := _populate(fx)
		fx._process(0.01)
		for reference in next_refs:
			_check(reference.get_ref() != null, "reused pool renders live art")
		fx.free()
		await _settle()
		for reference in next_refs:
			_check(reference.get_ref() == null, "closed pool releases textures")
	FrameDB._sheets.erase("memory_fixture")
	await _chapters()
	print("EFFECT_MEMORY failures=", failures)
	get_tree().quit(1 if failures else 0)
