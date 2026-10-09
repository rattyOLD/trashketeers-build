class_name CosmeticPreview
extends Control
## Isolated showcase uses the selected skin's art without equipping it.

var key := ""
var kind := "dash"
var hero: RaccoonVisual
var _time := 0.0
var _shot := 0.0
var _bullets: Array[Dictionary] = []
var _burst: Texture2D
var _trail: Texture2D
var _bit: Texture2D
var _tracer: Texture2D
var _color := Color("#3fb8ff")
var _rainbow := false


func _init(skin_key: String = "", skin_kind: String = "dash") -> void:
	key = skin_key
	kind = skin_kind
	custom_minimum_size = Vector2(0, 300)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero = RaccoonVisual.new()
	hero.apply_look(SaveService.get_character(), SaveService.get_skin())
	hero.weapon_icon = SaveService.get_loadout().icon
	hero.weapon_color = SaveService.get_loadout().effect_color
	hero.scale = Vector2.ONE * 1.1
	add_child(hero)
	if not key.is_empty():
		_color = Cosmetics.color_of(key)
		_rainbow = bool((Cosmetics.CATALOG.get(key, {}) as Dictionary).get("rainbow", false))
	_burst = Cosmetics.texture_for(key, "burst")
	_trail = Cosmetics.texture_for(key, "trail")
	_bit = Cosmetics.texture_for(key, "bit")
	_tracer = Cosmetics.texture_for(key, "tracer")
	if kind == "shot" and key.is_empty():
		_color = hero.weapon_color


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if kind == "dash":
		var phase := fmod(_time, 2.0)
		var from := Vector2(size.x * 0.22, size.y * 0.78)
		var to := Vector2(size.x * 0.78, from.y)
		hero.dashing = phase < 0.32
		hero.position = from.lerp(to, clampf(phase / 0.32, 0.0, 1.0))
		hero.update_motion((to - from) / 0.32 if hero.dashing else Vector2.ZERO, Vector2.RIGHT, delta)
	else:
		hero.position = Vector2(size.x * 0.5, size.y * 0.72)
		var aim := Vector2.from_angle(_time * 1.1)
		hero.update_motion(Vector2.ZERO, aim, delta)
		_shot -= delta
		if _shot <= 0.0:
			_shot = 0.18
			hero.kick(aim, 1.0)
			var muzzle := get_global_transform().affine_inverse() * hero.get_muzzle_global(aim)
			_bullets.append({"pos": muzzle, "dir": aim, "age": 0.0})
		for i in range(_bullets.size() - 1, -1, -1):
			_bullets[i]["age"] = float(_bullets[i]["age"]) + delta
			_bullets[i]["pos"] = (_bullets[i]["pos"] as Vector2) + (_bullets[i]["dir"] as Vector2) * 430.0 * delta
			if float(_bullets[i]["age"]) > 0.8:
				_bullets.remove_at(i)
	queue_redraw()


func _draw() -> void:
	draw_style_box(UiStyle.card_box(), Rect2(Vector2.ZERO, size))
	if kind == "dash":
		var phase := fmod(_time, 2.0)
		if phase < 1.2:
			var from := Vector2(size.x * 0.22, size.y * 0.78 - 35.0)
			var to := Vector2(hero.position.x, from.y)
			var fade := 1.0 - clampf((phase - 0.32) / 0.88, 0.0, 1.0)
			if _trail != null:
				draw_texture_rect(_trail, Rect2(from.x, from.y - 24.0, maxf(1.0, to.x - from.x), 48.0), false, Color(1, 1, 1, fade))
			else:
				draw_line(from, to, Color(_color, fade * 0.55), 18.0, true)
			if _burst != null and phase < 6.0 / 22.0:
				var frame := mini(5, int(phase * 22.0))
				var side := _burst.get_height()
				draw_texture_rect_region(_burst, Rect2(from - Vector2(48, 48), Vector2(96, 96)), Rect2(frame * side, 0, side, side))
			for i in 6:
				var point := from.lerp(to, float(i) / 6.0) + Vector2(0, sin(i * 2.1 + phase * 8.0) * 14.0)
				if _bit != null:
					draw_texture_rect(_bit, Rect2(point - Vector2(10, 10), Vector2(20, 20)), false, Color(1, 1, 1, fade))
				elif not key.is_empty():
					draw_circle(point, 3.0, Color(_color, fade))
	else:
		for bullet in _bullets:
			var pos: Vector2 = bullet["pos"]
			var dir: Vector2 = bullet["dir"]
			var color := Color.from_hsv(fmod(_time * 0.7 + float(bullet["age"]), 1.0), 0.8, 1.0) if _rainbow else _color
			draw_line(pos - dir * 46.0, pos, Color(color, 0.5), 8.0, true)
			if _tracer != null and not _rainbow:
				var px := _tracer.get_size() * (64.0 / maxf(1.0, _tracer.get_width()))
				draw_set_transform(pos, dir.angle())
				draw_texture_rect(_tracer, Rect2(-px * 0.5, px), false)
				draw_set_transform(Vector2.ZERO)
			else:
				draw_line(pos - dir * 24.0, pos, color.lightened(0.4), 4.0, true)
				draw_circle(pos, 3.5, Color.WHITE)
