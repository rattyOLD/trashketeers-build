class_name EnemyParts
extends Node2D
## Составные части врага поверх основного спрайта (enemies.json → parts): базука Короля Хлама,
## пилот и стволы меха Магната. Узел — ребёнок RigSprite, поэтому координаты частей — пиксели
## основной текстуры относительно опоры рига, и они повторяют разворот, приседание и тряску тела.
## Прицельные части (aim) поворачиваются к цели в локальных координатах тела (учитывая зеркало),
## отдача (kick) отводит часть назад по стволу. У каждой части свой материал rig2d (без костей):
## вспышка попадания, обводка и свет окружения — как у тела.

const KICK_TIME := 0.12
const SHADER_PATH := "res://shaders/rig2d.gdshader"

var _sprites: Array[Sprite2D] = []
var _materials: Array[ShaderMaterial] = []
var _base: PackedVector2Array = PackedVector2Array()
var _muzzle: PackedVector2Array = PackedVector2Array()
var _aim: Array[bool] = []
var _bob: PackedFloat32Array = PackedFloat32Array()
var _kick: PackedFloat32Array = PackedFloat32Array()
var _flip: Array[bool] = []
var _time := 0.0


func setup(defs: Array) -> void:
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	_materials.clear()
	_base.clear()
	_muzzle.clear()
	_aim.clear()
	_bob.clear()
	_kick.clear()
	_flip.clear()
	for raw in defs:
		var d: Dictionary = raw
		var tex := ArenaProp.texture_of(str(d.get("texture", "")))
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		var pivot := _vec(d.get("pivot", [tex.get_width() * 0.5, tex.get_height() * 0.5]))
		var flip := bool(d.get("flip", false))
		sprite.flip_h = flip
		sprite.offset = -Vector2(tex.get_width() - pivot.x if flip else pivot.x, pivot.y)
		sprite.scale = Vector2.ONE * float(d.get("scale", 1.0))
		sprite.z_index = int(d.get("z", 1))
		var material := ShaderMaterial.new()
		material.shader = load(SHADER_PATH)
		material.set_shader_parameter("rig_enabled", false)
		sprite.material = material
		var at := _vec(d.get("pos", [0, 0]))
		sprite.position = at
		add_child(sprite)
		var m := _vec(d.get("muzzle", [tex.get_width(), tex.get_height() * 0.5]))
		var local_muzzle := Vector2((pivot.x - m.x) if flip else (m.x - pivot.x), m.y - pivot.y)
		_sprites.append(sprite)
		_materials.append(material)
		_base.append(at)
		_muzzle.append(local_muzzle)
		_aim.append(bool(d.get("aim", false)))
		_bob.append(float(d.get("bob", 0.0)))
		_kick.append(0.0)
		_flip.append(flip)


func count() -> int:
	return _sprites.size()


func set_param(param: StringName, value: Variant) -> void:
	for m in _materials:
		m.set_shader_parameter(param, value)


## Прицел всех наводимых частей на точку мира.
func aim(world_target: Vector2) -> void:
	for i in _sprites.size():
		if not _aim[i]:
			continue
		var s := _sprites[i]
		var to := to_local(world_target) - _base[i]
		if to.length_squared() < 1.0:
			continue
		s.rotation = clampf(wrapf(to.angle(), -PI, PI), -1.3, 1.3)


func kick(index: int) -> void:
	if index >= 0 and index < _kick.size():
		_kick[index] = KICK_TIME


## Дуло части в координатах мира.
func muzzle(index: int) -> Vector2:
	if index < 0 or index >= _sprites.size():
		return global_position
	var s := _sprites[index]
	return s.global_transform * _muzzle[index]


func tick(delta: float) -> void:
	_time += delta
	for i in _sprites.size():
		var s := _sprites[i]
		var offset := Vector2(0, sin(_time * 3.2 + i) * _bob[i])
		if _kick[i] > 0.0:
			_kick[i] = maxf(_kick[i] - delta, 0.0)
			var k := _kick[i] / KICK_TIME
			offset += Vector2.from_angle(s.rotation) * -14.0 * k
		s.position = _base[i] + offset


static func _vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO
