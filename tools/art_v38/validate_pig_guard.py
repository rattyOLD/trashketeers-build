#!/usr/bin/env python3
"""Independent guard contract: silhouette, real scale, palette/alpha and form normals."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import label,binary_erosion
RICO={'raccoon_idle.png':'07e6aff3fd9686c076e1d1595c745c8023a89e80805021f3417feca66beb7e8d','raccoon_idle_n.png':'58ff06aedabfdcb5d6bffa1a30a2cf74173405d17dc728b6fb69381d1878f689','raccoon_badge.png':'cdf132a5dd4b198894bc938b3bb6dead5135e1b75062dee3b8e7ebdd7d22926c'}
def validate(folder):
 m=json.loads((folder/'manifest.json').read_text());c=m['characters']['pig_guard'];assert c['pixels_per_metre']==96 and c['anchor_px']==[128,224]
 files={f['file']:f for f in m['files']};names=['pig_guard_idle.png','pig_guard_idle_n.png','pig_guard_palette.png']
 for name in names:
  f=folder/name;assert hashlib.sha256(f.read_bytes()).hexdigest()==files[name]['sha256'];assert f.stat().st_size==files[name]['bytes']
 palette=Image.open(folder/'pig_guard_palette.png').convert('RGB');colors=set(map(tuple,np.array(palette).reshape(-1,3)));assert palette.size==(128,1) and len(colors)==128
 im=Image.open(folder/'pig_guard_idle.png');assert im.mode=='P' and im.size==(256,256)
 a=np.array(im.convert('RGBA'));assert set(np.unique(a[:,:,3]))=={0,255};mask=a[:,:,3]>0
 assert set(map(tuple,a[:,:,:3][mask]))<=colors
 _,count=label(mask,np.ones((3,3)));assert count==1,('Detached pixels',count)
 y,x=np.where(mask);bounds=[int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1)]
 assert bounds==files['pig_guard_idle.png']['visible_bounds_px'];assert y.max()+1==224 and y.max()-y.min()+1==175
 assert not(mask[0].any() or mask[-1].any() or mask[:,0].any() or mask[:,-1].any())
 boundary=mask&~binary_erosion(mask);assert np.max(a[:,:,:3][boundary])<45,'Colored fringe instead of dark contour'
 pink=(a[:,:,0]>a[:,:,1]*1.2)&(a[:,:,0]>150)&mask;navy=(a[:,:,2]>a[:,:,0]*1.08)&(a[:,:,0]<100)&mask;gold=(a[:,:,0]>160)&(a[:,:,1]>90)&(a[:,:,2]<90)&mask
 assert pink.sum()>200 and navy.sum()>400 and gold.sum()>600,('Material readability',pink.sum(),navy.sum(),gold.sum())
 n=np.array(Image.open(folder/'pig_guard_idle_n.png').convert('RGB')).astype(float)/255*2-1
 assert n.shape==(256,256,3);err=float(abs(np.linalg.norm(n,axis=2)-1).max());assert err<.015 and n[:,:,2].min()>.7
 assert np.unique(n[mask],axis=0).shape[0]>500
 for name,expected in RICO.items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==expected,('Accepted Riko changed',name)
 assert c['clips']['idle']['frames']==[0]
 return dict(ok=True,files={n:files[n]['sha256'] for n in names},visible_bounds_px=bounds,visible_height_px=175,core_height_m=173/96,anchor_px=[128,224],pixels_per_metre=96,palette_colors=128,binary_alpha=True,dark_1px_boundary=True,single_connected_character=True,normal_unit_max_error=err,accepted_riko_unchanged=True,animation_frames=1,artistic_approval=c['owner_visual_approved'])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('chars',type=Path);p.add_argument('--report',type=Path);a=p.parse_args();r=validate(a.chars)
 if a.report:a.report.write_text(json.dumps(r,indent=2)+'\n')
 print('PIG_GUARD_CONTRACT_OK',json.dumps(r))
