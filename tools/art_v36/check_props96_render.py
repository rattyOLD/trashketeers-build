#!/usr/bin/env python3
"""Validate isolated emission/normal captures; independent of the asset generator."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('project',type=Path)
    args=parser.parse_args()
    root=args.project
    log=(root/'props_render.log').read_text()
    assert 'PROPS96_MATERIAL_RENDER_OK' in log and 'ERROR:' not in log
    frames={};hashes={}
    for name in ('base','emission','normal','glass_projection'):
        p=root/f'props96_{name}.png'
        image=Image.open(p).convert('RGB')
        assert image.size==(1280,720)
        frames[name]=np.array(image).astype(np.int16)
        hashes[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
    glass=frames['glass_projection'][:,:,0]>128
    emission=np.max(abs(frames['emission']-frames['base']),axis=2)>1
    normal=np.max(abs(frames['normal']-frames['base']),axis=2)>1
    count=int(emission.sum());outside=int(np.count_nonzero(emission&~glass));relief=int(normal.sum())
    assert count>100 and outside==0,(count,outside)
    assert relief>1000,relief
    report={'ok':True,'godot':'4.4.1.stable.official.49a5bc7b6',
        'renderer':'Compatibility / llvmpipe OpenGL4.5',
        'emission_changed_pixels':count,'emission_changed_outside_projected_glass':outside,
        'glass_projection_pixels':int(glass.sum()),'normal_changed_pixels':relief,
        'emission_operator':'multiply','emission_energy':.45,'normal_scale':.45,
        'scope':'isolated material validation, plus separate actual plaza day/evening captures',
        'screenshots_sha256':hashes,'source_modified':False,'owner_visual_approved':False,
        'limitations':['Static sample only; actual plaza retains old48px/m materials and temporary facades',
            'No new animations, mobs or physical-device/gameplay test',
            'System V-Sync warning; no scene/script errors']}
    (root/'props_render_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('PROPS96_RENDER_CHECK_OK',count,'emission pixels;',outside,'outside glass;',relief,'normal pixels')


if __name__=='__main__':main()
