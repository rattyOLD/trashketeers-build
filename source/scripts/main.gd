extends Node
## Точка входа: меню ↔ (загрузочный экран) ↔ бой на Свалке / Налёт.
## Сцены собираются кодом; смена экрана — не геймплей, поэтому создание/удаление нод здесь
## не нарушает запрет на instantiate в бою. Переходы из кнопок делаются deferred:
## кнопки живут внутри удаляемого экрана.

const INPUT_BINDINGS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"dash": [KEY_SPACE, KEY_SHIFT],
}
const UI_FONT := "res://assets/fonts/RussoOne-Regular.ttf"

const BATTLE_RESOURCES := [
	"res://assets/enemies/rat_base.png",
	"res://assets/enemies/spark_rat.png",
	"res://assets/biome/ch1_floor.png",
	"res://assets/props/ch1/container.png",
	"res://assets/props/ch1/junk_pile.png",
	"res://assets/audio/music/battle.ogg",
	"res://assets/player/raccoon.png",
	"res://assets/player/raccoon_body.png",
	"res://assets/player/raccoon_arm.png",
]
const RAID_RESOURCES := [
	"res://assets/bosses/ice_dragon_idle.png",
	"res://assets/bosses/ice_dragon_fly.png",
	"res://assets/bosses/ice_dragon_breath.png",
	"res://assets/bosses/ice_dragon_tail.png",
	"res://assets/raid/ice_shield.png",
	"res://assets/raid/ice_puddle.png",
	"res://assets/audio/music/raid.ogg",
	"res://assets/bullets/ice_shard.png",
	"res://assets/player/raccoon.png",
	"res://assets/player/raccoon_body.png",
	"res://assets/player/raccoon_arm.png",
]

var _debug_hash := ""
var _screen: Node
var _loading: LoadingScreen


func _ready() -> void:
	# Интерполяция физики включена в проекте, но по умолчанию выключена для всего дерева: её
	# включают только узлы, которым нужна плавность (дракон Хладгор).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Шрифт по умолчанию для всего, что рисуется через ThemeDB.fallback_font (цифры урона,
	# подписи в _draw) — тот же, что у контролов (gui/theme/custom_font).
	if ResourceLoader.exists(UI_FONT):
		ThemeDB.fallback_font = load(UI_FONT)
	# Телефоны с экраном 90–120 Гц иначе гонят вдвое больше кадров: греются и начинают
	# троттлить. Игра рассчитана на 60.
	Engine.max_fps = 60
	_handle_unclean_exit()
	SaveService.apply_quality()
	_register_input()
	_show_menu()
	if OS.has_feature("web"):
		var url_hash := str(JavaScriptBridge.eval("window.location.hash"))
		if url_hash.begins_with("#raid"):
			_debug_hash = url_hash.substr(1)
			_start_raid.call_deferred(SaveService.get_selected_weapon())


func _handle_unclean_exit() -> void:
	var info := Platform.consume_unclean_exit()
	if info.is_empty():
		return
	var quality := SaveService.get_quality()
	if quality > 0:
		SaveService.set_quality(quality - 1)
		SaveService.set_flag("crash_downgraded", true)
	Platform.send_report("unclean_exit", "%s | now quality %d | last: %s | %s" % [info, SaveService.get_quality(), Platform.last_context(), Platform.device_info()])


func _register_input() -> void:
	Controls.apply_keys()


func _show_menu() -> void:
	var menu := MainMenuUI.new()
	menu.start_requested.connect(_start_game, CONNECT_DEFERRED)
	menu.raid_requested.connect(_start_raid, CONNECT_DEFERRED)
	_swap_screen(menu)


func _start_game(weapon_id: StringName) -> void:
	_with_loading(BATTLE_RESOURCES, func() -> void:
		var game := Game.new()
		game.exit_requested.connect(_show_menu, CONNECT_DEFERRED)
		game.restart_requested.connect(_start_game.bind(weapon_id), CONNECT_DEFERRED)
		_swap_screen(game)
		game.start(weapon_id))


func _start_raid(weapon_id: StringName) -> void:
	_with_loading(RAID_RESOURCES, func() -> void:
		var raid := Raid.new()
		raid.exit_requested.connect(_show_menu, CONNECT_DEFERRED)
		raid.restart_requested.connect(_start_raid.bind(weapon_id), CONNECT_DEFERRED)
		_swap_screen(raid)
		raid.start(weapon_id)
		if not _debug_hash.is_empty():
			raid.debug_setup(_debug_hash)
			_debug_hash = "")


## Загрузочный экран поверх текущего; новая сцена собирается в пике белой вспышки.
func _with_loading(resources: Array, build: Callable) -> void:
	if _loading != null:
		return
	get_tree().paused = false
	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.transition_point.connect(build, CONNECT_ONE_SHOT)
	_loading.finished.connect(func() -> void: _loading = null, CONNECT_ONE_SHOT)
	_loading.track_resources(PackedStringArray(resources))


func _swap_screen(next: Node) -> void:
	get_tree().paused = false
	if _screen != null:
		# remove_child сразу вызывает _exit_tree старого экрана (бой чистит BulletPool)
		# до того, как новый экран сделает первый кадр.
		remove_child(_screen)
		_screen.queue_free()
	_screen = next
	add_child(next)
	if _loading != null:
		move_child(_loading, get_child_count() - 1)
