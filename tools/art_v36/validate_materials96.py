"""Check new families and explicitly tagged legacy surfaces independently."""
import hashlib
import itertools
import json
import numpy as np
from PIL import Image

REQUESTED={'cobble_gold','cobble_worn','rose_path','marble','lawn','stone_wall','step_riser'}


def validate(root):
    errors=[]
    def require(ok,message):
        if not ok:errors.append(message)
    folder=root/'materials';m=json.loads((folder/'manifest.json').read_text());groups={};normals={};stats={}
    palette=np.array(Image.open(root/'palettes/materials96.png').convert('RGB'))
    colors=set(map(tuple,palette.reshape(-1,3)))
    require(palette.shape==(1,128,3) and len(colors)==128,'128 distinct material colors')
    require(set(m['requested_materials'])==REQUESTED,'Seven requested families')
    names=set();legacy=[]
    for f in m['files']:
        name=f['file'];p=folder/name
        require(name not in names,'Duplicate '+name);names.add(name)
        with Image.open(p) as probe:probe.verify()
        im=Image.open(p).convert('RGB');a=np.array(im)
        require(hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256'],name+': SHA')
        require(p.stat().st_size==f['bytes'],name+': bytes')
        density=f['pixels_per_metre'];size=192 if density==96 else 96
        require(im.size==(size,size) and [f['width'],f['height']]==[size,size],name+': dimensions')
        require(f['size_m']==[2.,2.],name+': 2x2m footprint')
        require(f['anchor_px']==[0,0] and f['anchor_uv']==[0.,0.],name+': UV origin')
        if density==48:
            require(f['material'] in {'plaster','roof_red','garden_soil'} and f['delivery_status']=='legacy_48_not_migrated',name+': unmarked legacy')
            legacy.append(name);continue
        require(f['material'] in REQUESTED,name+': unexpected96 family')
        if f['role']=='albedo':
            require(set(map(tuple,a.reshape(-1,3)))<=colors,name+': outside material palette')
            require(f['resampled_from_concept'] is True,name+': provenance')
            rgba=np.array(Image.open(p).convert('RGBA'))
            require(np.all(rgba[:,:,3]==255),name+': nonopaque surface')
            require(len(np.unique(a[:,:4].reshape(-1,3),axis=0))>=10,name+': flat artificial seam strip')
            groups.setdefault(f['material'],[]).append((f,a))
        else:
            n=a/255*2-1
            require(np.max(abs(np.linalg.norm(n,axis=2)-1))<.008,name+': non-unit normal')
            require(n[:,:,2].min()>.95,name+': excessive/inverted relief')
            normals.setdefault(f['material'],[]).append((f,a))
    pairs=0;npairs=0
    for material in REQUESTED:
        files=groups.get(material,[]);normal=normals.get(material,[])
        require(len(files)==len(normal)==3,material+': three albedo+normal variants')
        require(len({f['sha256'] for f,a in files})==3,material+': duplicate variants')
        for bucket in (files,normal):
            for (af,a),(bf,b) in itertools.product(bucket,repeat=2):
                require(np.array_equal(a[:,-1],b[:,0]),'X seam '+af['file']+'/'+bf['file'])
                require(np.array_equal(a[-1],b[0]),'Y seam '+af['file']+'/'+bf['file'])
                if bucket is files:pairs+=2
                else:npairs+=2
        means=[];contrast=[]
        for f,a in files:
            luma=a[:,:,0]*.299+a[:,:,1]*.587+a[:,:,2]*.114
            means.append(round(float(luma.mean()),3));contrast.append(round(float(luma.std()),3))
            require(luma.std()<35,f['file']+': excessive ground contrast')
            if material=='lawn':
                mean=a.mean(axis=(0,1));require(mean[1]>mean[0]*1.10 and mean[1]>mean[2]*1.3,f['file']+': not living green')
            if material=='marble':require(luma.mean()>195,f['file']+': marble too dark')
        stats[material]={'variants':3,'mean_luma':means,'luma_std':contrast}
    require(names=={p.name for p in folder.glob('*.png')},'Unlisted or missing PNG')
    return {'ok':not errors,'errors':errors,'density':96,'requested_family_count':7,
        'new_png_count':42,'legacy_png_count':len(legacy),'legacy_families_pending_96':m['legacy_materials_pending_96'],
        'checked_png':len(names),'edge_pair_checks':pairs,'normal_edge_pair_checks':npairs,
        'palette_colors':128,'materials':stats,'owner_visual_approved':m['owner_visual_approved']}
