#!/usr/bin/env python3
"""Add an isolated, reproducible material control to a staged plaza project."""
import argparse
from pathlib import Path

SCRIPT='''extends Node3D
var lamp: MeshInstance3D
var stone: MeshInstance3D
var items: Array[MeshInstance3D] = []

func part(file: String, anchor: Vector2, at: Vector3) -> MeshInstance3D:
\tvar tex := load("res://prototypes/hd2d/props/" + file + ".png") as Texture2D
\tvar material := StandardMaterial3D.new()
\tmaterial.albedo_texture = tex
\tmaterial.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
\tmaterial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
\tmaterial.alpha_scissor_threshold = .5
\tmaterial.cull_mode = BaseMaterial3D.CULL_DISABLED
\tmaterial.roughness = .85
\tvar quad := QuadMesh.new()
\tquad.size = tex.get_size() / 96.0
\tvar mesh := MeshInstance3D.new()
\tmesh.mesh = quad
\tmesh.material_override = material
\tmesh.position = at + Vector3(tex.get_width()*.5-anchor.x,anchor.y-tex.get_height()*.5,0)/96.0
\tadd_child(mesh)
\titems.append(mesh)
\treturn mesh

func capture(file: String) -> void:
\tawait get_tree().process_frame
\tawait get_tree().process_frame
\tawait RenderingServer.frame_post_draw
\tget_viewport().get_texture().get_image().save_png("res://"+file+".png")

func _ready() -> void:
\tvar environment := Environment.new()
\tenvironment.background_mode = Environment.BG_COLOR
\tenvironment.background_color = Color(.045,.045,.045)
\tenvironment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
\tenvironment.ambient_light_color = Color.WHITE
\tenvironment.ambient_light_energy = .4
\tvar world := WorldEnvironment.new()
\tworld.environment = environment
\tadd_child(world)
\tvar sun := DirectionalLight3D.new()
\tsun.rotation_degrees = Vector3(-35,-30,0)
\tsun.light_energy = .8
\tadd_child(sun)
\tstone = part("bank_pedestal",Vector2(96,174),Vector3(-1.3,0,0))
\tlamp = part("bank_lantern",Vector2(64,182),Vector3(-1.3,148.0/96,.005))
\tpart("bank_flower_planter",Vector2(104,206),Vector3(1.25,0,0))
\tvar sm := stone.material_override as StandardMaterial3D
\tsm.normal_texture = load("res://prototypes/hd2d/props/bank_pedestal_n.png")
\tsm.normal_scale = .45
\tvar lm := lamp.material_override as StandardMaterial3D
\tlm.emission_texture = load("res://prototypes/hd2d/props/bank_lantern_glow.png")
\tlm.emission = Color("#ffc574")
\tlm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
\tlm.emission_energy_multiplier = .45
\tvar camera := Camera3D.new()
\tcamera.projection = Camera3D.PROJECTION_ORTHOGONAL
\tcamera.size = 4.1
\tcamera.position = Vector3(0,1.72,9)
\tadd_child(camera)
\tcamera.look_at(Vector3(0,1.72,0))
\tcamera.current = true
\tawait capture("props96_base")
\tsm.normal_enabled = true
\tawait capture("props96_normal")
\tsm.normal_enabled = false
\tlm.emission_enabled = true
\tawait capture("props96_emission")
\t# Rasterize exactly the same mask projection; no lighting, post or AA.
\tfor item in items:
\t\tvar mask := ShaderMaterial.new()
\t\tvar shader := Shader.new()
\t\tshader.code = "shader_type spatial; render_mode unshaded,cull_disabled; uniform sampler2D a:filter_nearest; uniform sampler2D g:filter_nearest; uniform bool show_glass=false; void fragment(){ ALBEDO=vec3(show_glass && texture(g,UV).r>.01 ? 1.0 : 0.0); ALPHA=texture(a,UV).a; ALPHA_SCISSOR_THRESHOLD=.5; }"
\t\tmask.shader = shader
\t\tmask.set_shader_parameter("a",(item.material_override as StandardMaterial3D).albedo_texture)
\t\tmask.set_shader_parameter("g",lm.emission_texture)
\t\tmask.set_shader_parameter("show_glass",item==lamp)
\t\titem.material_override = mask
\tenvironment.background_color = Color.BLACK
\tawait capture("props96_glass_projection")
\tprint("PROPS96_MATERIAL_RENDER_OK")
\tget_tree().quit()
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('project',type=Path)
    args=parser.parse_args()
    (args.project/'props_review.gd').write_text(SCRIPT)
    (args.project/'props_review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://props_review.gd" id="1"]
[node name="MaterialReview" type="Node3D"]
script = ExtResource("1")
''')
    print('PROPS96_MATERIAL_STAGED')


if __name__=='__main__':main()
