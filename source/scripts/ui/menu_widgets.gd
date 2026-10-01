class_name MenuWidgets
extends RefCounted
## Нарисованные кодом элементы меню из паспорта интерфейса: иконки кнопок, лапки-тумблеры,
## круглая аватарка и размытый задник биома. Всё с тёмной мультяшной обводкой.

const LINE := Color("#1a0f2a")
const GEAR := Color("#e0e0e0")


## Квадратная кнопка нижней панели с нарисованной иконкой.
class IconButton:
	extends Button
	enum Kind { SHOP, ARMORY }
	var kind: Kind = Kind.SHOP
	var caption := ""

	func _init(button_kind: Kind, label_text: String, color: Color) -> void:
		kind = button_kind
		caption = label_text
		custom_minimum_size = Vector2(150, 150)
		focus_mode = Control.FOCUS_NONE
		add_theme_stylebox_override("normal", UiStyle.box(color, LINE, 6, 28))
		add_theme_stylebox_override("hover", UiStyle.box(color.lightened(0.1), LINE, 6, 28))
		add_theme_stylebox_override("pressed", UiStyle.box(color.darkened(0.1), Color.WHITE, 6, 28))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		pressed.connect(func() -> void: SoundManager.play(&"ui_click"))

	func _draw() -> void:
		var c := size * Vector2(0.5, 0.42)
		if kind == Kind.SHOP:
			_draw_box(c)
		else:
			_draw_armory(c)
		var font := ThemeDB.fallback_font
		var pos := Vector2(0, size.y - 14)
		draw_string_outline(font, pos, caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, 7, LINE)
		draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, UiStyle.TEXT)

	## Картонная коробка с торчащими фиолетовыми лазерными очками.
	func _draw_box(c: Vector2) -> void:
		var box := Rect2(c + Vector2(-40, -14), Vector2(80, 52))
		draw_rect(box.grow(4), LINE)
		draw_rect(box, Color("#c08a55"))
		draw_rect(Rect2(box.position, Vector2(box.size.x, 12)), Color("#a8743f"))
		draw_line(c + Vector2(0, -14), c + Vector2(0, 38), Color("#8a5a2c"), 3.0)
		var glasses := c + Vector2(0, -26)
		draw_line(glasses + Vector2(-30, 0), glasses + Vector2(30, 0), LINE, 7.0)
		for side in [-1.0, 1.0]:
			var lens := Rect2(glasses + Vector2(side * 16 - 12, -8), Vector2(24, 16))
			draw_rect(lens.grow(3), LINE)
			draw_rect(lens, Color("#b84dff"))
			draw_line(lens.position + Vector2(4, 4), lens.position + Vector2(10, 4), Color(1, 1, 1, 0.7), 2.0)

	## Скрещённые патроны и гаечный ключ.
	func _draw_armory(c: Vector2) -> void:
		for side in [-1.0, 1.0]:
			var xf := Transform2D(side * 0.6, c)
			var shell := PackedVector2Array([Vector2(-7, 30), Vector2(7, 30), Vector2(7, -12), Vector2(0, -30), Vector2(-7, -12)])
			draw_colored_polygon(xf * PackedVector2Array([Vector2(-10, 33), Vector2(10, 33), Vector2(10, -13), Vector2(0, -35), Vector2(-10, -13)]), LINE)
			draw_colored_polygon(xf * shell, Color("#ffd257"))
			draw_colored_polygon(xf * PackedVector2Array([Vector2(-7, -12), Vector2(7, -12), Vector2(0, -30)]), Color("#d98a3a"))
		var wrench := Transform2D(0.0, c + Vector2(0, 8))
		draw_line(wrench * Vector2(0, -26), wrench * Vector2(0, 30), LINE, 14.0)
		draw_line(wrench * Vector2(0, -24), wrench * Vector2(0, 28), Color("#b8c0d0"), 8.0)
		draw_circle(wrench * Vector2(0, -28), 13.0, LINE)
		draw_circle(wrench * Vector2(0, -28), 9.0, Color("#b8c0d0"))
		draw_rect(Rect2(wrench * Vector2(-4, -42), Vector2(8, 14)), LINE)


## Неоново-серая шестерёнка: при наведении/тапе плавно проворачивается на 45° по часовой.
class GearButton:
	extends Button

	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_entered.connect(_spin)
		button_down.connect(_spin)
		resized.connect(func() -> void: pivot_offset = size * 0.5)
		pressed.connect(func() -> void: SoundManager.play(&"ui_click"))

	func _spin() -> void:
		var tween := create_tween()
		tween.tween_property(self, "rotation", rotation + PI * 0.25, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var c := size * 0.5
		var art := ArenaProp.texture_of("res://assets/ui/hub/settings.png")
		if art != null:
			draw_texture_rect(art, Rect2(c - size * 0.5, size), false)
			return
		var teeth := PackedVector2Array()
		for i in 16:
			var r := 28.0 if i % 2 == 0 else 21.0
			teeth.append(c + Vector2.from_angle(TAU * i / 16.0 - PI / 16.0) * r)
			teeth.append(c + Vector2.from_angle(TAU * i / 16.0 + PI / 16.0) * r)
		draw_colored_polygon(teeth, GEAR)
		var loop := teeth.duplicate()
		loop.append(teeth[0])
		draw_polyline(loop, LINE, 3.0, true)
		draw_circle(c, 9.0, LINE)
		draw_circle(c, 6.0, Color("#3a3552"))


## Кнопка «на весь экран»: четыре уголка, при включённом режиме уголки смотрят внутрь.
class FullscreenButton:
	extends Button

	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		focus_mode = Control.FOCUS_NONE
		flat = true
		pressed.connect(func() -> void:
			SoundManager.play(&"ui_click")
			if not Platform.fullscreen_supported():
				_show_install_hint()
				return
			Platform.set_fullscreen(not Platform.is_fullscreen())
			get_tree().create_timer(0.4).timeout.connect(queue_redraw))

	func _show_install_hint() -> void:
		var layer := CanvasLayer.new()
		layer.layer = 90
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.72)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.add_child(center)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.NEON, 4, 24))
		center.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 14)
		panel.add_child(column)
		var title := UiStyle.label("ИГРА НА ВЕСЬ ЭКРАН", 34, UiStyle.GOLD, 8)
		column.add_child(title)
		var text := UiStyle.label("iPhone не даёт включить полный экран из браузера.\n1. Нажми «Поделиться» в Safari.\n2. Выбери «На экран Домой».\n3. Запускай игру с иконки: без адресной строки и панелей.", 24, UiStyle.TEXT, 5)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(700, 0)
		column.add_child(text)
		var ok := UiStyle.button("ПОНЯТНО", UiStyle.HOT, 32, Vector2(0, 76))
		ok.pressed.connect(layer.queue_free)
		column.add_child(ok)
		get_tree().root.add_child(layer)

	func _draw() -> void:
		var inside := Platform.is_fullscreen()
		var box := Rect2(size * 0.22, size * 0.56)
		var arm := 11.0
		draw_rect(Rect2(Vector2.ZERO, size).grow(-4.0), Color(0.08, 0.06, 0.16, 0.85), true)
		draw_rect(Rect2(Vector2.ZERO, size).grow(-4.0), Color("#7b6ad8"), false, 3.0)
		for corner in 4:
			var origin := box.position + Vector2(box.size.x * (corner % 2), box.size.y * (corner / 2))
			var sx := 1.0 if corner % 2 == 0 else -1.0
			var sy := 1.0 if corner / 2 == 0 else -1.0
			if inside:
				sx = -sx
				sy = -sy
				origin -= Vector2(sx, sy) * arm
			draw_line(origin, origin + Vector2(sx * arm, 0), Color("#ffe27a"), 4.0)
			draw_line(origin, origin + Vector2(0, sy * arm), Color("#ffe27a"), 4.0)


## Тумблер в виде енотовой лапки: включён — светлая лапка с неоновыми подушечками.
class PawToggle:
	extends Button
	var caption := ""

	func _init(label_text: String, enabled: bool) -> void:
		caption = label_text
		toggle_mode = true
		button_pressed = enabled
		focus_mode = Control.FOCUS_NONE
		flat = true
		custom_minimum_size = Vector2(0, 96)
		toggled.connect(func(_on: bool) -> void:
			SoundManager.play(&"ui_click")
			queue_redraw())

	func _draw() -> void:
		var on := button_pressed
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(0, size.y * 0.5 + 12), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 120, 32, 8, LINE)
		draw_string(font, Vector2(0, size.y * 0.5 + 12), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 120, 32, UiStyle.TEXT)
		var c := Vector2(size.x - 56, size.y * 0.5 + 6)
		var pad := Color("#ff9fc4") if on else Color("#5a5068")
		var fur := Color("#f4f0ff") if on else Color("#3a3552")
		draw_circle(c, 26.0 + 3.0, LINE)
		draw_circle(c, 26.0, fur)
		draw_circle(c + Vector2(0, 4), 12.0, pad)
		for i in 4:
			var toe := c + Vector2.from_angle(-PI * 0.85 + i * PI * 0.23) * 22.0
			draw_circle(toe, 8.0 + 2.0, LINE)
			draw_circle(toe, 8.0, fur)
			draw_circle(toe, 4.5, pad)
		if on:
			draw_arc(c, 36.0, 0.0, TAU, 32, Color(UiStyle.NEON, 0.6), 3.0, true)


## Круглая аватарка героя: голова вырезается из цельного кадра с круглой альфа-маской и
## перекрашивается на CPU той же градиентной картой, что и шейдер (окрас героя + наряд + слой
## аксессуаров). Результат кэшируется по паре «герой:наряд».
class Avatar:
	extends Control
	static var _cache: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(72, 72)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, LINE)
		draw_circle(c, r - 4.0, Color("#3a2d60"))
		var tex: Texture2D = null
		var custom := str(SaveService.data.get("avatar", ""))
		if not custom.is_empty() and ResourceLoader.exists(custom):
			tex = load(custom) as Texture2D
		if tex == null:
			tex = get_texture_for(SaveService.get_character(), SaveService.get_selected_skin())
		if tex != null:
			draw_texture_rect(tex, Rect2(c - Vector2.ONE * (r - 5.0), Vector2.ONE * (r - 5.0) * 2.0), false)
		draw_arc(c, r - 2.0, 0.0, TAU, 40, UiStyle.NEON, 3.0, true)

	static func get_texture_for(character: Dictionary, skin_id: String) -> ImageTexture:
		var key := "%s:%s" % [character.get("id", ""), skin_id]
		if _cache.has(key):
			return _cache[key]
		if character.has("portrait") and character.has("sprite"):
			var portrait := str(character["portrait"])
			if ResourceLoader.exists(portrait):
				var image := (load(portrait) as Texture2D).get_image()
				if image.is_compressed():
					image.decompress()
				var cropped := ImageTexture.create_from_image(image)
				_cache[key] = cropped
				return cropped
		var full := RaccoonVisual.get_sprite_texture()
		if full == null:
			return null
		var source := full.get_image()
		if source.is_compressed():
			source.decompress()
		source.convert(Image.FORMAT_RGBA8)
		var region := RaccoonVisual.get_avatar_rect().intersection(Rect2i(Vector2i.ZERO, source.get_size()))
		var side := mini(region.size.x, region.size.y)
		var rect := Rect2i(region.position, Vector2i(side, side))
		var head := source.get_region(rect)
		var skin: Dictionary = SaveService.SKINS.get(skin_id, {})
		var look: Dictionary = skin.get("look", {})
		var recolor: Dictionary = (character.get("recolor", {}) as Dictionary).duplicate()
		var skin_recolor: Dictionary = look.get("recolor", {})
		for region_name in skin_recolor:
			recolor[region_name] = skin_recolor[region_name]
		var regions := _region_images(rect)
		var overlay: Image = null
		var overlay_path := RaccoonVisual.OVERLAY_DIR + str(look.get("overlay", "")) + "_body.png"
		if look.has("overlay") and ResourceLoader.exists(overlay_path):
			var ov := (load(overlay_path) as Texture2D).get_image()
			if ov.is_compressed():
				ov.decompress()
			ov.convert(Image.FORMAT_RGBA8)
			overlay = ov.get_region(rect)
		var params := RaccoonVisual.build_recolor(recolor)
		var center := Vector2(side, side) * 0.5
		for y in side:
			for x in side:
				if Vector2(x + 0.5, y + 0.5).distance_to(center) > side * 0.5:
					head.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				var col := head.get_pixel(x, y)
				if not recolor.is_empty() and regions.size() == 2:
					col = _recolor_pixel(col, regions[0].get_pixel(x, y), regions[1].get_pixel(x, y), params)
				if overlay != null:
					var ov_col := overlay.get_pixel(x, y)
					col = Color(col.lerp(ov_col, ov_col.a), maxf(col.a, ov_col.a))
				head.set_pixel(x, y, col)
		var texture := ImageTexture.create_from_image(head)
		_cache[key] = texture
		return texture

	static func _region_images(rect: Rect2i) -> Array:
		var paths: PackedStringArray = RigDB.get_rig(RaccoonVisual.RIG_ID).get("regions", PackedStringArray())
		var out := []
		for path in paths:
			var tex := RigDB.data_texture(path)
			if tex == null:
				return []
			out.append(tex.get_image().get_region(rect))
		return out

	## CPU-копия recolor() из rig2d.gdshader.
	static func _recolor_pixel(col: Color, r0: Color, r1: Color, params: Dictionary) -> Color:
		var weights := [r0.r, r0.g, r0.b, r0.a, r1.r, r1.g]
		var luma := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
		var dark: PackedColorArray = params["grad_dark"]
		var mid: PackedColorArray = params["grad_mid"]
		var light: PackedColorArray = params["grad_light"]
		var ranges: PackedVector2Array = params["grad_range"]
		var rgb := Color(col.r, col.g, col.b)
		for i in 6:
			var amount: float = weights[i] * light[i].a
			if amount < 0.003:
				continue
			var t := clampf((luma - ranges[i].x) / maxf(ranges[i].y - ranges[i].x, 0.01), 0.0, 1.0)
			var g := dark[i].lerp(mid[i], t * 2.0) if t < 0.5 else mid[i].lerp(Color(light[i].r, light[i].g, light[i].b), t * 2.0 - 1.0)
			rgb = rgb.lerp(Color(g.r, g.g, g.b), amount)
		return Color(rgb.r, rgb.g, rgb.b, col.a)


## Размытый затемнённый силуэт Свалки за Енотом: фиолетовые заборы, неон и виньетка.
class StageBackdrop:
	extends Control
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var horizon := size.y * 0.62
		for layer in 3:
			var shade := Color("#2a1a4a").lerp(Color("#140c28"), layer * 0.4)
			var y := horizon - 120.0 + layer * 55.0
			var x := -40.0 + layer * 35.0
			while x < size.x + 40.0:
				var w := 150.0 + (int(x) % 70)
				var h := 150.0 - layer * 30.0 + (int(x * 0.37) % 40)
				draw_rect(Rect2(x, y - h, w, h + 400.0), Color(shade, 0.85))
				x += w + 18.0
		var flicker := 0.7 + 0.3 * absf(sin(_time * 2.3)) if int(_time * 3.0) % 7 != 0 else 0.2
		for s in [Vector2(0.18, 0.3), Vector2(0.82, 0.24)]:
			var p := Vector2(size.x * s.x, size.y * s.y)
			draw_circle(p, 70.0, Color(UiStyle.HOT, 0.07 * flicker))
			draw_arc(p, 22.0, 0.0, TAU, 24, Color(UiStyle.HOT, 0.5 * flicker), 4.0, true)
		for k in 6:
			var t := float(k) / 5.0
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * 0.12 * (1.0 - t), size.y)), Color(0, 0, 0, 0.07))
			draw_rect(Rect2(Vector2(size.x * (1.0 - 0.12 * (1.0 - t)), 0), Vector2(size.x, size.y)), Color(0, 0, 0, 0.07))
		draw_rect(Rect2(Vector2(0, horizon + 60.0), size), Color(0.02, 0.01, 0.05, 0.5))


## Живое превью героя в интерфейсе (гардероб, логотип): RaccoonVisual на риге внутри Control —
## дышит, моргает, оглядывается; окрас героя, наряд и эффект — настоящие.
class RaccoonPreview:
	extends Control
	const TRACER_SPEED := 1250.0
	const BURST_SHOTS := 3
	const SHOT_GAP := 0.14
	var raccoon: RaccoonVisual
	var _time := 0.0
	var _scale := 1.0
	var _cheer_timer := 0.0
	## Витрина боя: герой периодически замирает в стойке, разворачивается и даёт очередь; тап делает то же самое.
	var _volley_timer := 0.0
	var _aim_dir := Vector2.RIGHT
	var _aim_hold := 0.0
	var _shots_left := 0
	var _shot_timer := 0.0
	var _tracers: Array[Vector3] = []
	var _tracer_dirs: Array[Vector2] = []

	func _init(skin: Dictionary, preview_scale: float = 1.0, character: Dictionary = {}) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scale = preview_scale
		raccoon = RaccoonVisual.new()
		raccoon.apply_look(character if not character.is_empty() else SaveService.get_character(), skin)
		raccoon.weapon_icon = SaveService.get_loadout().icon
		raccoon.weapon_color = SaveService.get_loadout().effect_color
		raccoon.scale = Vector2.ONE * preview_scale
		add_child(raccoon)
		_time = randf() * 10.0
		_cheer_timer = randf_range(3.0, 7.0)
		_volley_timer = randf_range(1.2, 2.5)

	func set_skin(skin: Dictionary) -> void:
		raccoon.apply_look(SaveService.get_character(), skin)

	func set_look(character: Dictionary, skin: Dictionary) -> void:
		raccoon.apply_look(character, skin)

	## Короткая радость по запросу (покупка, выбор) — превью подпрыгивает.
	func celebrate() -> void:
		raccoon.cheer()

	## Очередь в случайную сторону: герой поворачивается, отдача и трассеры.
	func fire_burst() -> void:
		var side := 1.0 if randf() < 0.5 else -1.0
		_aim_dir = Vector2(side, randf_range(-0.12, 0.05)).normalized()
		_aim_hold = SHOT_GAP * BURST_SHOTS + 0.55
		_shots_left = BURST_SHOTS
		_shot_timer = 0.12

	func _process(delta: float) -> void:
		_time += delta
		raccoon.position = Vector2(size.x * 0.5, size.y * 0.5 + 34.0 * _scale)
		var look := Vector2(cos(_time * 0.7), sin(_time * 1.1) * 0.3)
		if _aim_hold > 0.0:
			_aim_hold -= delta
			look = _aim_dir
			_tick_burst(delta)
		else:
			_volley_timer -= delta
			if _volley_timer <= 0.0:
				_volley_timer = randf_range(3.0, 5.5)
				fire_burst()
		raccoon.update_motion(Vector2.ZERO, look, delta)
		_cheer_timer -= delta
		if _cheer_timer <= 0.0:
			_cheer_timer = randf_range(6.0, 11.0)
			raccoon.cheer()
		_move_tracers(delta)

	func _tick_burst(delta: float) -> void:
		if _shots_left <= 0:
			return
		_shot_timer -= delta
		if _shot_timer > 0.0:
			return
		_shot_timer = SHOT_GAP
		_shots_left -= 1
		raccoon.kick(_aim_dir, 1.0)
		var muzzle := get_global_transform().affine_inverse() * raccoon.get_muzzle_global(_aim_dir)
		_tracers.append(Vector3(muzzle.x, muzzle.y, 0.0))
		_tracer_dirs.append(_aim_dir)

	func _move_tracers(delta: float) -> void:
		for i in range(_tracers.size() - 1, -1, -1):
			var t := _tracers[i]
			var pos := Vector2(t.x, t.y) + _tracer_dirs[i] * TRACER_SPEED * delta
			var life := t.z + delta
			if life > 0.5 or not Rect2(-160.0, -160.0, size.x + 320.0, size.y + 320.0).has_point(pos):
				_tracers.remove_at(i)
				_tracer_dirs.remove_at(i)
			else:
				_tracers[i] = Vector3(pos.x, pos.y, life)
		queue_redraw()

	func _draw() -> void:
		var color := raccoon.weapon_color
		for i in _tracers.size():
			var pos := Vector2(_tracers[i].x, _tracers[i].y)
			var dir := _tracer_dirs[i]
			draw_line(pos - dir * 46.0, pos, Color(color, 0.35), 8.0, true)
			draw_line(pos - dir * 30.0, pos, Color(color.lightened(0.5), 0.9), 4.0, true)
			draw_circle(pos, 5.0, Color.WHITE)


## Кнопка нижней навигации хаба: нарисованная иконка + подпись.
class NavButton:
	extends Button
	enum Kind { UPGRADES, WEAPONS, SKINS, ACHIEVEMENTS, OUTFITS }
	var kind: Kind = Kind.UPGRADES
	var caption := ""
	var accent := Color.WHITE
	var badge := false
	## Рисованная иконка с концепт-листа; без неё — запасная векторная.
	var icon_texture: Texture2D

	func _init(button_kind: Kind, label_text: String, color: Color, icon: Texture2D = null) -> void:
		icon_texture = icon
		kind = button_kind
		caption = label_text
		accent = color
		custom_minimum_size = Vector2(0, 124)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_NONE
		add_theme_stylebox_override("normal", UiStyle.box(Color(0.1, 0.07, 0.2, 0.82), color.darkened(0.2), 4, 22))
		add_theme_stylebox_override("hover", UiStyle.box(Color(0.14, 0.1, 0.26, 0.9), color, 4, 22))
		add_theme_stylebox_override("pressed", UiStyle.box(color.darkened(0.55), Color.WHITE, 4, 22))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		pressed.connect(func() -> void: SoundManager.play(&"ui_click"))

	func _draw() -> void:
		var captioned := not Orient.portrait or badge or is_pressed() or is_hovered()
		var c := Vector2(size.x * 0.5, size.y * (0.4 if captioned else 0.5))
		if icon_texture != null:
			var side := minf(size.x * 0.72, size.y * (0.62 if captioned else 0.78))
			var tex_size := icon_texture.get_size()
			var fit := side / maxf(tex_size.x, tex_size.y)
			var draw_size := tex_size * fit
			draw_texture_rect(icon_texture, Rect2(c - draw_size * 0.5 + Vector2(0, -2), draw_size), false)
			_draw_caption()
			return
		match kind:
			Kind.UPGRADES:
				var arrow := PackedVector2Array([c + Vector2(0, -30), c + Vector2(26, -2), c + Vector2(10, -2), c + Vector2(10, 26), c + Vector2(-10, 26), c + Vector2(-10, -2), c + Vector2(-26, -2)])
				var grown := Geometry2D.offset_polygon(arrow, 4.0, Geometry2D.JOIN_ROUND)
				if not grown.is_empty():
					draw_colored_polygon(grown[0], LINE)
				draw_colored_polygon(arrow, accent)
			Kind.WEAPONS:
				WeaponIcons.draw(self, &"rifle", c, 0.9, -0.35, accent)
			Kind.SKINS:
				draw_circle(c + Vector2(-20, -18), 11.0, LINE)
				draw_circle(c + Vector2(20, -18), 11.0, LINE)
				draw_circle(c + Vector2(-20, -18), 8.0, Color("#8e8aa6"))
				draw_circle(c + Vector2(20, -18), 8.0, Color("#8e8aa6"))
				draw_circle(c, 27.0, LINE)
				draw_circle(c, 24.0, Color("#8e8aa6"))
				draw_rect(Rect2(c + Vector2(-20, -8), Vector2(40, 12)), Color("#231d33"))
				draw_circle(c + Vector2(-9, -2), 4.0, Color.WHITE)
				draw_circle(c + Vector2(9, -2), 4.0, Color.WHITE)
				draw_circle(c + Vector2(0, 10), 4.0, LINE)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-26, -26), c + Vector2(26, -26), c + Vector2(0, -44)]), accent)
			Kind.OUTFITS:
				var shirt := PackedVector2Array([c + Vector2(-14, -28), c + Vector2(-32, -18), c + Vector2(-24, -2), c + Vector2(-16, -8), c + Vector2(-16, 28), c + Vector2(16, 28), c + Vector2(16, -8), c + Vector2(24, -2), c + Vector2(32, -18), c + Vector2(14, -28), c + Vector2(6, -22), c + Vector2(-6, -22)])
				var shirt_edge := Geometry2D.offset_polygon(shirt, 4.0, Geometry2D.JOIN_ROUND)
				if not shirt_edge.is_empty():
					draw_colored_polygon(shirt_edge[0], LINE)
				draw_colored_polygon(shirt, accent)
				draw_circle(c + Vector2(0, 6), 7.0, Color(1, 1, 1, 0.85))
			Kind.ACHIEVEMENTS:
				var cup := PackedVector2Array([c + Vector2(-22, -26), c + Vector2(22, -26), c + Vector2(16, 2), c + Vector2(4, 10), c + Vector2(4, 18), c + Vector2(14, 22), c + Vector2(14, 28), c + Vector2(-14, 28), c + Vector2(-14, 22), c + Vector2(-4, 18), c + Vector2(-4, 10), c + Vector2(-16, 2)])
				var grown := Geometry2D.offset_polygon(cup, 4.0, Geometry2D.JOIN_ROUND)
				if not grown.is_empty():
					draw_colored_polygon(grown[0], LINE)
				draw_colored_polygon(cup, accent)
				draw_arc(c + Vector2(-22, -14), 10.0, PI * 0.5, PI * 1.5, 10, LINE, 5.0)
				draw_arc(c + Vector2(22, -14), 10.0, -PI * 0.5, PI * 0.5, 10, LINE, 5.0)
		_draw_caption()

	func _draw_caption() -> void:
		if badge:
			draw_circle(Vector2(size.x - 18, 18), 10.0, LINE)
			draw_circle(Vector2(size.x - 18, 18), 7.0, UiStyle.DANGER)
		if not (not Orient.portrait or badge or is_pressed() or is_hovered()):
			return
		var font := ThemeDB.fallback_font
		var pos := Vector2(0, size.y - 12)
		draw_string_outline(font, pos, caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, 6, LINE)
		draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, accent.lightened(0.55) if not is_pressed() else Color.WHITE)


## Кубик — случайный ник.
class DiceButton:
	extends Button

	func _init() -> void:
		custom_minimum_size = Vector2(84, 84)
		focus_mode = Control.FOCUS_NONE
		add_theme_stylebox_override("normal", UiStyle.box(Color("#ffffff"), LINE, 4, 18))
		add_theme_stylebox_override("hover", UiStyle.box(Color("#e8f6ff"), LINE, 4, 18))
		add_theme_stylebox_override("pressed", UiStyle.box(Color("#c8e8ff"), LINE, 4, 18))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		pressed.connect(func() -> void:
			SoundManager.play(&"ui_click")
			var tween := create_tween()
			pivot_offset = size * 0.5
			tween.tween_property(self, "rotation", rotation + PI * 0.5, 0.25).set_trans(Tween.TRANS_BACK))

	func _draw() -> void:
		var c := size * 0.5
		var r := Rect2(c - Vector2(24, 24), Vector2(48, 48))
		draw_rect(r.grow(3.0), LINE)
		draw_rect(r, Color("#ff2ea6"))
		for p in [Vector2(-12, -12), Vector2(12, -12), Vector2(0, 0), Vector2(-12, 12), Vector2(12, 12)]:
			draw_circle(c + p, 5.0, Color.WHITE)


class PlusBadge extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, UiStyle.OUTLINE)
		draw_circle(c, r - 3.0, Color("#2fae5f"))
		draw_line(c + Vector2(-r * 0.4, 0.0), c + Vector2(r * 0.4, 0.0), Color.WHITE, 4.0, true)
		draw_line(c + Vector2(0.0, -r * 0.4), c + Vector2(0.0, r * 0.4), Color.WHITE, 4.0, true)
