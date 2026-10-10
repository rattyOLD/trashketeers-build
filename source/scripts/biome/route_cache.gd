class_name RouteCache
extends Node2D
## Необязательный склад: отключить зону и взять 15 монет или рискнуть ради 40.
## Две точки на главу, без эмиттеров, источников света и отдельных узлов для меток.
signal rewarded(coins: int)
signal disabled(at: Vector2, radius: float, seconds: float)

const RADIUS := 105.0
const CONTROL_HOLD := 2.0
const CACHE_HOLD := 2.8
const OFF_TIME := 30.0
const CYCLE := 2.8
const WARNING := 1.6
var player: Player
var enemies: EnemyManager
var theme := "junk"
var cache_offset := Vector2(0, -190)
var control_offset := Vector2(210, 160)
var claimed := false
var control_used := false
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
	if not control_used:
		_control_hold = clampf(_control_hold + (delta if at.distance_squared_to(control_offset) < 65.0 * 65.0 else -delta * 2), 0, CONTROL_HOLD)
		if _control_hold >= CONTROL_HOLD:
			control_used = true
			off_left = OFF_TIME
			disabled.emit(global_position + cache_offset, 320.0, OFF_TIME)
			SoundManager.play(&"shield_up", -6)
	if not claimed:
		_cache_hold = clampf(_cache_hold + (delta if at.distance_squared_to(cache_offset) < 55.0 * 55.0 else -delta * 2), 0, CACHE_HOLD)
		if _cache_hold >= CACHE_HOLD:
			claimed = true
			rewarded.emit(15 if off_left > 0 else 40)
			SoundManager.play(&"crate_break", -8)
	_tick -= delta
	if danger_active() and _tick <= 0:
		_tick = 0.5
		_apply_zone()
	_redraw -= delta
	if _redraw <= 0:
		_redraw = 0.1
		queue_redraw()


func danger_active() -> bool:
	return off_left <= 0 and fmod(_age, CYCLE) >= WARNING


func _apply_zone() -> void:
	var center := global_position + cache_offset
	if player.global_position.distance_squared_to(center) < RADIUS * RADIUS:
		Player.last_source = &"acid" if theme == "junk" else &"shock"
		player.take_damage(4.0)
	if is_instance_valid(enemies):
		for enemy in enemies.get_active().duplicate():
			if enemy.is_alive() and enemy.global_position.distance_squared_to(center) < RADIUS * RADIUS:
				Enemy.next_kind = &"acid" if theme == "junk" else &"shock"
				enemy.take_damage(12.0)
				if enemy.is_alive() and not enemy.data.is_boss():
					enemy.add_slow(0.35, 0.6)


func _draw() -> void:
	var safe := off_left > 0
	var color := Color("#71dfa2") if safe else (Color("#b0df54") if theme == "junk" else Color("#55d9ed"))
	var batch := _batch
	batch.circle(cache_offset, RADIUS, Color(color, 0.08 if not danger_active() else 0.2))
	batch.arc(cache_offset, RADIUS, 0, TAU, 32, UiStyle.OUTLINE, 7)
	batch.arc(cache_offset, RADIUS, 0, TAU, 32, color, 3)
	if not safe and not danger_active():
		batch.arc(cache_offset, RADIUS + 6, -PI / 2, -PI / 2 + TAU * fmod(_age, CYCLE) / WARNING, 24, Color("#ffd28a"), 4)
	for i in 8:
		var edge := cache_offset + Vector2.from_angle(i * TAU / 8) * (RADIUS - 15)
		batch.line(edge - Vector2(4, 4), edge + Vector2(4, 4), color, 3)
	batch.rect(Rect2(control_offset + Vector2(-25, -40), Vector2(50, 40)), UiStyle.OUTLINE)
	batch.rect(Rect2(control_offset + Vector2(-20, -35), Vector2(40, 30)), Color("#686657"))
	batch.rect(Rect2(control_offset + Vector2(-14, -28), Vector2(28, 14)), Color("#163529"))
	batch.line(control_offset + Vector2(-8, -20), control_offset + Vector2(8, -20), color, 4)
	if _control_hold > 0 and not control_used:
		batch.arc(control_offset, 62, -PI / 2, -PI / 2 + TAU * _control_hold / CONTROL_HOLD, 24, UiStyle.GOLD, 4)
	if _cache_hold > 0 and not claimed:
		batch.arc(cache_offset, 61, -PI / 2, -PI / 2 + TAU * _cache_hold / CACHE_HOLD, 24, UiStyle.GOLD, 4)
	batch.flush(self)
	var texture := _open if claimed else _closed
	if texture != null:
		draw_texture_rect(texture, Rect2(cache_offset + Vector2(-42, -72), Vector2(84, 84)), false)
	_label(cache_offset + Vector2(0, -112), "СКЛАД ОТКРЫТ" if claimed else ("БЕЗОПАСНО · 15 МОНЕТ" if safe else "РИСК · 40 МОНЕТ"), UiStyle.GOLD)
	_label(control_offset + Vector2(0, 26), ("ОТКЛЮЧЕНО · %d С" % ceili(off_left)) if safe else ("ЩИТОК ИСПОЛЬЗОВАН" if control_used else "ОТКЛЮЧИТЬ · 2 С"), color)
	if not claimed:
		_label(cache_offset + Vector2(0, 128), "ПОСТОЙ У СУНДУКА · 3 С", UiStyle.TEXT)
	if not safe:
		_label(cache_offset + Vector2(0, -88), ("КИСЛОТА!" if theme == "junk" else "РАЗРЯД!") if danger_active() else "ЗОНА ЗАРЯЖАЕТСЯ", color)


func _label(at: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	at.x -= width * 0.5
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, UiStyle.OUTLINE)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
