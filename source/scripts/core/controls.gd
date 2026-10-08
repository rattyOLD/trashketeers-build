class_name Controls
extends RefCounted
## Настройки управления: раскладка кнопок на экране (положение и размер), сторона джойстика,
## жесты, переназначение клавиш и пять пресетов. Хранится в SaveService.data["controls"].

const ELEMENTS := ["dash", "dodge", "slots", "interact"]
## Остальные элементы боевого интерфейса, которые игрок может двигать, масштабировать и делать прозрачными.
const HUD_ELEMENTS := ["hp", "xp", "coins", "pause", "time", "kills", "loot", "fps", "wave", "boss", "minimap", "order", "story_bar", "story_meter", "wanted", "barks"]
const HUD_TITLES := {
	"hp": "ЗДОРОВЬЕ", "xp": "ОПЫТ", "coins": "МОНЕТЫ", "pause": "ПАУЗА", "time": "ВРЕМЯ", "kills": "ВРАГИ",
	"loot": "ЛУТ НА КАРТЕ", "fps": "СЧЁТЧИК FPS", "wave": "ВОЛНА", "boss": "ПОЛОСА БОССА", "minimap": "МИНИКАРТА",
	"order": "ЗАДАНИЕ", "story_bar": "ОЧКИ, ЖИЗНИ, ЗОНА", "story_meter": "ДЕТАЛИ СУПЕР-СТВОЛА", "wanted": "РОЗЫСК", "barks": "РЕПЛИКИ",
}
const ELEMENT_TITLES := {"dash": "НАВЫК", "dodge": "РЫВОК", "slots": "СЛОТЫ ОРУЖИЯ", "interact": "ВЗЯТЬ"}
const ELEMENT_SIZE := {"dash": Vector2(160, 160), "dodge": Vector2(144, 144), "slots": Vector2(200, 96), "interact": Vector2(250, 96)}
const PRESET_SLOTS := 3

const KEY_ACTIONS := [
	[&"move_up", "Вверх"],
	[&"move_down", "Вниз"],
	[&"move_left", "Влево"],
	[&"move_right", "Вправо"],
	[&"dash", "Навык"],
	[&"dodge", "Рывок"],
	[&"interact", "Подобрать ствол"],
	[&"weapon_next", "Следующий ствол"],
	[&"weapon_1", "Слот 1"],
	[&"weapon_2", "Слот 2"],
	[&"weapon_3", "Слот 3"],
]
const DEFAULT_KEYS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"dash": [KEY_R],
	&"dodge": [KEY_SPACE, KEY_SHIFT],
	&"interact": [KEY_E, KEY_F],
	&"weapon_next": [KEY_Q, KEY_TAB],
	&"weapon_1": [KEY_1],
	&"weapon_2": [KEY_2],
	&"weapon_3": [KEY_3],
}

const SKILL_X := 0.92
const SKILL_Y := 0.8
const SLOTS_X := 0.835
const SLOTS_Y := 0.6
const INTERACT_Y := 0.4

static var revision := 0


static func default_config(left_handed: bool = false) -> Dictionary:
	# Хват двумя большими пальцами снизу: навык — в правом нижнем углу под большим пальцем,
	# рядом — отдельный рывок; оружие лежит горизонтально ниже центра экрана.
	var cx := SKILL_X if not left_handed else 1.0 - SKILL_X
	var sx := SLOTS_X if not left_handed else 1.0 - SLOTS_X
	return {
		"left_handed": left_handed,
		"joystick_scale": 1.0,
		"joystick_fixed": false,
		"opacity": 1.0,
		"swipe_switch": true,
		"auto_pick": false,
		"auto_fire": true,
		"weapon_slots": 2,
		"layout": {
			"dash": {"x": cx, "y": SKILL_Y, "s": 1.0},
			"dodge": {"x": 0.79 if not left_handed else 0.21, "y": 0.8, "s": 1.0},
			"slots": {"x": sx, "y": SLOTS_Y, "s": 1.0},
			"interact": {"x": 0.79 if not left_handed else 0.21, "y": INTERACT_Y, "s": 1.0},
		},
		"hud": {},
		"layout_v": 12,
		"keys": {},
		"presets": {},
	}


static func config() -> Dictionary:
	var stored: Dictionary = SaveService.data.get("controls", {})
	if stored.is_empty():
		stored = default_config(false)
		SaveService.data["controls"] = stored
	var base := default_config(bool(stored.get("left_handed", false)))
	for key in base:
		if not stored.has(key):
			stored[key] = base[key]
	var layout: Dictionary = stored["layout"]
	for id in ELEMENTS:
		if not layout.has(id):
			layout[id] = (base["layout"] as Dictionary)[id]
	if int(stored.get("layout_v", 1)) < 2:
		stored["layout_v"] = 2
		var dash: Dictionary = layout["dash"]
		if float(dash["y"]) > 0.78:
			dash["y"] = 0.74
		var slots: Dictionary = layout["slots"]
		if float(slots["y"]) > 0.58:
			slots["y"] = 0.54
	if int(stored.get("layout_v", 1)) < 4:
		stored["layout_v"] = 4
		var interact: Dictionary = layout["interact"]
		if float(interact["y"]) > 0.5 or is_equal_approx(float(interact["y"]), 0.27):
			interact["y"] = 0.32
	if int(stored.get("layout_v", 1)) < 5:
		stored["layout_v"] = 5
		var take: Dictionary = layout["interact"]
		if is_equal_approx(float(take["y"]), 0.32):
			take["y"] = 0.66
	if int(stored.get("layout_v", 1)) < 6:
		stored["layout_v"] = 6
		var low: Dictionary = layout["interact"]
		if float(low["y"]) < 0.7 and float(low["y"]) > 0.25:
			low["y"] = 0.8
	if int(stored.get("layout_v", 1)) < 7:
		stored["layout_v"] = 7
		# Кнопка «ВЗЯТЬ» стояла слишком низко: стандартное положение переносим ближе к центру экрана.
		var closer: Dictionary = layout["interact"]
		if is_equal_approx(float(closer["y"]), 0.8):
			closer["y"] = 0.62
	if int(stored.get("layout_v", 1)) < 8:
		stored["layout_v"] = 8
		# Ещё выше: кнопка над подписью оружия и ником енота, а не под ними.
		var above: Dictionary = layout["interact"]
		if is_equal_approx(float(above["y"]), 0.62) or is_equal_approx(float(above["y"]), 0.8):
			above["y"] = 0.46
	if int(stored.get("layout_v", 1)) < 9:
		stored["layout_v"] = 9
		# Навык и стволы опустились под большой палец; свои раскладки игрока не трогаем.
		var left := bool(stored.get("left_handed", false))
		var skill: Dictionary = layout["dash"]
		if absf(float(skill["y"]) - 0.74) < 0.005 and absf(float(skill["x"]) - (0.13 if left else 0.87)) < 0.005:
			skill["x"] = 1.0 - SKILL_X if left else SKILL_X
			skill["y"] = SKILL_Y
		var column: Dictionary = layout["slots"]
		if absf(float(column["y"]) - 0.54) < 0.005 and absf(float(column["x"]) - (0.13 if left else 0.87)) < 0.005:
			column["x"] = 1.0 - SLOTS_X if left else SLOTS_X
			column["y"] = SLOTS_Y
	if int(stored.get("layout_v", 1)) < 10:
		stored["portrait_layout_backup"] = {"layout": layout.duplicate(true), "hud": (stored["hud"] as Dictionary).duplicate(true)}
		stored["layout"] = (base["layout"] as Dictionary).duplicate(true)
		stored["hud"] = {}
		stored["layout_v"] = 10
	if int(stored.get("layout_v", 1)) < 11:
		stored["landscape_layout_backup"] = {"layout": (stored["layout"] as Dictionary).duplicate(true), "hud": (stored["hud"] as Dictionary).duplicate(true)}
		stored["layout"] = (base["layout"] as Dictionary).duplicate(true)
		stored["hud"] = {}
		stored["layout_v"] = 11
	if int(stored.get("layout_v", 1)) < 12:
		# Слоты оружия — над рывком и навыком (тот же большой палец), «ВЗЯТЬ» — выше слотов. Свои раскладки не трогаем.
		stored["layout_v"] = 12
		var left := bool(stored.get("left_handed", false))
		var fresh_layout: Dictionary = stored["layout"]
		var slots_now: Dictionary = fresh_layout["slots"]
		if absf(float(slots_now["x"]) - (0.4 if left else 0.6)) < 0.005 and absf(float(slots_now["y"]) - 0.84) < 0.005:
			slots_now["x"] = 1.0 - SLOTS_X if left else SLOTS_X
			slots_now["y"] = SLOTS_Y
		var take: Dictionary = fresh_layout["interact"]
		if absf(float(take["y"]) - 0.51) < 0.005:
			take["y"] = INTERACT_Y
	return stored


static func save() -> void:
	revision += 1
	SaveService.save_data()


static func element(id: String) -> Dictionary:
	return (config()["layout"] as Dictionary)[id]


static func set_element(id: String, x: float, y: float, scale: float) -> void:
	var e := element(id)
	e["x"] = clampf(x, 0.06, 0.94)
	e["y"] = clampf(y, 0.14, 0.94)
	e["s"] = clampf(scale, 0.6, 1.6)


static func title_of(id: String) -> String:
	return str(ELEMENT_TITLES.get(id, HUD_TITLES.get(id, id)))


static func is_hud_element(id: String) -> bool:
	return HUD_ELEMENTS.has(id)


## Настройки элемента интерфейса: x/y (центр, доли экрана; нет — стоит на месте), s (масштаб), o (прозрачность).
static func hud_item(id: String) -> Dictionary:
	var all: Dictionary = config().get("hud", {})
	return all.get(id, {})


static func hud_set(id: String, values: Dictionary) -> void:
	var cfg := config()
	if not cfg.has("hud"):
		cfg["hud"] = {}
	var all: Dictionary = cfg["hud"]
	var item: Dictionary = all.get(id, {})
	for key in values:
		item[key] = values[key]
	all[id] = item


static func hud_reset(id: String) -> void:
	var all: Dictionary = config().get("hud", {})
	all.erase(id)
	if ELEMENTS.has(id):
		var base := default_config(bool(config().get("left_handed", false)))
		(config()["layout"] as Dictionary)[id] = (base["layout"] as Dictionary)[id]
	save()


static func hud_reset_all() -> void:
	config()["hud"] = {}
	for id in ELEMENTS:
		hud_reset(id)
	save()


## Масштаб любого элемента (кнопки раскладки или элемента интерфейса).
static func scale_of(id: String) -> float:
	if ELEMENTS.has(id):
		return float(element(id)["s"])
	return clampf(float(hud_item(id).get("s", 1.0)), 0.5, 1.8)


static func opacity_of(id: String) -> float:
	if ELEMENTS.has(id):
		return element_opacity(id)
	return clampf(float(hud_item(id).get("o", 1.0)), 0.2, 1.0)


static func set_scale_of(id: String, value: float) -> void:
	if ELEMENTS.has(id):
		var e := element(id)
		set_element(id, float(e["x"]), float(e["y"]), value)
	else:
		hud_set(id, {"s": clampf(value, 0.5, 1.8)})
	save()


static func set_opacity_of(id: String, value: float) -> void:
	if ELEMENTS.has(id):
		set_element_opacity(id, value)
	else:
		hud_set(id, {"o": clampf(value, 0.2, 1.0)})
	save()


## Прозрачность отдельной кнопки (множитель к общей прозрачности).
static func element_opacity(id: String) -> float:
	return clampf(float(element(id).get("o", 1.0)), 0.2, 1.0)


static func set_element_opacity(id: String, value: float) -> void:
	element(id)["o"] = clampf(value, 0.2, 1.0)


static func get_value(key: String) -> Variant:
	return config()[key]


static func set_value(key: String, value: Variant) -> void:
	config()[key] = value
	save()


static func weapon_slot_count() -> int:
	if not SaveService.has_slot3():
		return 2
	return clampi(int(config()["weapon_slots"]), 2, 3)


## Готовая раскладка «Большие пальцы»: крупные кнопки с запасом между ними.
static func apply_big(left_handed: bool) -> void:
	apply_preset(left_handed)
	var cx := 0.09 if left_handed else 0.91
	var sx := 0.24 if left_handed else 0.76
	set_element("dash", cx, 0.78, 1.15)
	set_element("dodge", sx, 0.78, 1.15)
	set_element("slots", 0.46 if left_handed else 0.54, 0.84, 1.1)
	set_element("interact", sx, 0.48, 1.15)
	set_value("joystick_scale", 1.3)
	save()


static func apply_preset(left_handed: bool) -> void:
	var keep_presets: Dictionary = config()["presets"]
	var keep_keys: Dictionary = config()["keys"]
	var fresh := default_config(left_handed)
	for key in ["joystick_scale", "joystick_fixed", "opacity", "swipe_switch", "auto_pick", "auto_fire", "weapon_slots"]:
		fresh[key] = config()[key]
	fresh["presets"] = keep_presets
	fresh["keys"] = keep_keys
	if config().has("landscape_layout_backup"):
		fresh["landscape_layout_backup"] = config()["landscape_layout_backup"]
	fresh["hud"] = config().get("hud", {})
	if config().has("portrait_layout_backup"):
		fresh["portrait_layout_backup"] = config()["portrait_layout_backup"]
	SaveService.data["controls"] = fresh
	save()


static func save_preset(slot: int) -> void:
	var cfg := config()
	var snapshot := cfg.duplicate(true)
	snapshot.erase("presets")
	(cfg["presets"] as Dictionary)[str(slot)] = snapshot
	save()


static func has_preset(slot: int) -> bool:
	return (config()["presets"] as Dictionary).has(str(slot))


static func load_preset(slot: int) -> bool:
	var cfg := config()
	var presets: Dictionary = cfg["presets"]
	if not presets.has(str(slot)):
		return false
	var snapshot: Dictionary = (presets[str(slot)] as Dictionary).duplicate(true)
	snapshot["presets"] = presets
	if not snapshot.has("landscape_layout_backup") and cfg.has("landscape_layout_backup"):
		snapshot["landscape_layout_backup"] = cfg["landscape_layout_backup"]
	if not snapshot.has("portrait_layout_backup") and cfg.has("portrait_layout_backup"):
		snapshot["portrait_layout_backup"] = cfg["portrait_layout_backup"]
	SaveService.data["controls"] = snapshot
	apply_keys()
	save()
	return true


static func keys_for(action: StringName) -> Array:
	var custom: Dictionary = config()["keys"]
	if custom.has(str(action)):
		return custom[str(action)]
	if action == &"dodge":
		var skill_keys: Array = custom.get("dash", DEFAULT_KEYS[&"dash"])
		var free_keys: Array = []
		for key in DEFAULT_KEYS[&"dodge"]:
			if not skill_keys.has(key):
				free_keys.append(key)
		return [KEY_C] if free_keys.is_empty() else free_keys
	return DEFAULT_KEYS.get(action, [])


static func set_key(action: StringName, keycode: int) -> void:
	config()["keys"][str(action)] = [keycode]
	apply_keys()
	save()


static func reset_keys() -> void:
	config()["keys"] = {}
	apply_keys()
	save()


static func key_title(keycode: int) -> String:
	return OS.get_keycode_string(keycode)


## Пересобирает события InputMap из сохранённых клавиш.
static func apply_keys() -> void:
	for action in DEFAULT_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for keycode in keys_for(action):
			var event := InputEventKey.new()
			event.physical_keycode = int(keycode) as Key
			InputMap.action_add_event(action, event)


## Положение центра элемента в пикселях области viewport и его размер.
static func place(control: Control, id: String, area: Vector2, base_override: Vector2 = Vector2.ZERO) -> void:
	var e := element(id)
	var s: float = float(e["s"])
	var base: Vector2 = base_override if base_override != Vector2.ZERO else ELEMENT_SIZE[id]
	var size := base * s
	control.size = size
	control.position = Vector2(float(e["x"]) * area.x, float(e["y"]) * area.y) - size * 0.5


## Навык и рывок не должны налезать друг на друга, а слоты — на рывок. Общее для боя и превью в редакторе.
static func resolve_overlap(skill: Control, dodge: Control, slots: Control, area: Vector2) -> void:
	for button in [dodge, skill]:
		button.position.x = clampf(button.position.x, 4.0, area.x - button.size.x - 4.0)
	var skill_rect := Rect2(skill.position, skill.size).grow(10.0)
	if skill_rect.intersects(Rect2(dodge.position, dodge.size)):
		dodge.position.x = skill.position.x - 14.0 - dodge.size.x if skill.position.x > area.x * 0.5 else skill.position.x + skill.size.x + 14.0
	var main_btn: Control = dodge
	var slot_rect := Rect2(slots.position, slots.size).grow(6.0)
	if not slot_rect.intersects(Rect2(main_btn.position, main_btn.size)):
		return
	var gap := 14.0
	var left_side := main_btn.position.x + main_btn.size.x * 0.5 > area.x * 0.5
	var x := main_btn.position.x - gap - slots.size.x if left_side else main_btn.position.x + main_btn.size.x + gap
	var y := main_btn.position.y + main_btn.size.y - slots.size.y
	slots.position = Vector2(clampf(x, 4.0, area.x - slots.size.x - 4.0), maxf(y, 4.0))
