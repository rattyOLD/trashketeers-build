class_name RouteCache
extends Node2D
## Склад Выживания: безопасный запас здоровья или оборона ради прошивки.
## Две точки на главу, без эмиттеров, источников света и отдельных узлов для меток.
signal rewarded(coins: int)
signal disabled(at: Vector2, radius: float, seconds: float)
signal resolved(safe: bool, at: Vector2)

const RADIUS := 105.0
const CONTROL_HOLD := 2.0
const CACHE_HOLD := 2.8
const OFF_TIME := 30.0
const DEFENSE_TIME := 10.0
const DEFENSE_RADIUS := 240.0
const CYCLE := 2.8
const WARNING := 1.6
var player: Player
var enemies: EnemyManager
var theme := "junk"
var cache_offset := Vector2(0, -190)
var control_offset := Vector2(210, 160)
var claimed := false
var control_used := false
var alarm_started := false
var defense_progress := 0.0
var off_left := 0.0
var _control_hold := 0.0
var _cache_hold := 0.0
var _age := 0.0
var _tick := 0.0
var _redraw := 0.0
var _closed: Texture2D
var _open: Texture2D
var _batch := PolyBatch.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_as_relative = false
	z_index = 2
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	self.material = material
	_closed = ArenaProp.texture_of("res://assets/ui/chests_v2/common.png")
	_open = ArenaProp.texture_of("res://assets/ui/chests_v2/common_open.png")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		# Отрисовать последний физический шаг до остановки обновлений с частотой 10 Гц.
		queue_redraw()


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion() or not is_instance_valid(player) or player.is_dead:
		return
	_age += delta
	off_left = maxf(off_left - delta, 0.0)
	var at := player.global_position - global_position
	if not claimed and not alarm_started and not control_used:
		_control_hold = clampf(_control_hold + (delta if at.distance_squared_to(control_offset) < 65.0 * 65.0 else -delta * 2), 0, CONTROL_HOLD)
		if _control_hold >= CONTROL_HOLD:
			control_used = true
			off_left = OFF_TIME
			disabled.emit(global_position + cache_offset, 320.0, OFF_TIME)
			SoundManager.play(&"shield_up", -6)
	if not claimed:
		if alarm_started:
			if at.distance_squared_to(cache_offset) <= DEFENSE_RADIUS * DEFENSE_RADIUS:
				defense_progress = minf(defense_progress + delta, DEFENSE_TIME)
				if defense_progress >= DEFENSE_TIME:
					_complete(false)
		else:
			_cache_hold = clampf(_cache_hold + (delta if at.distance_squared_to(cache_offset) < 55.0 * 55.0 else -delta * 2), 0, CACHE_HOLD)
			if _cache_hold >= CACHE_HOLD:
				if control_used:
					_complete(true)
				else:
					alarm_started = true
					_age = 0.0
					SoundManager.play(&"ui_confirm", -6)
	_tick -= delta
	if danger_active() and _tick <= 0:
		_tick = 0.5
		_apply_zone()
	_redraw -= delta
	if _redraw <= 0:
		_redraw = 0.1
		queue_redraw()


func _complete(safe: bool) -> void:
	if claimed:
		return
	claimed = true
	rewarded.emit(15 if safe else 40)
	resolved.emit(safe, global_position + cache_offset)
	SoundManager.play(&"crate_break", -8)


func danger_active() -> bool:
	return alarm_started and not claimed and off_left <= 0 and fmod(_age, CYCLE) >= WARNING


func _outer_pulse() -> bool:
	return alarm_started and int(floor(_age / CYCLE)) % 2 == 1


func _in_danger(at: Vector2) -> bool:
	var distance := at.distance_squared_to(global_position + cache_offset)
	if _outer_pulse():
		return distance >= RADIUS * RADIUS and distance <= DEFENSE_RADIUS * DEFENSE_RADIUS
	return distance < RADIUS * RADIUS


func _apply_zone() -> void:
	if _in_danger(player.global_position):
		Player.last_source = &"route_cache"
		player.take_damage(4.0)
	if is_instance_valid(enemies):
		for enemy in enemies.get_active().duplicate():
			if enemy.is_alive() and _in_danger(enemy.global_position):
				Enemy.next_source = &"environment"
				Enemy.next_kind = &"acid" if theme == "junk" else &"shock"
				enemy.take_damage(12.0)
				if enemy.is_alive() and not enemy.data.is_boss():
					enemy.add_slow(0.35, 0.6)


func _progress_arc(at: Vector2, radius: float, fraction: float, color: Color, width: float, point_count: int = 24) -> void:
	# PolyBatch хранит формы дуг глобально; фиксированные ступени не растят кэш во время ожидания.
	var amount := clampf(snappedf(fraction, 1.0 / 64.0), 0.0, 1.0)
	if amount > 0.0:
		_batch.arc(at, radius, -PI / 2, -PI / 2 + TAU * amount, point_count, color, width)


func _draw() -> void:
	var safe := off_left > 0
	var color := Color("#71dfa2") if safe else (Color("#b0df54") if theme == "junk" else Color("#55d9ed"))
	if alarm_started and not claimed:
		color = Color("#ff704c") if danger_active() else Color("#ffca70")
	var batch := _batch
	if _outer_pulse() and not claimed:
		batch.arc(cache_offset, (DEFENSE_RADIUS + RADIUS) * 0.5, 0, TAU, 48, Color(color, 0.12 if not danger_active() else 0.26), DEFENSE_RADIUS - RADIUS)
	else:
		batch.circle(cache_offset, RADIUS, Color(color, 0.08 if not danger_active() else 0.2))
	batch.arc(cache_offset, RADIUS, 0, TAU, 32, UiStyle.OUTLINE, 7)
	batch.arc(cache_offset, RADIUS, 0, TAU, 32, color, 3)
	if alarm_started and not claimed and not safe and not danger_active():
		_progress_arc(cache_offset, (DEFENSE_RADIUS if _outer_pulse() else RADIUS) + 6, fmod(_age, CYCLE) / WARNING, Color("#ffd28a"), 4)
	for i in 8:
		var edge := cache_offset + Vector2.from_angle(i * TAU / 8) * (RADIUS - 15)
		batch.line(edge - Vector2(4, 4), edge + Vector2(4, 4), color, 3)
	batch.rect(Rect2(control_offset + Vector2(-25, -40), Vector2(50, 40)), UiStyle.OUTLINE)
	batch.rect(Rect2(control_offset + Vector2(-20, -35), Vector2(40, 30)), Color("#686657"))
	batch.rect(Rect2(control_offset + Vector2(-14, -28), Vector2(28, 14)), Color("#163529"))
	batch.line(control_offset + Vector2(-8, -20), control_offset + Vector2(8, -20), color, 4)
	if alarm_started and not claimed:
		batch.arc(cache_offset, DEFENSE_RADIUS, 0, TAU, 48, Color("#ffad55"), 3)
		if defense_progress > 0.0:
			_progress_arc(cache_offset, DEFENSE_RADIUS + 5, defense_progress / DEFENSE_TIME, UiStyle.GOLD, 4, 48)
	if _control_hold > 0 and not control_used and not alarm_started and not claimed:
		_progress_arc(control_offset, 62, _control_hold / CONTROL_HOLD, UiStyle.GOLD, 4)
	if _cache_hold > 0 and not claimed and not alarm_started:
		_progress_arc(cache_offset, 61, _cache_hold / CACHE_HOLD, UiStyle.GOLD, 4)
	batch.flush(self)
	var texture := _open if claimed else _closed
	if texture != null:
		draw_texture_rect(texture, Rect2(cache_offset + Vector2(-42, -72), Vector2(84, 84)), false)
	var title := "СКЛАД ОТКРЫТ" if claimed else ("ЗАПАСЫ · 15 МОНЕТ + ЛЕЧЕНИЕ" if control_used else "РИСК · 40 МОНЕТ + ПРОШИВКА")
	_label(cache_offset + Vector2(0, -112), title, UiStyle.GOLD)
	if not claimed:
		var hint := "ВОЗЬМИ ЗАПАСЫ · 3 С" if control_used else "ВСКРЫТИЕ 3 С → ОБОРОНА 10 С"
		if alarm_started: hint = "ОБОРОНА · %d/%d С" % [int(defense_progress), int(DEFENSE_TIME)]
		_label(cache_offset + Vector2(0, 128), hint, UiStyle.TEXT)
		if alarm_started:
			_label(cache_offset + Vector2(0, 150), "ЧЕРЕДУЙ ЦЕНТР И КРАЙ · МОЖНО ОТСТУПИТЬ", UiStyle.TEXT)
	_label(control_offset + Vector2(0, 26), "РИСК ВЫБРАН" if alarm_started else ((("ОТКЛЮЧЕНО · %d С" % ceili(off_left)) if safe else "ИСПОЛЬЗОВАНО") if control_used else "БЕЗОПАСНО · 2 С"), color)
	if not claimed and not alarm_started and not control_used:
		_label(control_offset + Vector2(0, 48), "15 МОНЕТ · +25% HP", UiStyle.TEXT)
	if not safe and not claimed and alarm_started:
		_label(cache_offset + Vector2(0, -88), ("КРАЙ ОПАСЕН!" if _outer_pulse() else "ЦЕНТР ОПАСЕН!") if danger_active() else ("ЗАРЯЖАЕТСЯ КРАЙ" if _outer_pulse() else "ЗАРЯЖАЕТСЯ ЦЕНТР"), color)
	elif not safe and not claimed:
		_label(cache_offset + Vector2(0, -88), "ЗОНА ВКЛЮЧИТСЯ ПОСЛЕ ВСКРЫТИЯ", color)


func _label(at: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	at.x -= width * 0.5
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, UiStyle.OUTLINE)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
