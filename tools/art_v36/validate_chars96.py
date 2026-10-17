#!/usr/bin/env python3
"""Independent character delivery checks: palette, silhouette, anchors and identity."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import label


def validate(chars):
    manifest=json.loads((chars/'manifest.json').read_text())
    palette=Image.open(chars/manifest['palette']).convert('RGB')
    colors=set(palette.getdata())
    assert palette.size==(128,1) and len(colors)==128
    images={}; checked=[]
    for entry in manifest['files']:
        p=chars/entry['file']; raw=p.read_bytes()
        assert hashlib.sha256(raw).hexdigest()==entry['sha256'], p
        im=Image.open(p); im.load()
        assert im.size==(entry['width'],entry['height']), p
        a=np.array(im.convert('RGBA')); images[p.name]=a
        if entry['role']=='normal_map':
            n=a[:,:,:3].astype(float)/255*2-1
            assert np.max(abs(np.linalg.norm(n,axis=2)-1))<.015, p
            assert n[:,:,2].min()>.65, p
        else:
            assert set(np.unique(a[:,:,3]))<={0,255}, p
            mask=a[:,:,3]>0
            assert set(map(tuple,a[:,:,:3][mask]))<=colors, p
            assert mask.sum()>30, p
            if p.name=='raccoon_idle.png':
                _,count=label(mask,np.ones((3,3))); assert count==1
                yy,xx=np.where(mask);assert [xx.min(),yy.min(),xx.max()+1,yy.max()+1]==[29,54,197,224]
        checked.append(p.name)
    idle=images['raccoon_idle.png'];badge=images['raccoon_badge.png']
    x,y=manifest['canonical_badge']['idle_origin_px']; mask=badge[:,:,3]>0
    assert np.array_equal(idle[y:y+15,x:x+15][mask],badge[mask]), 'Idle badge mismatch'
    report={'ok':True,'files':checked,'palette_colors':128,'hard_alpha':True,
            'idle_anchor_px':[128,224],'badge_reference_sha256':hashlib.sha256((chars/'raccoon_badge.png').read_bytes()).hexdigest(),
            'run_checked':False,'visual_approval':False}
    if 'raccoon_run.png' in images:
        sheet=images['raccoon_run.png'];assert sheet.shape==(256,2048,4)
        frames=[sheet[:,f*256:(f+1)*256] for f in range(8)]
        clip=manifest['clips']['run'];assert clip['fps']==12 and clip['contact_frames']==[0,4]
        hashes=[]
        for f,(frame,spec) in enumerate(zip(frames,clip['frame_metadata'])):
            mask=frame[:,:,3]>0
            _,count=label(mask,np.ones((3,3)));assert count==1,(f,count)
            assert not mask[0].any() and not mask[-1].any() and not mask[:,0].any() and not mask[:,-1].any(), ('Clipping',f)
            if f in (0,4):assert np.where(mask)[0].max()+1==224, ('Foot contact',f)
            x,y=spec['badge_origin'];bm=badge[:,:,3]>0
            assert np.array_equal(frame[y:y+15,x:x+15][bm],badge[bm]), ('Badge drift',f)
            dx,dy=spec['head_offset']
            # Fixed protected face rectangle, excluding silhouette and neck seams.
            assert np.array_equal(frame[76+dy:106+dy,111+dx:158+dx],idle[76:106,111:158]), ('Face drift',f)
            hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
        assert len(set(hashes))==8, 'Repeated animation frames'
        report.update(run_checked=True,run_frames=8,face_locked=True,badge_locked=True,contact_frames=[0,4])
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('chars',type=Path);args=parser.parse_args()
    print('CHARS96_OK',json.dumps(validate(args.chars)))
