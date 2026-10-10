#!/usr/bin/env python3
"""Check the complete v32 delivery, PNG integrity and per-folder manifests."""
import hashlib
import json
from pathlib import Path
from validate_tactical import png, validate


def check(folder, names, size):
    root = Path('astra/inbox')/folder
    manifest = json.loads((root/'manifest.json').read_text())
    images = manifest.get('images',{})
    for name in names:
        path=root/(name+'.png')
        assert png(path)==size,(path,size)
        if name+'.png' in images:
            assert images[name+'.png']['sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),path
    return len(names)


if __name__=='__main__':
    total=0
    total+=check('story/diary',[f'diary_{i:02}' for i in range(1,7)],(960,540))
    total+=check('story/backdrops',[f'm{i}_mid' for i in [1,3,4,5,6]],(2048,512))
    total+=check('story/enemies2',[f'{id}_{clip}_sheet' for id in ['chef','trash_sea_pirate'] for clip in ['walk_a','walk_b','combat']],(3072,1024))
    total+=check('ui/chests_v2',[id+suffix for id in ['free','common','rare','epic','legendary','cosmetic'] for suffix in ['','_open']],(256,256))
    for orientation,size in [('landscape',(1920,1080)),('portrait',(1080,1920))]:
        total+=check('story/loading',[f'bg_{id}_{orientation}' for id in ['acid','vault','ice','roofs']],size)
    total+=check('story/portraits3',[id+suffix for id in ['snyr','deputy','pigguard','clerk','agent'] for suffix in ['','_alt']],(512,512))
    total+=check('world/survival2',['firmware_icons'],(1024,128))
    total+=check('ui/ascension',[f'tier_{i}' for i in range(1,11)],(128,128))
    total+=check('ui/ascension',['elite_fast','elite_armored','elite_explosive'],(128,64))
    total+=check('ui/patches',['fist','bullet','boot','heart','magnet','clover','rat','bolt','gear','skull','mug','star','slot_empty','slot_locked'],(128,128))
    total+=check('ui/rewards',['boost_coins','boost_pass','title_plate','nick_color'],(256,256))
    for hero in ['neon_hopper','fluffy_chemist','pigeon_mafioso','sniper_f','medic_f']:
        validate(hero);total+=32
    for id in ['beer','confetti','dust','ice']:
        for file,size in [('burst',(768,128)),('bit',(32,32)),('trail',(256,64))]:
            total+=check(f'cosmetics/dash/{id}',[file],size)
    total+=check('story/scars',[f'scar_{id}' for id in ['brow','cracked_cap','eye_patch','nose_plaster','torn_ear']],(512,512))
    print(f'V32_ART OK: {total} PNG files, dimensions, CRC/IEND, manifests and imported hero grids')
