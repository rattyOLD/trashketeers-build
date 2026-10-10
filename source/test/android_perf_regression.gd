extends Node

var failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("ANDROID_PERF FAIL: " + message)


func _check_field(field: FlowField) -> void:
	for y in range(-1, field.size.y + 1):
		for x in range(-1, field.size.x + 1):
			var cell := Vector2i(x, y)
			var expected := field._direction_uncached(cell) if field._inside(cell) else Vector2.ZERO
			_check(field.direction_at(cell) == expected, "cached direction %s" % cell)
			_check(field.direction_at(cell) == expected, "repeated direction %s" % cell)


func _ready() -> void:
	WeaponController.force_auto = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 17032
	var field := FlowField.new()
	for run in 8:
		var size := Vector2i(16 + run, 20 + run)
		var blocked := PackedByteArray()
		blocked.resize(size.x * size.y)
		for i in blocked.size():
			blocked[i] = 1 if rng.randf() < 0.2 else 0
		field.setup(size, blocked)
		for target in [Vector2i(8, 10), Vector2i.ZERO, size - Vector2i.ONE, Vector2i(-1, 0)]:
			field.rebuild(target, 12)
			_check_field(field)
			for i in 6:
				var cell := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
				field.set_blocked(cell, field._blocked[field._index(cell)] == 0)
				_check_field(field)
	var empty := FlowField.new()
	empty.setup(Vector2i.ZERO, PackedByteArray())
	empty.rebuild(Vector2i.ZERO, 10)
	_check(empty.direction_at(Vector2i.ZERO) == Vector2.ZERO, "empty map")
	_check_atlas()
	_check_rig_release()
	_check_device_profile()
	_benchmark()
	print("ANDROID_PERF_REGRESSION failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check_device_profile() -> void:
	for model in ["SM-A135F", "SM-A135F/DS", "SM-A137F", "SM-A136U", "Galaxy A13"]:
		_check(DevicePerformance.is_galaxy_a13(model), "A13 model " + model)
	for model in ["SM-A145F", "SM-A315F", "SM-S918B", "", "Galaxy A13x"]:
		_check(not DevicePerformance.is_galaxy_a13(model), "other model " + model)
	var old_profile := Platform._a13
	var old_native := Platform.is_native_app
	var old_data: Dictionary = SaveService.data.duplicate(true)
	var old_size := get_window().content_scale_size
	Platform._a13 = 1
	Platform.is_native_app = true
	SaveService.data["fps_cap"] = 0
	SaveService.data["eco_fps"] = false
	_check(SaveService.get_fps_cap() == 30, "A13 default frame cap")
	SaveService.data["fps_cap"] = 60
	_check(SaveService.get_fps_cap() == 60, "explicit cap preserved")
	Platform.set_render_cap(1.0)
	_check(get_window().content_scale_size == Vector2i(960, 540), "native cap changes render size")
	_check(is_equal_approx(BattleBase.camera_zoom() / Platform.native_render_scale, BattleBase.LANDSCAPE_ZOOM), "native render cap preserves world view")
	Orient.refresh(get_window())
	_check(get_window().content_scale_size == Vector2i(960, 540), "orientation refresh retains render cap")
	Platform.set_render_cap(1.5)
	_check(get_window().content_scale_size == Orient.LANDSCAPE_SIZE, "render size restored")
	_check(DevicePerformance.adapt_threshold(30, false) < 30.0 and DevicePerformance.adapt_threshold(30, true) < 30.0, "stable 30 FPS does not degrade")
	Platform._a13 = old_profile
	Platform.is_native_app = old_native
	SaveService.data = old_data
	get_window().content_scale_size = old_size


func _check_atlas() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var batch := PolyBatch.new()
	var canvas := Node2D.new()
	add_child(canvas)
	for white in [Vector2(0.125, 0.125), Vector2(0.875, 0.875)]:
		batch.use_atlas(texture, white)
		for circles in [1, 2, 1, 1]:
			for i in circles:
				batch.circle(Vector2(i * 3, 0), 6, Color(1, 0, 0, 0.5))
			var shape_vertices := batch.points.size()
			batch.texture_rect(Rect2(0, 0, 4, 4), Rect2(0, 0, 1, 1))
			_check(batch._uvs.size() == batch.points.size(), "UV count matches geometry")
			for i in shape_vertices:
				_check(batch._uvs[i] == white, "shape UV uses current atlas white texel")
			_check(batch._uvs.slice(shape_vertices) == PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2(0, 1)]), "sprite UVs preserved")
			batch.flush(canvas)
			_check(batch.points.is_empty() and batch._uvs.is_empty(), "batch resets after flush")
	canvas.queue_free()


func _check_rig_release() -> void:
	var raw := ConfigLoader.load_json(RigDB.CONFIG_PATH)
	for entry: Dictionary in raw.get("rigs", []).slice(0, 3):
		var id := str(entry["id"])
		var rig := RigDB.get_rig(id)
		_check(rig.get("texture") != null, "rig loads " + id)
		var reference: WeakRef = weakref(rig["texture"])
		BattleMemory.release()
		_check(rig["texture"] == null and reference.get_ref() == null, "battle release drops rig texture " + id)
		_check(RigDB.get_rig(id)["texture"] != null, "rig reloads after release " + id)
	RigDB.release_textures()


func _benchmark() -> void:
	var field := FlowField.new()
	var size := Vector2i(32, 40)
	var blocked := PackedByteArray()
	blocked.resize(size.x * size.y)
	field.setup(size, blocked)
	var queries: Array[Vector2i] = []
	for i in 90:
		queries.append(Vector2i(6 + i % 12, 6 + i / 12))
	var durations: Array[int] = []
	var sum := Vector2.ZERO
	for cached in [false, true]:
		var start := Time.get_ticks_usec()
		for tick in 2000:
			if tick % 18 == 0:
				field.rebuild(Vector2i(20, 24), 22)
			for cell in queries:
				sum += field.direction_at(cell) if cached else field._direction_uncached(cell)
		durations.append(Time.get_ticks_usec() - start)
	print("NAV_BENCHMARK uncached_us=%d cached_us=%d speedup=%.2f checksum=%s" % [durations[0], durations[1], float(durations[0]) / maxf(durations[1], 1), sum])
