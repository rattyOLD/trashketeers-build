class_name WeaponPreview
extends Control
## Витрина оружия: ствол в рамке стреляет (или бьёт) по мишени так, как в бою: пули, вспышки, попадания,
## рикошет, поджог, взрыв и дуги взмаха берутся из данных оружия на выбранном тире. Тап — выстрел сейчас.

const FLOOR := 0.8
const SHOT_SPEED_MUL := 0.62
const BULLET_DRAW_MUL := 1.6
const MAX_BULLETS := 40
const NO_CASING := [&"blaster", &"coil", &"prism", &"rail", &"railgun", &"magnet", &"toaster", &"casino", &"launcher", &"mortar", &"flamer", &"slingshot", &"harpoon", &"capgun", &"heavy_barrel"]
const MELEE_K := 1.9
const HELD_SCALE := 0.8

var weapon: WeaponData
var _t := 0.0
var _next_shot := 0.5
var _burst_left := 0
var _recoil := 0.0
var _flash := 0.0
var _hit := 0.0
var _hit2 := 0.0
var _swing := -1.0
var _swings := 0
var _echo := -1.0
var _burn := 0.0
var _blast := -1.0
var _frost := -1.0
var _bullets: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _numbers: Array[Dictionary] = []
var _casings: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 290)
	clip_contents = true
	set_process(true)


func set_weapon(w: WeaponData) -> void:
	weapon = w
	_bullets.clear()
	_impacts.clear()
	_numbers.clear()
	_casings.clear()
	_swing = -1.0
	_burst_left = 0
	_next_shot = _t + 0.45
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed and weapon != null:
		_next_shot = _t
		_burst_left = 0


# ---- геометрия сцены ----

func _origin() -> Vector2:
	return Vector2(size.x * (0.27 if weapon != null and weapon.is_melee() else 0.22), size.y * 0.58)


func _target() -> Vector2:
	var x := size.x * 0.84
	if weapon != null and weapon.is_melee():
		x = minf(_origin().x + weapon.melee_reach * MELEE_K * 0.9, size.x - 70.0)
	return Vector2(x, size.y * FLOOR - 62.0)


func _back_target() -> Vector2:
	return _target() + Vector2(52.0, -58.0)


func _icon_scale() -> float:
	return clampf(size.x / 215.0, 1.7, 3.1)


func _muzzle_pos() -> Vector2:
	return _origin() + WeaponIcons.muzzle(weapon.icon) * _icon_scale() + Vector2(-_recoil * 10.0, 0.0)


# ---- логика ----

func _process(delta: float) -> void:
	if weapon == null or not is_visible_in_tree():
		return
	_t += delta
	_recoil = maxf(_recoil - delta * 7.0, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_hit = maxf(_hit - delta * 3.5, 0.0)
	_hit2 = maxf(_hit2 - delta * 3.5, 0.0)
	_burn = maxf(_burn - delta, 0.0)
	if _blast >= 0.0:
		_blast += delta
		if _blast > 0.45:
			_blast = -1.0
	if _frost >= 0.0:
		_frost += delta
		if _frost > 0.7:
			_frost = -1.0
	if weapon.is_melee():
		_step_melee(delta)
	else:
		_step_gun(delta)
	_step_effects(delta)
	queue_redraw()


func _step_gun(delta: float) -> void:
	if _t >= _next_shot:
		var interval := clampf(weapon.fire_interval, 0.07, 1.1)
		if _burst_left <= 0 and interval < 0.25:
			_burst_left = 7
		_fire()
		if _burst_left > 0:
			_burst_left -= 1
			_next_shot = _t + (interval if _burst_left > 0 else 0.9)
		else:
			_next_shot = _t + maxf(interval, 0.55)
	var live: Array[Dictionary] = []
	for b in _bullets:
		_move_bullet(b, delta)
		if float(b["life"]) > 0.0:
			live.append(b)
	_bullets = live


func _fire() -> void:
	_recoil = 1.0
	_flash = 0.09
	if weapon.icon not in NO_CASING:
		_casings.append({"pos": _origin() + Vector2(10.0, -6.0), "vel": Vector2(randf_range(-70.0, -20.0), randf_range(-190.0, -120.0)), "rot": randf() * TAU, "age": 0.0})
		while _casings.size() > 6:
			_casings.pop_front()
	var count := clampi(weapon.projectiles_per_shot, 1, 7)
	var base := _muzzle_pos()
	for i in count:
		var angle := 0.0
		if count > 1:
			angle = lerpf(-1.0, 1.0, float(i) / float(count - 1)) * maxf(weapon.spread_rad, 0.12) * 0.55
		var speed := clampf(weapon.bullet_speed, 380.0, 1500.0) * SHOT_SPEED_MUL
		var dir := Vector2.from_angle(angle)
		if count == 1 and weapon.spread_rad > 0.02:
			dir = Vector2.from_angle(randf_range(-0.5, 0.5) * minf(weapon.spread_rad, 0.1))
		_bullets.append({
			"pos": base, "vel": dir * speed, "life": 2.0, "trail": [], "hits": 0,
			"goal": 0, "done": false,
		})
	if _bullets.size() > MAX_BULLETS:
		_bullets = _bullets.slice(_bullets.size() - MAX_BULLETS)


func _move_bullet(b: Dictionary, delta: float) -> void:
	var pos: Vector2 = b["pos"]
	var trail: Array = b["trail"]
	trail.push_front(pos)
	var keep := clampi(weapon.trail_points + 3, 4, 14)
	while trail.size() > keep:
		trail.pop_back()
	var vel: Vector2 = b["vel"]
	pos += vel * delta
	b["pos"] = pos
	b["life"] = float(b["life"]) - delta
	var goal: Vector2 = _target() if int(b["goal"]) == 0 else _back_target()
	var radius := 30.0 if int(b["goal"]) == 0 else 22.0
	if not bool(b["done"]) and pos.distance_to(goal) < radius + weapon.bullet_radius:
		_on_hit(b, goal)
	elif pos.x > size.x + 40.0 or pos.y < -40.0 or pos.y > size.y + 40.0:
		b["life"] = 0.0


func _on_hit(b: Dictionary, goal: Vector2) -> void:
	var hits := int(b["hits"]) + 1
	b["hits"] = hits
	_spark(goal)
	if int(b["goal"]) == 0:
		_hit = 1.0
	else:
		_hit2 = 1.0
	if weapon.explosion_radius > 0.0 and hits == 1:
		_blast = 0.0
	if weapon.burn > 0.0:
		_burn = 1.6
	if weapon.ricochet_count >= hits:
		b["goal"] = 1 - int(b["goal"])
		var next_goal: Vector2 = _target() if int(b["goal"]) == 0 else _back_target()
		var speed: float = (b["vel"] as Vector2).length()
		b["vel"] = (next_goal - goal).normalized() * speed
		return
	if weapon.piercing:
		b["done"] = true
		return
	b["life"] = 0.0


func _spark(at: Vector2) -> void:
	_impacts.append({"pos": at, "age": 0.0})
	var amount := int(weapon.damage * (randf_range(0.9, 1.1)))
	_numbers.append({"pos": at + Vector2(randf_range(-14.0, 14.0), -34.0), "age": 0.0, "text": "-%d" % amount})
	while _numbers.size() > 8:
		_numbers.pop_front()


func _step_melee(delta: float) -> void:
	var period := clampf(weapon.fire_interval * 1.15, 0.5, 1.6)
	if _swing < 0.0 and _t >= _next_shot:
		_swing = 0.0
		_swings += 1
		_next_shot = _t + period
	if _swing >= 0.0:
		var total := maxf(weapon.windup + weapon.swing + weapon.recovery, 0.3) * 1.4
		var before := _swing
		_swing += delta
		var hit_time := (weapon.windup + weapon.swing * 0.5) * 1.4
		if before < hit_time and _swing >= hit_time:
			_melee_hit()
		if _swing >= total:
			_swing = -1.0
	if _echo >= 0.0:
		_echo -= delta
		if _echo < 0.0:
			_spark(_target())
			_hit = 1.0


func _melee_hit() -> void:
	_hit = 1.0
	_hit2 = 1.0
	_spark(_target())
	_recoil = 1.0
	match weapon.trait_id:
		&"ice_wave":
			if _swings % 3 == 0:
				_frost = 0.0
		&"quake":
			_blast = 0.0
		&"gravity":
			_blast = 0.0
		&"echo":
			_echo = 0.12


func _step_effects(delta: float) -> void:
	for impact in _impacts:
		impact["age"] = float(impact["age"]) + delta
	_impacts = _impacts.filter(func(i: Dictionary) -> bool: return float(i["age"]) < 0.3)
	for casing in _casings:
		casing["age"] = float(casing["age"]) + delta
		casing["vel"] = (casing["vel"] as Vector2) + Vector2(0.0, 620.0) * delta
		casing["pos"] = (casing["pos"] as Vector2) + (casing["vel"] as Vector2) * delta
		casing["rot"] = float(casing["rot"]) + delta * 14.0
	_casings = _casings.filter(func(c: Dictionary) -> bool: return float(c["age"]) < 0.55)
	for number in _numbers:
		number["age"] = float(number["age"]) + delta
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return float(n["age"]) < 0.8)


# ---- рисование ----

func _draw() -> void:
	if weapon == null:
		return
	_draw_backdrop()
	_draw_dummy(_back_target(), 0.62, _hit2)
	_draw_dummy(_target(), 1.0, _hit)
	var shadow_at := Vector2(_origin().x + 6.0, size.y * FLOOR + 10.0)
	draw_set_transform(shadow_at, 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, _icon_scale() * 34.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if weapon.is_melee():
		_draw_melee()
	else:
		_draw_gun()
	for casing in _casings:
		var cp: Vector2 = casing["pos"]
		draw_set_transform(cp, float(casing["rot"]), Vector2.ONE)
		draw_rect(Rect2(-3, -1.5, 6, 3), Color("#e0b24a").lerp(Color("#7a5a20"), float(casing["age"]) / 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_impacts()
	_draw_extras()
	var font := ThemeDB.fallback_font
	for n in _numbers:
		var age := float(n["age"])
		var p: Vector2 = n["pos"]
		var a := clampf(1.0 - age / 0.8, 0.0, 1.0)
		draw_string(font, p + Vector2(0, -age * 46.0), str(n["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(1.0, 0.95, 0.5, a))


func _draw_backdrop() -> void:
	var accent := weapon.get_rarity_color()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#070b17"))
	draw_rect(Rect2(0, size.y * 0.35, size.x, size.y * 0.65), accent.darkened(0.82))
	var floor_y := size.y * FLOOR
	for i in 7:
		var x := size.x * (0.05 + 0.15 * i)
		draw_line(Vector2(x, floor_y), Vector2(size.x * 0.5 + (x - size.x * 0.5) * 2.2, size.y), Color(accent, 0.12), 2.0)
	draw_line(Vector2(0, floor_y), Vector2(size.x, floor_y), Color(accent, 0.55), 3.0)
	for i in 4:
		var y := floor_y + (size.y - floor_y) * float(i) / 4.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(accent, 0.08), 1.5)


func _draw_dummy(at: Vector2, s: float, hit: float) -> void:
	var floor_y := size.y * FLOOR - (0.0 if s >= 1.0 else 56.0)
	var shake := Vector2(sin(_t * 70.0) * 3.0 * hit, 0.0)
	var c := at + shake + Vector2(hit * 5.0, 0.0)
	draw_line(Vector2(c.x, floor_y), Vector2(c.x, c.y + 24.0 * s), Color("#5a4630"), 8.0 * s)
	draw_rect(Rect2(c.x - 26.0 * s, floor_y - 6.0, 52.0 * s, 8.0), Color("#2c2438"))
	var body := Color("#c9ccd8").lerp(Color.WHITE, hit)
	draw_circle(c, 34.0 * s, Color("#08151d"))
	draw_circle(c, 30.0 * s, body)
	draw_circle(c, 22.0 * s, Color("#d9344f").lerp(Color.WHITE, hit))
	draw_circle(c, 14.0 * s, body)
	draw_circle(c, 7.0 * s, Color("#d9344f").lerp(Color.WHITE, hit))


func _draw_gun() -> void:
	var scale_factor := _icon_scale()
	var bob := sin(_t * 1.6) * 2.5
	var pos := _origin() + Vector2(-_recoil * 10.0, bob)
	var m0 := _muzzle_pos() + Vector2(0, bob)
	var aim_end := _target() + Vector2(-34.0, 0.0)
	for i in 14:
		var u := float(i) / 14.0
		var q := m0.lerp(aim_end, u)
		if i % 2 == 0:
			draw_circle(q, 1.6, Color(weapon.effect_color, 0.28 * (1.0 - u)))
	WeaponIcons.draw(self, weapon.icon, pos, scale_factor, -_recoil * 0.05, weapon.effect_color)
	if _flash > 0.0:
		_draw_muzzle_flash()
	for b in _bullets:
		_draw_bullet(b)


func _draw_muzzle_flash() -> void:
	var m := _muzzle_pos()
	var tex := WeaponVfx.muzzle_for(weapon)
	var a := clampf(_flash / 0.09, 0.0, 1.0)
	if tex != null:
		var w := WeaponVfx.muzzle_width(weapon) * 0.85
		draw_texture_rect(tex, Rect2(m + Vector2(-w * 0.3, -w * 0.5), Vector2(w, w)), false, Color(1, 1, 1, a))
	else:
		draw_circle(m + Vector2(10, 0), 18.0 * a, Color(weapon.effect_color, 0.8))


func _draw_bullet(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var vel: Vector2 = b["vel"]
	var trail: Array = b["trail"]
	var color := weapon.effect_color
	for i in range(trail.size() - 1):
		var a := 1.0 - float(i) / float(trail.size())
		draw_line(trail[i], trail[i + 1], Color(color, 0.55 * a), maxf(weapon.bullet_radius * 0.9 * a, 1.5))
	var tex: Texture2D = weapon.bullet_texture
	if tex != null:
		var px := tex.get_size() * weapon.sprite_scale * BULLET_DRAW_MUL
		draw_set_transform(pos, vel.angle(), Vector2.ONE)
		draw_texture_rect(tex, Rect2(-px * 0.5, px), false, weapon.bullet_modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_set_transform(pos, vel.angle(), Vector2.ONE)
		draw_rect(Rect2(-14, -2.5, 28, 5), color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_impacts() -> void:
	var tex := WeaponVfx.impact_for(weapon)
	for impact in _impacts:
		var age := float(impact["age"])
		var p: Vector2 = impact["pos"]
		var a := clampf(1.0 - age / 0.3, 0.0, 1.0)
		if tex != null:
			var w := WeaponVfx.impact_width(weapon) * (1.0 + age * 2.0) * 1.3
			draw_texture_rect(tex, Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w)), false, Color(1, 1, 1, a))
		else:
			draw_circle(p, 10.0 + age * 60.0, Color(weapon.effect_color, a * 0.7))


func _draw_extras() -> void:
	var t := _target()
	if _blast >= 0.0:
		var k := _blast / 0.45
		var r := maxf(minf(weapon.explosion_radius * 0.55, 95.0), 55.0) * (0.35 + k)
		draw_circle(t, r, Color(weapon.effect_color, 0.28 * (1.0 - k)))
		draw_arc(t, r, 0.0, TAU, 36, Color(weapon.effect_color, 0.9 * (1.0 - k)), 4.0)
	if _frost >= 0.0:
		var k := _frost / 0.7
		for i in 9:
			var ang := TAU * float(i) / 9.0
			var len := 60.0 * minf(k * 2.5, 1.0)
			draw_line(t + Vector2.from_angle(ang) * 20.0, t + Vector2.from_angle(ang) * (20.0 + len), Color("#bfeeff", 1.0 - k), 5.0)
		draw_arc(t, 90.0 * minf(k * 2.0, 1.0), 0.0, TAU, 32, Color("#7fdcff", 1.0 - k), 4.0)
	if _burn > 0.0:
		for i in 6:
			var phase := fmod(_t * 1.7 + float(i) * 0.37, 1.0)
			var p := t + Vector2(sin(float(i) * 2.1 + _t * 5.0) * 18.0, -26.0 - phase * 50.0)
			draw_circle(p, 6.0 * (1.0 - phase) + 2.0, Color(1.0, 0.55 - phase * 0.3, 0.15, 0.85 * minf(_burn, 1.0)))


func _draw_melee() -> void:
	var pivot := _origin()
	var scale_factor := HELD_SCALE * MELEE_K
	var total := maxf(weapon.windup + weapon.swing + weapon.recovery, 0.3) * 1.4
	var angle := -0.2 + sin(_t * 1.6) * 0.02
	var swing_k := -1.0
	if _swing >= 0.0:
		var wind := weapon.windup * 1.4
		var sw := weapon.swing * 1.4
		if _swing < wind:
			var k := _swing / maxf(wind, 0.01)
			angle = lerpf(-0.2, -1.3, k * k * (3.0 - 2.0 * k))
		elif _swing < wind + sw:
			swing_k = (_swing - wind) / maxf(sw, 0.01)
			angle = lerpf(-1.3, 1.0, swing_k * swing_k)
		else:
			var k2 := (_swing - wind - sw) / maxf(total - wind - sw, 0.01)
			angle = lerpf(1.0, -0.2, k2 * k2 * (3.0 - 2.0 * k2))
	var grip := WeaponIcons.grip(weapon.icon) * scale_factor
	var center := pivot - grip.rotated(angle)
	if _swing >= 0.0:
		var wind_t := weapon.windup * 1.4
		var life := weapon.swing * 1.4 + 0.2
		var u := (_swing - wind_t) / life
		if u > 0.0 and u < 1.0:
			var lead := clampf(u * 1.15, 0.0, 1.0)
			var eased := lead * lead * (3.0 - 2.0 * lead)
			var a := smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.45, 1.0, u))
			_draw_slash(pivot, a, lerpf(-1.0, 1.0, eased) * weapon.arc_rad * 0.3 * (-1.0 if _swings % 2 == 0 else 1.0), lerpf(0.85, 1.05, eased))
	WeaponIcons.draw(self, weapon.icon, center, scale_factor, angle, weapon.effect_color)
	draw_circle(pivot, 5.0, Color("#08151d"))
	draw_circle(pivot, 3.0, Color("#f3d1a8"))


func _draw_slash(pivot: Vector2, alpha: float, turn: float, grow: float) -> void:
	var tex := WeaponVfx.slash_for(weapon)
	var visual := weapon.melee_reach * WeaponVfx.slash_scale(weapon) * MELEE_K * grow
	var flip := -1.0 if _swings % 2 == 0 else 1.0
	if tex != null:
		draw_set_transform(pivot, PI + turn, Vector2(1.0, flip))
		draw_texture_rect(tex, Rect2(Vector2(-visual * 0.55 - visual, -visual), Vector2(visual * 2.0, visual * 2.0)), false, Color(1, 1, 1, alpha * 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var half := weapon.arc_rad * 0.5
		draw_arc(pivot, visual, -half + turn, half + turn, 24, Color(weapon.effect_color, alpha), 8.0)
