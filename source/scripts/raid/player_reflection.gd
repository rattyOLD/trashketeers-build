class_name PlayerReflection
extends Sprite2D

const FOOT_LINE := 8.0
const ALPHA := 0.9

var _player: Player


func setup(player: Player, decals: Node2D) -> void:
	_player = player
	flip_v = true
	z_index = -9
	z_as_relative = false
	var mirror := ShaderMaterial.new()
	mirror.shader = load("res://shaders/mirror_reflection.gdshader")
	mirror.set_shader_parameter("strength", 0.2)
	material = mirror
	decals.add_child(self)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var visual := _player.visual
	var tex := visual.get_ghost_texture()
	visible = tex != null and not _player.is_falling
	if not visible:
		return
	texture = tex
	var off := visual.get_ghost_offset()
	scale = visual.get_ghost_scale() * 0.96
	global_position = _player.global_position + Vector2(off.x, FOOT_LINE - off.y)
	modulate.a = ALPHA * (0.4 if _player.is_dead else 1.0)
