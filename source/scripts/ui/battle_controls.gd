class_name BattleControls
extends RefCounted
## Экранные элементы боя, положение которых задаёт редактор управления:
## панель слотов оружия, кнопка «ВЗЯТЬ» и жест смены ствола свайпом.

const SLOT_W := 96.0
const SLOT_H := 96.0
const SLOT_GAP := 8.0
const RARITY_FALLBACK := Color("#b9c2d9")


static func slots_base_size(count: int) -> Vector2:
	return Vector2(SLOT_W * count + SLOT_GAP * (count - 1), SLOT_H)


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
	signal slot_held(index: int)

	const HOLD_MS := 550

	var weapons: Array = []
	var active := 0
	var count := 2
	var editor_preview := false
	var _flash := 0.0
	var _hold_index := -1
	var _hold_start := 0

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
		return size.y / SLOT_H

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash = maxf(_flash - delta * 4.0, 0.0)
			queue_redraw()
		if _hold_index >= 0 and Time.get_ticks_msec() - _hold_start >= HOLD_MS:
			var index := _hold_index
			_hold_index = -1
			slot_held.emit(index)

	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and not event.pressed:
			_hold_index = -1
		if editor_preview or not is_visible_in_tree() or get_tree().paused:
			return
		if event is InputEventScreenTouch and event.pressed:
			var local := ((event as InputEventScreenTouch).position - get_global_rect().position) / _scale()
			if local.y < 0.0 or local.y > SLOT_H:
				return
			for i in count:
				var top := i * (SLOT_W + SLOT_GAP)
				if local.x >= top and local.x <= top + SLOT_W:
					_hold_index = i
					_hold_start = Time.get_ticks_msec()
					slot_pressed.emit(i)
					get_viewport().set_input_as_handled()
					return

	func _draw() -> void:
		var k := _scale()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		var font := ThemeDB.fallback_font
		for i in count:
			var rect := Rect2(i * (SLOT_W + SLOT_GAP), 0, SLOT_W, SLOT_H)
			var weapon: WeaponData = weapons[i] if i < weapons.size() else null
			var is_active := i == active
			var accent: Color = weapon.get_rarity_color() if weapon != null else RARITY_FALLBACK
			var fill := Color(0.08, 0.05, 0.16, 0.78 if is_active else 0.5)
			var border := Color(accent, 1.0 if is_active else 0.45)
			draw_style_box(BattleControls.button_style(fill, border, 6 if is_active else 3), rect)
			if is_active and _flash > 0.0:
				draw_style_box(BattleControls.button_style(Color(1, 1, 1, 0.35 * _flash), Color(1, 1, 1, 0), 0), rect)
			draw_string_outline(font, rect.position + Vector2(8, 22), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 24, 20, 6, Color(0.06, 0.03, 0.1))
			draw_string(font, rect.position + Vector2(8, 22), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 24, 20, Color(1, 1, 1, 0.95 if is_active else 0.6))
			if weapon == null:
				draw_string(font, rect.position + Vector2(0, 62), "+", HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 40, Color(1, 1, 1, 0.25))
				continue
			WeaponIcons.draw(self, weapon.icon, rect.position + Vector2(SLOT_W * 0.5 + 4, SLOT_H * 0.5 + 4), 0.78 if is_active else 0.62, 0.0, weapon.effect_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class InteractButton:
	extends Control
	signal pressed

	## Подбор срабатывает при отпускании короткого касания: долгое удержание открывает правку кнопки.
	const HOLD_TAP_MS := 900

	var weapon: WeaponData
	var note := ""
	var editor_preview := false
	var _time := 0.0
	var _touch := -1
	var _down := 0

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
			_touch = -1
			return
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				if _touch == -1 and get_global_rect().grow(14.0).has_point(touch.position):
					_touch = touch.index
					_down = Time.get_ticks_msec()
					get_viewport().set_input_as_handled()
			elif touch.index == _touch:
				_touch = -1
				if Time.get_ticks_msec() - _down < HOLD_TAP_MS:
					pressed.emit()
				get_viewport().set_input_as_handled()

	func _draw() -> void:
		var k := size.x / 250.0
		var accent: Color = weapon.get_rarity_color() if weapon != null else UiStyle.GOLD
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_style_box(BattleControls.button_style(Color(0.184, 0.177, 0.166, 0.92), Color(accent, 0.7 + 0.3 * pulse), maxi(roundi(5.0 * k), 2)), Rect2(Vector2.ZERO, size))
		var font := ThemeDB.fallback_font
		if weapon != null:
			WeaponIcons.draw(self, weapon.icon, Vector2(56, 48) * k, 0.7 * k, 0.0, weapon.effect_color)
		var text_x := 104.0 * k
		var big := maxi(roundi(30.0 * k), 8)
		draw_string_outline(font, Vector2(text_x, 38.0 * k), "ВЗЯТЬ", HORIZONTAL_ALIGNMENT_LEFT, 140.0 * k, big, maxi(roundi(8.0 * k), 2), Color(0.06, 0.03, 0.1))
		draw_string(font, Vector2(text_x, 38.0 * k), "ВЗЯТЬ", HORIZONTAL_ALIGNMENT_LEFT, 140.0 * k, big, UiStyle.GOLD)
		var title := weapon.get_title() if weapon != null else "Хлопушка T1"
		draw_string(font, Vector2(text_x, 62.0 * k), title, HORIZONTAL_ALIGNMENT_LEFT, 138.0 * k, maxi(roundi(16.0 * k), 7), Color(accent, 1.0))
		draw_string(font, Vector2(text_x, 84.0 * k), note, HORIZONTAL_ALIGNMENT_LEFT, 138.0 * k, maxi(roundi(14.0 * k), 6), Color(1, 1, 1, 0.6))
