"""Independent delivery contract for the 96 px/m control sample."""
import hashlib
import json
import numpy as np
from PIL import Image
from scipy import ndimage


def validate(root):
    errors=[]
    def check(ok,message):
        if not ok: errors.append(message)
    folder=root/'props'
    m=json.loads((folder/'manifest.json').read_text())
    palette=np.array(Image.open(root/'palettes/bank96.png').convert('RGB'))
    colors=set(map(tuple,palette.reshape(-1,3)))
    check(palette.shape==(1,128,3) and len(colors)==128,'128 distinct environment colors')
    expected={'bank_lantern.png':(128,184),'bank_pedestal.png':(192,176),
        'bank_flower_planter.png':(208,208),'bank_lantern_glow.png':(128,184),
        'bank_pedestal_n.png':(192,176)}
    check(m['pixels_per_metre']==96,'Density must be 96 px/m')
    check({f['file'] for f in m['files']}==set(expected),'Complete manifest')
    check({p.name for p in folder.glob('*.png')}==set(expected),'Complete PNG set')
    images={}; entries={};stats={}
    for f in m['files']:
        name=f['file'];path=folder/name
        with Image.open(path) as im:im.verify()
        im=Image.open(path).convert('RGBA');a=np.array(im)
        images[name]=im;entries[name]=f
        check(im.size==expected[name],name+': dimensions')
        check([f['width'],f['height']]==list(im.size),name+': manifest dimensions')
        check(hashlib.sha256(path.read_bytes()).hexdigest()==f['sha256'],name+': SHA256')
        check(path.stat().st_size==f['bytes'],name+': bytes')
        check(f['size_m']==[v/96 for v in im.size],name+': metre scale')
        check(f['anchor_uv']==[v/n for v,n in zip(f['anchor_px'],im.size)],name+': UV anchor')
        if f['role']=='vertical_sprite':
            check(set(a[:,:,3].ravel())=={0,255},name+': hard alpha')
            visible=a[:,:,3]>0
            used=set(map(tuple,a[visible,:3]))
            check(used<=colors and 40<=len(used)<=128,name+': palette')
            edge=visible & ~ndimage.binary_erosion(visible,structure=ndimage.generate_binary_structure(2,1))
            # Every silhouette boundary pixel must be the reserved dark contour.
            check(np.all(a[edge,:3]==(30,28,27)),name+': interrupted dark contour')
            labels,count=ndimage.label(visible,structure=np.ones((3,3)))
            sizes=sorted(np.bincount(labels.ravel())[1:].tolist(),reverse=True)
            check(count==1,name+': disconnected stray pixels')
            check(f['resampled_from_concept'] is True,name+': honest provenance')
            check(f['ground_cast_shadow_baked'] is False,name+': baked cast shadow')
            check(f['collider_radius_m']>0,name+': collider radius')
            stats[name]={'bounds':list(im.getbbox()),'colors':len(used),'components':sizes}
    lamp=images['bank_lantern.png'];stone=images['bank_pedestal.png']
    lb,sb=lamp.getbbox(),stone.getbbox()
    wr=(lb[2]-lb[0])/(sb[2]-sb[0]);hr=(lb[3]-lb[1])/(sb[3]-sb[1])
    check(.55<=wr<=.72 and hr<=1.2,'Slender lamp relative to massive pedestal')
    glow=np.array(images['bank_lantern_glow.png'])[:,:,:3]
    check(np.array_equal(glow[:,:,0],glow[:,:,1]) and np.array_equal(glow[:,:,0],glow[:,:,2]),'Linear greyscale mask')
    g=glow[:,:,0]
    check(set(g.ravel())=={0,48,255},'Mask preserves glass/filament intensities')
    check(np.all(g[np.array(lamp)[:,:,3]==0]==0),'Mask outside silhouette')
    check(np.all(g[:70]==0) and np.all(g[123:]==0),'Emission outside glass chamber')
    probe=entries['bank_lantern.png']['mullion_probe_px'];y0,y1=probe['y_range']
    for x in probe['x_columns']:check(np.all(g[y0:y1+1,x]==0),'Mullion overwritten by glow')
    for x0,x1 in ((39,52),(58,70),(77,88)):check(np.count_nonzero(g[75:117,x0:x1])>150,'Missing glass pane')
    check(entries['bank_lantern.png']['emission_operator']=='multiply','Emission must MULTIPLY')
    normal=np.array(images['bank_pedestal_n.png'])[:,:,:3]/255*2-1
    error=float(np.max(abs(np.linalg.norm(normal,axis=2)-1)))
    check(error<.008 and normal[:,:,2].min()>0,'Normal vector convention/length')
    check(len(np.unique(normal.reshape(-1,3),axis=0))>50,'Stone relief missing')
    assembly=m['assembly'];combined=Image.new('RGBA',tuple(assembly['canvas_px']))
    for part in assembly['parts']:combined.alpha_composite(images[part['file']],tuple(part['top_left_px']))
    b=combined.getbbox();check(b[3]-b[1]==assembly['visible_height_px']==330,'330px assembly height')
    sp,lp=assembly['parts'];socket=entries['bank_pedestal.png']['mount_points']['lantern']['anchor_px']
    check([sp['top_left_px'][i]+socket[i] for i in range(2)]==
          [lp['top_left_px'][i]+entries['bank_lantern.png']['anchor_px'][i] for i in range(2)],'Mount alignment')
    check(sp['collision_enabled'] and not lp['collision_enabled'],'One assembly collision owner')
    check(lp['depth_offset_m']>0,'No depth separation')
    return {'ok':not errors,'errors':errors,'density':96,'png_count':5,'palette_colors':128,
        'sprites':stats,'lamp_pedestal_width_ratio':wr,'lamp_pedestal_height_ratio':hr,
        'assembly_visible_height_px':b[3]-b[1],'normal_unit_max_error':error,
        'owner_visual_approval':m['owner_visual_approved']}
