class_name BattleControls
extends RefCounted
## Экранные элементы боя, положение которых задаёт редактор управления:
## панель слотов оружия, кнопка «ВЗЯТЬ» и жест смены ствола свайпом.

const SLOT_W := 132.0
const SLOT_H := 100.0
const SLOT_GAP := 8.0
const RARITY_FALLBACK := Color("#b9c2d9")


static func slots_base_size(count: int) -> Vector2:
	return Vector2(SLOT_W, SLOT_H * count + SLOT_GAP * (count - 1))


static func button_style(fill: Color, border: Color, width: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(18)
	box.anti_aliasing = true
	return box


class SlotBar:
	extends Control
	signal slot_pressed(index: int)

	var weapons: Array = []
	var active := 0
	var count := 2
	var editor_preview := false
	var _flash := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_slots(list: Array, active_index: int, slots: int) -> void:
		if active_index != active:
			_flash = 1.0
		weapons = list
		active = active_index
		count = slots
		queue_redraw()

	func _scale() -> float:
		return size.x / SLOT_W

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash = maxf(_flash - delta * 4.0, 0.0)
			queue_redraw()

	func _input(event: InputEvent) -> void:
		if editor_preview or not is_visible_in_tree() or get_tree().paused:
			return
		if event is InputEventScreenTouch and event.pressed:
			var local := ((event as InputEventScreenTouch).position - get_global_rect().position) / _scale()
			if local.x < 0.0 or local.x > SLOT_W:
				return
			for i in count:
				var top := i * (SLOT_H + SLOT_GAP)
				if local.y >= top and local.y <= top + SLOT_H:
					slot_pressed.emit(i)
					get_viewport().set_input_as_handled()
					return

	func _draw() -> void:
		var k := _scale()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		var font := ThemeDB.fallback_font
		for i in count:
			var rect := Rect2(0, i * (SLOT_H + SLOT_GAP), SLOT_W, SLOT_H)
			var weapon: WeaponData = weapons[i] if i < weapons.size() else null
			var is_active := i == active
			var accent: Color = weapon.get_rarity_color() if weapon != null else RARITY_FALLBACK
			var fill := Color(0.08, 0.05, 0.16, 0.78 if is_active else 0.5)
			var border := Color(accent, 1.0 if is_active else 0.45)
			draw_style_box(BattleControls.button_style(fill, border, 6 if is_active else 3), rect)
			if is_active and _flash > 0.0:
				draw_style_box(BattleControls.button_style(Color(1, 1, 1, 0.35 * _flash), Color(1, 1, 1, 0), 0), rect)
			draw_string_outline(font, rect.position + Vector2(10, 24), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 30, 22, 6, Color(0.06, 0.03, 0.1))
			draw_string(font, rect.position + Vector2(10, 24), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 30, 22, Color(1, 1, 1, 0.95 if is_active else 0.6))
			if weapon == null:
				draw_string(font, rect.position + Vector2(0, 62), "ПУСТО", HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 18, Color(1, 1, 1, 0.3))
				continue
			var tilt := 0.0
			WeaponIcons.draw(self, weapon.icon, rect.position + Vector2(SLOT_W * 0.5 + 6, 44), 0.62 if is_active else 0.52, tilt, weapon.effect_color)
			var label := weapon.short_name
			draw_string_outline(font, rect.position + Vector2(4, 90), label, HORIZONTAL_ALIGNMENT_CENTER, SLOT_W - 8, 16, 5, Color(0.06, 0.03, 0.1))
			draw_string(font, rect.position + Vector2(4, 90), label, HORIZONTAL_ALIGNMENT_CENTER, SLOT_W - 8, 16, Color(accent, 1.0 if is_active else 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class InteractButton:
	extends Control
	signal pressed

	var weapon: WeaponData
	var note := ""
	var editor_preview := false
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func show_for(new_weapon: WeaponData, new_note: String) -> void:
		var changed := weapon == null or new_weapon == null or weapon.id != new_weapon.id or weapon.tier != new_weapon.tier
		weapon = new_weapon
		note = new_note
		visible = new_weapon != null or editor_preview
		if changed and visible:
			UiStyle.pop_in(self, 0.35)
		queue_redraw()

	func _process(delta: float) -> void:
		if visible:
			_time += delta
			queue_redraw()

	func _input(event: InputEvent) -> void:
		if editor_preview or not visible or get_tree().paused:
			return
		if event is InputEventScreenTouch and event.pressed:
			if get_global_rect().grow(14.0).has_point((event as InputEventScreenTouch).position):
				pressed.emit()
				get_viewport().set_input_as_handled()

	func _draw() -> void:
		var k := size.x / 250.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		var accent: Color = weapon.get_rarity_color() if weapon != null else UiStyle.GOLD
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		var rect := Rect2(0, 0, 250, 96)
		draw_style_box(BattleControls.button_style(Color(0.1, 0.06, 0.2, 0.92), Color(accent, 0.7 + 0.3 * pulse), 5), rect)
		var font := ThemeDB.fallback_font
		if weapon != null:
			WeaponIcons.draw(self, weapon.icon, Vector2(56, 48), 0.7, 0.0, weapon.effect_color)
		draw_string_outline(font, Vector2(104, 38), "ВЗЯТЬ", HORIZONTAL_ALIGNMENT_LEFT, 140, 30, 8, Color(0.06, 0.03, 0.1))
		draw_string(font, Vector2(104, 38), "ВЗЯТЬ", HORIZONTAL_ALIGNMENT_LEFT, 140, 30, UiStyle.GOLD)
		var title := weapon.get_title() if weapon != null else "Пистолет T1"
		draw_string(font, Vector2(104, 62), title, HORIZONTAL_ALIGNMENT_LEFT, 138, 16, Color(accent, 1.0))
		draw_string(font, Vector2(104, 84), note, HORIZONTAL_ALIGNMENT_LEFT, 138, 14, Color(1, 1, 1, 0.6))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Свайп вверх/вниз по свободной половине экрана листает слоты оружия.
class SwipeSwitch:
	extends Control
	signal swiped

	const MIN_DISTANCE := 120.0
	const MAX_TIME := 0.55

	var _index := -1
	var _start := Vector2.ZERO
	var _t0 := 0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree() or get_tree().paused or not bool(Controls.get_value("swipe_switch")):
			return
		var left_side := bool(Controls.get_value("left_handed"))
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed and _index == -1:
				var on_free_side := touch.position.x < size.x * 0.4 if left_side else touch.position.x > size.x * 0.6
				if on_free_side and touch.position.y > 220.0:
					_index = touch.index
					_start = touch.position
					_t0 = Time.get_ticks_msec()
			elif not touch.pressed and touch.index == _index:
				var delta := touch.position - _start
				var fast := Time.get_ticks_msec() - _t0 < int(MAX_TIME * 1000.0)
				_index = -1
				if fast and absf(delta.y) > MIN_DISTANCE and absf(delta.y) > absf(delta.x) * 1.4:
					swiped.emit()
