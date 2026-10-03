class_name LiquidFx
extends Node2D
## Жидкости босса-пивовара: брызги (6 кадров), лужи, которые за пару секунд подсыхают и гаснут.
## Пул фиксированного размера, без аллокаций в бою.

const CAPACITY := 24
const SPLASH_FRAMES := 6
const SPLASH_TIME := 0.36
const DRY_FRACTION := 0.72
## Пиво и рвота слегка светятся в карте освещения (как неон/огонь): в тёмной главе жидкость
## остаётся сочной и блестящей, а не бурой. Брызги — короткая вспышка, лужа — источник на время жизни.
const GLOW := [Color(1.0, 0.72, 0.25), Color(0.6, 1.0, 0.25)]
const GLOW_STRENGTH := 0.5
const BASE := "res://assets/vfx/liquid/"

var _sprites: Array[Sprite2D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _kind: PackedInt32Array = PackedInt32Array()
var _next := 0
var _glow: PackedInt32Array = PackedInt32Array()
var _beer_puddles: Array[Texture2D] = []
var _vomit_puddles: Array[Texture2D] = []
var _drying: Array[Texture2D] = []
var _beer_splash: Array[Texture2D] = []
var _vomit_splash: Array[Texture2D] = []
var _foam: Array[Texture2D] = []


func _ready() -> void:
	z_index = -1
	for i in 4:
		_beer_puddles.append(load(BASE + "beer_puddle_%02d.png" % (i + 1)) as Texture2D)
	for i in 3:
		_vomit_puddles.append(load(BASE + "vomit_puddle_%02d.png" % (i + 1)) as Texture2D)
	for i in 2:
		_drying.append(load(BASE + "beer_drying_%02d.png" % (i + 1)) as Texture2D)
	for i in SPLASH_FRAMES:
		_beer_splash.append(load(BASE + "beer_splash_%02d.png" % (i + 1)) as Texture2D)
		_vomit_splash.append(load(BASE + "vomit_splash_%02d.png" % (i + 1)) as Texture2D)
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
	set_process(false)


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
	sprite.rotation = 0.0 if is_splash else randf() * TAU
	sprite.scale = Vector2.ONE * (radius * 2.0 / 160.0)
	sprite.modulate = Color.WHITE
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
		return frames[mini(int(t * SPLASH_FRAMES), SPLASH_FRAMES - 1)]
	if kind == 0:
		if t >= DRY_FRACTION:
			return _drying[0 if t < 0.8 else 1]
		return _beer_puddles[(get_instance_id() + k) % _beer_puddles.size()]
	return _vomit_puddles[k % _vomit_puddles.size()]


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
		if _kind[k] < 2:
			sprite.modulate.a = 1.0 if t < 0.7 else (1.0 - t) / 0.3
	if not active:
		set_process(false)
