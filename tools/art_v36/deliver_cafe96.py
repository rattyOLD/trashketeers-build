#!/usr/bin/env python3
import argparse,hashlib,json,shutil
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
INBOX=ROOT/'astra/inbox/hd2d_test'


def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')


def info(p,**extra):
    im=Image.open(p)
    return {'file':p.name,'width':im.width,'height':im.height,'format':im.mode,'bytes':p.stat().st_size,
        'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),**extra}


def main():
    p=argparse.ArgumentParser();p.add_argument('cafe',type=Path);p.add_argument('rails',type=Path);a=p.parse_args()
    out=INBOX/'props/street96';m=json.loads((out/'manifest.json').read_text());base=next(f for f in m['files'] if f['file']=='bank_balustrade.png');base['owner_visual_approved']=True
    retained={'bank_balustrade.png','bank_balustrade_n.png','bank_bistro_table.png'}
    files=[f for f in m['files'] if f['file'] in retained]
    cafe=json.loads((a.cafe/'export.json').read_text());rails=json.loads((a.rails/'export.json').read_text())
    for f in cafe['files']:
        dest=out/f['file'];shutil.copy2(a.cafe/f['file'],dest);size=f['canvas'];anchor=f['anchor_px'];overlay=f.get('role')=='assembly_overlay'
        entry=info(dest,role='assembly_overlay' if overlay else 'vertical_sprite',pixels_per_metre=96,
            size_m=[v/96 for v in size],anchor_px=anchor,anchor_uv=[v/n for v,n in zip(anchor,size)],
            palette='../../palettes/street96.png',alpha='binary0/255',resampled_from_concept=True,
            ground_cast_shadow_baked=False,local_form_shading_baked=True,owner_visual_approved=False,
            collider_radius_m=0 if overlay else .16 if 'umbrella' in dest.name else .3 if 'chair' in dest.name else .48)
        if overlay:entry.update(assembly_only=True,cast_shadow=False,collision_enabled=False,clip_rect_px=f['clip_rect_px'])
        else:entry.update(outline='uninterrupted dark1px',visible_bounds_px=f['visible_bounds'])
        if dest.name=='bank_umbrella.png':entry.update(camera_down_angle_deg=35,
            canopy_view='top dome; no exposed underside/ribs',canopy_material_tone_limit=7,
            cluster_cleanup='same-material5x5 medians on canopy, target-grid hard quantization',
            assembled_collision_enabled=False)
        if dest.name=='bank_bistro_table_parasol.png':entry.update(pole_socket_px=cafe['table_socket_px'],
            pole_socket_height_m=cafe['table_socket_height_m'],center_bottle=False,
            estimated_tabletop_height_m=.8,requires_upper_pole_overlay=True)
        files.append(entry)
    for f in rails['variants']:
        for name,role in ((f['file'],'vertical_sprite'),(f['normal_map'],'normal_map')):
            dest=out/name;shutil.copy2(a.rails/name,dest)
            entry=info(dest,role=role,pixels_per_metre=96,size_m=[2.,128/96],anchor_px=[96,126],anchor_uv=[.5,126/128],owner_visual_approved=False)
            if role=='vertical_sprite':entry.update(palette='../../palettes/street96.png',alpha='binary0/255',
                resampled_from_concept=True,ground_cast_shadow_baked=False,local_form_shading_baked=True,
                tileable_x=True,normal_map=f['normal_map'],suggested_normal_scale=.35,normal_map_invert_y=False,
                collider_radius_m=1.,collider_shape='box',collider_size_m=[2,100/96,.2],repeat_step_m=[2,0,0],
                end_pillars_baked=False,damage_changed_pixels=f['changed_pixels'])
            else:entry.update(paired_albedo=f['file'],color_space='linear_data',normal_convention='OpenGL +Y',
                normal_source='accepted form normals plus shallow grooves from transferred fracture masks')
            files.append(entry)
    m.update(revision='street96-control-2',files=files,owner_visual_approved=False,
        accepted_files=['bank_balustrade.png','bank_balustrade_n.png'],
        balustrade_variants=['bank_balustrade.png','bank_balustrade_02.png','bank_balustrade_03.png'],
        source_pipeline=cafe['method'],source_image='../../../../previews/v36/cafe96_source.png',
        assembly={'shared_ground_anchor':True,'common_sprite_plane':True,
            'collision_owners':['bank_bistro_table_parasol.png','bank_chair_left.png','bank_chair_right.png'],
            'parts':[{'file':'bank_umbrella.png','position_m':[0,0,0]},
                {'file':'bank_chair_left.png','position_m':[-65/96,0,.005]},
                {'file':'bank_chair_right.png','position_m':[65/96,0,.005]},
                {'file':'bank_bistro_table_parasol.png','position_m':[0,0,.025]},
                {'file':'bank_umbrella_pole_front.png','position_m':[0,0,.04],'cast_shadow':False,'collision_enabled':False}],
            'note':'Upper pole overlay ends at table socket; table cloth occludes lower pole. Standalone table remains separate.'},
        verification={'godot_render_verified':False,'report':'VALIDATION.json'})
    write(out/'manifest.json',m);write(out/'CAFE_PIXEL_EXPORT.json',cafe);write(out/'RAIL_VARIANTS_EXPORT.json',rails)
    print('CAFE96_AND_RAIL_VARIANTS_PACKAGED')


if __name__=='__main__':main()
