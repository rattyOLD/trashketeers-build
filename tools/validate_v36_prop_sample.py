#!/usr/bin/env python3
"""Check actual delivered PNGs and assembly, independently of render tooling."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image


def validate(root):
    errors=[]
    def check(ok,message):
        if not ok:errors.append(message)
    folder=root/'props'
    manifest=json.loads((folder/'manifest.json').read_text())
    palette=Image.open(root/'palettes/bank.png').convert('RGB')
    palette_colors=set(map(tuple,np.array(palette).reshape(-1,3)))
    check(palette.size==(64,1) and len(palette_colors)==64,'Bank palette: 64 unique colors')
    check(manifest['pixels_per_metre']==48,'Prop density must be 48 px/m')
    expected={'bank_lantern.png':(72,104),'bank_pedestal.png':(96,72),
              'bank_flower_planter.png':(96,100),'bank_lantern_glow.png':(72,104),
              'bank_pedestal_n.png':(96,72)}
    check({f['file'] for f in manifest['files']}==set(expected),'Complete 3 sprites + 2 data maps')
    check({p.name for p in folder.glob('*.png')}==set(expected),'Unlisted or missing PNG')
    images={}
    entries={}
    stats={}
    for f in manifest['files']:
        name=f['file']
        path=folder/name
        with Image.open(path) as p:p.verify()
        im=Image.open(path)
        images[name]=im.convert('RGBA')
        entries[name]=f
        a=np.array(images[name])
        check(im.size==expected[name],f'{name}: native resolution')
        check((f['width'],f['height'])==im.size,f'{name}: manifest dimensions')
        check(hashlib.sha256(path.read_bytes()).hexdigest()==f['sha256'],f'{name}: hash')
        check(path.stat().st_size==f['bytes'],f'{name}: byte count')
        check(f['size_m']==[im.width/48,im.height/48],f'{name}: physical size')
        ax,ay=f['anchor_px']
        check(0<=ax<=im.width and 0<=ay<=im.height,f'{name}: anchor outside frame')
        check(f['anchor_uv']==[ax/im.width,ay/im.height],f'{name}: normalized anchor')
        check(set(a[:,:,3].ravel())<={0,255},f'{name}: soft alpha')
        if f['role']=='vertical_sprite':
            visible=a[:,:,3]==255
            colors=set(map(tuple,a[visible,:3]))
            check(colors<=palette_colors,f'{name}: not in Bank palette')
            check(len(colors)>=10,f'{name}: suspiciously few material tones')
            check(f.get('resampled') is False and f['source_render_size_px']==list(im.size),f'{name}: native-render provenance')
            check(f['collider_radius_m']>0,f'{name}: own collider radius')
            check(f.get('ground_cast_shadow_baked') is False,f'{name}: cast shadow prohibited')
            stats[name]={'size':list(im.size),'visible_bounds':list(im.getbbox()),'colors':len(colors)}
    lamp=np.array(images['bank_lantern.png'])
    mask_rgb=np.array(images['bank_lantern_glow.png'])[:,:,:3]
    mask=mask_rgb[:,:,0]
    check(np.all(mask_rgb==mask[:,:,None]),'Emission mask must be grayscale data')
    check(set(mask.ravel())=={0,255},'Emission mask: nonempty white on black')
    check(np.all(mask[lamp[:,:,3]==0]==0),'Emission mask outside lamp silhouette')
    yy,xx=np.nonzero(mask)
    check(xx.max()-xx.min()>8 and yy.max()-yy.min()>12,'Glass mask is implausibly small')
    check(yy.min()>lamp.shape[0]*.25 and yy.max()<lamp.shape[0]*.8,'Mask incorrectly includes roof/base')
    check(entries['bank_lantern.png']['emission_operator']=='multiply','Emission must not light the whole casing')
    n=np.array(images['bank_pedestal_n.png'])[:,:,:3].astype(float)/255*2-1
    check(np.max(np.abs(np.linalg.norm(n,axis=2)-1))<.015,'Stone normals not normalized')
    check(n[:,:,2].min()>=-.01,'Stone normal faces away from sprite')
    check(len(np.unique(n.reshape(-1,3),axis=0))>50,'Stone normal lacks actual relief')
    check(entries['bank_pedestal.png']['normal_map_invert_y'] is False,'OpenGL normal convention')
    assembly=manifest['assembly']
    check(assembly['canvas_px']==[96,165],'Assembly canvas must be 165px tall')
    combined=Image.new('RGBA',tuple(assembly['canvas_px']))
    for part in assembly['parts']:
        combined.alpha_composite(images[part['file']],tuple(part['top_left_px']))
    bounds=combined.getbbox()
    check(bounds[3]-bounds[1]==assembly['visible_height_px'],'Assembly measured height mismatch')
    check(160<=bounds[3]-bounds[1]<=168,'Assembly must be about 165px tall')
    stone_part,lamp_part=assembly['parts']
    mount=entries['bank_pedestal.png']['mount_points']['lantern']['anchor_px']
    lamp_anchor=entries['bank_lantern.png']['anchor_px']
    check([stone_part['top_left_px'][i]+mount[i] for i in range(2)]==
          [lamp_part['top_left_px'][i]+lamp_anchor[i] for i in range(2)],'Lamp/pedestal socket mismatch')
    check(not lamp_part['collision_enabled'] and stone_part['collision_enabled'],'Mounted assembly double collision')
    check(lamp_part.get('depth_offset_m',0)>0,'Coplanar parts risk z-fighting')
    return {'ok':not errors,'errors':errors,'sprites':stats,'png_count':len(expected),
            'density':48,'assembly_visible_height_px':bounds[3]-bounds[1],
            'palette_colors':len(palette_colors),'owner_visual_approval':manifest['owner_visual_approved']}


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]/'astra/inbox/hd2d_test')
    p.add_argument('--report',type=Path)
    args=p.parse_args()
    report=validate(args.root)
    if args.report:args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    print('V36_PROP_SAMPLE_OK' if report['ok'] else 'V36_PROP_SAMPLE_FAILED')
    raise SystemExit(0 if report['ok'] else 1)
