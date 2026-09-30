class_name LoadingScreen
extends CanvasLayer
## Загрузочный экран по паспорту интерфейса: прячет подгрузку ресурсов при переходе
## из меню в бой или в Налёт и удерживает внимание в Telegram Mini App.
##
## - Текст «Енот перемещается» и три точки, плавно появляющиеся по очереди раз в секунду.
## - Тонкая неоново-синяя рамка, заполняется кислотно-зелёным (#39FF14).
## - Енот бежит по верхней грани заливки: position.x жёстко привязан к значению 0..100.
##   Бег — цикл из 4 поз (подскок, наклон, сжатие) + покачивание хвоста.
## - На 100% Енот кувыркается вперёд и превращается в белую вспышку; в пике вспышки
##   испускается transition_point — вызывающий код подменяет сцену под вспышкой.
##
## Прогресс подаётся через set_progress() или track_resources() (threaded-загрузка).
## Отображаемое значение догоняет реальное с ограниченной скоростью, поэтому даже
## мгновенная загрузка не «проскакивает»: Енот всегда успевает пробежать полосу.

signal transition_point
signal finished

const BG := Color("#0b0418")
const FRAME := Color("#2e7bff")
const FILL := Color("#39ff14")
const PHRASES := [
	"Енот перемещается",
	"Енот роется в мусоре",
	"Крысы точат зубы",
	"Енот заряжает пушку",
	"Голубь пересчитывает налоги",
	"Енот выбирает лучший контейнер",
	"Свиньи делят неонит",
	"Енот греет лапы у бочки",
	"Хладгор потягивается подо льдом",
	"Енот завязывает шарф",
	"Бомбо-Крыса ищет спички",
	"Енот договаривается с сыром",
	"Разлом шепчет: «налоги»",
	"Енот проверяет, заряжен ли рывок",
	"Крысиный профсоюз требует сыра",
	"Енот прикидывается мусорным баком",
]
const PHRASE_TIME := 2.4
const PHRASE_FADE := 0.2
const DUST_INTERVAL := 0.11
const BAR_RADIUS := 15
const BAR_WIDTH_FRACTION := 0.72
const BAR_HEIGHT := 34.0
const MAX_FILL_SPEED := 85.0
const RUNNER_SCALE := 1.0
const RUNNER_SPEED := 230.0
const TUMBLE_TIME := 0.45
const FLASH_IN := 0.12
const FLASH_OUT := 0.35

## Советы и лор под полосой загрузки (случайный на каждый переход).
const TIPS := [
	"Совет: рывок даёт короткую неуязвимость — прыгай сквозь замах крысы.",
	"Совет: «!» над крысой — она сейчас кинется. Рывок в сторону!",
	"Совет: Бомбо-Крыса мигает перед взрывом. Её взрыв ранит и других крыс.",
	"Совет: ящики с оружием светятся цветом редкости. Золотой — легендарный ствол.",
	"Совет: два одинаковых ствола в Оружейной сливаются в тир выше (Merge).",
	"Совет: у свиней-охранников щит спереди. Зайди сбоку — «БЛОК» пропадёт.",
	"Совет: Магнитчик ставит мины-магниты. Рывок срывает захват.",
	"Совет: Искро-Заточка прячется в тени — следи за искрами на полу.",
	"Совет: красный круг на земле — туда что-то летит. Не стой в нём.",
	"Совет: босс выходит на 10-й волне. После него на помосте открывается портал.",
	"Совет: после каждой волны Енот лечится на 15%, а весь лут летит к нему.",
	"Совет: тормозит? Настройки → Графика → «Эконом».",
	"Лор: в ночь Великого Погасания люди исчезли, а свет — остался.",
	"Лор: Разломы сшивают куски мира. Только золото Дыхание Разлома не берёт.",
	"Лор: крысам нужно золото, свиньям — неонит. Еноты берут и то и другое.",
	"Лор: неонит — застывший свет на краю Разлома. Говорят, он тёплый.",
	"Лор: Ледяной дракон Хладгор заморозил озеро над свалкой. Кто ступит на лёд без щита - тот замёрзнет.",
	"Совет: рывок пересекает лужи и щиты - копи заряды перед боссом.",
	"Совет: не бери всё подряд. Три сильные улучшения одного типа лучше, чем шесть слабых.",
	"Совет: реролл улучшений бесплатный один раз за забег. Не трать его на первой волне.",
	"Совет: крыс лучше собирать в кучу - тогда одна граната делает всю работу.",
	"Совет: стоять на месте и стрелять - плохая идея. Енот, ты не турель.",
	"Совет: чем дальше волна, тем больше очков Боевого пропуска. Умирать рано невыгодно.",
	"Совет: в налёте лужи льда замедляют. Не танцуй в них.",
	"Совет: щит из льда закрывает от дыхания дракона, но не вечен. Береги его.",
	"Совет: ежедневный подарок копится в серии. Пропустил день - серия горюет.",
	"Совет: дубликаты героев превращаются в монеты, ничего не пропадает.",
	"Совет: бесплатный сундук раз в несколько часов. Заходи, пока он не остыл.",
	"Совет: перед боссом проверь здоровье. Термос с чаем никто не отменял.",
	"Совет: игра создана для горизонтального экрана. Переверни телефон - Енот скажет спасибо.",
	"Совет: не любишь альбомный режим? Енот тоже не любил диван, пока не попробовал.",
	"Совет: критический урон любит скорострельные стволы. Пулемёт счастлив.",
	"Совет: магнит подтягивает лут, но не пиццу. Пиццу приходится подбирать самому.",
	"Совет: если крыса блестит - это не золото. Это бомбо-крыса. Беги.",
	"Совет: редкие герои не слабее эпических, просто у них меньше пафоса.",
	"Совет: тир оружия - это не только цифры. Смотри на полоски у иконки.",
	"Лор: Енот не помнит, зачем пошёл на свалку. Зато помнит, где лежит хороший мусор.",
	"Лор: с тех пор как Крёстный Голубь сбил налоги с деревни свиней, в биоме свиней его недолюбливают.",
	"Лор: Крёстный Голубь утверждает, что налоги - это просто зерно с процентами.",
	"Лор: Доктор Пушок уверен, что его яд полезен. Кому - он не уточняет.",
	"Лор: Косой Турбо не косой. Он просто всегда смотрит на финиш.",
	"Лор: Рыжий Фитиль зажигает всё, что горит, и кое-что из того, что не должно.",
	"Лор: Капитан Пломбир носит холодный шарф даже в жару. Говорит, стиль обязывает.",
	"Лор: Полуночный Шнырь появляется, когда его не ждёшь, и исчезает, когда его ищут.",
	"Лор: Пивной Барон варит своё пиво из чего попало. Не спрашивай, из чего.",
	"Лор: Свинья-Магнат считает монеты вслух. Считать он умеет только до шести.",
	"Лор: у крыс есть профсоюз. Он в основном требует больше сыра и меньше Енотов.",
	"Лор: никто не знает, кто построил ящики с оружием. Все просто пользуются.",
	"Лор: Хладгор спал подо льдом сто лет. Проснулся он не по своей воле - кто-то включил музыку.",
	"Лор: лёд Хладгора не тает, только обиженно поскрипывает.",
	"Лор: у Хладгора холодные лапы, но горячее сердце. Не проверяй.",
	"Лор: когда-то на свалке был город. Теперь там пиццерия... без пиццы.",
	"Лор: светящиеся грибы на свалке - единственные, кому тут хорошо.",
	"Лор: говорят, где-то есть чистая свалка. Еноты считают это байкой.",
	"Лор: Енот однажды пытался договориться с крысой. Сыр они так и не поделили.",
	"Лор: неоновые вывески на свалке горят сами. Электрика никто давно не видел.",
	"Лор: свинья в кепке - это не охранник. Это инспектор. Опаснее охранника.",
	"Лор: легенда гласит, что самый вкусный мусор лежит на дне самого большого контейнера.",
	"Лор: Еноты считают полосатые хвосты признаком благородства. Панды не спорят.",
	"Лор: у Разлома нет дна, но есть эхо. Оно повторяет только «налоги».",
	"Лор: Голубь и Свинья-Магнат однажды играли в покер. Игру до сих пор объясняют юристы.",
]

var target_progress := 0.0
var shown_progress := 0.0

var _root: Control
var _title: Label
var _dots: Array[Label] = []
var _bar: Control
var _runner: Node2D
## Бегун — настоящий герой игрока на риге (выбранный персонаж и наряд), бежит без цели.
var _runner_hero: RaccoonVisual
var _fx: Node2D
var _percent: Label
var _phrase_index := 0
var _phrase_timer := PHRASE_TIME
var _act := ""
var _act_t := 0.0
var _act_timer := 1.6
var _shot_timer := 0.0
var _dust_timer := 0.0
var _hop_height := 0.0
var _particles: Array = []
var _flash: ColorRect
var _time := 0.0
var _tracked: PackedStringArray = PackedStringArray()
var _finishing := false


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var text_col := VBoxContainer.new()
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.anchor_left = 0.05
	text_col.anchor_right = 0.95
	text_col.anchor_top = 0.36
	text_col.anchor_bottom = 0.36
	text_col.offset_top = -80.0
	text_col.offset_bottom = 80.0
	_root.add_child(text_col)
	_phrase_index = randi() % PHRASES.size()
	_title = UiStyle.label(PHRASES[_phrase_index], 46, UiStyle.TEXT, 14)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(0, 124)
	text_col.add_child(_title)
	var dot_row := HBoxContainer.new()
	dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.add_child(dot_row)
	for i in 3:
		var dot := UiStyle.label("●", 26, FILL, 8)
		dot.custom_minimum_size = Vector2(34, 0)
		dot_row.add_child(dot)
		_dots.append(dot)

	_bar = Control.new()
	_bar.anchor_left = (1.0 - BAR_WIDTH_FRACTION) * 0.5
	_bar.anchor_right = 1.0 - (1.0 - BAR_WIDTH_FRACTION) * 0.5
	_bar.anchor_top = 0.7
	_bar.anchor_bottom = 0.7
	_bar.offset_bottom = BAR_HEIGHT
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)
	_percent = UiStyle.label("0%", 30, FILL, 8)
	_percent.anchor_right = 1.0
	_percent.offset_top = BAR_HEIGHT + 10.0
	_percent.offset_bottom = BAR_HEIGHT + 56.0
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bar.add_child(_percent)

	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	_root.add_child(_fx)

	_runner = Node2D.new()
	_runner_hero = RaccoonVisual.new()
	_runner_hero.aiming = false
	_runner_hero.scale = Vector2.ONE * RUNNER_SCALE
	_runner.add_child(_runner_hero)
	_root.add_child(_runner)

	var tip := UiStyle.label(TIPS.pick_random(), 24, Color("#b5a9d6"), 6)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.anchor_left = 0.08
	tip.anchor_right = 0.92
	tip.anchor_top = 0.78
	tip.anchor_bottom = 0.78
	tip.offset_bottom = 120.0
	_root.add_child(tip)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


## Прогресс 0..100 от внешнего источника.
func set_progress(value: float) -> void:
	target_progress = clampf(value, 0.0, 100.0)


## Запускает threaded-загрузку ресурсов и сам считает прогресс по ним.
func track_resources(paths: PackedStringArray) -> void:
	_tracked = PackedStringArray()
	for path in paths:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			_tracked.append(path)
	if _tracked.is_empty():
		set_progress(100.0)


func _process(delta: float) -> void:
	_time += delta
	if not _tracked.is_empty():
		_poll_tracked()
	_animate_dots()
	_animate_phrase(delta)
	if _finishing:
		return
	shown_progress = move_toward(shown_progress, target_progress, MAX_FILL_SPEED * delta)
	_bar.queue_redraw()
	_percent.text = "%d%%" % int(shown_progress)
	_animate_runner(delta)
	_update_particles(delta)
	if shown_progress >= 100.0:
		_finish()


func _poll_tracked() -> void:
	var total := 0.0
	var progress := []
	for path in _tracked:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				total += 1.0
			_:
				total += float(progress[0]) if not progress.is_empty() else 0.0
	set_progress(total / _tracked.size() * 100.0)
	if total >= _tracked.size():
		for path in _tracked:
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(path)
		_tracked = PackedStringArray()


## Три точки бегут волной: каждая на миг вспыхивает и уходит в тень.
func _animate_dots() -> void:
	for i in _dots.size():
		var wave := 0.5 + 0.5 * sin(_time * 5.0 - i * 0.9)
		_dots[i].modulate.a = 0.25 + 0.75 * wave
		_dots[i].scale = Vector2.ONE * (0.8 + 0.3 * wave)
		_dots[i].pivot_offset = _dots[i].size * 0.5


func _animate_phrase(delta: float) -> void:
	_phrase_timer -= delta
	if _phrase_timer > 0.0:
		return
	_phrase_timer = PHRASE_TIME
	_phrase_index = (_phrase_index + 1 + randi() % (PHRASES.size() - 1)) % PHRASES.size()
	var tween := create_tween()
	tween.tween_property(_title, "modulate:a", 0.0, PHRASE_FADE)
	tween.tween_callback(func() -> void: _title.text = PHRASES[_phrase_index])
	tween.tween_property(_title, "modulate:a", 1.0, PHRASE_FADE)


func _animate_runner(delta: float) -> void:
	var rect := _bar.get_global_rect()
	var lift := _act_offset(delta)
	_runner.position = Vector2(rect.position.x + rect.size.x * shown_progress / 100.0, rect.position.y - 26.0 * RUNNER_SCALE - lift)
	if _finishing:
		return
	var speed := RUNNER_SPEED * (1.7 if _act == "dash" else 1.0)
	var aim := Vector2.RIGHT if _act == "shoot" else Vector2.ZERO
	_runner_hero.dashing = _act == "dash"
	_runner_hero.aiming = _act == "shoot"
	_runner_hero.update_motion(Vector2(speed, 0.0), aim, delta)
	_dust_timer -= delta
	if _dust_timer <= 0.0 and lift < 4.0:
		_dust_timer = DUST_INTERVAL * (0.55 if _act == "dash" else 1.0)
		_puff(_runner.position + Vector2(-16.0, 24.0), Color(0.75, 0.7, 0.9, 0.5), 3)
	if _act == "shoot":
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_shot_timer = 0.16
			_runner_hero.kick(Vector2.RIGHT, 1.0)
			_muzzle_flash()
	_act_timer -= delta
	if _act.is_empty() and _act_timer <= 0.0:
		_start_act(["hop", "flip", "shoot", "cheer", "dash"].pick_random())
	elif not _act.is_empty() and _act_t <= 0.0:
		_act = ""
		_act_timer = randf_range(1.8, 3.2)
		_runner_hero.rotation = 0.0


func _start_act(act: String) -> void:
	_act = act
	match act:
		"hop":
			_act_t = 0.55
			_hop_height = 54.0
		"flip":
			_act_t = 0.75
			_hop_height = 78.0
		"shoot":
			_act_t = 0.85
			_shot_timer = 0.05
		"cheer":
			_act_t = 0.7
			_runner_hero.cheer()
		"dash":
			_act_t = 0.6


## Высота подскока над полосой; тайминг актов считается здесь же.
func _act_offset(delta: float) -> float:
	if _act.is_empty():
		return 0.0
	var duration := {"hop": 0.55, "flip": 0.75, "shoot": 0.85, "cheer": 0.7, "dash": 0.6}[_act] as float
	_act_t -= delta
	var k := clampf(1.0 - _act_t / duration, 0.0, 1.0)
	if _act == "hop" or _act == "flip":
		if _act == "flip":
			_runner_hero.rotation = TAU * k
		if k > 0.9 and _act_t > 0.0 and int(_time * 60.0) % 3 == 0:
			_puff(_runner.position + Vector2(0, 26.0), Color(0.8, 0.75, 1.0, 0.6), 2)
		return sin(k * PI) * _hop_height
	if _act == "cheer":
		return sin(k * PI * 2.0) * 10.0 * (1.0 - k)
	return 0.0


func _puff(at: Vector2, color: Color, count: int) -> void:
	for i in count:
		_particles.append([at, Vector2(randf_range(-70.0, -20.0), randf_range(-30.0, -4.0)), 0.0, randf_range(0.35, 0.6), randf_range(4.0, 8.0), color])


func _muzzle_flash() -> void:
	var at := _runner_hero.get_muzzle_global(Vector2.RIGHT)
	for i in 5:
		_particles.append([at, Vector2(randf_range(160.0, 380.0), randf_range(-70.0, 70.0)), 0.0, randf_range(0.12, 0.26), randf_range(3.0, 6.0), Color(1.0, randf_range(0.75, 0.95), 0.3, 1.0)])


func _update_particles(delta: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var pt: Array = _particles[i]
		pt[2] += delta
		pt[0] += pt[1] * delta
		pt[1] *= 1.0 - delta * 3.0
		if pt[2] >= pt[3]:
			_particles.remove_at(i)
	_fx.queue_redraw()


func _draw_fx() -> void:
	for pt in _particles:
		var life: float = 1.0 - float(pt[2]) / float(pt[3])
		var color: Color = pt[5]
		_fx.draw_circle(pt[0], float(pt[4]) * (0.5 + 0.5 * life), Color(color, color.a * life))
	if _act == "dash" and not _finishing:
		for k in 4:
			var y := _runner.position.y + 4.0 + k * 11.0
			var x := _runner.position.x - 30.0 - k * 6.0
			_fx.draw_line(Vector2(x, y), Vector2(x - 60.0 - (k % 2) * 30.0, y), Color(FILL, 0.5), 3.0)


## 100%: кувырок вперёд → белая вспышка → в её пике transition_point → вспышка гаснет.
func _finish() -> void:
	_finishing = true
	var tween := create_tween()
	tween.set_parallel(true)
	_runner_hero.cheer()
	tween.tween_property(_runner_hero, "rotation", TAU, TUMBLE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_runner, "position:x", _runner.position.x + 70.0, TUMBLE_TIME)
	tween.tween_property(_runner_hero, "modulate", Color(4, 4, 4, 1), TUMBLE_TIME)
	tween.set_parallel(false)
	tween.tween_property(_flash, "color:a", 1.0, FLASH_IN)
	tween.tween_callback(func() -> void:
		_root.get_child(0).visible = false
		_title.get_parent().visible = false
		_bar.visible = false
		_runner.visible = false
		_fx.visible = false
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		transition_point.emit())
	tween.tween_property(_flash, "color:a", 0.0, FLASH_OUT)
	tween.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(FRAME, 0.0)
	glow.set_corner_radius_all(BAR_RADIUS + 4)
	glow.shadow_color = Color(FRAME, 0.45)
	glow.shadow_size = 14
	_bar.draw_style_box(glow, r)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#120a2a")
	track.set_corner_radius_all(BAR_RADIUS)
	track.set_border_width_all(3)
	track.border_color = FRAME
	_bar.draw_style_box(track, r)
	for tick in [0.25, 0.5, 0.75]:
		var x: float = r.size.x * tick
		_bar.draw_line(Vector2(x, 9.0), Vector2(x, r.size.y - 9.0), Color(FRAME, 0.35), 2.0)
	var width := r.size.x * shown_progress / 100.0
	if width < 4.0:
		return
	var fill_rect := Rect2(Vector2(3, 3), Vector2(maxf(width - 6.0, 2.0), r.size.y - 6.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = FILL.darkened(0.12)
	fill.set_corner_radius_all(BAR_RADIUS - 3)
	_bar.draw_style_box(fill, fill_rect)
	var inner_l := fill_rect.position.x + 8.0
	var inner_r := fill_rect.end.x - 8.0
	if inner_r > inner_l:
		var top := StyleBoxFlat.new()
		top.bg_color = Color(1, 1, 1, 0.38)
		top.set_corner_radius_all(3)
		_bar.draw_style_box(top, Rect2(inner_l, fill_rect.position.y + 3.0, inner_r - inner_l, 5.0))
		var shift := fmod(_time * 46.0, 44.0)
		var y0 := fill_rect.position.y + 9.0
		var y1 := fill_rect.end.y - 4.0
		var x0 := inner_l - 44.0 + shift
		while x0 < inner_r:
			var pts := PackedVector2Array([Vector2(x0, y1), Vector2(x0 + 14.0, y1), Vector2(x0 + 30.0, y0), Vector2(x0 + 16.0, y0)])
			for i in pts.size():
				pts[i].x = clampf(pts[i].x, inner_l, inner_r)
			if absf(pts[0].x - pts[2].x) + absf(pts[1].x - pts[3].x) > 1.0:
				_bar.draw_colored_polygon(pts, Color(0.0, 0.25, 0.0, 0.16))
			x0 += 44.0
	var head := Vector2(fill_rect.end.x - 4.0, r.size.y * 0.5)
	for k in 3:
		_bar.draw_circle(head, 20.0 - k * 6.0, Color(FILL, 0.10 + 0.08 * k))
