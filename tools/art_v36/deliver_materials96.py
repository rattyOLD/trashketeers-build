#!/usr/bin/env python3
"""Deliver only the seven requested 96 px/m families; label legacy files honestly."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
INBOX=ROOT/'astra/inbox/hd2d_test'


def write(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def info(p,**extra):
    im=Image.open(p)
    return {'file':p.name,'width':im.width,'height':im.height,'format':im.mode,
        'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),**extra}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('export',type=Path);args=parser.parse_args()
    export=json.loads((args.export/'export.json').read_text())
    folder=INBOX/'materials';old=json.loads((folder/'manifest.json').read_text())
    families={f['material'] for f in export['files']}
    legacy=[f for f in old['files'] if f['material'] not in families]
    for f in legacy:f.update(pixels_per_metre=48,delivery_status='legacy_48_not_migrated')
    files=[]
    for f in export['files']:
        for filename,role in ((f['file'],'albedo'),(f['normal_map'],'normal')):
            p=folder/filename;shutil.copy2(args.export/filename,p)
            entry=info(p,material=f['material'],variant=f['variant'],role=role,
                pixels_per_metre=96,size_m=[2.,2.],anchor_px=[0,0],anchor_uv=[0.,0.],
                tileable_x=True,tileable_y=True,color_space='sRGB' if role=='albedo' else 'linear_data')
            if role=='albedo':entry.update(palette='../palettes/materials96.png',
                resampled_from_concept=True,normal_map=f['normal_map'],normal_scale=.35,
                roughness=.55 if f['material']=='marble' else .92,metallic=0.,
                ground_cast_shadow_baked=False,directional_light_baked=False)
            else:entry.update(normal_convention='OpenGL +Y',normal_map_invert_y=False,
                normal_source=export['normal_method'])
            files.append(entry)
    write(folder/'manifest.json',{'schema_version':1,'brief':'v36','revision':'seven-materials-96-control-1',
        'studio':'TrashSquad · Beer Party Studio','pixels_per_metre':96,
        'uniform_density':False,'requested_materials':sorted(families),
        'legacy_materials_pending_96':sorted({f['material'] for f in legacy}),
        'palette':'../palettes/materials96.png','color_space':'sRGB',
        'texture_filter':'nearest_with_mipmaps','texture_repeat':'enabled',
        'cast_shadows_baked':False,'directional_light_baked':False,
        'variant_edge_compatibility':'all ordered pairs horizontal/vertical within each family, including normals',
        'normal_convention':'OpenGL +Y, normal_map_invert_y=false; import data linear',
        'source_pipeline':export['source_method'],'owner_visual_approved':False,
        'files':files+legacy})
    p=INBOX/'palettes/materials96.png';shutil.copy2(args.export/p.name,p)
    pm=INBOX/'palettes/manifest.json';m=json.loads(pm.read_text());m['files']=[f for f in m['files'] if f['file']!=p.name]
    m['files'].append(info(p,role='material_palette_candidate',colors=128,size_m=None,
        anchor_px=None,not_a_world_surface=True,provisional_until_visual_review=True))
    m['pending']=['Consolidate authoring palettes to the chapter palette after material/prop review; accepted sprites preserved']
    write(pm,m);write(folder/'PIXEL_EXPORT.json',export)
    print('MATERIALS96_PACKAGED',len(files),'new PNG;',len(legacy),'explicit legacy PNG')


if __name__=='__main__':main()
