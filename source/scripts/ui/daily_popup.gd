class_name DailyPopup
extends GlassPopup
## Ежедневная награда: семь дней серии, сегодняшний подсвечен, пропуск дня сбрасывает серию.

signal claimed

var _grid: GridContainer
var _finale: VBoxContainer
var _button: Button
var _hint: Label


func _init() -> void:
	super("ЕЖЕДНЕВНЫЙ ПОДАРОК")
	_hint = UiStyle.label("", 20, UiStyle.TEXT_DIM, 4)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(540, 0)
	content.add_child(_hint)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(_grid)
	_finale = VBoxContainer.new()
	content.add_child(_finale)
	_button = UiStyle.button("ЗАБРАТЬ", Color("#2fae5f"), 32, Vector2(0, 92))
	_button.pressed.connect(_claim)
	content.add_child(_button)


func _refresh() -> void:
	MenuPopups.clear(_grid)
	MenuPopups.clear(_finale)
	var can := SaveService.can_claim_daily()
	var step := SaveService.get_daily_step()
	for day in range(1, SaveService.DAILY_REWARDS.size()):
		_grid.add_child(_make_cell(day, step, can))
	var last := SaveService.DAILY_REWARDS.size()
	_finale.add_child(_make_cell(last, step, can))
	_button.disabled = not can
	_button.text = "ЗАБРАТЬ · +%s" % SaveService.format_coins(SaveService.get_daily_reward()) if can else "Уже забрано - приходи завтра"
	_hint.text = "Заходи каждый день: серия растёт, награды больше. Пропустишь день - серия начнётся заново." + (" VIP: награда x%d." % Premium.daily_mult() if Premium.daily_mult() > 1 else "")


func _make_cell(day: int, step: int, can: bool) -> Control:
	var state := RewardTile.State.LOCKED
	if day < step or (day == step and not can):
		state = RewardTile.State.DONE
	elif day == step:
		state = RewardTile.State.CURRENT
	var mult := Premium.daily_mult()
	var coins := int(SaveService.DAILY_REWARDS[day - 1]) * mult
	var gems := int(SaveService.DAILY_GEMS.get(day, 0)) * mult
	var tier := 2 if day == 7 else (1 if gems > 0 else 0)
	return RewardTile.new("ДЕНЬ %d" % day, coins, gems, tier, state, day == 7)


func _claim() -> void:
	if SaveService.claim_daily() > 0:
		SoundManager.play(&"star_dust")
		claimed.emit()
		_refresh()
