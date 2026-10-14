"""Verify deferred packs preserve every exported byte and bootstrap offsets across code updates."""
from pathlib import Path
import argparse,json,struct,tempfile
from pack_layout import read_pack,split_pack,write_pack

def main():
 parser=argparse.ArgumentParser();parser.add_argument('pack',type=Path);parser.add_argument('source',type=Path);args=parser.parse_args()
 header,original=read_pack(args.pack)
 packs,manifest=split_pack(args.pack,args.source)
 restored={};boot=None
 with tempfile.TemporaryDirectory() as work:
  for group,raw in packs.items():
   path=Path(work)/f'{group}.pck';path.write_bytes(raw);_,members=read_pack(path)
   assert not set(restored)&set(members),group
   restored.update(members)
   if group=='boot':boot=members
  assert restored==original,'original resource bytes changed'
  assert set(manifest['resources'].values()) <= set(packs)-{'boot'}
  assert all(set(groups)<=set(packs)-{'boot'} for groups in manifest['enemies'].values())
  assert 'res://assets/heroes/tactical/raccoon_idle.png' not in manifest['resources']
  assert 'res://assets/enemies/razor_card.png' not in manifest['resources']
  def assets(raw):
   count=struct.unpack_from('<I',raw,96)[0];pos=100;out={}
   for _ in range(count):
    size=struct.unpack_from('<I',raw,pos)[0];pos+=4;name=raw[pos:pos+size].rstrip(b'\0').decode();pos+=size
    offset,length=struct.unpack_from('<QQ',raw,pos);pos+=36
    if name.startswith(('.godot/imported/','assets/')):out[name]=(offset,length)
   return out
  before=write_pack(header,boot,1048576)
  changed=dict(boot);changed['scripts/aaa-new-code.gdc']=b'code'*128
  after=write_pack(header,changed,1048576)
  assert assets(before)==assets(after),'code update moved assets'
  assert before[1048576:1048576+max(o+s for o,s in assets(before).values())]==after[1048576:1048576+max(o+s for o,s in assets(after).values())]
 print('PACK_LAYOUT_OK',json.dumps({'files':len(original),'groups':len(packs),'bootBytes':len(packs['boot']),'fullBytes':args.pack.stat().st_size,'byteExact':True,'stableAssets':True}))
if __name__=='__main__':main()
