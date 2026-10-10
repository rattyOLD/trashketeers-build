class_name WaveActivity
extends Node2D
## Одно необязательное событие: фиксированная зона, короткий маршрут и два таймера.
signal completed(coins: int)
signal announced(title: String, text: String, color: Color)
signal encounter_requested(who: String)

enum Kind { CARGO, VALVE, DEFENSE, MEETING }
const TITLES := ["Сопроводи груз", "Перекрой утечку", "Удержи точку", "Встреча"]
const HOLD := [8.0, 3.0, 12.0, 1.2]
const DURATION := 30.0
const RADIUS := 120.0
const ACID_RADIUS := 100.0
const WARNING_TIME := 2.5

var player: Player
var enemies: EnemyManager
var map: LevelSpawner
var kind: Kind = Kind.CARGO
var active := false
var reward := 40
var who := "nell"
var progress := 0.0
var remaining := 0.0
var _age := 0.0
var _route_a := Vector2.ZERO
var _route_b := Vector2.ZERO
var _acid_tick := 0.0
var _scan_left := 0.0
var _contested := false
var _waiting_choice := false
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_font = ThemeDB.fallback_font
	visible = false
	set_physics_process(false)
	z_as_relative = false
	z_index = 29


func start(event_kind: Kind, chapter: int) -> bool:
	reset()
	if player == null or map == null or player.is_dead:
		return false
	var at := map.find_spawn_point(player.global_position, 260.0, 550.0, 180.0)
	if at == Vector2.INF:
		return false
	kind = event_kind
	reward = 40 + mini(chapter, 5) * 10
	who = "nell" if chapter % 2 == 0 else "snyr"
	global_position = at
	_route_a = at
	_route_b = at
	if kind == Kind.CARGO:
		# Вся короткая дорога проверена заранее; груз не уезжает сквозь укрытия.
		for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var clear := true
			for step in range(1, 7):
				clear = clear and map.is_area_clear(at + direction * step * 48.0, 90.0)
			if clear:
				_route_b = at + direction * 288.0
				break
		if _route_b == _route_a:
			return false
	active = true
	visible = true
	remaining = DURATION
	set_physics_process(true)
	var hint := _hint()
	announced.emit("ВСТРЕЧА: " + ("НЭЛЛ" if who == "nell" else "ШНЫРЬ") if kind == Kind.MEETING else TITLES[kind].to_upper(), hint, UiStyle.GOLD)
	queue_redraw()
	return true


func reset() -> void:
	active = false
	visible = false
	progress = 0.0
	remaining = 0.0
	_age = 0.0
	_acid_tick = 0.0
	_scan_left = 0.0
	_contested = false
	_waiting_choice = false
	set_physics_process(false)


func rows() -> Array:
	if not active or kind == Kind.MEETING:
		return []
	return [{"title": TITLES[kind], "progress": floori(progress), "goal": int(HOLD[kind]), "done": false, "hint": _hint() + " Осталось %d с." % ceili(remaining), "reward": reward}]


func _hint() -> String:
	match kind:
		Kind.CARGO: return "Иди рядом с тележкой 8 с. Она движется только с сопровождением."
		Kind.VALVE: return "Постой у вентиля 3 с. Кислота появится через 2,5 с в отмеченном круге справа."
		Kind.DEFENSE: return "Стой в круге 12 с; враги внутри мешают удержанию."
	return "Подойди и задержись рядом, чтобы поговорить. Можно пройти мимо."


func choose_risk(risky: bool) -> void:
	if not active or kind != Kind.MEETING or not _waiting_choice:
		return
	_waiting_choice = false
	if not risky:
		player.heal(15.0)
		_finish(15)
		return
	kind = Kind.DEFENSE
	progress = 0.0
	remaining = 25.0
	_age = 0.0
	reward += 30
	announced.emit("ПОРУЧЕНИЕ " + ("НЭЛЛ" if who == "nell" else "ШНЫРЯ"), "Удержи круг 12 с до конца волны · +%d монет" % reward, UiStyle.GOLD)


func _physics_process(delta: float) -> void:
	if not active or _waiting_choice:
		return
	if not is_instance_valid(player) or player.is_dead:
		reset()
		return
	_age += delta
	remaining -= delta
	if remaining <= 0.0:
		announced.emit("СОБЫТИЕ ЗАКОНЧИЛОСЬ", "Награда не получена. Волна продолжается.", UiStyle.TEXT_DIM)
		reset()
		return
	var inside := player.global_position.distance_squared_to(global_position) <= RADIUS * RADIUS
	if kind == Kind.DEFENSE:
		_scan_left -= delta
		if _scan_left <= 0.0:
			_scan_left = 0.25
			_contested = false
			if enemies != null:
				for enemy in enemies.get_active():
					if enemy.is_alive() and enemy.global_position.distance_squared_to(global_position) < RADIUS * RADIUS:
						_contested = true
						break
	if kind == Kind.VALVE:
		_tick_acid(delta)
	var gain := delta if inside and not _contested else (0.0 if kind == Kind.CARGO else -delta * 0.25)
	progress = clampf(progress + gain, 0.0, float(HOLD[kind]))
	if kind == Kind.CARGO and inside:
		global_position = _route_a.lerp(_route_b, progress / HOLD[kind])
	if progress >= HOLD[kind]:
		if kind == Kind.MEETING:
			_waiting_choice = true
			encounter_requested.emit(who)
		else:
			_finish(reward)
	queue_redraw()


func _tick_acid(delta: float) -> void:
	if _age < WARNING_TIME:
		return
	_acid_tick -= delta
	if _acid_tick > 0.0:
		return
	_acid_tick = 0.5
	var center := global_position + Vector2(230, 0)
	if player.global_position.distance_squared_to(center) < ACID_RADIUS * ACID_RADIUS:
		Player.last_source = &"acid"
		player.take_damage(3.0, Vector2.ZERO)
	if enemies != null:
		for enemy in enemies.get_active().duplicate():
			if enemy.is_alive() and enemy.global_position.distance_squared_to(center) < ACID_RADIUS * ACID_RADIUS:
				Enemy.next_kind = &"acid"
				enemy.take_damage(5.0)


func _finish(coins: int) -> void:
	# Выключается до сигнала: вложенные события и повторный тик не выдают награду дважды.
	reset()
	completed.emit(coins)


func _draw() -> void:
	if not active:
		return
	var tint := UiStyle.DANGER if _contested else UiStyle.GOLD
	draw_circle(Vector2.ZERO, RADIUS, Color(tint, 0.07))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, UiStyle.OUTLINE, 7, true)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, tint, 3, true)
	if progress > 0.0:
		draw_arc(Vector2.ZERO, RADIUS + 6, -PI * 0.5, -PI * 0.5 + TAU * progress / HOLD[kind], 32, tint, 5, true)
	match kind:
		Kind.CARGO:
			WorldArt.draw(self, "greed_register", 0.45)
			for x in [-24, 24]:
				draw_circle(Vector2(x, 5), 10, UiStyle.OUTLINE)
				draw_circle(Vector2(x, 5), 5, Color("#8b8275"))
		Kind.VALVE:
			var center := Vector2(230, 0)
			var color := Color("#a0e846")
			draw_circle(center, ACID_RADIUS, Color(color, 0.24 if _age >= WARNING_TIME else 0.07))
			draw_arc(center, ACID_RADIUS, 0, TAU, 40, UiStyle.OUTLINE, 8, true)
			draw_arc(center, ACID_RADIUS, 0, TAU, 40, color, 4, true)
			for i in 8:
				var at := center + Vector2.from_angle(i * TAU / 8.0) * (ACID_RADIUS - 18)
				draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), color, 3)
			draw_circle(Vector2(0, -26), 22, UiStyle.OUTLINE)
			draw_arc(Vector2(0, -26), 17, _age * 0.2, _age * 0.2 + TAU, 24, tint, 5)
			draw_line(Vector2(-15, -26), Vector2(15, -26), tint, 4)
		Kind.DEFENSE:
			WorldArt.draw(self, "charge_tower", 0.35)
		Kind.MEETING:
			if who == "snyr":
				WorldArt.draw(self, "fence_dealer/idle", 0.45, int(_age * 6) % 6, Vector2(256, 256), 4)
			else:
				WorldArt.draw(self, "charge_tower", 0.35)
	var title: String = "НЭЛЛ · РАЦИЯ" if kind == Kind.MEETING and who == "nell" else ("ШНЫРЬ" if kind == Kind.MEETING else TITLES[kind].to_upper())
	var width := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var at := Vector2(-width * 0.5, -108)
	draw_string_outline(_font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, UiStyle.OUTLINE)
	draw_string(_font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tint)
