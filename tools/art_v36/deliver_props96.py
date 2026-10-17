#!/usr/bin/env python3
"""Package a 96 px/m concept-cleaned review sample, preserving legacy materials."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
INBOX=ROOT/'astra/inbox/hd2d_test'


def write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def info(path,**extra):
    image=Image.open(path)
    return {'file':path.name,'width':image.width,'height':image.height,'format':image.mode,
        'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**extra}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('export',type=Path)
    args=parser.parse_args()
    source=args.export
    out=INBOX/'props'
    report=json.loads((source/'pixel_validation.json').read_text())
    files=[]
    for name,size,anchor,radius in [('bank_lantern',(128,184),(64,182),.28),
            ('bank_pedestal',(192,176),(96,174),.76),
            ('bank_flower_planter',(208,208),(104,206),.65)]:
        src=source/(name+'.png')
        assert Image.open(src).size==size
        dest=out/src.name
        shutil.copy2(src,dest)
        stat=next(f for f in report['files'] if f['file']==dest.name)
        files.append(info(dest,role='vertical_sprite',size_m=[n/96 for n in size],
            anchor_px=list(anchor),anchor_uv=[a/n for a,n in zip(anchor,size)],
            anchor_space='pixel boundaries from top-left',collider_radius_m=radius,
            palette='../palettes/bank96.png',alpha='binary 0/255',
            view='front + top; yaw 0',local_form_shading_baked=True,
            ground_cast_shadow_baked=False,resampled_from_concept=True,
            visible_bounds_px=stat['visible_bounds'],visible_colors=stat['visible_colors'],
            outline='uninterrupted dark colored 1px',source_image='../../../previews/v36/props96_source.png'))
    for name,role,parent in [('bank_lantern_glow','emission_mask',files[0]),('bank_pedestal_n','normal_map',files[1])]:
        dest=out/(name+'.png')
        shutil.copy2(source/dest.name,dest)
        files.append(info(dest,role=role,paired_albedo=parent['file'],size_m=parent['size_m'],
            anchor_px=parent['anchor_px'],anchor_uv=parent['anchor_uv'],color_space='linear_data'))
    files[0].update(glow_mask='bank_lantern_glow.png',light_source_px=[63,101],
        light_source_m_from_anchor=[-1/96,81/96,.2],day_emission_energy=0,
        emission_mask_levels={'0':'iron, roof, mullions, reflection','48':'amber glass','255':'filament'},
        mullion_probe_px={'y_range':[75,117],'x_columns':[54,73]},
        emission_operator='multiply',suggested_emission_color='#ffc574',
        suggested_emission_energy=.45,suggested_light_energy=.4,suggested_light_range_m=5.)
    files[1].update(normal_map='bank_pedestal_n.png',normal_convention='OpenGL +Y',
        normal_map_invert_y=False,suggested_normal_scale=.45,
        normal_source=report['normal_source'],
        mount_points={'lantern':{'anchor_px':[96,26],'position_m_from_anchor':[0,148/96,0]}})
    write(out/'manifest.json',{'schema_version':1,'brief':'v36','revision':'modular-96-control-1',
        'studio':'TrashSquad · Beer Party Studio','delivery_status':'review_candidate',
        'owner_visual_approved':False,'pixels_per_metre':96,'palette':'../palettes/bank96.png',
        'scope':'three props only, not the remaining HD-2D set','files':files,
        'source_pipeline':report['creation_method'],'resampled_from_concept':True,
        'assembly':{'canvas_px':[192,332],'anchor_px':[96,330],
            'visible_height_px':330,'visible_height_m':330/96,
            'collision_owner':'bank_pedestal.png',
            'parts':[{'file':'bank_pedestal.png','top_left_px':[0,156],'position_m':[0,0,0],'collision_enabled':True},
                {'file':'bank_lantern.png','top_left_px':[32,0],'position_m':[0,148/96,0],
                 'collision_enabled':False,'depth_offset_m':.005}],
            'transform_with_common_sprite_plane':True},
        'sprite3d':{'pixel_size':1/96,'centered':True,
            'offset_formula':'Vector2(width/2-anchor_x, anchor_y-height/2)',
            'alpha_scissor':.5,'filter':'nearest with optional mipmaps'},
        'verification':{'godot_render_verified':False,'format_report':'VALIDATION.json'},
        'pending':['Owner visual review','Remaining props, facades, materials192 and character animations']})
    shutil.copy2(source/'bank96.png',INBOX/'palettes/bank96.png')
    palette_manifest=INBOX/'palettes/manifest.json'
    data=json.loads(palette_manifest.read_text())
    data['revision']='96-control-props-and-rico'
    data['files']=[f for f in data['files'] if f['file']!='bank96.png']
    data['files'].append(info(INBOX/'palettes/bank96.png',role='environment_palette_candidate',
        colors=128,size_m=None,anchor_px=None,not_a_world_surface=True,provisional_until_visual_review=True))
    write(palette_manifest,data)
    shutil.copy2(source/'pixel_validation.json',out/'PIXEL_EXPORT.json')
    # A previous 48 px/m render report does not validate these new sprites.
    (out/'RENDER_VALIDATION.json').unlink(missing_ok=True)
    print('PROPS96_PACKAGED')


if __name__=='__main__':main()
