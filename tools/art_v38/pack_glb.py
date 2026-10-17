#!/usr/bin/env python3
"""Pack geometry into GLB; keep PNG image URIs external as required by v37."""
import argparse
import json
import shutil
import struct
from pathlib import Path
from urllib.parse import unquote

def main():
    p=argparse.ArgumentParser();p.add_argument('gltf',type=Path);p.add_argument('out',type=Path);a=p.parse_args()
    g=json.loads(a.gltf.read_text());assert len(g['buffers'])==1
    binary=(a.gltf.parent/unquote(g['buffers'][0]['uri'])).read_bytes();g['buffers'][0].pop('uri')
    a.out.mkdir(parents=True,exist_ok=True)
    for im in g['images']:
        assert 'uri' in im and not im['uri'].startswith('data:'),'Embedded image rejected'
        src=(a.gltf.parent/unquote(im['uri'])).resolve();assert src.suffix.lower()=='.png'
        target=a.out/src.name
        if src!=target:shutil.copy2(src,target)
        im['uri']=src.name;im.pop('mimeType',None)
    for m in g.get('materials',[]):
        name=m.get('name','')
        if name in ('Bank_Ivy','Bank_Crowned_Pig_Crest'):
            m.update(alphaMode='MASK',alphaCutoff=.5,doubleSided=True)
        if 'emissiveTexture' in m:m['emissiveFactor']=[0,0,0]
    for s in g.get('samplers',[]):s.update(magFilter=9728,minFilter=9728,wrapS=10497,wrapT=10497)
    encoded=json.dumps(g,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    binary+=b'\0'*((-len(binary))%4)
    raw=struct.pack('<4sII',b'glTF',2,12+8+len(encoded)+8+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary
    (a.out/'bank_hall.glb').write_bytes(raw)
    print('BANK38_GLB_PACKED',len(raw),'bytes;',len(g['images']),'external PNG images')
if __name__=='__main__':main()
