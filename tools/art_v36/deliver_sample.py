#!/usr/bin/env python3
"""Package the validated-size native render; no resizing of game assets."""
import hashlib
import json
import os
import shutil
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
INBOX=ROOT/'astra/inbox/hd2d_test'
SOURCE=Path(os.environ.get('TRASHSQUAD_V36_RENDER_DIR','/tmp/trashsquad-v36-native'))


def write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def info(path,**extra):
    im=Image.open(path)
    return {'file':path.name,'width':im.width,'height':im.height,'format':im.mode,
            'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**extra}


def main():
    out=INBOX/'props'
    out.mkdir(parents=True,exist_ok=True)
    files=[]
    for stem,size,anchor,radius in [('bank_lantern',(72,104),(36,103),.28),
            ('bank_pedestal',(96,72),(48,71),.64),('bank_flower_planter',(96,100),(48,99),.48)]:
        src=SOURCE/'encoded'/f'{stem}.png'
        assert Image.open(src).size==size
        dst=out/src.name
        shutil.copy2(src,dst)
        files.append(info(dst,role='vertical_sprite',size_m=[size[0]/48,size[1]/48],
            anchor_px=list(anchor),anchor_uv=[anchor[0]/size[0],anchor[1]/size[1]],
            anchor_space='pixel boundaries from top-left',collider_radius_m=radius,
            palette='../palettes/bank.png',alpha='binary',view='front + top; yaw 0',
            local_form_shading_baked=True,ground_cast_shadow_baked=False,
            source_render_size_px=list(size),resampled=False))
    for stem,role,albedo in [('bank_lantern_glow','emission_mask','bank_lantern.png'),
                            ('bank_pedestal_n','normal_map','bank_pedestal.png')]:
        src=SOURCE/'encoded'/f'{stem}.png'
        dst=out/src.name
        shutil.copy2(src,dst)
        parent=next(f for f in files if f['file']==albedo)
        files.append(info(dst,role=role,paired_albedo=albedo,size_m=parent['size_m'],
            anchor_px=parent['anchor_px'],anchor_uv=parent['anchor_uv'],color_space='linear_data'))
    files[0].update(glow_mask='bank_lantern_glow.png',light_source_px=[36,54],
        light_source_m_from_anchor=[0,49/48,.20],day_emission_energy=0,
        emission_operator='multiply',suggested_emission_color='#ffc574',
        suggested_emission_energy=.55,suggested_light_energy=.4,suggested_light_range_m=5.)
    files[1].update(normal_map='bank_pedestal_n.png',normal_convention='OpenGL +Y',
        normal_map_invert_y=False,suggested_normal_scale=.45,
        normal_source='same-size geometry normal render; not albedo luminance',
        mount_points={'lantern':{'anchor_px':[48,10],'position_m_from_anchor':[0,61/48,0]}})
    write(out/'manifest.json',{'schema_version':1,'brief':'v36','revision':'modular-48-1',
        'studio':'TrashSquad · Beer Party Studio','delivery_status':'review_candidate',
        'owner_visual_approved':False,'scope':'three new props only; remaining v36 props/facades/characters pending',
        'pixels_per_metre':48,'palette':'../palettes/bank.png','files':files,
        'assembly':{'canvas_px':[96,165],'anchor_px':[48,164],
            'visible_height_px':163,'visible_height_m':163/48,'canvas_height_m':165/48,
            'collision_owner':'bank_pedestal.png',
            'parts':[{'file':'bank_pedestal.png','top_left_px':[0,93],'position_m':[0,0,0],'collision_enabled':True},
                     {'file':'bank_lantern.png','top_left_px':[12,0],'position_m':[0,61/48,0],
                      'collision_enabled':False,'depth_offset_m':.005}],
            'transform_with_common_sprite_plane':True,
            'note':'Mount/depth offsets use the common sprite plane basis. Rotate offsets with its tilt/billboard. Depth offset prevents coplanar z-fighting.'},
        'sprite3d':{'pixel_size':1/48,'centered':True,
            'offset_formula':'Vector2(width/2-anchor_x, anchor_y-height/2)',
            'albedo_color_space':'sRGB','normal_mask_color_space':'linear_data',
            'alpha_scissor':.5,'filter':'nearest with optional mipmaps',
            'glow_note':'Use emission color MULTIPLIED by mask; ADD makes the whole iron frame emit.'},
        'source_pipeline':'native-resolution 3D form render, material-ramp encoding and 1px selective outline; no high-res art downsampling'})
    # Install the proposed warm slots; the 32 old material colors remain intact.
    proposal=ROOT/'astra/previews/v36/bank_palette_proposal.png'
    shutil.copy2(proposal,INBOX/'palettes/bank.png')
    data=json.loads((ROOT/'astra/previews/v36/bank_palette_proposal.json').read_text())
    im=Image.open(proposal).convert('RGB')
    colors=im.get_flattened_data() if hasattr(im,'get_flattened_data') else im.getdata()
    write(INBOX/'palettes/colors.json',{'schema_version':1,'revision':'v36-warm-48',
        'colors':['#%02x%02x%02x'%c for c in colors],
        'props_ramps':data['new_material_ramps'],'existing_material_colors_preserved':32,
        'note':'Palette itself has no world size. Existing material textures remain 32 px/m; new props use 48 px/m.'})
    write(INBOX/'palettes/manifest.json',{'schema_version':1,'brief':'v36',
        'revision':'warm-48-sample','studio':'TrashSquad · Beer Party Studio',
        'files':[info(INBOX/'palettes/bank.png',role='environment_palette',colors=64,
                size_m=None,anchor_px=None,not_a_world_surface=True)],
        'definition_file':'colors.json','pending':['chars.png with future character batch']})
    shutil.copy2(SOURCE/'sample_review.png',ROOT/'astra/previews/v36/modular_48_review.png')
    print('V36_PROP_SAMPLE_PACKAGED: 3 sprites, emission mask, normal map; existing material colors preserved')


if __name__=='__main__':main()
