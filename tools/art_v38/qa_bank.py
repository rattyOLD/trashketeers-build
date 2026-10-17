#!/usr/bin/env python3
"""Load the actual GLB in a disposable Godot project; keep the game unchanged."""
import argparse
import shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SCRIPT='''extends Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var world: WorldEnvironment
var mats: Array[StandardMaterial3D] = []
var lamps: Array[OmniLight3D] = []

func collect(node: Node) -> void:
\tif node is MeshInstance3D:
\t\tfor i in node.mesh.get_surface_count():
\t\t\tvar m := node.get_active_material(i).duplicate() as StandardMaterial3D
\t\t\tnode.set_surface_override_material(i,m)
\t\t\tm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
\t\t\tif "Window_Glass" in m.resource_name:
\t\t\t\tm.emission_texture = load("res://bank/bank_glass_glow.png")
\t\t\t\tm.emission = Color("#ffb465")
\t\t\tif "Lantern_Glass" in m.resource_name:
\t\t\t\tm.emission_texture = load("res://bank/bank_trim_glow.png")
\t\t\t\tm.emission = Color("#ffc46d")
\t\t\tm.emission_enabled = false
\t\t\tm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
\t\t\tmats.append(m)
\tfor child in node.get_children():collect(child)

func lighting(evening: bool) -> void:
\tsun.light_energy = .12 if evening else .9
\tworld.environment.ambient_light_energy = .22 if evening else .32
\tfor m in mats:
\t\tif m.emission_texture != null:
\t\t\tm.emission_enabled = evening
\t\t\tm.emission_energy_multiplier = .55
\tfor lamp in lamps:lamp.light_energy = .5 if evening else 0

func capture(name: String) -> void:
\tawait get_tree().process_frame
\tawait get_tree().process_frame
\tawait RenderingServer.frame_post_draw
\tget_viewport().get_texture().get_image().save_png("res://"+name+".png")

func aim(side_deg: float) -> void:
\tvar pitch := deg_to_rad(32.0)
\tvar side := deg_to_rad(side_deg)
\tvar target := Vector3(0,4.75,1.2)
\tcamera.position = target + Vector3(sin(side)*cos(pitch)*28,sin(pitch)*28,cos(side)*cos(pitch)*28)
\tcamera.look_at(target)

func _ready() -> void:
\tvar env := Environment.new()
\tenv.background_mode = Environment.BG_COLOR
\tenv.background_color = Color("#8c9ba5")
\tenv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
\tenv.ambient_light_color = Color("#aab4d0")
\tenv.tonemap_mode = Environment.TONE_MAPPER_FILMIC
\tenv.tonemap_white = 6
\tenv.tonemap_exposure = .8
\tworld = WorldEnvironment.new()
\tworld.environment = env
\tadd_child(world)
\tsun = DirectionalLight3D.new()
\tsun.rotation_degrees = Vector3(-36,-28,0)
\tsun.shadow_enabled = true
\tadd_child(sun)
\tvar bank := (load("res://bank/bank_hall.glb") as PackedScene).instantiate()
\tadd_child(bank)
\tcollect(bank)
\tvar floor_mesh := MeshInstance3D.new()
\tvar plane := PlaneMesh.new()
\tplane.size = Vector2(70,70)
\tfloor_mesh.mesh = plane
\tvar material := StandardMaterial3D.new()
\tmaterial.albedo_texture = load("res://cobble.png")
\tmaterial.uv1_scale = Vector3(35,35,35)
\tmaterial.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
\tfloor_mesh.material_override = material
\tadd_child(floor_mesh)
\tvar rico := Sprite3D.new()
\trico.texture = load("res://raccoon_idle.png")
\trico.pixel_size = 1.0/96
\trico.offset = Vector2(0,96)
\trico.position = Vector3(-4.5,0,6.3)
\trico.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
\trico.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
\trico.shaded = true
\trico.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
\tadd_child(rico)
\tfor x: float in [-2.28,2.28]:
\t\tvar lamp := OmniLight3D.new()
\t\tlamp.position = Vector3(x,3.4,4.9)
\t\tlamp.light_color = Color("#ffb45e")
\t\tlamp.omni_range = 3
\t\tadd_child(lamp)
\t\tlamps.append(lamp)
\tcamera = Camera3D.new()
\tcamera.fov = 30
\tadd_child(camera)
\taim(0)
\tlighting(false)
\tawait capture("bank_godot_day")
\tfor m in mats:m.normal_enabled = false
\tawait capture("bank_godot_day_flat")
\tfor m in mats:m.normal_enabled = m.normal_texture!=null
\taim(24)
\tawait capture("bank_godot_three_quarter")
\taim(0)
\tlighting(true)
\tawait capture("bank_godot_evening")
\tprint("BANK38_GLB_RENDER_OK materials=",mats.size()," cameraFOV30 pitch32 distance28 source unchanged")
\tget_tree().quit()
'''

def main():
    p=argparse.ArgumentParser();p.add_argument('bank',type=Path);p.add_argument('project',type=Path);a=p.parse_args()
    a.project.mkdir(parents=True,exist_ok=True);shutil.copytree(a.bank,a.project/'bank',dirs_exist_ok=True)
    shutil.copy2(ROOT/'astra/inbox/hd2d_test/materials/cobble_gold_01.png',a.project/'cobble.png')
    shutil.copy2(ROOT/'astra/inbox/hd2d_test/chars/raccoon_idle.png',a.project/'raccoon_idle.png')
    (a.project/'project.godot').write_text('''config_version=5
[application]
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    (a.project/'review.gd').write_text(SCRIPT)
    (a.project/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://review.gd" id="1"]
[node name="Review" type="Node3D"]
script = ExtResource("1")
''')
    print('BANK38_GODOT_STAGED',a.project)
if __name__=='__main__':main()
