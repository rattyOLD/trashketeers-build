#!/usr/bin/env python3
"""Stage a disposable Bank prototype with candidate art; never edit source/."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('destination',type=Path)
    parser.add_argument('--rico-dir',type=Path)
    args=parser.parse_args()
    out=args.destination.resolve()
    assert out!=ROOT and ROOT not in out.parents
    out.mkdir(parents=True,exist_ok=True)
    code=(ROOT/'source/prototypes/hd2d/plaza.gd').read_text()
    props=ROOT/'astra/inbox/hd2d_test/props'
    manifest=json.loads((props/'manifest.json').read_text())
    entries={f['file']:f for f in manifest['files']}
    old={'bank_pedestal':(48,71),'bank_lantern':(36,103),'bank_flower_planter':(48,99)}
    for stem,(x,y) in old.items():
        ax,ay=entries[stem+'.png']['anchor_px']
        code=code.replace(f'"{stem}", Vector2({x}, {y})',f'"{stem}", Vector2({ax}, {ay})')
    mount=entries['bank_pedestal.png']['mount_points']['lantern']['position_m_from_anchor'][1]
    code=re.sub(r'const LANTERN_MOUNT := [\d.]+',f'const LANTERN_MOUNT := {mount:.10f}',code)
    paths=set(re.findall(r'res://([^"\n]+\.(?:png|json|gdshader))',code))
    paths={p for p in paths if '%' not in p}
    for name in ('umbrella','picnic_table','cash_pile','column'):
        paths.add(f'assets/props/ch2/{name}.png')
    for name in ('pig_default','pig_heavy','pig_royal','pig_angry','pig_sniper'):
        paths.add(f'assets/enemies/{name}.png')
    copied=[]
    for path in sorted(paths):
        source=ROOT/'source'/path
        dest=out/path
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,dest)
        copied.append({'file':path,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
    candidates=[]
    for family in ('materials','props'):
        dest=out/'prototypes/hd2d'/family
        dest.mkdir(parents=True,exist_ok=True)
        for source in (ROOT/'astra/inbox/hd2d_test'/family).glob('*.png'):
            shutil.copy2(source,dest/source.name)
            candidates.append({'file':family+'/'+source.name,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
    shutil.copy2(props/'manifest.json',out/'prototypes/hd2d/props/manifest.json')
    rico_source='original source Riko, temporary smooth art; no accepted pixel redraw'
    rico_setup=''
    if args.rico_dir:
        chars=args.rico_dir.resolve()
        character=json.loads((chars/'manifest.json').read_text())
        sprite=next(f for f in character['files'] if f['role']=='character_idle_sprite')
        assert sprite['frame_count']==1
        dest=out/'candidate_chars'
        dest.mkdir(exist_ok=True)
        for entry in character['files']:
            shutil.copy2(chars/entry['file'],dest/entry['file'])
        settings=character['sprite3d']
        rico_source={'manifest':character,'albedo_sha256':hashlib.sha256((chars/sprite['file']).read_bytes()).hexdigest()}
        rico_setup=f'''
func _build_hero() -> void:
\tvar candidate := Sprite3D.new()
\t_hero = candidate
\tcandidate.texture = load("res://candidate_chars/{sprite['file']}")
\tcandidate.pixel_size = {settings['pixel_size']}
\tcandidate.offset = Vector2({settings['offset_px'][0]}, {settings['offset_px'][1]})
\tvar m := StandardMaterial3D.new()
\tm.albedo_texture = candidate.texture
\tm.normal_enabled = true
\tm.normal_texture = load("res://candidate_chars/{sprite['normal_map']}")
\tm.normal_scale = {settings['normal_scale']}
\tm.roughness = {settings['roughness']}
\tm.metallic_specular = {settings['metallic_specular']}
\tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
\tm.alpha_scissor_threshold = .5
\tm.cull_mode = BaseMaterial3D.CULL_DISABLED
\tm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
\tcandidate.material_override = m
\t_style(candidate)
\tcandidate.position = Vector3(-3,0,4)
\tadd_child(candidate)
'''
    (out/'prototypes/hd2d/plaza.gd').write_text(code)
    (out/'project.godot').write_text('''config_version=5
[application]
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    (out/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://review.gd" id="1"]
[node name="Review" type="Node3D"]
script = ExtResource("1")
''')
    (out/'review.gd').write_text('''extends "res://prototypes/hd2d/plaza.gd"

func capture(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://"+name+".png")

func lighting(evening: bool) -> void:
	for node in get_children():
		if node is DirectionalLight3D:
			node.light_energy = .18 if evening else 1.0
		if node is WorldEnvironment:
			node.environment.ambient_light_energy = .32 if evening else .42
			node.environment.ambient_light_color = Color("#8290ac") if evening else Color("#9a8fb8")
			node.environment.fog_light_color = Color("#535b78") if evening else Color("#f2cf9c")
		if node is OmniLight3D:
			node.light_energy = .4 if evening else 0
	for pivot in get_children():
		for lamp in pivot.get_children():
			for mesh in lamp.get_children():
				if mesh is MeshInstance3D:
					var m = mesh.material_override as StandardMaterial3D
					if m != null and m.emission_texture != null:
						m.emission_enabled = evening
						m.emission_energy_multiplier = .45

func _ready() -> void:
	super._ready()
	set_process(false)
	for mob in _mobs:
		mob.node.visible = false
	lighting(false)
	_camera.position = Vector3(0,21,30)
	_camera.look_at(Vector3(0,1,-4))
	_camera.fov = 38
	_post.set_shader_parameter(&"focus_y", .55)
	await capture("plaza_overview_day")
	# Same actual courtyard, closer camera for the control sample, no new set.
	_hero.position = Vector3(-6.8,0,-2.8)
	_camera.position = Vector3(-8.8,8.5,9)
	_camera.look_at(Vector3(-8.8,1.4,-4))
	_camera.fov = 30
	_post.set_shader_parameter(&"focus_y", .5)
	_post.set_shader_parameter(&"focus_half", .31)
	await capture("plaza_sample_day")
	lighting(true)
	await capture("plaza_sample_evening")
	print("V36_PLAZA_REVIEW_OK: actual prototype geometry, candidate art, unchanged source; Riko source recorded in staging.json, mobs hidden")
	get_tree().quit()
''')
    if rico_setup:
        path=out/'review.gd'
        review=path.read_text()
        checks='''
\tvar candidate := _hero as Sprite3D
\tvar material := candidate.material_override as StandardMaterial3D
\tmaterial.normal_enabled = false
\tawait capture("plaza_sample_evening_flat")
\tlighting(false)
\tawait capture("plaza_sample_day_flat")
\tmaterial.normal_enabled = true
\tcandidate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
\tawait capture("plaza_sample_day_no_shadow")
'''
        path.write_text(review.replace('\tget_tree().quit()',checks+'\tget_tree().quit()')+rico_setup)
    (out/'staging.json').write_text(json.dumps({'prototype_source_sha256':hashlib.sha256((ROOT/'source/prototypes/hd2d/plaza.gd').read_bytes()).hexdigest(),
        'source_modified':False,'candidate_revision':manifest['revision'],'copied_assets':copied,
        'candidate_overlays':candidates,'rico_source':rico_source,
        'qa_overrides':['candidate prop anchors and mount','day lamps off; evening Omni .4, emission .45',
                        'overview camera 38deg; closer control camera 30deg',
                        'frozen actors; unfinished mobs hidden',
                        'Riko normal on/off and shadow on/off when --rico-dir provided']},indent=2)+'\n')
    print('V36_PLAZA_STAGED',out)


if __name__=='__main__':main()
