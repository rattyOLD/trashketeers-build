class_name LiquidFx
extends Node2D
## Жидкости босса-пивовара: брызги (кадры Астры) и лужи, которые растекаются, блестят и за пару секунд высыхают.
## Лужи рисуются процедурно (LiquidDraw): полупрозрачная гладь с пеной, рябью и бликами, а не плоская картинка.
## Пул фиксированного размера, без аллокаций в бою.

const CAPACITY := 24
const SPLASH_TIME := 0.36
const DRY_FRACTION := 0.72
## Пиво и рвота слегка светятся в карте освещения (как неон/огонь): в тёмной главе жидкость
## остаётся сочной и блестящей, а не бурой. Брызги — короткая вспышка, лужа — источник на время жизни.
const GLOW := [Color(1.0, 0.72, 0.25), Color(0.6, 1.0, 0.25)]
const GLOW_STRENGTH := 0.5
const BASE := "res://assets/vfx/liquid/"
## Цвет глади и пены: пиво — янтарное с белой пеной, рвота — болотная с жёлтыми пузырями.
const BODY := [Color(1.0, 0.7, 0.16), Color(0.6, 0.74, 0.14)]
const FOAM := [Color(1.0, 0.97, 0.88), Color(0.86, 0.88, 0.35)]
const SPREAD_TIME := 0.28

var _sprites: Array[Sprite2D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _kind: PackedInt32Array = PackedInt32Array()
var _next := 0
var _glow: PackedInt32Array = PackedInt32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _seed: PackedInt32Array = PackedInt32Array()
var _clock := 0.0
var _overlay: FxManager.DrawLayer
var _beer_splash: Array[Texture2D] = []
var _vomit_splash: Array[Texture2D] = []
var _foam: Array[Texture2D] = []


func _ready() -> void:
	z_index = -1
	_beer_splash = _slice(BASE + "astra_beer_splash_frames.png")
	_vomit_splash = _slice(BASE + "astra_puke_splash_frames.png")
	for i in 4:
		_foam.append(load(BASE + "beer_foam_%02d.png" % (i + 1)) as Texture2D)
	for i in CAPACITY:
		var sprite := Sprite2D.new()
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
		_age.append(0.0)
		_life.append(0.0)
		_kind.append(0)
		_glow.append(-1)
		_radius.append(0.0)
		_seed.append(0)
	_overlay = FxManager.DrawLayer.new()
	_overlay.painter = _draw_sheen
	add_child(_overlay)
	set_process(false)


## Лист брызг Астры: 4 кадра по 128 px в ряд.
static func _slice(path: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var sheet := load(path) as Texture2D
	if sheet == null:
		return frames
	var cell := sheet.get_height()
	for i in int(sheet.get_width() / cell):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * cell, 0, cell, cell)
		frames.append(atlas)
	return frames


## kind: 0 — пиво, 1 — рвота. life — сколько живёт лужа.
func puddle(at: Vector2, kind: int, radius: float, life: float) -> void:
	_start(at, kind, radius, life, false)


func splash(at: Vector2, kind: int, radius: float) -> void:
	_start(at, kind, radius, SPLASH_TIME, true)


func foam(at: Vector2, radius: float) -> void:
	_start(at, 2, radius, 0.7, true)


func _start(at: Vector2, kind: int, radius: float, life: float, is_splash: bool) -> void:
	var k := _next
	_next = (_next + 1) % CAPACITY
	var sprite := _sprites[k]
	sprite.visible = true
	sprite.position = at
	sprite.rotation = 0.0
	# Брызги стоят вертикально (кадры 128 px); лужу рисует оверлей, спрайт лишь держит место и свет.
	sprite.scale = Vector2.ONE * (radius * 2.0 / 128.0)
	sprite.flip_h = randf() < 0.5
	sprite.offset = Vector2(0, -48.0)
	sprite.modulate = Color.WHITE
	_radius[k] = radius
	_seed[k] = randi() % 997
	_age[k] = 0.0
	_life[k] = life
	_kind[k] = (kind + 2) if is_splash else kind
	if is_splash and kind == 2 and life > SPLASH_TIME:
		_kind[k] = 4
	sprite.texture = _frame_for(k)
	EnvLights.remove(_glow[k])
	_glow[k] = -1
	var tint: Color = GLOW[1 if kind == 1 else 0]
	if is_splash:
		EnvLights.flash(at, tint, radius * 2.2, GLOW_STRENGTH, life)
	else:
		_glow[k] = EnvLights.add(at, tint, radius * 1.8, GLOW_STRENGTH * 0.8, sprite)
	set_process(true)


func _frame_for(k: int) -> Texture2D:
	var t := _age[k] / maxf(_life[k], 0.01)
	var kind := _kind[k]
	if kind == 4:
		return _foam[mini(int(t * _foam.size()), _foam.size() - 1)]
	if kind >= 2:
		var frames := _beer_splash if kind == 2 else _vomit_splash
		return frames[mini(int(t * frames.size()), frames.size() - 1)]
	return null


func _process(delta: float) -> void:
	var active := false
	for k in CAPACITY:
		var sprite := _sprites[k]
		if not sprite.visible:
			continue
		_age[k] += delta
		if _age[k] >= _life[k]:
			sprite.visible = false
			EnvLights.remove(_glow[k])
			_glow[k] = -1
			continue
		active = true
		var t := _age[k] / _life[k]
		sprite.texture = _frame_for(k)
	_clock += delta
	_overlay.queue_redraw()
	if not active:
		set_process(false)


## Лужи: растекаются за SPREAD_TIME, к концу высыхают — тают и чуть сжимаются, без бурой «глины».
func _draw_sheen(canvas: CanvasItem) -> void:
	for k in CAPACITY:
		if not _sprites[k].visible or _kind[k] >= 2:
			continue
		var age := _age[k]
		var dry := clampf((age / maxf(_life[k], 0.01) - DRY_FRACTION) / (1.0 - DRY_FRACTION), 0.0, 1.0)
		var spread := 1.0 - pow(1.0 - clampf(age / SPREAD_TIME, 0.0, 1.0), 3.0)
		var radius := _radius[k] * (0.35 + 0.65 * spread) * (1.0 - 0.18 * dry)
		var kind := _kind[k]
		LiquidDraw.puddle(canvas, _sprites[k].position, radius, BODY[kind], _seed[k], _clock, 1.0 - dry, FOAM[kind], dry < 0.5)
