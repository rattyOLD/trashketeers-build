#!/usr/bin/env python3
"""Stage the CURRENT Bank plaza and two scale-matched characters. No source edits."""
import argparse,hashlib,json,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SCRIPT='''extends "res://prototypes/hd2d/plaza.gd"
var guard: Node3D
var guard_body: MeshInstance3D
var guard_material: StandardMaterial3D

func _build_mobs() -> void:
\tguard = Node3D.new()
\tguard.position = Vector3(1.15,0,4)
\tadd_child(guard)
\tvar pivot := Node3D.new()
\tpivot.rotation_degrees.x = SPRITE_TILT
\tguard.add_child(pivot)
\tguard_material = StandardMaterial3D.new()
\tguard_material.albedo_texture = load("res://prototypes/hd2d/chars/pig_guard_idle.png")
\tguard_material.normal_texture = load("res://prototypes/hd2d/chars/pig_guard_idle_n.png")
\tguard_material.normal_enabled = true
\tguard_material.normal_scale = .25
\tguard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
\tguard_material.alpha_scissor_threshold = .5
\tguard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
\tguard_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
\tguard_material.roughness = .85
\tguard_material.metallic_specular = .15
\tvar quad := QuadMesh.new()
\tquad.size = Vector2(256.0/96,256.0/96)
\tguard_body = MeshInstance3D.new()
\tguard_body.mesh = quad
\tguard_body.material_override = guard_material
\tguard_body.position.y = 96.0/96
\tguard_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
\tpivot.add_child(guard_body)

func capture(name: String) -> void:
\tawait get_tree().process_frame
\tawait get_tree().process_frame
\tawait RenderingServer.frame_post_draw
\tget_viewport().get_texture().get_image().save_png("res://"+name+".png")

func light_mode(evening: bool) -> void:
\tfor node in get_children():
\t\tif node is DirectionalLight3D:node.light_energy = .18 if evening else 1.15
\t\tif node is WorldEnvironment:node.environment.ambient_light_energy = .32 if evening else .42
\t\tif node is OmniLight3D:node.light_energy = .4 if evening else 0

func aim(distance_m: float, target: Vector3) -> void:
\tvar pitch := deg_to_rad(32.0)
\t_camera.fov = 30
\t_camera.position = target + Vector3(0,sin(pitch)*distance_m,cos(pitch)*distance_m)
\t_camera.look_at(target)

func _ready() -> void:
\tsuper._ready()
\tset_process(false)
\t_hero.position = Vector3(-1.15,0,4)
\t# Pair comparisons are sharp: the unmodified plaza remains around them;
\t# shader settings below are QA camera settings, not production changes.
\t_post.set_shader_parameter(&"tilt_blur",0.0)
\t_post.set_shader_parameter(&"glow_strength",0.0)
\tlight_mode(false)
\taim(28,Vector3(0,2.8,0))
\tawait capture("pig_guard_plaza_day")
\taim(9,Vector3(0,.95,4))
\tawait capture("pig_guard_pair_day")
\tguard_material.normal_enabled = false
\tawait capture("pig_guard_pair_day_flat")
\tguard_material.normal_enabled = true
\tguard_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
\tawait capture("pig_guard_pair_no_shadow")
\tguard_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
\tlight_mode(true)
\tawait capture("pig_guard_pair_evening")
\tguard_material.normal_enabled = false
\tawait capture("pig_guard_pair_evening_flat")
\tprint("PIG_GUARD_PLAZA_OK: current plaza; guard175px Riko170px;96px/m;normal.25; source unchanged")
\tget_tree().quit()
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('out',type=Path);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
 assert a.out.resolve()!=ROOT and ROOT not in a.out.resolve().parents
 prototype=ROOT/'source/prototypes/hd2d';shutil.copytree(prototype,a.out/'prototypes/hd2d',dirs_exist_ok=True)
 code=(prototype/'plaza.gd').read_text();paths=set(re.findall(r'res://([^"\n]+\.(?:png|json|gdshader))',code));paths={s for s in paths if '%' not in s}
 for f in ['raccoon_run.png','raccoon_idle.png']:paths.add('assets/heroes/tactical/'+f)
 paths.add('data/frames.json')
 for source in (ROOT/'source/assets/enemies').glob('pig_*.png'):paths.add(str(source.relative_to(ROOT/'source')))
 for relative in sorted(paths):
  src=ROOT/'source'/relative;dest=a.out/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
 for family in ('materials','props'):
  shutil.copytree(ROOT/'astra/inbox/hd2d_test'/family,a.out/'prototypes/hd2d'/family,dirs_exist_ok=True)
 chars=a.out/'prototypes/hd2d/chars';chars.mkdir(parents=True,exist_ok=True)
 for name in ['raccoon_idle.png','raccoon_idle_n.png']:shutil.copy2(ROOT/'astra/inbox/hd2d_test/chars'/name,chars/name)
 for name in ['pig_guard_idle.png','pig_guard_idle_n.png']:shutil.copy2(a.candidate/name,chars/name)
 # Deterministic lossless QA texture import; normal maps are linear RGB data.
 for image in a.out.rglob('*.png'):
  imp=Path(str(image)+'.import');imp.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\nsource_file="res://'+str(image.relative_to(a.out))+'"\n\n[params]\ncompress/mode=0\ndetect_3d/compress_to=0\nroughness/mode=1\nmipmaps/generate=false\ncompress/normal_map='+('1' if image.stem.endswith('_n') else '0')+'\n')
 (a.out/'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://review.tscn"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
 (a.out/'review.gd').write_text(SCRIPT)
 (a.out/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Review" type="Node3D"]\nscript = ExtResource("1")\n')
 report={'prototype_source_sha256':hashlib.sha256((prototype/'plaza.gd').read_bytes()).hexdigest(),'bank_model_sha256':hashlib.sha256((prototype/'buildings/bank_hall.glb').read_bytes()).hexdigest(),'source_modified':False,'source_branch':'big-build','candidate_files':{n:hashlib.sha256((a.candidate/n).read_bytes()).hexdigest() for n in ['pig_guard_idle.png','pig_guard_idle_n.png']},'camera':{'vertical_fov':30,'pitch_down':32,'overview_distance_m':28,'pair_distance_m':9},'qa_overrides':['One idle guard replaces old mobs; actors frozen','Accepted Riko at same96px/m and same sprite tilt-12deg','Close camera and paired normal/shadow controls; QA blur/glow off','Current developer bank with roof terrace preserved; old shops/fountain remain temporary']}
 (a.out/'staging.json').write_text(json.dumps(report,indent=2)+'\n');print('PIG_GUARD_QA_STAGED',a.out)
if __name__=='__main__':main()
