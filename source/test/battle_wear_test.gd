extends Node
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("BATTLE_WEAR FAIL: " + message)


func _settle() -> void:
	await get_tree().create_timer(0.18, true, false, true).timeout
	await RenderingServer.frame_post_draw


func _run() -> void:
	SaveService.data = SaveService.DEFAULTS.duplicate(true)
	var view := SubViewport.new()
	view.size = Vector2i(640, 480)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2.ZERO, Vector2(640, 0), Vector2(640, 480), Vector2(0, 480)])
	bg.color = Color("#404040")
	view.add_child(bg)
	var patch := SectorPatch.new()
	view.add_child(patch)
	patch.build(Vector2(320, 240), 160, load("res://assets/maps/night_dump/floor.png"), Color.WHITE, Color.BLACK, 5353)
	var transition := patch.get_node("SurfaceTransition") as MeshInstance2D
	_check(transition != null and not patch.is_processing(), "organic floor has a static transition mesh")
	var data := transition.mesh.surface_get_arrays(0)
	var alpha := data[Mesh.ARRAY_COLOR] as PackedColorArray
	_check(alpha[0].a == 1 and alpha[2].a == 0, "edge fades continuously to the underlying floor")
	await _settle()
	var baseline := view.get_texture().get_image()
	var floor_before := baseline
	var wear := BattleWear.new()
	view.add_child(wear)
	seed(5353)
	var expected := randf()
	seed(5353)
	wear.stamp(Vector2(320, 240), 0, 180)
	_check(randf() == expected, "cosmetic marks preserve the gameplay random stream")
	await _settle()
	var stamped := view.get_texture().get_image()
	_check(baseline.get_data() != stamped.get_data(), "explosion visibly changes the ground")
	_check(not wear.is_processing(), "persistent marks have no per-frame work")
	get_tree().paused = true
	wear.queue_redraw()
	wear.stamp(Vector2(100, 100), 1, 80)
	await _settle()
	_check(stamped.get_data() == view.get_texture().get_image().get_data() and wear.marks.size() == 1, "pause and redraw keep the exact ground pixels")
	get_tree().paused = false
	wear.stamp(Vector2(320, 240), 0, 180)
	_check(wear.marks.size() == 1, "repeated impacts do not stack identical marks")
	for i in BattleWear.CAPACITY + 30:
		wear.stamp(Vector2(i * 36, 40), i % 4, 80)
	await _settle()
	_check(wear.marks.size() == BattleWear.CAPACITY, "long fights have a bounded ground buffer")
	wear.clear()
	await _settle()
	_check(wear.marks.is_empty() and wear._mesh == null, "chapter transition removes old damage")
	var object := DestructibleObject.new()
	object.position = Vector2(320, 360)
	var decals := Node2D.new()
	view.add_child(decals)
	object.setup_art("d_dumpster", decals)
	view.add_child(object)
	await _settle()
	baseline = view.get_texture().get_image()
	object.take_damage(object.max_hp * 0.45)
	object._process(0.2)
	object.set_process(false)
	await _settle()
	_check(object.hp > 0 and is_equal_approx(object._flash_material.get_shader_parameter("damage_amount"), 0.45), "surface damage follows health without changing combat")
	var prop_after := view.get_texture().get_image()
	_check(baseline.get_data() != prop_after.get_data(), "dents remain after the hit flash")
	object.take_damage(object.max_hp)
	await _settle()
	_check(object.hp == 0, "object destruction still works")
	if object.has_node("Glow"):
		_check(not object.get_node("Glow").visible, "destroyed equipment stops lighting")
	_check(object._flash_material.get_shader_parameter("damage_amount") == 0.0, "replacement debris does not inherit sprite damage")
	var output := OS.get_environment("BATTLE_WEAR_OUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		floor_before.save_png(output.path_join("floor-before.png"))
		baseline.save_png(output.path_join("prop-before.png"))
		prop_after.save_png(output.path_join("prop-after.png"))
		stamped.save_png(output.path_join("floor-after.png"))
	view.free()
	print("BATTLE_WEAR failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
