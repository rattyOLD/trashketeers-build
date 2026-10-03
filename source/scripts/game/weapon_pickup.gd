class_name WeaponPickup
extends Node2D
## Ствол на земле (.io-механика): луч цвета редкости, парящий силуэт и подпись «АК T2».
## Енот подбирает, просто наступив; старый ствол при этом падает на то же место
## (с задержкой подбора, чтобы не «пинговать» туда-обратно). Узлы создаёт Game заранее
## (маленький пул), в бою они только переставляются.

signal picked(pickup: WeaponPickup)

const PICK_RADIUS := 42.0
const INTERACT_RADIUS := 105.0
const LIFETIME := 32.0
const BLINK_TIME := 7.0
const BEAM_HEIGHT := 150.0

var weapon: WeaponData
## true — найден в забеге (уйдёт в арсенал), false — выброшенный Енотом старый ствол.
var is_loot := false
var active := false
## Ствол в зоне подбора: подсвечен, кнопка «ВЗЯТЬ» показывает именно его.
var focused := false
var life := LIFETIME
static var auto_pick := false
signal expired(pickup: WeaponPickup)

var _player: Player
var _cooldown := 0.0
var _time := 0.0


func _init() -> void:
	visible = false
	set_physics_process(false)


func setup(player: Player) -> void:
	_player = player


func drop(new_weapon: WeaponData, at: Vector2, loot: bool, pickup_delay: float = 0.0) -> void:
	weapon = new_weapon
	is_loot = loot
	global_position = at
	_cooldown = pickup_delay
	life = LIFETIME + (14.0 if loot else 0.0)
	focused = false
	_time = randf() * TAU
	active = true
	visible = true
	set_physics_process(true)
	queue_redraw()


func clear() -> void:
	active = false
	visible = false
	weapon = null
	focused = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not active or weapon == null:
		return
	_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	queue_redraw()
	life -= delta
	if life <= 0.0:
		expired.emit(self)
		return
	if not auto_pick or _player == null or _player.is_dead or _cooldown > 0.0:
		return
	if global_position.distance_squared_to(_player.global_position) < PICK_RADIUS * PICK_RADIUS:
		picked.emit(self)


func can_pick() -> bool:
	return active and _cooldown <= 0.0


func _draw() -> void:
	if weapon == null:
		return
	if life < BLINK_TIME and int(life * 6.0) % 2 == 0:
		return
	var color := weapon.get_rarity_color()
	var pulse := 0.6 + 0.4 * sin(_time * 3.0)
	SoftGlow.pool(self, Vector2(0, 2), 44.0, 0.38, Color(color, 0.3 * pulse))
	SoftGlow.rim(self, Vector2(0, 2), 40.0, 0.38, Color(color, 0.42))
	SoftGlow.pool(self, Vector2(0, -BEAM_HEIGHT * 0.5), 15.0, BEAM_HEIGHT * 0.5 / 15.0, Color(color, 0.08 + 0.05 * pulse))
	if focused:
		SoftGlow.rim(self, Vector2(0, 2), 58.0 + 4.0 * pulse, 0.38, Color(1, 1, 1, 0.7))
	var bob := sin(_time * 2.4) * 5.0
	var tilt := sin(_time * 1.3) * 0.18
	WeaponIcons.draw(self, weapon.icon, Vector2(0, -34 + bob), 0.85, tilt, weapon.effect_color)
	var font := ThemeDB.fallback_font
	var label := weapon.get_title()
	# Подпись крупно — только у ствола, к которому енот подошёл; остальные мелко и полупрозрачно, чтобы не засорять бой.
	var alpha := 0.55 if _cooldown > 0.0 else (1.0 if focused else 0.6)
	var size := 20 if focused else 15
	draw_string_outline(font, Vector2(-110, -66 + bob), label, HORIZONTAL_ALIGNMENT_CENTER, 220, size, 6, Color(0.08, 0.04, 0.12, alpha))
	draw_string(font, Vector2(-110, -66 + bob), label, HORIZONTAL_ALIGNMENT_CENTER, 220, size, Color(color, alpha))
