#!/usr/bin/env python3
"""Append one guard candidate without touching accepted Riko art or bank assets."""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];DEST=ROOT/'astra/inbox/hd2d_test/chars'
def main():
 p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);a=p.parse_args()
 old=json.loads((DEST/'manifest.json').read_text());before={n:hashlib.sha256((DEST/n).read_bytes()).hexdigest() for n in ['raccoon_idle.png','raccoon_idle_n.png','raccoon_badge.png']}
 names=['pig_guard_idle.png','pig_guard_idle_n.png','pig_guard_palette.png']
 for n in names:shutil.copy2(a.candidate/n,DEST/n)
 subprocess.run(['node',str(ROOT/'tools/art_v38/optimize_png.mjs'),*[str(DEST/n) for n in names]],check=True)
 recipe=json.loads((a.candidate/'pixel_export.json').read_text());entries=[]
 for name in names:
  f=DEST/name;im=Image.open(f);d={'file':name,'character_id':'pig_guard','width':im.width,'height':im.height,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size}
  if name.endswith('_palette.png'):d.update(role='character_palette',format='RGB',color_count=128,not_a_world_surface=True)
  elif name.endswith('_n.png'):d.update(role='normal_map',paired_albedo='pig_guard_idle.png',format='RGB',size_m=[256/96,256/96],anchor_px=[128,224],color_space='linear_data',normal_convention='OpenGL +Y',normal_map_invert_y=False,suggested_normal_scale=.25,source=recipe['normal_source'])
  else:d.update(role='character_idle_sprite',format='indexed PNG, binary tRNS',cell_px=[256,256],frame_count=1,pixels_per_metre=96,size_m=[256/96,256/96],core_body_height_px=173,core_body_height_m=173/96,visible_height_px=175,visible_height_m=175/96,visible_bounds_px=recipe['visible_bounds'],anchor_px=[128,224],anchor_uv=[.5,.875],anchor_space='pixel boundaries from top-left',collider_radius_m=.38,palette='pig_guard_palette.png',alpha='binary 0/255',visible_colors=recipe['visible_colors'],outline='continuous dark1px around whole silhouette',normal_map='pig_guard_idle_n.png',normal_map_invert_y=False,suggested_normal_scale=.25,ground_cast_shadow_baked=False,local_form_shading_baked=True,source_image='../../../previews/v38/pig_guard_source.png',source_sha256=recipe['source_sha256'],creation_method=recipe['creation_method'],resampled_from_concept=True)
  entries.append(d)
 old['files']=[e for e in old['files'] if e.get('character_id')!='pig_guard']+entries
 old.update(brief='v38 + v36 character96',revision='rico-badge-2+pig-guard-idle-1',scope='Accepted Riko identity/badge preserved. One pig_guard idle candidate; no other pigs or new animation delivered.',delivery_status='accepted_riko_identity_plus_guard_review_candidate')
 old.setdefault('characters',{})['pig_guard']={'delivery_status':'review_candidate','owner_visual_approved':False,'ready_for_scene_review':True,'ready_for_gameplay':False,'albedo':'pig_guard_idle.png','normal':'pig_guard_idle_n.png','palette':'pig_guard_palette.png','pixels_per_metre':96,'anchor_px':[128,224],'collider_radius_m':.38,'clips':{'idle':{'frames':[0],'fps':1,'loop':True}},'identity_reference':{'source_design':'source/assets/enemies/pig_security.png','face_head_bounds_px':[88,49,165,120],'rule':'Preserve face, cap and uniform identity across future clips; use this idle as the approved-reference candidate.'},'sprite3d':{'pixel_size':1/96,'quad_size_m':[256/96,256/96],'quad_center_m_from_anchor':[0,1,0],'alpha_scissor':.5,'texture_filter':'nearest','normal_scale':.25,'normal_convention':'OpenGL +Y','shaded':True,'cast_shadow_in_engine':True},'pending':['Visual review of this single idle','pig_sniper/pig_angry after guard review','idle4 run6 windup2 strike3 hit2 death6 after visual review']}
 old['characters']['pig_guard']['verification']={'format':'PIG_GUARD_VALIDATION.json','render_report':'PIG_GUARD_RENDER_VALIDATION.json','scope':'one idle frame in current plaza copy; artistic review pending'}
 old['palette_note']='Riko palette/pixels unchanged. Guard has its own restrained128-color palette with matched dark outline, warm neutrals and brass; shared roster-palette unification is not claimed.'
 (DEST/'manifest.json').write_text(json.dumps(old,ensure_ascii=False,indent=2)+'\n')
 for n,h in before.items():assert hashlib.sha256((DEST/n).read_bytes()).hexdigest()==h
 recipe['files']={n:{'sha256':hashlib.sha256((DEST/n).read_bytes()).hexdigest(),'bytes':(DEST/n).stat().st_size} for n in names};recipe['accepted_riko_unchanged']=before
 (DEST/'PIG_GUARD_EXPORT.json').write_text(json.dumps(recipe,ensure_ascii=False,indent=2)+'\n');print('PIG_GUARD_DELIVERED',before)
if __name__=='__main__':main()
