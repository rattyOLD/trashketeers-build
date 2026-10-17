#!/usr/bin/env python3
"""Paired-render checks for actual sprite pixels in the current Bank plaza."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('qa',type=Path);p.add_argument('chars',type=Path);a=p.parse_args();log=(a.qa/'render.log').read_text()
 assert 'PIG_GUARD_PLAZA_OK' in log and 'ERROR:' not in log and 'SCRIPT ERROR' not in log
 staging=json.loads((a.qa/'staging.json').read_text());assert hashlib.sha256((ROOT/'source/prototypes/hd2d/plaza.gd').read_bytes()).hexdigest()==staging['prototype_source_sha256']
 assert hashlib.sha256((ROOT/'source/prototypes/hd2d/buildings/bank_hall.glb').read_bytes()).hexdigest()==staging['bank_model_sha256']
 files={};frames={}
 for name in ['day','day_flat','no_shadow','evening','evening_flat']:
  f=a.qa/f'pig_guard_pair_{name}.png';im=Image.open(f).convert('RGB');assert im.size==(1920,1080);frames[name]=np.array(im).astype(np.int16);files[f.name]=hashlib.sha256(f.read_bytes()).hexdigest()
 overview=a.qa/'pig_guard_plaza_day.png';assert Image.open(overview).size==(1920,1080);files[overview.name]=hashlib.sha256(overview.read_bytes()).hexdigest()
 comparisons={}
 for name,other in [('day','day_flat'),('evening','evening_flat'),('day','no_shadow')]:
  d=abs(frames[name]-frames[other]).max(axis=2);y,x=np.where(d>1);assert len(x)>500
  box=[int(x.min()),int(y.min()),int(x.max()),int(y.max())];assert box[0]>950 and box[1]>250 and box[2]<1550 and box[3]<850,('Difference escaped guard area',box)
  if other.endswith('_flat'):assert d.max()<32,'Normal overwhelms albedo'
  else:assert d.max()>8,'No engine-cast contact shadow'
  comparisons[name+'/'+other]={'changed_pixels_above1':len(x),'max_channel_delta':int(d.max()),'bounds_inclusive':box}
 actual={}
 for name in ['pig_guard_idle.png','pig_guard_idle_n.png']:
  # Lossless PNG recompression changes bytes, never the rendered source pixels.
  src=a.qa/'prototypes/hd2d/chars'/name;dst=a.chars/name
  assert np.array_equal(np.array(Image.open(src).convert('RGBA')),np.array(Image.open(dst).convert('RGBA')))
  actual[name]=hashlib.sha256(dst.read_bytes()).hexdigest()
 report=dict(ok=True,godot='4.4.1.stable.official.49a5bc7b6',renderer='Compatibility / Mesa llvmpipe software OpenGL4.5',prototype_source_sha256=staging['prototype_source_sha256'],developer_bank_model_sha256=staging['bank_model_sha256'],delivered_files=actual,delivered_pixels_equal_rendered_pixels=True,source_modified=False,scene_script_errors=False,artistic_approval=False,camera=staging['camera'],comparisons=comparisons,screenshots_sha256=files,limits=['Single static idle frame in current Bank prototype copy; no animation, combat or physical-device test.','Old side buildings/fountain remain temporary; no claim of complete plaza delivery.','QA close cameras disable shader blur/glow for inspection; source scene/settings unchanged.','Editor initialization reports missing local Vulkan surface; Compatibility runtime completes without scene/resource errors.'])
 (a.chars/'PIG_GUARD_RENDER_VALIDATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('PIG_GUARD_RENDER_OK',json.dumps(comparisons))
if __name__=='__main__':main()
