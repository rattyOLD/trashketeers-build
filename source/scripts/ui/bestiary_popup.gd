class_name BestiaryPopup
extends GlassPopup

const ART := "res://assets/ui/bestiary/"
const HINTS := {
	"chaser": "Кайти по кругу; не позволяй толпе зажать тебя у стены.",
	"ranged": "Уходи поперёк линии огня, затем сближайся в паузе между выстрелами.",
	"exploder": "Держи дистанцию: после смерти он взрывается.",
	"dasher": "Уходи в сторону после замаха; рывок не меняет направление.",
	"bomber": "Выходи из отмеченной зоны до падения снаряда.",
	"slammer": "Уступи место замаху, затем атакуй во время восстановления.",
	"assassin": "Следи за полупрозрачным силуэтом и не стой на месте.",
	"trapper": "Обходи ловушки и сначала убирай самого ловца.",
	"trickster": "Не ведись на приманки; оставляй себе путь отхода.",
	"boss": "Избегай телеграфов; золотое кольцо после серии — окно усиленного урона."
}
const BOSS_HINTS := {
	"junk_overlord": "Не стой перед залпом и выходи из круга прыжка; бей после серии.",
	"beer_baron": "Заходи сбоку от струи, обходи лужи и бей в паузе после тарана.",
	"electric_shaman": "Держись вне электрического поля и уходи с отмеченных разрядов.",
	"mud_magnate": "Обходи мех сбоку; пережди денежный дождь, затем наказывай за серию.",
	"pig_magnate": "Двигайся поперёк гатлинга и не приближайся во время топота.",
	"sea_pirate": "Обходи залпы и взрывающиеся бочки; атакуй после серии.",
	"chef_boss": "Держись вне замаха сковороды и выходи из зоны прыжка.",
	"white_dragon": "Прячься за кристаллами от лазера, грейся в кругах и бей после посадки."
}
const FILTERS := [["", "ВСЕ"], ["chaser", "БЕГУНЫ"], ["ranged", "СТРЕЛКИ"],
	["dasher", "РЫВКИ"], ["bomber", "БОМБИСТЫ"], ["slammer", "МОЛОТЫ"],
	["trapper", "ЛОВЦЫ"], ["trickster", "ОБМАНЩИКИ"], ["assassin", "УБИЙЦЫ"], ["boss", "БОССЫ"]]
const FILTER_ICONS := {"chaser": "runner", "ranged": "shooter", "dasher": "dash", "bomber": "bomber",
	"slammer": "hammer", "trapper": "trap", "trickster": "trickster", "assassin": "assassin", "boss": "boss"}

var _entries: Array[Dictionary] = []
var _filter := ""
var _grid: GridContainer
var _count: Label
var _filter_buttons: Array[Button] = []


func _init() -> void:
	super("БЕСТИАРИЙ")
	for id in ContentDB.get_enemy_ids():
		var enemy := ContentDB.get_enemy(id)
		var kind := str(EnemyData.BEHAVIORS.find_key(enemy.behavior))
		_entries.append({"id": String(id), "title": enemy.display_name, "kind": kind,
			"shield": enemy.shield,
			"elite": not enemy.is_boss() and enemy.max_hp >= 90.0,
			"hint": "Заходи сзади: щит прикрывает только переднюю дугу." if enemy.shield else str(BOSS_HINTS.get(String(id), HINTS.get(kind, HINTS["chaser"])))})
	_entries.append({"id": "white_dragon", "title": "Хладгор", "kind": "boss", "elite": false, "hint": BOSS_HINTS["white_dragon"]})
	var banner := TextureRect.new()
	banner.texture = load(ART + "bestiary_banner.png") as Texture2D
	banner.custom_minimum_size = Vector2(0, 64)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(banner)
	var heading := HBoxContainer.new()
	heading.add_child(_icon("bestiary_menu", 32))
	_count = UiStyle.label("", 19, UiStyle.TEXT_DIM, 3)
	_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_count)
	content.add_child(heading)
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 6)
	for row in FILTERS:
		var button := UiStyle.button(str(row[1]), UiStyle.PANEL_LIGHT, 16, Vector2(0, 42))
		button.toggle_mode = true
		button.button_pressed = str(row[0]) == _filter
		button.set_meta(&"kind", str(row[0]))
		_filter_buttons.append(button)
		if FILTER_ICONS.has(str(row[0])):
			button.icon = load(ART + "filter_%s.png" % FILTER_ICONS[str(row[0])]) as Texture2D
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 22)
		button.pressed.connect(_select_filter.bind(str(row[0])))
		filters.add_child(button)
	content.add_child(filters)
	var list := MenuPopups.scroll_list(content)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	list.add_child(_grid)


static func discovered(id: String) -> bool:
	return SaveService.get_stat("seen_" + id) > 0 or SaveService.get_stat("k_" + id) > 0 or (id == "white_dragon" and SaveService.get_stat("raid_wins") > 0)


func _select_filter(kind: String) -> void:
	_filter = kind
	for button in _filter_buttons:
		button.set_pressed_no_signal(str(button.get_meta(&"kind")) == kind)
	_refresh()


func _refresh() -> void:
	MenuPopups.clear(_grid)
	var known := 0
	for entry in _entries:
		known += int(discovered(str(entry["id"])))
		var kind := str(entry["kind"])
		if _filter.is_empty() or kind == _filter or (_filter == "bomber" and kind == "exploder"):
			_grid.add_child(_card(entry))
	_count.text = "Встречено %d / %d · Карточка открывается при первой встрече" % [known, _entries.size()]


func _card(entry: Dictionary) -> Control:
	var id := str(entry["id"])
	var known := discovered(id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2((panel_width() - 76.0) / 3.0, 440)
	var family := "boss" if entry["kind"] == "boss" else ("elite" if bool(entry["elite"]) else "normal")
	var frame := StyleBoxTexture.new()
	frame.texture = load(ART + "card_%s.png" % (family if known else "locked")) as Texture2D
	frame.content_margin_left = 44
	frame.content_margin_right = 44
	frame.content_margin_top = 60
	frame.content_margin_bottom = 90
	panel.add_theme_stylebox_override("panel", frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var portrait := TextureRect.new()
	portrait.texture = load(ART + "portraits/%s.png" % id) as Texture2D if known else null
	portrait.custom_minimum_size = Vector2(0, 96 if known else 200)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(portrait)
	var title := UiStyle.label(str(entry["title"]) if known else "???", 20, UiStyle.TEXT, 4)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.visible = known
	column.add_child(title)
	var hint := UiStyle.label(str(entry["hint"]) if known else "Встреть этого противника в бою", 16, UiStyle.TEXT_DIM, 2)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tips := HBoxContainer.new()
	tips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tips.add_child(_icon("badge_weakness" if entry.get("shield", false) else ("badge_hint" if known else "badge_locked"), 20))
	tips.add_child(hint)
	column.add_child(tips)
	if known:
		var status := HBoxContainer.new()
		var kills := SaveService.get_stat("k_" + id)
		status.add_child(_icon("badge_defeated" if kills > 0 else "badge_new", 20))
		status.add_child(_icon("badge_kills", 20))
		status.add_child(UiStyle.label(str(kills), 16, UiStyle.GOLD, 2))
		column.add_child(status)
	return panel


static func _icon(name: String, side: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(ART + name + ".png") as Texture2D
	icon.custom_minimum_size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
