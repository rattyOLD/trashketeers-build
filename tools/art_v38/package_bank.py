#!/usr/bin/env python3
"""Package the detailed bank revision; never publish other v38 stages here."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'astra/inbox/hd2d_test/buildings'

def main():
    p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('build',type=Path);p.add_argument('textures',type=Path);a=p.parse_args()
    DEST.mkdir(parents=True,exist_ok=True)
    for f in a.candidate.glob('*'):
        if f.suffix in ('.png','.glb') or f.name=='VALIDATION.json':shutil.copy2(f,DEST/f.name)
    shutil.copy2(a.textures/'bank_palette.png',DEST/'bank_palette.png')
    subprocess.run(['node',str(ROOT/'tools/art_v38/optimize_png.mjs'),str(DEST/'bank_palette.png')],check=True)
    model=json.loads((a.build/'model_report.json').read_text());validation=json.loads((a.candidate/'VALIDATION.json').read_text())
    texture=json.loads((a.textures/'texture_export.json').read_text())
    files=[]
    for path in sorted([*DEST.glob('*.png'),*DEST.glob('*.glb')]):
        item={'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
        if path.suffix=='.glb':
            item.update(role='building_model',body_size_m=[16,10.5,8],actual_render_bounds_m=validation['bounds_m'],
                anchor_m=[0,0,0],up_axis='+Y',front_axis='+Z',units='metres',triangles=validation['triangles'],
                collider_radius_m=9.1,collider_shape='compound boxes',
                collision_boxes=[{'center_m':[0,4.65,0],'size_m':[16,8.1,8]},
                    {'center_m':[0,.3,0],'size_m':[16.2,.6,8.15]},
                    *[{'center_m':[x,3.04,4.25],'size_m':[.98,4.88,.95]} for x in [-3.18,3.18]],
                    *[{'center_m':[0,.075*(i+1),3.95+(1.8-i*.4)/2],'size_m':[8-i*.22,.15*(i+1),1.8-i*.4]} for i in range(4)]])
        else:
            im=Image.open(path);item.update(width=im.width,height=im.height,format=im.mode,pixels_per_metre=96)
            if path.name=='bank_palette.png':item.update(role='palette',color_count=128)
            elif path.name.endswith('_n.png'):item.update(role='normal',color_space='linear_data',convention='OpenGL +Y',normal_map_invert_y=False,suggested_strength=.3)
            elif path.name.endswith('_glow.png'):item.update(role='emission_mask',color_space='linear_data',operator='multiply')
            else:item.update(role='albedo',color_space='sRGB',palette='bank_palette.png',alpha='binary 0/255')
            if im.size==(192,192):item.update(size_m=[2,2],tileable=True,anchor_px=[0,0])
            elif path.name=='bank_crest.png':item.update(role='cutout_atlas',collision=False,regions_px={'crowned_pig':[64,0,384,288],'window_acanthus':[0,320,128,64]},region_sizes_m={'crowned_pig':[4,3],'window_acanthus':[128/96,64/96]},description='Clean isolated crest and window ornament, separate padded atlas islands; mapped at96px/m')
            elif path.name=='bank_ivy.png':item.update(size_m=[256/96,256/96],anchor_px=[128,256],collision=False,description='Lush flowering ivy on eight separate alpha-scissor cards')
        files.append(item)
    manifest={'schema_version':1,'brief':'v38 + v37 + owner bank-detail revision','revision':'bank3d-detail-2','studio':'TrashSquad · Beer Party Studio',
        'scope':'Bank refinement only: low parapet roof, v36 detail, pixel materials, plinth/stairs and clean crest. Other v38 stages pending.',
        'delivery_status':'review_candidate','owner_approach_approved':True,'owner_visual_approved':False,'ready_for_scene_review':True,
        'pixels_per_metre':96,'files':files,'trim_sheet':{'file':'bank_trim.png','size_px':[1024,1024],
            'regions_px':{'frieze':[0,0,256,64],'gold_leaf':[256,0,256,64],'shaft':[512,0,256,256],'brass':[768,0,256,256],
                'plinth':[0,256,128,128],'wood':[256,256,256,256],'iron':[512,256,256,256],'amber_glass':[768,256,256,256]},
            'normal':'bank_trim_n.png','emission_mask':'bank_trim_glow.png','unused_regions':'reserved; not sampled by model'},
        'materials':model['materials'],'normal_maps_note':texture['normal_note'],
        'import_settings':{'filter':'nearest (GLB sampler9728)','alpha_mode':'MASK / cutoff0.5 for ivy and crest',
            'png_files':'external next to bank_hall.glb; do not move GLB alone','normal_convention':'OpenGL +Y',
            'review_texture_compression':'lossless; avoid BC artifacts during visual evaluation'},
        'night_settings':{'day_emission_off':True,'emission_operator':'multiply','warm_tint_rgb':[1,.53,.16],
            'suggested_energy':.55,'windows_material':'Bank_Window_Glass','windows_mask':'bank_glass_glow.png',
            'wall_lamps_material':'Bank_Lantern_Glass','wall_lamps_mask':'bank_trim_glow.png',
            'note':'Opaque frames and metal are separate geometry/materials; black mask does not emit. Scene lights supplied by developer.'},
        'camera_review':{'vertical_fov_deg':30,'pitch_down_deg':32,'distance_m':28,'target_m_y_up':[0,4.75,1.2],
            'three_quarter_yaw_deg':24,'resolution_px':[1920,1080]},
        'geometry':{'triangles':model['triangles'],'meshes':model['mesh_count'],'materials':model['material_count'],
            'roof_pitch_deg':model['roof_pitch_deg'],'recess_m':.28,'roof_behind_parapet':True,'body_depth_m':8,
            'foundation_height_m':.6,'entrance_steps':4,'step_rise_m':.15,'parapet_balusters':14,'balconettes':4,
            'actual_bounds_note':'Ivy, cornices and four entrance steps extend beyond the16x8m wall body; use actual_render_bounds_m for framing.'},
        'next_v38_stage':'Bank refinement awaits scene review. Then one pig_guard idle and the remaining ordered stages; no3D cafe/shop before bank assessment.'}
    (DEST/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    shutil.copy2(a.build/'model_report.json',DEST/'MODEL_REPORT.json')
    for f in texture['files']:
        path=DEST/f['file']
        if path.exists():f['uncompressed_sha256']=f.pop('sha256');f.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size)
    texture['lossless_idat_optimized']=True
    (DEST/'TEXTURE_EXPORT.json').write_text(json.dumps(texture,ensure_ascii=False,indent=2)+'\n')
    print('BANK38_PACKAGED',len(files),'files, GLB',validation['glb_sha256'])
if __name__=='__main__':main()
