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

const BG := Color("#161514")
const FRAME := Color("#ff9629")
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
	"Енот проверяет, заряжен ли навык",
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
	"Совет: зажми палец справа и тяни туда, куда стрелять. Отпустил — стрельба остановилась.",
	"Совет: отпустил палец — Рико перестал стрелять. Он не железный, он енот.",
	"Совет: стреляй в ящики и бочки сам: по крысам в тесноте иногда выгодно кинуть взрыв.",
	"Совет: одной рукой бежим, другой стреляем. Енот ждёт, что ты справишься.",
	"Совет: линия выстрела — это подсказка, а не прицел. Крысы двигаются, думай на шаг вперёд.",
	"Совет: в сюжете одна пушка. Подобрал новую — старая ушла на пенсию.",
	"Совет: красная зона — подарок от босса. Не бери подарок.",
	"Совет: в сюжете ворота открываются, когда умер последний крыс. Ищи стрелку над головой.",
	"Совет: пленникам плевать на твою репутацию. Освободи их, и они спасибо скажут. Возможно.",
	"Совет: Нэлл записывает всё. Особенно твои смерти.",
	"Шутка: Енот не умирает, он «временно отдыхает» на чекпоинте.",
	"Шутка: на свалке нет слова «осторожно». Есть слово «ой».",
	"Шутка: Король Хлама правил тут ещё до того, как это стало мусором.",
	"Шутка: Пивной Барон считает, что любую проблему решает бочка. Он, кстати, прав.",
	"Шутка: если бочка взрывается, это не баг. Это такая особенность жизни.",
	"Шутка: рельсотрон в боевом пропуске. Барон его запомнит. И ты тоже.",
	"Шутка: Игрок, если ты читаешь это на загрузке, то загрузка идёт слишком долго или ты просто любишь читать.",
	"Шутка: смерть в игре — это не конец. Это повод попробовать ещё раз и ругаться тише.",
	"Шутка: Рико не жадный. Он просто любит, когда монеты у него в кармане, а не на полу.",
	"Шутка: Рико любит пиво, но только после смены. Нэлл проверяет, а Каска наливает.",
	"Совет: бочки на карте взрываются. Рико смотрит на них с уважением, но пить из них не советует.",
	"Шутка: у Рико растёт сын, Малой. Носит его старую красную толстовку и говорит, что это ретро.",
	"Шутка: некоторые враги дерутся за деньги, некоторые за идею. Крысы — за пиво.",
	"Шутка: босс — это просто крыса, которая очень хорошо питалась.",
	"Совет: ранг S даётся за забег без единого урона. Да, мы тоже не поверили.",
	"Совет: заказ Нэлл меняется каждый день и платит монетами и неонитом.",
	"Совет: секретные плиты в стенах ломаются, если стрелять по ним. Ищи трещины.",
	"Совет: в сюжете перед боссом дают передышку. Пользуйся: подбери аптечку и выдохни.",
	"Совет: пощадить босса или ограбить — выбор влияет на концовку и награду.",
	"Совет: навык героя — твой козырь. Береги его на толпу или босса.",
	"Совет: «!» над крысой — она сейчас кинется. Уходи в сторону!",
	"Совет: Бомбо-Крыса мигает перед взрывом. Её взрыв ранит и других крыс.",
	"Совет: ящики с оружием светятся цветом редкости. Золотой — легендарный ствол.",
	"Совет: два одинаковых ствола в Оружейной сливаются в тир выше (Merge).",
	"Совет: у свиней-охранников щит спереди. Зайди сбоку — «БЛОК» пропадёт.",
	"Совет: Магнитчик ставит мины-магниты. Не стой у мины — она тянет к себе.",
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
	"Совет: обходи лужи и щиты — под огнём босса каждый шаг на счету.",
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
	"Совет: критический урон любит скорострельные стволы. Пулемёт счастлив.",
	"Совет: магнит подтягивает лут, но не пиццу. Пиццу приходится подбирать самому.",
	"Совет: если крыса блестит - это не золото. Это бомбо-крыса. Беги.",
	"Совет: редкие герои не слабее эпических, просто у них меньше пафоса.",
	"Совет: тир оружия - это не только цифры. Смотри на полоски у иконки.",
	"Лор: Енот не помнит, зачем пошёл на свалку. Зато помнит, где лежит хороший мусор.",
	"Лор: с тех пор как Тони «Дон» сбил налоги с деревни свиней, в биоме свиней его недолюбливают.",
	"Лор: Тони «Дон» утверждает, что налоги - это просто зерно с процентами.",
	"Лор: Фрэнк «Фаззи» уверен, что его яд полезен. Кому - он не уточняет.",
	"Лор: Нэлл по позывному «Турбо» не косая. Она просто всегда смотрит на финиш.",
	"Лор: Тимур «Фитиль» зажигает всё, что горит, и кое-что из того, что не должно.",
	"Лор: Джек «Фрост» носит холодный шарф даже в жару. Говорит, стиль обязывает.",
	"Лор: Эйден «Шэдоу» появляется, когда его не ждёшь, и исчезает, когда его ищут.",
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
var _cast_root: Node2D
var _scenery: Control
var _extras: Array[Extra] = []
var _cast_timer := 2.2
var _last_scene := ""


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
	_bleed(bg)
	_root.add_child(bg)

	_scenery = Scenery.new()
	_scenery.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scenery)

	# Логотип TRASH SQUAD (Астра, assets/ui/loading/logo.png) над надписью «ЗАГРУЗКА».
	if ResourceLoader.exists("res://assets/ui/loading/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/ui/loading/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.anchor_left = 0.5
		logo.anchor_right = 0.5
		logo.anchor_top = 0.16
		logo.anchor_bottom = 0.16
		logo.offset_left = -170.0
		logo.offset_right = 170.0
		logo.offset_top = -108.0
		logo.offset_bottom = -8.0
		_root.add_child(logo)
	var head := UiStyle.label("ЗАГРУЗКА", 20, Color("#ffb347"), 4)
	head.anchor_left = 0.0
	head.anchor_right = 1.0
	head.anchor_top = 0.16
	head.anchor_bottom = 0.16
	head.offset_bottom = 30.0
	_root.add_child(head)
	var head_line := Control.new()
	head_line.anchor_left = 0.5
	head_line.anchor_right = 0.5
	head_line.anchor_top = 0.16
	head_line.anchor_bottom = 0.16
	head_line.offset_left = -90.0
	head_line.offset_right = 90.0
	head_line.offset_top = 36.0
	head_line.offset_bottom = 44.0
	head_line.draw.connect(func() -> void:
		var x := 0.0
		while x < head_line.size.x:
			var pts := PackedVector2Array([Vector2(x, 8), Vector2(x + 10, 8), Vector2(x + 18, 0), Vector2(x + 8, 0)])
			head_line.draw_colored_polygon(pts, Color("#ffb347", 0.85) if int(x / 18.0) % 2 == 0 else Color(0, 0, 0, 0.6))
			x += 18.0)
	_root.add_child(head_line)

	var text_col := VBoxContainer.new()
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.anchor_left = 0.05
	text_col.anchor_right = 0.95
	text_col.anchor_top = 0.32
	text_col.anchor_bottom = 0.32
	text_col.offset_top = -80.0
	text_col.offset_bottom = 80.0
	_root.add_child(text_col)
	_phrase_index = randi() % PHRASES.size()
	_title = UiStyle.label(PHRASES[_phrase_index], 38, UiStyle.TEXT, 14)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(0, 96)
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
	# Полоса загрузки — внизу экрана, совет — над ней.
	_bar.anchor_top = 0.78
	_bar.anchor_bottom = 0.78
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

	_cast_root = Node2D.new()
	_root.add_child(_cast_root)
	_runner = Node2D.new()
	_runner_hero = RaccoonVisual.new()
	_runner_hero.aiming = false
	_runner_hero.scale = Vector2.ONE * RUNNER_SCALE
	_runner.add_child(_runner_hero)
	_root.add_child(_runner)

	var tip_text: String = TIPS.pick_random()
	var tag := ""
	for prefix in ["Совет: ", "Лор: ", "Шутка: "]:
		if tip_text.begins_with(prefix):
			tag = prefix.trim_suffix(": ").to_upper()
			tip_text = tip_text.trim_prefix(prefix)
			tip_text = tip_text.left(1).to_upper() + tip_text.substr(1)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.129, 0.124, 0.116, 0.88), Color("#ffb347", 0.55), 3, 14))
	card.anchor_left = 0.08
	card.anchor_right = 0.92
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.grow_vertical = Control.GROW_DIRECTION_END
	var card_col := VBoxContainer.new()
	card_col.add_theme_constant_override("separation", 4)
	card.add_child(card_col)
	if not tag.is_empty():
		card_col.add_child(UiStyle.label(tag, 17, Color("#ffb347"), 4))
	var tip := UiStyle.label(tip_text, 20, Color("#d4cbef"), 6)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_col.add_child(tip)
	_root.add_child(card)

	var build := UiStyle.label("Версия %s" % Platform.build_label(), 18, Color("#b89c80"), 4)
	build.anchor_left = 0.0
	build.anchor_right = 1.0
	build.anchor_top = 1.0
	build.anchor_bottom = 1.0
	build.offset_top = -44.0
	build.offset_bottom = -10.0
	_root.add_child(build)

	_flash = ColorRect.new()
	# Переход через затемнение, а не белую вспышку: в тёмной игре белый экран режет глаза.
	_flash.color = Color(0.035, 0.03, 0.05, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bleed(_flash)
	_root.add_child(_flash)


## _root ужат до безопасной зоны (вырез, «чёлка»), а фон и затемнение должны закрывать весь экран:
## иначе по краям iPhone просвечивало меню под загрузкой (кнопки «Прокачка/Друзья» снизу).
func _bleed(control: Control) -> void:
	control.offset_left = -600.0
	control.offset_top = -600.0
	control.offset_right = 600.0
	control.offset_bottom = 600.0


func _ready() -> void:
	ScreenSafeArea.fit(_root, get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(func() -> void: ScreenSafeArea.fit(_root, get_viewport().get_visible_rect().size))


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
	_animate_cast(delta)
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
	var rect := Rect2(_bar.position, _bar.size)
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
		_puff(_runner.position + Vector2(-16.0, 24.0), Color(0.900, 0.768, 0.630, 0.5), 3)
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
			_puff(_runner.position + Vector2(0, 26.0), Color(1.000, 0.841, 0.675, 0.6), 2)
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
## Titles already contain the chapter name; no duplicate label on top.
func show_chapter(mission: String) -> void:
	if mission not in ["m1", "m2"] or _title == null:
		return
	var card := TextureRect.new()
	card.texture = load("res://assets/story/chapter_cards/chapter_%s.png" % mission.trim_prefix("m")) as Texture2D
	card.custom_minimum_size = Vector2(0, 150)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(card)
	_title.get_parent().move_child(card, 0)
	_title.hide()


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
		_cast_root.visible = false
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
	track.bg_color = Color("#272523")
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


# --- Массовка: враги и друзья пробегают мимо полосы загрузки ---------------------------------------------

const SCENES: Array[String] = ["chase", "pigeon", "courier", "sniper", "parade", "pirate", "chef"]
const MAX_EXTRAS := 6


## Один персонаж массовки: кадровый лист, клип, движение и сценарий смены клипов.
class Extra:
	extends Node2D

	var sprite := RigSprite.new()
	var clip := "run"
	var phase := 0.0
	var vel := Vector2.ZERO
	var ttl := 4.0
	var follow: Node2D = null
	var follow_offset := Vector2.ZERO
	var bob := 0.0
	var fade := 0.35
	var steps: Array = []
	var _t := 0.0
	var _base_y := 0.0
	var _ready_ok := false

	func setup(sheet_id: String, size: float, face: float) -> bool:
		add_child(sprite)
		_ready_ok = sprite.setup_frames(sheet_id, 6.0)
		scale = Vector2(size * face, size)
		return _ready_ok

	func start(at: Vector2) -> void:
		position = at
		_base_y = at.y

	func tick(delta: float) -> bool:
		_t += delta
		ttl -= delta
		for step: Array in steps:
			if not bool(step[2]) and _t >= float(step[0]):
				step[2] = true
				clip = str(step[1])
				phase = 0.0
		var sheet := sprite.frame_sheet
		if not FrameDB.has_clip(sheet, clip):
			clip = "idle"
		phase += delta * FrameDB.clip_fps(sheet, clip)
		sprite.set_frame(FrameDB.clip_frame(sheet, clip, phase))
		if follow != null:
			position.x = follow.position.x + follow_offset.x
		else:
			position.x += vel.x * delta
		position.y = _base_y + (sin(_t * 9.0) * bob if bob > 0.0 else 0.0)
		modulate.a = clampf(minf(ttl, _t * 6.0) / fade, 0.0, 1.0) * (0.9 if bob > 0.0 else 1.0)
		return ttl > 0.0


func _animate_cast(delta: float) -> void:
	var index := _extras.size() - 1
	while index >= 0:
		var extra := _extras[index]
		if not extra.tick(delta):
			extra.queue_free()
			_extras.remove_at(index)
		index -= 1
	_cast_timer -= delta
	if _cast_timer > 0.0 or _extras.size() > 0 or _finishing:
		return
	_cast_timer = randf_range(2.6, 4.2)
	var scene: String = SCENES.pick_random()
	if scene == _last_scene:
		scene = SCENES[(SCENES.find(scene) + 1) % SCENES.size()]
	_last_scene = scene
	_run_scene(scene)


func _spawn_extra(sheet_id: String, size: float, face: float, at: Vector2, clip: String, ttl: float) -> Extra:
	if _extras.size() >= MAX_EXTRAS:
		return null
	var extra := Extra.new()
	if not extra.setup(sheet_id, size, face):
		extra.queue_free()
		return null
	extra.clip = clip
	extra.ttl = ttl
	_cast_root.add_child(extra)
	extra.start(at)
	_extras.append(extra)
	return extra


func _run_scene(scene: String) -> void:
	var rect := Rect2(_bar.position, _bar.size)
	var line := rect.position.y - 6.0
	var lane := rect.position.y - 120.0
	var left := rect.position.x - 80.0
	var right := rect.end.x + 80.0
	match scene:
		"chase":
			for i in 3:
				var extra := _spawn_extra("rat_mad" if i == 1 else "rat_base", 0.62, 1.0, Vector2(_runner.position.x - 160.0 - i * 90.0, line), "run", 3.4)
				if extra != null:
					extra.follow = _runner
					extra.follow_offset = Vector2(-170.0 - i * 90.0, 0.0)
		"pigeon":
			var extra := _spawn_extra("pigeon_bomber", 0.8, 1.0, Vector2(left, rect.position.y - 300.0), "run", 6.0)
			if extra != null:
				extra.vel = Vector2(rect.size.x / 4.5, 0.0)
				extra.bob = 22.0
		"courier":
			var extra := _spawn_extra("courier_rat", 0.74, -1.0, Vector2(right, lane), "run", 3.6)
			if extra != null:
				extra.vel = Vector2(-rect.size.x / 1.9, 0.0)
		"sniper":
			var at := minf(_runner.position.x + 280.0, rect.end.x - 30.0)
			var extra := _spawn_extra("pig_sniper", 0.62, -1.0, Vector2(at, line), "idle", 3.6)
			if extra != null:
				extra.steps = [[0.3, "windup", false], [1.0, "strike", false], [1.6, "hit", false], [2.2, "death", false]]
				_start_act("shoot")
		"parade":
			for pair in [["trash_tank", 0.8, 0.0], ["cash_collector", 0.62, 150.0]]:
				var extra := _spawn_extra(str(pair[0]), float(pair[1]), 1.0, Vector2(left - float(pair[2]), lane), "run", 7.5)
				if extra != null:
					extra.vel = Vector2(rect.size.x / 6.2, 0.0)
		"pirate":
			var extra := _spawn_extra("sea_pirate", 0.9, 1.0, Vector2(rect.position.x + rect.size.x * 0.18, lane), "idle", 3.8)
			if extra != null:
				extra.steps = [[0.4, "taunt", false], [2.6, "idle", false]]
		"chef":
			var extra := _spawn_extra("chef_boss", 0.92, -1.0, Vector2(right, lane), "run", 5.2)
			if extra != null:
				extra.vel = Vector2(-rect.size.x / 4.2, 0.0)


## Фон загрузки: ночное небо с луной и две полосы свалки, которые плывут влево, пока Енот бежит.
class Scenery:
	extends Control
	const LAYERS := [
		{"base": 0.60, "speed": 14.0, "color": Color("#282724"), "seed": 3.0, "height": 120.0},
		{"base": 0.66, "speed": 32.0, "color": Color("#3b3935"), "seed": 11.0, "height": 90.0},
	]
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _init() -> void:
		set_process(true)

	func _hash(n: float) -> float:
		return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)

	## Фон загрузки Астры: кадр «cover», чуть плывёт и притемнён — на нём бежит Енот. Сцена выбирается случайно,
	## подряд одна и та же не выпадает.
	const VARIANTS := {
		"street": "res://assets/ui/loading/bg_street_%s.jpg",
		"camp": "res://assets/ui/camp/bg_%s.jpg",
		"hangar": "res://assets/ui/loading/bg_hangar_%s.jpg",
		"briefing": "res://assets/ui/loading/bg_briefing_%s.jpg",
	}
	static var _last_variant := ""
	var _bg: Texture2D

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if _bg == null:
			# Каждый раз новая сцена: улица баров, лагерь старьёвщиков, ангар базы, штаб отряда (арт Астры).
			var paths: Array[String] = []
			for id: String in VARIANTS:
				var path := str(VARIANTS[id]) % ("portrait" if h > w else "landscape")
				if ResourceLoader.exists(path) and id != _last_variant:
					paths.append(path)
			if not paths.is_empty():
				var pick := paths.pick_random() as String
				_last_variant = str(VARIANTS.find_key(pick.replace("portrait", "%s").replace("landscape", "%s")))
				_bg = load(pick)
		if _bg != null:
			var k := maxf(w / _bg.get_width(), h / _bg.get_height()) * 1.06
			var shown := _bg.get_size() * k
			var drift := sin(_t * 0.15) * (shown.x - w) * 0.45
			draw_texture_rect(_bg, Rect2(Vector2((w - shown.x) * 0.5 + drift, (h - shown.y) * 0.5), shown), false, Color(0.62, 0.6, 0.66))
			draw_rect(Rect2(0, h * 0.66, w, h * 0.34), Color("#1d1b1a", 0.45))
			return
		draw_rect(Rect2(0, 0, w, h * 0.45), Color("#23221f"))
		draw_rect(Rect2(0, h * 0.45, w, h * 0.2), Color("#32302d"))
		for i in 26:
			var sx := _hash(float(i) * 1.7) * w
			var sy := _hash(float(i) * 3.1) * h * 0.4
			var tw := 0.35 + 0.35 * sin(_t * (1.2 + _hash(float(i)) * 2.0) + float(i))
			draw_circle(Vector2(sx, sy), 1.6, Color(1, 1, 1, tw))
		var moon := Vector2(w * 0.8, h * 0.12)
		for k in 4:
			draw_circle(moon, 70.0 - k * 14.0, Color("#ffb347", 0.04 + 0.03 * k))
		draw_circle(moon, 34.0, Color("#ffe9b8", 0.9))
		draw_circle(moon + Vector2(10, -6), 30.0, Color("#23221f", 0.35))
		for layer: Dictionary in LAYERS:
			var base: float = h * float(layer["base"])
			var spd: float = float(layer["speed"])
			var seed_v: float = float(layer["seed"])
			var tall: float = float(layer["height"])
			var col: Color = layer["color"]
			var shift := fposmod(_t * spd, 160.0)
			var x := -shift - 160.0
			while x < w + 160.0:
				var idx := floorf((x + _t * spd) / 160.0)
				var r := _hash(idx + seed_v)
				var bw := 70.0 + 90.0 * _hash(idx * 1.3 + seed_v)
				var bh := tall * (0.35 + 0.65 * r)
				draw_rect(Rect2(x, base - bh, bw, h - base + bh), col)
				if r > 0.55:
					draw_circle(Vector2(x + bw * 0.5, base - bh), bw * 0.32, col)
				elif r < 0.25:
					draw_rect(Rect2(x + bw * 0.2, base - bh - 26.0, 8.0, 26.0), col)
				x += 160.0
		draw_rect(Rect2(0, h * 0.66, w, h * 0.34), Color("#1d1b1a", 0.55))
