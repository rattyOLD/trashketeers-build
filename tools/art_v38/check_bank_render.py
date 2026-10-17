#!/usr/bin/env python3
"""Check final actual-GLB captures and record the precise local QA limits."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

def main():
    p=argparse.ArgumentParser();p.add_argument('project',type=Path);p.add_argument('out',type=Path);a=p.parse_args()
    log=(a.project/'render.log').read_text();assert 'BANK38_GLB_RENDER_OK materials=11' in log
    assert 'ERROR:' not in log and 'SCRIPT ERROR' not in log,log
    frames={};hashes={}
    for name in ['day','day_flat','three_quarter','evening']:
        f=a.project/f'bank_godot_{name}.png';im=Image.open(f).convert('RGB');assert im.size==(1920,1080)
        frames[name]=np.array(im).astype(np.int16);hashes[f.name]=hashlib.sha256(f.read_bytes()).hexdigest()
    diff=abs(frames['day']-frames['day_flat']).max(axis=2);changed=int((diff>1).sum());assert changed>500
    night=abs(frames['day']-frames['evening']).max(axis=2);assert int((night>8).sum())>50000
    assert np.std(frames['day'])>25,'Empty/flat render'
    result={'ok':True,'glb_sha256':hashlib.sha256((a.project/'bank/bank_hall.glb').read_bytes()).hexdigest(),
        'godot':'4.4.1.stable.official.49a5bc7b6','renderer':'Compatibility / Mesa llvmpipe software OpenGL4.5',
        'actual_glb_loaded':True,'external_png_loaded':True,'source_modified':False,
        'scene_script_errors':False,'camera':{'fov_vertical':30,'pitch_down':32,'distance_m':28,'resolution':[1920,1080]},
        'normal_comparison':{'pixels_delta_above1':changed,'max_channel_delta':int(diff.max())},
        'screenshots_sha256':hashes,'artistic_approval':False,
        'limits':['Standalone bank inspection with accepted Riko and paving, not the complete Bank plaza or gameplay.',
            'No physical device/performance test; preview uses software OpenGL.',
            'Editor initialization reports unavailable local Vulkan surface in this environment; runtime Compatibility scene completes without scene/resource errors.',
            'System V-Sync warning; no physical camera DOF or atmosphere tuning claimed.']}
    a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print('BANK38_RENDER_CHECK_OK',changed,int(diff.max()))
if __name__=='__main__':main()
