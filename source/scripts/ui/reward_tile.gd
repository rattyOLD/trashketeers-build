class_name RewardTile
extends PanelContainer
## Единая плитка награды (монеты + неонит): иконка-стопка растёт с размером награды, суммы в плашках с валютными значками.

enum State { LOCKED, CURRENT, DONE }

const COIN_ICON := "res://assets/ui/hub/coin.png"
const GEM_ICON := "res://assets/ui/hub/neonite.png"
const COIN_PILE := "res://assets/ui/hub/coins_pile.png"
const GEM_PILE := "res://assets/ui/hub/neonite_pile.png"
const GEM_COLOR := Color("#c98bff")


## tier 0..2 задаёт размер иконки и цвет рамки; big делает плитку крупной (главный приз).
func _init(title: String, coins: int, gems: int, tier: int, state: State, big: bool = false) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 176 if big else 168)
	var accent := [Color("#ffba72"), Color("#c98bff"), UiStyle.GOLD][clampi(tier, 0, 2)] as Color
	var bg := UiStyle.PANEL_LIGHT
	var border := UiStyle.CARD_BORDER
	match state:
		State.CURRENT:
			bg = Color(0.28, 0.21, 0.07, 0.98)
			border = UiStyle.GOLD
		State.DONE:
			bg = UiStyle.PANEL
			border = Color("#2fae5f")
		_:
			border = accent.darkened(0.45)
	add_theme_stylebox_override("panel", UiStyle.box(bg, border, 5 if state == State.CURRENT else 3, 20))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	column.add_child(UiStyle.label(title, 18, UiStyle.GOLD if state == State.CURRENT else accent.lightened(0.25), 4))
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 88 if big else 78)
	stage.modulate = Color(1, 1, 1, 0.5) if state == State.DONE else Color.WHITE
	column.add_child(stage)
	_fill_stage(stage, gems > 0, tier)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	column.add_child(row)
	row.add_child(_amount_row(COIN_ICON, "+%s" % SaveService.format_coins(coins), UiStyle.TEXT))
	if gems > 0:
		row.add_child(_amount_row(GEM_ICON, "+%d" % gems, GEM_COLOR.lightened(0.25)))
	if state == State.DONE:
		var mark := CheckMark.new()
		mark.anchor_left = 1.0
		mark.anchor_right = 1.0
		mark.offset_left = -36.0
		mark.offset_right = 0.0
		mark.offset_bottom = 36.0
		stage.add_child(mark)


func _fill_stage(stage: Control, has_gems: bool, tier: int) -> void:
	if has_gems:
		stage.add_child(_icon(COIN_PILE, 0.0, 0.66, 0.0, 1.0))
		stage.add_child(_icon(GEM_PILE, 0.4, 1.0, 0.0, 1.0))
	else:
		var span := [0.3, 0.2, 0.08][clampi(tier, 0, 2)] as float
		stage.add_child(_icon(COIN_PILE, span, 1.0 - span, 0.0, 1.0))


func _icon(path: String, left: float, right: float, top: float, bottom: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = ArenaProp.texture_of(path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_left = left
	icon.anchor_right = right
	icon.anchor_top = top
	icon.anchor_bottom = bottom
	return icon


func _amount_row(icon_path: String, text: String, color: Color) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.PANEL, 0.9), Color(0, 0, 0, 0), 0, 12))
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)
	pill.add_child(hbox)
	var icon := TextureRect.new()
	icon.texture = ArenaProp.texture_of(icon_path)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(icon)
	hbox.add_child(UiStyle.label(text, 20, color, 5))
	return pill


class CheckMark extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, UiStyle.OUTLINE)
		draw_circle(c, r - 3.0, Color("#2fae5f"))
		var pts := PackedVector2Array([c + Vector2(-r * 0.42, 0.0), c + Vector2(-r * 0.1, r * 0.36), c + Vector2(r * 0.46, -r * 0.34)])
		draw_polyline(pts, Color.WHITE, 4.0, true)
