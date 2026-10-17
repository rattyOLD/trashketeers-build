#!/usr/bin/env python3
"""Independent glTF contract: external images, metric UVs, bounds and budget."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import numpy as np
from PIL import Image

def read_glb(path):
    raw=path.read_bytes();magic,version,length=struct.unpack_from('<4sII',raw)
    assert magic==b'glTF' and version==2 and length==len(raw)
    size,kind=struct.unpack_from('<I4s',raw,12);assert kind==b'JSON'
    g=json.loads(raw[20:20+size]);off=20+size;n,k=struct.unpack_from('<I4s',raw,off);assert k==b'BIN\0'
    return g,raw[off+8:off+8+n]

def validate(folder,budget=6000):
    g,binary=read_glb(folder/'bank_hall.glb')
    def accessor(index):
        a=g['accessors'][index];view=g['bufferViews'][a['bufferView']]
        dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
        size={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        item=np.dtype(dtype).itemsize;stride=view.get('byteStride',size*item)
        return np.ndarray((a['count'],size),dtype=dtype,buffer=binary,offset=view.get('byteOffset',0)+a.get('byteOffset',0),strides=(stride,item))
    png={}
    for im in g['images']:
        assert 'uri' in im and 'bufferView' not in im and not im['uri'].startswith('data:')
        p=folder/im['uri'];assert p.is_file() and p.suffix=='.png';assert p.parent==folder
        png[im['uri']]=np.array(Image.open(p).convert('RGBA'))
    assert len(png)>=10
    for name,a in png.items():
        if name.endswith('_n.png'):
            n=a[:,:,:3].astype(float)/255*2-1;assert abs(np.linalg.norm(n,axis=2)-1).max()<.015,name
            assert n[:,:,2].min()>.8,name
        elif name.endswith('_glow.png'):
            assert np.array_equal(a[:,:,0],a[:,:,1]) and np.array_equal(a[:,:,1],a[:,:,2]),name
        else:assert set(np.unique(a[:,:,3]))<={0,255},name
    palette_path=folder/'bank_palette.png'
    if palette_path.exists():
        palette=set(map(tuple,np.array(Image.open(palette_path).convert('RGB')).reshape(-1,3)))
        assert len(palette)==128
        for name,a in png.items():
            if not name.endswith(('_n.png','_glow.png')):
                assert set(map(tuple,a[:,:,:3][a[:,:,3]>0]))<=palette,('Shared128-color palette',name)
    manifest_path=folder/'manifest.json'
    if manifest_path.exists():
        manifest=json.loads(manifest_path.read_text())
        for f in manifest['files']:
            path=folder/f['file'];assert hashlib.sha256(path.read_bytes()).hexdigest()==f['sha256'],('Manifest SHA',path)
            assert path.stat().st_size==f['bytes'],('Manifest bytes',path)
    assert png['bank_trim.png'].shape==(1024,1024,4)
    for name in ['bank_plaster.png','bank_masonry.png','bank_roof.png','bank_glass.png']:
        assert png[name].shape==(192,192,4),name
        assert np.array_equal(png[name][:,0],png[name][:,-1]),('Texture X seam',name)
        assert np.array_equal(png[name][0],png[name][-1]),('Texture Y seam',name)
    for name in ['bank_plaster_n.png','bank_masonry_n.png','bank_roof_n.png']:
        assert np.array_equal(png[name][:,0],png[name][:,-1]),('Normal X seam',name)
        assert np.array_equal(png[name][0],png[name][-1]),('Normal Y seam',name)
    assert np.count_nonzero(png['bank_trim_glow.png'][:,:,:3])==256*256*3
    assert np.all(png['bank_trim_glow.png'][256:512,768:1024,:3]==255)
    assert np.all(png['bank_glass_glow.png'][:,:,:3]==255)
    assert all(s['magFilter']==9728 and s['minFilter']==9728 for s in g['samplers'])
    triangles=0;positions=[];densities=[];per_material={};cutout_samples=[]
    for mesh in g['meshes']:
        for p in mesh['primitives']:
            xyz=accessor(p['attributes']['POSITION']).astype(float);uv=accessor(p['attributes']['TEXCOORD_0']).astype(float)
            idx=accessor(p['indices']).reshape(-1,3);triangles+=len(idx);positions.append(xyz)
            mat=g['materials'][p['material']];name=mat['name'];per_material[name]=per_material.get(name,0)+len(idx)
            image_index=g['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source']
            image_name=g['images'][image_index]['uri'];h,w=png[image_name].shape[:2]
            a,b,c=xyz[idx[:,0]],xyz[idx[:,1]],xyz[idx[:,2]]
            world=np.linalg.norm(np.cross(b-a,c-a),axis=1)/2
            u=uv*np.array([w,h]);ua,ub,uc=u[idx[:,0]],u[idx[:,1]],u[idx[:,2]]
            tex=np.abs((ub[:,0]-ua[:,0])*(uc[:,1]-ua[:,1])-(ub[:,1]-ua[:,1])*(uc[:,0]-ua[:,0]))/2
            valid=(world>1e-8)&(tex>1e-6)
            assert np.all(tex[world>1e-8]>1e-6),('Missing/degenerate UV faces',name)
            d=np.sqrt(tex[valid]/world[valid])
            if name in ('Bank_Ivy','Bank_Crowned_Pig_Crest'):
                assert mat['alphaMode']=='MASK' and mat['alphaCutoff']==.5
                cutout_samples.extend(d.tolist())
            else:densities.extend(d.tolist())
            if 'emissiveTexture' in mat:assert mat['emissiveFactor']==[0,0,0],('Day emission must default off',name)
    assert 3000<=triangles<=budget,triangles
    d=np.array(densities);assert d.min()>95 and d.max()<97,('Metric UV density',d.min(),d.max())
    cut=np.array(cutout_samples);assert cut.min()>90 and cut.max()<98,('Cutout projection density',cut.min(),cut.max())
    pts=np.vstack(positions);lo=pts.min(axis=0);hi=pts.max(axis=0)
    # Exported model is Y-up, feet/base at Y0, ridgeY10.5, front positiveZ.
    assert abs(lo[1])<1e-5 and abs(hi[1]-10.5)<1e-5,(lo,hi)
    assert 16<=hi[0]-lo[0]<=17.5 and 8<=hi[2]-lo[2]<=9.8
    return dict(ok=True,triangles=triangles,materials=len(g['materials']),meshes=len(g['meshes']),external_png=len(png),
        bounds_m=[lo.tolist(),hi.tolist()],uv_texels_per_metre=[float(d.min()),float(d.max())],
        cutout_projected_density=[float(cut.min()),float(cut.max())],nearest_filter=True,day_emission_off=True,
        material_triangles=per_material,glb_sha256=hashlib.sha256((folder/'bank_hall.glb').read_bytes()).hexdigest())

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--report',type=Path);p.add_argument('--budget',type=int,default=6000);a=p.parse_args()
    r=validate(a.folder,a.budget)
    if a.report:a.report.write_text(json.dumps(r,indent=2)+'\n')
    print('BANK38_CONTRACT_OK',json.dumps(r))
