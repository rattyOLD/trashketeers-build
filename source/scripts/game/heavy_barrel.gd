class_name HeavyBarrel
extends Node
## Супер-ствол в духе Heavy Barrel: 6 деталей из кейсов H.B.; собрал — 30 секунд аннигиляции.
## Модуль не знает про сюжет: детали добавляет внешний код (collect_part), UI слушает сигналы.

signal parts_changed(count: int, total: int)
signal ultimate_started
signal assembled
signal ultimate_ended

const TOTAL_PARTS := 6
const ASSEMBLY_TIME := 1.1
const ASSEMBLY_SLOWMO := 0.3
const DURATION := 30.0
const INVULN_TIME := 3.0
const WEAPON_ID := &"heavy_barrel"
const FLASH_COLOR := Color("#ff2ea6")
const SPARK_INTERVAL := 0.18

var parts := 0
var active := false
var time_left := 0.0

var _player: Player
var _fx: FxManager
var _atmosphere: AtmosphereFX
var _spark_clock := 0.0


func setup(player: Player, fx: FxManager, atmosphere: AtmosphereFX) -> void:
	_player = player
	_fx = fx
	_atmosphere = atmosphere
	set_process(false)


func collect_part() -> void:
	if active or parts >= TOTAL_PARTS:
		return
	parts += 1
	parts_changed.emit(parts, TOTAL_PARTS)
	if parts >= TOTAL_PARTS:
		_activate()


func _activate() -> void:
	var weapon := WeaponDB.get_weapon(WEAPON_ID)
	if weapon == null:
		return
	active = true
	time_left = DURATION
	_player.weapon_controller.set_base_weapon(weapon)
	_player.grant_invuln(INVULN_TIME)
	_atmosphere.flash(FLASH_COLOR, 1.0, 0.5)
	_fx.ring(_player.global_position, FLASH_COLOR, 260.0)
	_fx.burst(_player.global_position, FLASH_COLOR, 60, 420.0, 5.0)
	SoundManager.play(&"boss_spawn", 0.0, false)
	_play_assembly()
	set_process(true)
	ultimate_started.emit()


## Мини-кат-сцена: кино-полосы, замедление времени и серия вспышек вокруг Енота.
func _play_assembly() -> void:
	assembled.emit()
	_atmosphere.letterbox(true)
	Engine.time_scale = ASSEMBLY_SLOWMO
	for i in 3:
		get_tree().create_timer(0.12 + 0.22 * i, true, false, true).timeout.connect(func() -> void:
			if active and is_instance_valid(_player):
				_fx.ring(_player.global_position, FLASH_COLOR if i % 2 == 0 else Color.WHITE, 140.0 + 90.0 * i))
	get_tree().create_timer(ASSEMBLY_TIME, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_atmosphere.letterbox(false))


func _process(delta: float) -> void:
	time_left -= delta
	_spark_clock -= delta
	if _spark_clock <= 0.0:
		_spark_clock = SPARK_INTERVAL
		_fx.burst(_player.global_position + Vector2(randf_range(-18.0, 18.0), randf_range(-30.0, 10.0)), FLASH_COLOR, 6, 180.0, 3.0)
	if time_left <= 0.0:
		_deactivate()


func _deactivate() -> void:
	active = false
	parts = 0
	set_process(false)
	var wc := _player.weapon_controller
	wc.set_base_weapon(wc.slots[wc.active_slot])
	_atmosphere.flash(Color("#7df9ff"), 0.4, 0.3)
	parts_changed.emit(parts, TOTAL_PARTS)
	ultimate_ended.emit()


## Шкала сборки: металлический кейс, детали вщёлкиваются по одной; при сборке кейс горит и показывает таймер.
class Meter:
	extends Control

	const CELL := 22.0
	const GAP := 5.0

	var _parts := 0
	var _total := HeavyBarrel.TOTAL_PARTS
	var _time_left := 0.0
	var _active := false
	var _pop := 0.0
	var _clock := 0.0

	func bind(barrel: HeavyBarrel) -> void:
		barrel.parts_changed.connect(_on_parts)
		barrel.ultimate_started.connect(func() -> void: _active = true)
		barrel.ultimate_ended.connect(func() -> void: _active = false)
		custom_minimum_size = Vector2(_total * (CELL + GAP) + 74.0, CELL + 34.0)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)
		_barrel = barrel

	var _barrel: HeavyBarrel

	func _on_parts(count: int, total: int) -> void:
		if count > _parts:
			_pop = 1.0
		_parts = count
		_total = total

	func _process(delta: float) -> void:
		_clock += delta
		_pop = maxf(_pop - delta * 3.0, 0.0)
		if _barrel != null:
			_time_left = _barrel.time_left
		queue_redraw()

	func _draw() -> void:
		var glow := 0.6 + 0.4 * sin(_clock * 10.0) if _active else 0.0
		draw_rect(Rect2(0, 0, size.x, size.y), Color("#1a1c2b"), true)
		draw_rect(Rect2(0, 0, size.x, size.y), Color("#ffb020") if not _active else Color("#ff2ea6").lerp(Color.WHITE, glow * 0.4), false, 3.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(6, 26), "СТВОЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffb020"))
		draw_string(font, Vector2(6, size.y - 6), "ДЕТАЛИ СУПЕР-СТВОЛА", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9b98a"))
		for i in _total:
			var x := 56.0 + i * (CELL + GAP)
			var rect := Rect2(x, 6, CELL, CELL)
			draw_rect(rect, Color("#0c0d16"), true)
			if i < _parts or _active:
				var lift := _pop * 4.0 if i == _parts - 1 else 0.0
				draw_rect(Rect2(x + 2, 8 - lift, CELL - 4, CELL - 4), Color("#ff2ea6") if _active else Color("#ffd257"), true)
			draw_rect(rect, Color("#4a4e68"), false, 2.0)
		if _active:
			draw_string(font, Vector2(size.x + 8, size.y - 6), "%d" % int(ceilf(_time_left)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#ff2ea6"))


## Бронированный кейс H.B. с деталью: касание забирает её.
class Case:
	extends Node2D

	signal picked

	const PICK_RANGE := 80.0
	const MAGNET_RANGE := 420.0

	var player: Node2D
	var _time := 0.0

	func _init() -> void:
		z_index = 3

	func _physics_process(delta: float) -> void:
		_time += delta
		queue_redraw()
		if player == null:
			return
		var gap := global_position.distance_to(player.global_position)
		# Деталь сама летит к игроку: за стеной или в углу её иначе не достать.
		if _time > 0.35 and gap < MAGNET_RANGE:
			global_position = global_position.move_toward(player.global_position, (260.0 + (MAGNET_RANGE - gap) * 2.0) * delta)
		if gap < PICK_RANGE:
			SoundManager.play(&"level_up", -2.0, false)
			picked.emit()
			queue_free()

	func _draw() -> void:
		var bob := sin(_time * 4.0) * 3.0
		var pulse := 0.5 + 0.5 * sin(_time * 7.0)
		draw_circle(Vector2(0, bob + 10), 30.0, Color(0, 0, 0, 0.3))
		draw_circle(Vector2(0, bob), 40.0, Color(1.0, 0.18, 0.65, 0.12 + 0.12 * pulse))
		draw_rect(Rect2(-28, bob - 18, 56, 36), Color("#3a3d56"), true)
		draw_rect(Rect2(-28, bob - 18, 56, 36), Color("#ffb020"), false, 3.0)
		draw_rect(Rect2(-28, bob - 18, 56, 8), Color("#ffb020"), true)
		draw_string(ThemeDB.fallback_font, Vector2(-24, bob + 12), "ДЕТАЛЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffe9a8"))
