"""Palette/alpha encoding of same-size native renders; never resizes art."""
import json
import os
import numpy as np
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(os.environ.get('TRASHSQUAD_V36_RENDER_DIR','/tmp/trashsquad-v36-native'))
OUT=HERE/'encoded'
OUT.mkdir(exist_ok=True)
proposal=json.loads((ROOT/'astra/previews/v36/bank_palette_proposal.json').read_text())
ramps=proposal['new_material_ramps'].copy()
ramps.update({
    'stone':['#6c5550','#8b715c','#9d8268','#bab09e','#cec3ad','#eee7d5'],
    'petals':['#7f394a','#806b70','#b45868','#df8693','#dbbdb0','#f7bdbe'],
    'white':['#a49b8d','#cec3ad','#cbc5b7','#d9d3c3','#e4decd','#eee7d5'],
    'earth':['#6c5550','#7b6254','#8b715c','#9d8268']})
CATS=['iron','brass','amber_glass','stone','terracotta','foliage','petals','white','earth']
IDS=np.array([(1,0,0),(0,1,0),(0,0,1),(1,1,0),(1,0,1),(0,1,1),(.5,0,1),(1,.5,0),(.5,1,0)])*255
RGB={k:np.array([list(bytes.fromhex(h.lstrip('#'))) for h in v],dtype=np.float32) for k,v in ramps.items()}
GAINS={'iron':.65,'brass':1.10,'amber_glass':1.10,'stone':1.04,'terracotta':1.22,'foliage':1.03,'petals':1.08,'white':1.08}


def bake(stem):
    beauty=Image.open(HERE/f'{stem}_beauty.png').convert('RGBA')
    ids=Image.open(HERE/f'{stem}_id.png').convert('RGB')
    assert beauty.size==ids.size
    b=np.array(beauty)
    idarr=np.array(ids,dtype=np.float32)
    visible=b[:,:,3]>=128
    categories=np.argmin(np.sum((idarr[:,:,None,:]-IDS[None,None,:,:])**2,axis=3),axis=2)
    # Suppress sub-tone Monte Carlo noise only on coplanar stone pixels.
    # No edge, vein, chip or relief smoothing across normal/material changes.
    normals=np.array(Image.open(HERE/f'{stem}_normal.png').convert('RGB'),dtype=np.float32)/255*2-1
    normals/=np.maximum(np.linalg.norm(normals,axis=2,keepdims=True),.001)
    raw=b.copy()
    if stem=='bank_pedestal':
        for y in range(1,b.shape[0]-1):
            for x in range(1,b.shape[1]-1):
                if not visible[y,x] or CATS[categories[y,x]]!='stone':continue
                rgb=[]
                for dy in [-1,0,1]:
                    for dx in [-1,0,1]:
                        yy,xx=y+dy,x+dx
                        if (visible[yy,xx] and categories[yy,xx]==categories[y,x]
                            and np.dot(normals[yy,xx],normals[y,x])>.998
                            and np.max(np.abs(raw[yy,xx,:3].astype(float)-raw[y,x,:3]))<8):
                            rgb.append(raw[yy,xx,:3])
                if len(rgb)>=5:b[y,x,:3]=np.median(rgb,axis=0).astype(np.uint8)
    result=np.zeros_like(b)
    for i,cat in enumerate(CATS):
        select=visible&(categories==i)
        values=(b[select,:3].astype(np.float32)*GAINS.get(cat,1.)).clip(0,255)
        # Same-pixel quantization within each material's authored color ramp.
        d=np.sum((values[:,None,:]-RGB[cat][None,:,:])**2,axis=2)
        result[select,:3]=RGB[cat][np.argmin(d,axis=1)].astype(np.uint8)
        result[select,3]=255
    # One final-grid pixel of selective colored outline, lightened at upper edge.
    h,w=visible.shape
    outline=np.zeros_like(visible)
    for y in range(h):
        for x in range(w):
            if visible[y,x]:continue
            neighbors=[(y+dy,x+dx,dy) for dy,dx in [(1,0),(0,-1),(0,1),(-1,0)]
                       if 0<=y+dy<h and 0<=x+dx<w and visible[y+dy,x+dx]]
            if not neighbors:continue
            yy,xx,dy=neighbors[0]
            ramp=RGB[CATS[categories[yy,xx]]]
            index=1 if dy==1 else 0
            result[y,x,:3]=ramp[index]
            result[y,x,3]=255
            outline[y,x]=True
    im=Image.fromarray(result)
    im.save(OUT/f'{stem}.png')
    if stem=='bank_lantern':
        glow=np.array(Image.open(HERE/f'{stem}_glow.png').convert('RGB'))
        levels=np.array([0,48,255])
        m=levels[np.argmin(abs(glow[:,:,0,None].astype(float)-levels),axis=2)].astype(np.uint8)
        m[~visible]=0
        Image.fromarray(np.repeat(m[:,:,None],3,axis=2)).save(OUT/f'{stem}_glow.png')
    if stem=='bank_pedestal':
        n=np.array(Image.open(HERE/f'{stem}_normal.png').convert('RGB'),dtype=np.float32)/255*2-1
        # Backface-independent two-sided relief normals, oriented toward viewer.
        n[n[:,:,2]<0]*=-1
        lengths=np.linalg.norm(n,axis=2)
        n/=np.maximum(lengths[:,:,None],.001)
        encoded=np.rint((n*.5+.5)*255).clip(0,255).astype(np.uint8)
        encoded[~visible|outline]=(128,128,255)
        Image.fromarray(encoded).save(OUT/f'{stem}_n.png')
    print(stem,im.size,im.getbbox(),len(set(map(tuple,result[visible,:3]))))
    return im


def main():
    lamp=bake('bank_lantern')
    stone=bake('bank_pedestal')
    pot=bake('bank_flower_planter')
    group=Image.new('RGBA',(204,165))
    group.alpha_composite(stone,(0,77))
    group.alpha_composite(lamp,(20,0))
    group.alpha_composite(pot,(108,65))
    group.save(HERE/'assembly_native.png')
    board=Image.new('RGB',(900,610),(32,40,48))
    d=ImageDraw.Draw(board)
    fontpath='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    font=ImageFont.truetype(fontpath,15)
    small=ImageFont.truetype(fontpath,12)
    d.text((20,12),'BANK / 48 px/m · MODULAR SAMPLE · native pixels, warm material ramps',font=font,fill=(238,216,171))
    for x,bg in [(20,(32,40,48)),(468,(220,209,186))]:
        d.rectangle((x-4,48,x+412,387),fill=bg)
        im=group.resize((408,330),Image.Resampling.NEAREST)
        board.paste(im,(x,52),im)
    d.text((20,397),'2× / dark ground',font=font,fill=(212,211,195))
    d.text((468,397),'2× / pale ground',font=font,fill=(212,211,195))
    board.paste(group,(20,438),group)
    d.text((20,419),'1× / same source pixels',font=small,fill=(212,211,195))
    mask=Image.open(OUT/'bank_lantern_glow.png')
    board.paste(mask,(263,439))
    d.text((246,420),'glass emission mask',font=small,fill=(212,211,195))
    normal=Image.open(OUT/'bank_pedestal_n.png')
    board.paste(normal,(430,439))
    d.text((426,420),'stone normal map',font=small,fill=(212,211,195))
    d.text((580,444),'Assembly: 165 px / 3.4375 m',font=small,fill=(212,211,195))
    d.text((580,467),'Lamp, stone and planter separate',font=small,fill=(212,211,195))
    d.text((580,490),'Alpha: 0 or 255. No floor shadow.',font=small,fill=(212,211,195))
    d.text((580,513),'Relief normals from geometry,',font=small,fill=(212,211,195))
    d.text((580,532),'not from albedo brightness.',font=small,fill=(212,211,195))
    board.save(HERE/'sample_review.png')


if __name__=='__main__':main()
