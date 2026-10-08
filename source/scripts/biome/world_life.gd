class_name WorldLife
extends Node2D
## Живой мир выживания (по мотивам Hades, Enter the Gungeon, Stardew Valley): всё, что двигается само по себе.
##   Стаи голубей (Банк) и ворон (Свалка) клюют и подпрыгивают, взлетают от героя, выстрелов и взрывов
##   с хлопаньем крыльев и через полминуты садятся в другом месте.
##   Ветер несёт листья (Банк) и бумажки с пакетами (Свалка); над травой — светлячки, над бочками — искры.
##   На улицах Свалки — люки с паром; между домами квартала — бельё на верёвке (Свалка) или флажки (Банк).
##   По Банку плывут тени облаков. Жители бросают реплики, когда герой проходит рядом.
## Один узел, два слоя рисования (земля под персонажами, воздух над ними); считается и рисуется только то,
## что рядом с камерой. Качество 0 — только реплики; 1 — меньше частиц; 2 — всё.

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const BIRDS_PER_FLOCK := Vector2i(5, 9)
const SCARE_PLAYER := 150.0
const SCARE_SHOT := 260.0
const FLY_TIME := 4.0
const WIND := Vector2(1.0, 0.22)

const LINES_JUNK: Array[String] = ["Опять пальба…", "Енот! По газону не топай!", "Шаурма свежая. Почти.", "Крыс бей, а не мусор!",
	"Раньше свалка была тише", "Ты же Рико? Тот самый?", "Не наступи на кота!", "Бочку не трогай — греемся",
	"Давай, енот, жги!", "Сдачу крышками не даём", "Где мой самокат?!", "Это не хлам, это коллекция"]
const LINES_BANK: Array[String] = ["Фи, енот в приличном районе", "Охрана! А, это вы…", "Не испачкайте газон", "Частная собственность!",
	"Мой банкир будет в ужасе", "Бокал шампанского?", "Хрю. Простите, вырвалось.", "Кто пустил сюда енота?",
	"Осторожнее с фонтаном!", "Чек, наличные или крышки?"]
const LINES_BY_SHEET := {
	"npc_cat_stray": ["Мяу.", "Мрр?", "…мяу."], "npc_dumpster_cat": ["Мяу.", "Мрр."],
	"npc_robot_cleaner": ["ПИП. УБОРКА.", "МУСОР ОБНАРУЖЕН: ВЫ.", "ПИП-ПИП."],
	"npc_pigeon_postman": ["Курлык! Вам письмо.", "Почта! Курлык!"],
	"npc_crow_lamp": ["Кар!", "Карр…"],
}
const SILENT := ["npc_barrel_fire", "npc_raccoon_sign", "npc_equipment_sled", "npc_ice_fish_crate", "npc_frozen_fish", "npc_fish_under_ice"]

static var _font: Font

var bank := false
var quality := 2
var player: Node2D
## Кто может говорить (AmbientLife.Actor); места для стай; огни (искры); трава (светлячки); улицы (люки).
var actors: Array = []
var spots: Array[Vector2] = []
var fires: Array[Vector2] = []
var meadows: Array = []
var streets: Array[PackedVector2Array] = []
var ropes: Array = []
var bounds := Rect2()

var _ground: FxManager.DrawLayer
var _air: FxManager.DrawLayer
var _time := 0.0
var _view := Rect2()
var _flocks: Array = []
var _bits: Array = []
var _embers: Array = []
var _vents: Array = []
var _clouds: Array = []
var _bubble := {}
var _bubble_cd := 4.0
var _said := {}
var _check := 0.0
var _box: StyleBoxFlat


func build(ground_parent: Node2D, air_parent: Node2D) -> void:
	quality = SaveService.get_quality()
	_ground = FxManager.DrawLayer.new()
	_ground.painter = _paint_ground
	ground_parent.add_child(_ground)
	_air = FxManager.DrawLayer.new()
	_air.painter = _paint_air
	air_parent.add_child(_air)
	if quality > 0:
		for i in mini(spots.size(), 3 if quality == 1 else 6):
			_flocks.append(_new_flock(spots[i]))
		if not bank:
			for line in streets:
				if line.size() > 12:
					_vents.append({"p": line[line.size() / 3], "t": randf() * 2.0, "puffs": []})
		if bank:
			for i in 3:
				_clouds.append(Vector3(randf_range(bounds.position.x, bounds.end.x), randf_range(bounds.position.y, bounds.end.y), randf_range(260.0, 420.0)))
	if not BulletPool.exploded.is_connected(_on_explosion):
		BulletPool.exploded.connect(_on_explosion)


func _exit_tree() -> void:
	if BulletPool.exploded.is_connected(_on_explosion):
		BulletPool.exploded.disconnect(_on_explosion)
	# Слои рисования живут в чужих родителях (пол/воздух биома) — убираем их вместе с собой.
	for layer in [_ground, _air]:
		if layer != null and is_instance_valid(layer):
			layer.queue_free()


## Герой: от него взлетают птицы, его выстрелы их пугают, рядом с ним жители бросают реплики.
func attach(hero: Player) -> void:
	player = hero
	if hero != null and hero.weapon_controller != null and not hero.weapon_controller.fired.is_connected(on_shot):
		hero.weapon_controller.fired.connect(on_shot)


## Выстрел героя: птицы рядом взлетают.
func on_shot(_weapon: WeaponData, origin: Vector2, _direction: Vector2) -> void:
	_scare(origin, SCARE_SHOT)


func _on_explosion(at: Vector2, radius: float, _color: Color, _team: int) -> void:
	_scare(at, radius + 220.0)


func _scare(at: Vector2, radius: float) -> void:
	for flock: Dictionary in _flocks:
		if int(flock["state"]) == 0 and (flock["at"] as Vector2).distance_to(at) < radius:
			_take_off(flock, at)


# --- Стаи ---------------------------------------------------------------------------------------------

func _new_flock(at: Vector2) -> Dictionary:
	var birds: Array = []
	for i in randi_range(BIRDS_PER_FLOCK.x, BIRDS_PER_FLOCK.y):
		birds.append({"p": at + Vector2(randf_range(-60.0, 60.0), randf_range(-30.0, 30.0)), "v": Vector2.ZERO, "h": 0.0,
			"face": 1.0 if randf() < 0.5 else -1.0, "peck": randf() * 3.0, "hop": randf_range(1.0, 4.0), "flap": randf() * TAU,
			"shade": randf_range(-0.08, 0.08)})
	return {"at": at, "birds": birds, "state": 0, "timer": 0.0}


func _take_off(flock: Dictionary, from: Vector2) -> void:
	flock["state"] = 1
	flock["timer"] = FLY_TIME
	var away := ((flock["at"] as Vector2) - from).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	for b: Dictionary in flock["birds"]:
		b["v"] = away.rotated(randf_range(-0.7, 0.7)) * randf_range(150.0, 220.0)
		b["face"] = 1.0 if (b["v"] as Vector2).x >= 0.0 else -1.0
	if _view.has_point(flock["at"]):
		SoundManager.play(&"wing_flap", 0.0, true)


func _update_flocks(delta: float) -> void:
	for flock: Dictionary in _flocks:
		var state := int(flock["state"])
		if state == 0:
			if player != null and is_instance_valid(player) and player.global_position.distance_to(flock["at"]) < SCARE_PLAYER:
				_take_off(flock, player.global_position)
				continue
			if not _view.grow(200.0).has_point(flock["at"]):
				continue
			for b: Dictionary in flock["birds"]:
				b["peck"] = float(b["peck"]) - delta
				if float(b["peck"]) < -0.25:
					b["peck"] = randf_range(0.8, 3.5)
				b["hop"] = float(b["hop"]) - delta
				if float(b["hop"]) <= 0.0:
					b["hop"] = randf_range(1.5, 5.0)
					var step := Vector2(randf_range(-14.0, 14.0), randf_range(-6.0, 6.0))
					b["p"] = (b["p"] as Vector2) + step
					b["face"] = 1.0 if step.x >= 0.0 else -1.0
		elif state == 1:
			flock["timer"] = float(flock["timer"]) - delta
			for b: Dictionary in flock["birds"]:
				b["p"] = (b["p"] as Vector2) + (b["v"] as Vector2) * delta
				b["h"] = minf(float(b["h"]) + 120.0 * delta, 280.0)
				b["flap"] = float(b["flap"]) + delta * 22.0
			if float(flock["timer"]) <= 0.0:
				flock["state"] = 2
				flock["timer"] = randf_range(18.0, 35.0)
		elif state == 2:
			flock["timer"] = float(flock["timer"]) - delta
			if float(flock["timer"]) <= 0.0:
				_land(flock)
	# Посадка: птицы спускаются к новому месту.
	for flock: Dictionary in _flocks:
		if int(flock["state"]) != 3:
			continue
		var done := true
		for b: Dictionary in flock["birds"]:
			var target: Vector2 = b["target"]
			var to := target - (b["p"] as Vector2)
			if to.length() > 4.0 or float(b["h"]) > 0.5:
				done = false
				b["p"] = (b["p"] as Vector2) + to.limit_length(160.0 * delta)
				b["h"] = maxf(float(b["h"]) - 90.0 * delta, 0.0)
				b["flap"] = float(b["flap"]) + delta * 16.0
				b["face"] = 1.0 if to.x >= 0.0 else -1.0
		if done:
			flock["state"] = 0


func _land(flock: Dictionary) -> void:
	var options: Array[Vector2] = []
	for s in spots:
		if player == null or not is_instance_valid(player) or s.distance_to(player.global_position) > 500.0:
			options.append(s)
	var at: Vector2 = options.pick_random() if not options.is_empty() else flock["at"]
	flock["at"] = at
	flock["state"] = 3
	var from := at + Vector2(-WIND.x, -0.6).normalized() * 500.0
	for b: Dictionary in flock["birds"]:
		b["target"] = at + Vector2(randf_range(-60.0, 60.0), randf_range(-30.0, 30.0))
		b["p"] = from + Vector2(randf_range(-80.0, 80.0), randf_range(-40.0, 40.0))
		b["h"] = 220.0


# --- Ветер, светлячки, искры, пар ----------------------------------------------------------------------

func _update_bits(delta: float) -> void:
	var cap := 16 if quality > 1 else 8
	var gust := 1.0 + 0.6 * sin(_time * 0.37) + 0.3 * sin(_time * 1.3)
	if _bits.size() < cap and randf() < delta * 3.0:
		var p := Vector2(_view.position.x - 40.0, randf_range(_view.position.y, _view.end.y))
		if randf() < 0.4:
			p = Vector2(randf_range(_view.position.x, _view.end.x), _view.position.y - 30.0)
		_bits.append({"p": p, "rot": randf() * TAU, "spin": randf_range(-4.0, 4.0), "life": randf_range(9.0, 15.0),
			"kind": randi() % 3, "phase": randf() * TAU, "speed": randf_range(40.0, 75.0)})
	for i in range(_bits.size() - 1, -1, -1):
		var b: Dictionary = _bits[i]
		b["life"] = float(b["life"]) - delta
		var flutter := Vector2(0.0, sin(_time * 2.3 + float(b["phase"])) * 22.0)
		b["p"] = (b["p"] as Vector2) + (WIND * float(b["speed"]) * gust + flutter) * delta
		b["rot"] = float(b["rot"]) + float(b["spin"]) * delta * gust
		if float(b["life"]) <= 0.0 or not _view.grow(160.0).has_point(b["p"]):
			_bits.remove_at(i)
	# Искры над бочками с огнём.
	for f in fires:
		if _view.grow(80.0).has_point(f) and _embers.size() < (30 if quality > 1 else 12) and randf() < delta * 7.0:
			_embers.append(Vector4(f.x + randf_range(-10.0, 10.0), f.y - 34.0, randf_range(-12.0, 12.0), 0.0))
	for i in range(_embers.size() - 1, -1, -1):
		var e: Vector4 = _embers[i]
		e.w += delta
		e.x += (e.z + sin(_time * 4.0 + float(i)) * 10.0) * delta
		e.y -= 55.0 * delta
		_embers[i] = e
		if e.w > 1.6:
			_embers.remove_at(i)
	# Пар из люков: клубы поднимаются и тают, иногда — сильный выдох.
	for v: Dictionary in _vents:
		if not _view.grow(120.0).has_point(v["p"]):
			continue
		v["t"] = float(v["t"]) - delta
		var puffs: Array = v["puffs"]
		if float(v["t"]) <= 0.0:
			var burst := randf() < 0.08
			v["t"] = 0.08 if burst else randf_range(0.25, 0.5)
			puffs.append(Vector3(randf_range(-10.0, 10.0), 0.0, 0.0))
		for k in range(puffs.size() - 1, -1, -1):
			var p: Vector3 = puffs[k]
			p.z += delta
			p.y -= 34.0 * delta
			p.x += WIND.x * 14.0 * delta
			puffs[k] = p
			if p.z > 2.2:
				puffs.remove_at(k)
	for i in _clouds.size():
		var c: Vector3 = _clouds[i]
		c.x += 14.0 * delta
		c.y += 3.0 * delta
		if c.x - c.z > bounds.end.x:
			c.x = bounds.position.x - c.z
			c.y = randf_range(bounds.position.y, bounds.end.y)
		_clouds[i] = c


# --- Реплики ----------------------------------------------------------------------------------------------

func _update_barks(delta: float) -> void:
	if not _bubble.is_empty():
		_bubble["t"] = float(_bubble["t"]) - delta
		if float(_bubble["t"]) <= 0.0 or not is_instance_valid(_bubble["who"]):
			_bubble = {}
	_bubble_cd -= delta
	_check -= delta
	if _check > 0.0 or _bubble_cd > 0.0 or not _bubble.is_empty() or player == null or not is_instance_valid(player):
		return
	_check = 0.4
	var best: Node2D = null
	var best_d := 230.0
	for a in actors:
		if not is_instance_valid(a):
			continue
		var actor := a as Node2D
		var sheet := str(actor.get_meta("sheet", ""))
		if SILENT.has(sheet) or float(_said.get(actor.get_instance_id(), -100.0)) > _time - 25.0:
			continue
		var d := actor.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = actor
	if best == null:
		return
	var sheet := str(best.get_meta("sheet", ""))
	var pool: Array = LINES_BY_SHEET.get(sheet, LINES_BANK if bank else LINES_JUNK)
	_bubble = {"who": best, "text": str(pool.pick_random()), "t": 2.8}
	_said[best.get_instance_id()] = _time
	_bubble_cd = randf_range(5.0, 9.0)


# --- Кадр --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var vp := get_viewport()
	_view = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	if quality > 0:
		_update_flocks(delta)
		_update_bits(delta)
		_ground.queue_redraw()
	_update_barks(delta)
	_air.queue_redraw()


func _paint_ground(ci: CanvasItem) -> void:
	for c: Vector3 in _clouds:
		var at := Vector2(c.x, c.y)
		if not _view.grow(c.z).has_point(at):
			continue
		for k in 3:
			ci.draw_set_transform(at, 0.0, Vector2(1.0, 0.62))
			ci.draw_circle(Vector2.ZERO, c.z * (1.0 - 0.18 * k), Color(0.05, 0.08, 0.12, 0.035))
	ci.draw_set_transform(Vector2.ZERO)
	for v: Dictionary in _vents:
		var p: Vector2 = v["p"]
		if not _view.grow(60.0).has_point(p):
			continue
		ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
		ci.draw_circle(Vector2.ZERO, 26.0, Color(0.06, 0.05, 0.08, 0.9))
		ci.draw_circle(Vector2.ZERO, 22.0, Color(0.2, 0.18, 0.24))
		ci.draw_set_transform(Vector2.ZERO)
		for k in 4:
			var y := p.y - 7.0 + k * 4.5
			ci.draw_line(Vector2(p.x - 16.0, y), Vector2(p.x + 16.0, y), Color(0.05, 0.04, 0.07), 2.0)
	for flock: Dictionary in _flocks:
		if int(flock["state"]) == 2:
			continue
		for b: Dictionary in flock["birds"]:
			var p: Vector2 = b["p"]
			if not _view.grow(40.0).has_point(p):
				continue
			var h := float(b["h"])
			var shadow := clampf(1.0 - h / 300.0, 0.15, 1.0)
			ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.4))
			ci.draw_circle(Vector2.ZERO, 7.0 * (0.6 + 0.4 * shadow), Color(0, 0, 0, 0.3 * shadow))
			ci.draw_set_transform(Vector2.ZERO)
			if h < 0.5:
				_draw_bird(ci, p, b, false)


func _paint_air(ci: CanvasItem) -> void:
	for r: Array in ropes:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		if not _view.grow(200.0).intersects(Rect2(a, Vector2.ZERO).expand(b)):
			continue
		_draw_rope(ci, a, b, r[2])
	for flock: Dictionary in _flocks:
		if int(flock["state"]) == 0 or int(flock["state"]) == 2:
			continue
		for b: Dictionary in flock["birds"]:
			var p := (b["p"] as Vector2) - Vector2(0.0, float(b["h"]))
			if _view.grow(40.0).has_point(p) and float(b["h"]) >= 0.5:
				_draw_bird(ci, p, b, true)
	for b: Dictionary in _bits:
		var p: Vector2 = b["p"]
		var fade := clampf(float(b["life"]), 0.0, 1.0)
		var kind := int(b["kind"])
		ci.draw_set_transform(p, float(b["rot"]), Vector2(1.0, 0.55 + 0.45 * absf(sin(float(b["rot"])))))
		if bank:
			var leaf: Color = [Color("#7fbf4d"), Color("#e8a33a"), Color("#c9612f")][kind]
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, 0), Vector2(0, -3.5), Vector2(7, 0), Vector2(0, 3.5)]), Color(leaf, fade))
		elif kind == 2:
			ci.draw_rect(Rect2(-7, -5, 14, 10), Color(0.75, 0.72, 0.85, 0.55 * fade))
		else:
			ci.draw_rect(Rect2(-6, -4, 12, 8), Color(0.93, 0.9, 0.82, 0.8 * fade))
			ci.draw_line(Vector2(-4, -1), Vector2(4, -1), Color(0.4, 0.4, 0.5, 0.5 * fade), 1.0)
	ci.draw_set_transform(Vector2.ZERO)
	if quality > 0 and not bank:
		# Светлячки над травой: мерцают и медленно кружат.
		for m: Array in meadows:
			var center: Vector2 = m[0]
			var radius: float = m[1]
			if not _view.grow(radius).has_point(center):
				continue
			for k in (8 if quality > 1 else 4):
				var a := _time * (0.3 + 0.05 * k) + k * 2.4
				var p := center + Vector2(cos(a) * radius * (0.3 + 0.08 * k), sin(a * 1.3) * radius * 0.45) - Vector2(0, 30.0 + 12.0 * sin(_time + k))
				var blink := clampf(sin(_time * 2.0 + k * 1.7) * 0.8 + 0.4, 0.0, 1.0)
				ci.draw_circle(p, 6.0, Color(0.85, 1.0, 0.4, 0.18 * blink))
				ci.draw_circle(p, 2.2, Color(0.95, 1.0, 0.6, 0.9 * blink))
	for e: Vector4 in _embers:
		var t := e.w / 1.6
		ci.draw_circle(Vector2(e.x, e.y), 2.4 * (1.0 - t * 0.5), Color(1.0, 0.6 + 0.3 * (1.0 - t), 0.2, 0.9 * (1.0 - t)))
	for v: Dictionary in _vents:
		var base: Vector2 = v["p"]
		for p: Vector3 in v["puffs"]:
			var t := p.z / 2.2
			ci.draw_circle(base + Vector2(p.x, p.y - 6.0), 8.0 + t * 20.0, Color(0.85, 0.85, 0.92, 0.22 * (1.0 - t)))
	if not _bubble.is_empty():
		_draw_bubble(ci)


func _draw_bird(ci: CanvasItem, p: Vector2, b: Dictionary, flying: bool) -> void:
	var face := float(b["face"])
	var shade := float(b["shade"])
	var body := Color(0.16 + shade, 0.14 + shade, 0.2 + shade) if not bank else Color(0.6 + shade, 0.62 + shade, 0.7 + shade)
	var dark := body.darkened(0.35)
	if flying:
		var wing := sin(float(b["flap"])) * 8.0
		ci.draw_line(p, p + Vector2(-9.0, -wing), dark, 2.5)
		ci.draw_line(p, p + Vector2(9.0, -wing), dark, 2.5)
		ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
		ci.draw_circle(Vector2.ZERO, 4.5, body)
		ci.draw_set_transform(Vector2.ZERO)
		ci.draw_circle(p + Vector2(4.5 * face, -1.0), 2.6, body)
		return
	var peck := float(b["peck"]) < 0.0
	ci.draw_set_transform(p + Vector2(0, -5), 0.0, Vector2(1.0, 0.7))
	ci.draw_circle(Vector2.ZERO, 6.0, body)
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_line(p + Vector2(-5.0 * face, -5.0), p + Vector2(-10.0 * face, -7.0), dark, 3.0)
	var head := p + (Vector2(6.0 * face, -3.0) if peck else Vector2(5.0 * face, -10.0))
	ci.draw_circle(head, 3.4, body.lightened(0.05))
	if bank:
		ci.draw_circle(head + Vector2(-1.5 * face, 2.5), 2.2, Color(0.45, 0.72, 0.62, 0.8))
	ci.draw_line(head + Vector2(2.5 * face, 0), head + Vector2(5.5 * face, 1.0), Color("#e0a030"), 1.6)
	ci.draw_circle(head + Vector2(1.2 * face, -0.8), 0.9, Color(1, 1, 1, 0.9))
	ci.draw_line(p + Vector2(-1.0, 0), p + Vector2(-1.0, 3.0), Color("#d0702a"), 1.2)
	ci.draw_line(p + Vector2(2.0, 0), p + Vector2(2.0, 3.0), Color("#d0702a"), 1.2)


## Верёвка с бельём (Свалка) или гирлянда флажков (Банк) между домами квартала; качается на ветру.
func _draw_rope(ci: CanvasItem, a: Vector2, b: Vector2, colors: Array) -> void:
	var sag := a.distance_to(b) * 0.12
	var prev := a
	var n := colors.size() + 1
	for i in range(1, 17):
		var t := i / 16.0
		var p := a.lerp(b, t) + Vector2(0, sin(t * PI) * sag)
		ci.draw_line(prev, p, Color(0.12, 0.1, 0.12, 0.85), 1.6)
		prev = p
	for k in range(1, n):
		var t := float(k) / n
		var p := a.lerp(b, t) + Vector2(0, sin(t * PI) * sag)
		var sway := sin(_time * 2.2 + k * 0.9) * 0.18 * (1.0 + 0.5 * sin(_time * 0.37))
		var col: Color = colors[k - 1]
		if bank:
			var tip := p + Vector2(0, 16.0).rotated(sway)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(7, 0), tip]), col)
		else:
			var w := 16.0 + float(k % 3) * 4.0
			var h := 20.0 + float(k % 2) * 8.0
			var down := Vector2(0, h).rotated(sway)
			var side := Vector2(w * 0.5, 0)
			ci.draw_colored_polygon(PackedVector2Array([p - side, p + side, p + side + down, p - side + down]), col)
			ci.draw_line(p - side + down, p + side + down, col.darkened(0.3), 1.5)


func _draw_bubble(ci: CanvasItem) -> void:
	var who := _bubble["who"] as Node2D
	if _font == null:
		_font = load(FONT_PATH) as Font
	if _font == null:
		return
	var text := str(_bubble["text"])
	var size := 18
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 22.0
	var appear := clampf((2.8 - float(_bubble["t"])) * 6.0, 0.0, 1.0) * clampf(float(_bubble["t"]) * 3.0, 0.0, 1.0)
	var top := who.global_position + Vector2(-w * 0.5, -132.0 - 6.0 * (1.0 - appear))
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.set_corner_radius_all(10)
		_box.set_border_width_all(2)
	_box.bg_color = Color(0.98, 0.96, 0.9, 0.95 * appear)
	_box.border_color = Color(0.1, 0.08, 0.14, appear)
	ci.draw_style_box(_box, Rect2(top, Vector2(w, 32)))
	var tail := top + Vector2(w * 0.5, 32)
	ci.draw_colored_polygon(PackedVector2Array([tail + Vector2(-7, -1), tail + Vector2(7, -1), tail + Vector2(0, 10)]), _box.bg_color)
	ci.draw_string(_font, top + Vector2(11, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.12, 0.1, 0.16, appear))
