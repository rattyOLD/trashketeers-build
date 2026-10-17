#!/usr/bin/env python3
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
INBOX=ROOT/'astra/inbox/hd2d_test'


def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')


def info(p,**extra):
    im=Image.open(p)
    return {'file':p.name,'width':im.width,'height':im.height,'format':im.mode,
        'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size,**extra}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('export',type=Path);args=parser.parse_args()
    report=json.loads((args.export/'export.json').read_text());out=INBOX/'props/street96';out.mkdir(exist_ok=True)
    files=[]
    for f in report['files'][:3]:
        p=out/f['file'];shutil.copy2(args.export/p.name,p);size=f['canvas'];anchor=f['anchor_px']
        files.append(info(p,role='vertical_sprite',pixels_per_metre=96,size_m=[v/96 for v in size],
            anchor_px=anchor,anchor_uv=[v/n for v,n in zip(anchor,size)],visible_bounds_px=f['visible_bounds'],
            palette='../../palettes/street96.png',alpha='binary0/255',resampled_from_concept=True,
            tileable_x=f['tileable_x'],ground_cast_shadow_baked=False,local_form_shading_baked=True,
            outline='dark1px; open horizontal rail connections intentionally have no vertical end outline',
            collider_radius_m=.16 if 'umbrella' in p.name else .48 if 'table' in p.name else 1.0))
    files[0].update(normal_map='bank_balustrade_n.png',normal_map_invert_y=False,
        normal_convention='OpenGL +Y',suggested_normal_scale=.35,
        collider_shape='box',collider_size_m=[2,100/96,.20],repeat_step_m=[2,0,0],
        end_pillars_baked=False,connection_rule='abut full192px frames; no padding between copies')
    files[1].update(canopy_width_m=252/96,visible_height_m=250/96,
        collision_when_assembled='disable pole collider, table owns the combined footprint')
    files[2].update(estimated_tabletop_height_m=.8,visible_height_including_bottle_m=92/96)
    p=out/'bank_balustrade_n.png';shutil.copy2(args.export/p.name,p)
    files.append(info(p,role='normal_map',paired_albedo='bank_balustrade.png',pixels_per_metre=96,
        size_m=files[0]['size_m'],anchor_px=files[0]['anchor_px'],anchor_uv=files[0]['anchor_uv'],
        normal_convention='OpenGL +Y',color_space='linear_data',normal_source=report['files'][3]['normal_source']))
    write(out/'manifest.json',{'schema_version':1,'brief':'v36','revision':'street96-control-1',
        'studio':'TrashSquad · Beer Party Studio','pixels_per_metre':96,
        'owner_visual_approved':False,'delivery_status':'review_candidate','files':files,
        'palette':'../../palettes/street96.png','source_pipeline':report['method'],
        'source_image':'../../../../previews/v36/street96_source.png',
        'sprite3d':{'pixel_size':1/96,'centered':True,'alpha_scissor':.5,'filter':'nearest with optional mipmaps',
            'offset_formula':'Vector2(width/2-anchor_x,anchor_y-height/2)'},
        'assembly':{'table_under_umbrella':True,'shared_ground_anchor':True,
            'table_depth_offset_m':.025,'collision_owner':'bank_bistro_table.png'},
        'verification':{'godot_render_verified':False,'report':'VALIDATION.json'}})
    write(out/'PIXEL_EXPORT.json',report)
    p=INBOX/'palettes/street96.png';shutil.copy2(args.export/p.name,p)
    pm=INBOX/'palettes/manifest.json';m=json.loads(pm.read_text());m['files']=[f for f in m['files'] if f['file']!=p.name]
    m['files'].append(info(p,role='street_prop_palette_candidate',colors=128,size_m=None,anchor_px=None,not_a_world_surface=True))
    write(pm,m)
    parent=INBOX/'props/manifest.json';m=json.loads(parent.read_text());m['additional_batches']=['street96/manifest.json'];write(parent,m)
    print('STREET96_PACKAGED')


if __name__=='__main__':main()
