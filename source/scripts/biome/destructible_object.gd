class_name DestructibleObject
extends StaticBody2D
## Разрушаемый объект арены. Два вида:
##   ART — проп с концепт-листа (data/props.json, блок destructible): целый спрайт → разбитый
##     спрайт-обломки (остаются на полу без коллизии), эффект разрушения по типу (взрыв бочки,
##     искры ЭЛТ, банки, кислота, дерево, торт, монеты, кристаллы, камень);
##   WEAPON_CRATE — ящик с оружием: единственный «интерактивный» объект, поэтому он один светится
##     цветом редкости; падает с неба (сброс) и рисуется процедурно.
## Y-Sort: origin — точка касания пола. Кислотная лужа создаётся в setup(); обломки и искры —
## из общих пулов FxManager (play_break_fx), без эмиттеров на объект: на телефоне десятки
## GPUParticles2D с собственными материалами давали фризы компиляции шейдеров и лишнюю память.
## Коллизии меняются deferred: разрушение происходит внутри попадания пули.

signal destroyed(object: DestructibleObject)
signal landed(object: DestructibleObject)

enum Kind { ART, WEAPON_CRATE }

const CRATE_HP := 60.0
const CRATE_RADIUS := 27.0
const CRATE_NUTS := 3
## Шансы редкости ящика с оружием (редкость решает, какие стволы могут выпасть).
const CRATE_RARITY_ROLL := [["legendary", 0.015], ["epic", 0.08], ["rare", 0.30], ["common", 1.0]]
const CRATE_GREEN := Color("#4f7a3a")
const CRATE_GREEN_LIGHT := Color("#6f9e4f")
const CRATE_METAL := Color("#b8bfcc")
const DROP_GRAVITY := 2600.0
const FLASH_TIME := 0.06
const LINE := Color("#1a0f2a")
const LINE_WIDTH := 3.0
const BLAST_TIME := 0.42
## Эффект разрушения: [цвета обломков, число обломков, цвет искр (прозрачный — без искр), число искр].
const BREAK_FX := {
	"metal": [[Color("#b0443a"), Color("#6a7088"), Color("#3a3f58")], 16, Color("#ffd257"), 8],
	"explode": [[Color("#3b3040"), Color("#c0392b")], 12, Color("#ff9a3a"), 10],
	"sparks": [[Color("#8d8799"), Color("#5e586b")], 10, Color("#7df9ff"), 22],
	"cans": [[Color("#e0403a"), Color("#2e7bd8"), Color("#e8b030")], 12, Color("#ffd257"), 8],
	"toxic": [[Color("#8dff2a"), Color("#4f9a1a")], 16, Color("#b8ff5a"), 8],
	"wood": [[Color("#9a6334"), Color("#c98a4a"), Color("#e8c07a")], 16, Color("#ffd257"), 6],
	"cake": [[Color("#ffb6d0"), Color("#fff2e0"), Color("#e8446a"), Color("#8a4a2a")], 18, Color("#ffd257"), 6],
	"cloth": [[Color("#ff8ab8"), Color("#fff0f6")], 10, Color(0, 0, 0, 0), 0],
	"coins": [[Color("#3f8a3a"), Color("#6fbf5a")], 10, Color("#ffd700"), 18],
	"crystal": [[Color("#ff5cd6"), Color("#ffc0f0"), Color("#b84dff")], 18, Color("#ffc0f0"), 12],
	"stone": [[Color("#e8e0d0"), Color("#c9b98a"), Color("#d6a23a")], 16, Color(0, 0, 0, 0), 0],
	"crate": [[CRATE_GREEN_LIGHT, Color("#9a6334")], 16, Color.WHITE, 16],
}

static var _flash_shader: Shader

var kind: Kind = Kind.ART
var prop_id := ""
var hp := 1.0
var max_hp := 1.0
var nut_reward := 0
## Редкость содержимого ящика с оружием: "common" | "rare" | "epic" | "legendary".
var loot_rarity := "common"
## Высота падения ящика со сбросом (0 — стоит на земле).
var drop_height := 0.0

var _def: Dictionary = {}
var _destruct: Dictionary = {}
var _drop_speed := 0.0
var _collision: CollisionShape2D
var _flash_material: ShaderMaterial
var _flash_left := 0.0
var _time := 0.0
var _sprite: Sprite2D
var _blast: Sprite2D
var _blast_left := 0.0
var _acid: AcidPool
var _shake := 0.0
var _fx: FxManager
var _spark_left := 0.0
var _spark_cd := 0.0


## Форма коллизии объекта и её центр относительно origin (генератор проверяет наложения).
static func shape_for(object_kind: Kind, prop: String) -> Shape2D:
	if object_kind == Kind.WEAPON_CRATE:
		var circle := CircleShape2D.new()
		circle.radius = CRATE_RADIUS
		return circle
	return ArenaProp.make_shape(prop)


static func offset_for(object_kind: Kind, prop: String) -> Vector2:
	if object_kind == Kind.WEAPON_CRATE:
		return Vector2(0, -CRATE_RADIUS * 0.4)
	return ArenaProp.shape_offset(prop)


func setup_crate() -> void:
	kind = Kind.WEAPON_CRATE
	prop_id = ""
	max_hp = CRATE_HP
	hp = CRATE_HP
	nut_reward = CRATE_NUTS
	loot_rarity = roll_crate_rarity()
	_common_setup()
	set_process(true)


func setup_art(prop: String, decals_layer: Node2D) -> void:
	kind = Kind.ART
	prop_id = prop
	_def = ArenaProp.get_def(prop)
	_destruct = _def.get("destructible", {})
	max_hp = float(_destruct.get("hp", 40.0))
	hp = max_hp
	nut_reward = int(_destruct.get("reward", 2))
	_common_setup()
	_sprite = ArenaProp.make_sprite(str(_def.get("texture", "")), float(_def.get("width", 0.0)))
	if _def.get("flip", false):
		_sprite.flip_h = randf() < 0.5
	_sprite.material = _flash_material
	add_child(_sprite)
	if _def.has("light") and SaveService.are_prop_lights_enabled():
		var light_cfg: Dictionary = _def["light"]
		var glow := PointLight2D.new()
		glow.texture = NeonSign.get_light_texture()
		glow.texture_scale = float(light_cfg.get("radius", 120.0)) / 64.0
		glow.color = Color(str(light_cfg.get("color", "#ffffff")))
		glow.energy = float(light_cfg.get("energy", 0.3))
		glow.range_item_cull_mask = BiomeLayers.LIGHT_MASK_FLOOR
		glow.position = Vector2(0, 10)
		glow.name = &"Glow"
		add_child(glow)
	if str(_destruct.get("effect", "")) == "toxic":
		_acid = AcidPool.new()
		decals_layer.add_child(_acid)
	set_process(false)


func _common_setup() -> void:
	collision_layer = PhysicsLayers.OBSTACLE
	collision_mask = 0
	_collision = CollisionShape2D.new()
	_collision.shape = shape_for(kind, prop_id)
	_collision.position = offset_for(kind, prop_id)
	add_child(_collision)
	if _flash_shader == null:
		_flash_shader = load("res://shaders/flash.gdshader")
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = _flash_shader
	if kind == Kind.WEAPON_CRATE:
		material = _flash_material
	_time = randf() * TAU


static func roll_crate_rarity() -> String:
	var roll := randf()
	for entry in CRATE_RARITY_ROLL:
		if roll < float(entry[1]):
			return entry[0]
	return "common"


## Повторное использование ящика для сброса с неба: объект создан заранее при постройке
## уровня и просто возвращается в строй — в бою ничего не инстанцируется.
func respawn(at: Vector2, from_height: float) -> void:
	global_position = at
	hp = CRATE_HP
	loot_rarity = roll_crate_rarity()
	drop_height = from_height
	_drop_speed = 0.0
	visible = true
	collision_layer = 0 if from_height > 0.0 else PhysicsLayers.OBSTACLE
	_collision.set_deferred("disabled", from_height > 0.0)
	set_process(true)
	queue_redraw()


## Тип реакции для цепных взрывов: "explode" (огонь) или "toxic" (яд); иначе пусто.
func chain_kind() -> String:
	if kind != Kind.ART or hp <= 0.0:
		return ""
	var effect := str(_destruct.get("effect", ""))
	return effect if effect == "explode" or effect == "toxic" else ""


func is_intact() -> bool:
	return hp > 0.0 and drop_height <= 0.0


func is_targetable() -> bool:
	return is_intact()


func get_sound() -> StringName:
	if kind == Kind.WEAPON_CRATE:
		return &"crate_break"
	return StringName(str(_destruct.get("sound", "obstacle_break")))


func take_damage(amount: float, _direction: Vector2 = Vector2.ZERO, _is_crit: bool = false) -> void:
	if hp <= 0.0 or drop_height > 0.0:
		return
	hp -= amount
	_flash_left = FLASH_TIME
	_shake = 1.0
	_flash_material.set_shader_parameter(&"flash_amount", 0.85)
	set_process(true)
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	hp = 0.0
	collision_layer = 0
	_collision.set_deferred("disabled", true)
	if _acid != null:
		_acid.activate(global_position + Vector2(0, -6))
	if kind == Kind.ART:
		_break_art()
	destroyed.emit(self)
	queue_redraw()


func _break_art() -> void:
	var broken := str(_destruct.get("broken", ""))
	var glow := get_node_or_null(^"Glow")
	if glow != null:
		glow.visible = false
	if broken.is_empty():
		_sprite.visible = false
	else:
		var flip := _sprite.flip_h
		var fresh := ArenaProp.make_sprite(broken, float(_destruct.get("broken_width", 100.0)))
		_sprite.texture = fresh.texture
		_sprite.scale = fresh.scale
		_sprite.offset = fresh.offset
		_sprite.flip_h = flip
		fresh.free()
		_sprite.z_index = -1
	if _destruct.get("effect", "") == "explode":
		var cfg: Array = _destruct.get("explode", [120, 50])
		BulletPool.explode(global_position + Vector2(0, -20), float(cfg[0]), float(cfg[1]), Bullet.Team.PLAYER, Color("#ff8a2a"), 1.3)
		var blast_path := str(_destruct.get("blast", ""))
		if not blast_path.is_empty():
			_blast = ArenaProp.make_sprite(blast_path, float(cfg[0]) * 1.6)
			_blast.offset.y *= 0.55
			add_child(_blast)
			_blast_left = BLAST_TIME
	if str(_destruct.get("effect", "")) == "sparks":
		_spark_left = 25.0
		_spark_cd = randf_range(0.6, 1.5)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if drop_height > 0.0:
		_drop_speed += DROP_GRAVITY * delta
		drop_height = maxf(drop_height - _drop_speed * delta, 0.0)
		queue_redraw()
		if drop_height <= 0.0:
			collision_layer = PhysicsLayers.OBSTACLE
			_collision.set_deferred("disabled", false)
			landed.emit(self)
		return
	var busy := false
	if _flash_left > 0.0:
		_flash_left -= delta
		busy = true
		if _flash_left <= 0.0:
			_flash_material.set_shader_parameter(&"flash_amount", 0.0)
	if _sprite != null and _shake > 0.0:
		_shake = maxf(_shake - delta * 9.0, 0.0)
		_sprite.position = Vector2(sin(_time * 90.0) * 3.0 * _shake, 0.0)
		_sprite.scale.y = _sprite.scale.x * (1.0 - 0.06 * _shake)
		busy = true
	if _blast != null and _blast_left > 0.0:
		_blast_left -= delta
		var t := 1.0 - _blast_left / BLAST_TIME
		_blast.modulate.a = clampf(1.4 - t * 1.4, 0.0, 1.0)
		var base := _blast.scale.x
		_blast.scale = Vector2.ONE * base * (1.0 + delta * 1.2)
		if _blast_left <= 0.0:
			_blast.visible = false
		busy = true
	if _spark_left > 0.0 and _fx != null:
		_spark_left -= delta
		_spark_cd -= delta
		if _spark_cd <= 0.0:
			_spark_cd = randf_range(1.2, 3.0)
			_fx.burst(global_position + Vector2(0, -34), Color("#7df9ff"), 4, 130.0, 2.5)
		busy = true
	if kind == Kind.WEAPON_CRATE and hp > 0.0:
		queue_redraw()
		busy = true
	if not busy:
		set_process(false)


# --- Эффекты разрушения ------------------------------------------------------------------------

func play_break_fx(fx: FxManager) -> void:
	_fx = fx
	var effect := "crate" if kind == Kind.WEAPON_CRATE else str(_destruct.get("effect", "metal"))
	var cfg: Array = BREAK_FX.get(effect, BREAK_FX["metal"])
	var height := 26.0 if kind == Kind.WEAPON_CRATE else ArenaProp.visual_size(prop_id).y * 0.45
	var at := global_position + Vector2(0, -height)
	var colors: Array = cfg[0]
	var per_color := maxi(int(cfg[1]) / colors.size(), 2)
	for color in colors:
		fx.chunks(at, color, per_color, 300.0, 5.0)
	var spark: Color = cfg[2]
	if int(cfg[3]) > 0 and spark.a > 0.0:
		fx.burst(at, spark, int(cfg[3]), 340.0, 3.5)
	fx.dust(global_position, 5, 50.0)


# --- Ящик с оружием (процедурный: он и должен выглядеть интерактивно) ---------------------------

func _draw() -> void:
	if kind != Kind.WEAPON_CRATE:
		return
	var shadow_scale := 1.0 - clampf(drop_height / 900.0, 0.0, 0.7)
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.34) * shadow_scale)
	draw_circle(Vector2.ZERO, CRATE_RADIUS * 1.3, Color(0, 0, 0, 0.38))
	draw_set_transform(Vector2(0, -drop_height), 0.0, Vector2.ONE)
	if hp > 0.0:
		_draw_crate()
	else:
		for p in [Vector2(-18, -6), Vector2(12, -4), Vector2(-2, -14)]:
			_outlined_rect(Rect2(p - Vector2(12, 3), Vector2(24, 6)), CRATE_GREEN.darkened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func get_rarity_color() -> Color:
	return WeaponData.RARITY_COLORS.get(loot_rarity, Color.WHITE)


## Военный ящик в ¾: крышка светлее, доски на боку, металлические уголки,
## светящаяся полоса цвета редкости и трафарет ствола.
func _draw_crate() -> void:
	var glow := get_rarity_color()
	var pulse := 0.6 + 0.4 * sin(_time * 4.0)
	draw_set_transform(Vector2(0, -drop_height - 4), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 44.0, Color(glow, 0.12 * pulse))
	draw_set_transform(Vector2(0, -drop_height), 0.0, Vector2.ONE)
	var front := Rect2(-30, -30, 60, 30)
	var top := PackedVector2Array([Vector2(-30, -30), Vector2(30, -30), Vector2(24, -48), Vector2(-24, -48)])
	var top_outline := Geometry2D.offset_polygon(top, LINE_WIDTH, Geometry2D.JOIN_MITER)
	if not top_outline.is_empty():
		draw_colored_polygon(top_outline[0], LINE)
	_outlined_rect(front, CRATE_GREEN)
	draw_colored_polygon(top, CRATE_GREEN_LIGHT)
	for x in [-10.0, 10.0]:
		draw_line(Vector2(x, -30), Vector2(x, 0), CRATE_GREEN.darkened(0.3), 2.0)
	draw_rect(Rect2(-30, -19, 60, 7), Color(glow, 0.55 + 0.45 * pulse))
	for corner in [Vector2(-30, -30), Vector2(24, -30), Vector2(-30, -6), Vector2(24, -6)]:
		draw_rect(Rect2(corner, Vector2(6, 6)), CRATE_METAL)
	WeaponIcons.draw(self, &"rifle", Vector2(0, -39) + Vector2(0, -drop_height), 0.42, 0.0, glow)
	draw_set_transform(Vector2(0, -drop_height), 0.0, Vector2.ONE)
	if drop_height > 0.0:
		draw_line(Vector2(-18, -52), Vector2(-40, -120), Color(1, 1, 1, 0.5), 2.0)
		draw_line(Vector2(18, -52), Vector2(40, -120), Color(1, 1, 1, 0.5), 2.0)
		draw_circle(Vector2(0, -130), 46.0, Color(glow, 0.35))
		draw_arc(Vector2(0, -130), 46.0, PI, TAU, 24, LINE, 4.0, true)


func _outlined_rect(rect: Rect2, fill: Color) -> void:
	draw_rect(rect.grow(LINE_WIDTH), LINE)
	draw_rect(rect, fill)
