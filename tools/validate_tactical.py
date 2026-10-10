#!/usr/bin/env python3
"""Validate delivered v32 hero PNGs, manifests and imported clip geometry."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib
from PIL import Image

COUNTS = {'idle': 8, 'run': 8, 'shoot': 4, 'hit': 4, 'dash': 6,
          'death': 8, 'revive': 6, 'idle_fidget': 8}


def png(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    offset = 8
    ended = False
    while offset < len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        end = offset + length + 12
        assert end <= len(data), (path, 'truncated chunk')
        chunk = data[offset+4:offset+8]
        checksum = struct.unpack_from('>I', data, end-4)[0]
        assert zlib.crc32(data[offset+4:end-4]) & 0xffffffff == checksum, (path, 'CRC')
        offset = end
        if chunk == b'IEND':
            ended = True
            break
    assert ended and offset == len(data), (path, 'missing IEND or trailing bytes')
    with Image.open(path) as image:
        image.verify()
    with Image.open(path) as image:
        image.load()
        return image.size


def validate(hero):
    root = Path('astra/inbox/story/heroes_tactical') / hero
    manifest = json.loads((root / 'manifest.json').read_text())
    assert manifest['clips'] == COUNTS, hero
    listed = {item['path'] for item in manifest['assets']}
    assert listed == {str(p.relative_to(root)) for p in root.rglob('*.png')}, hero
    assert len(listed) == 32, hero
    for item in manifest['assets']:
        path = root / item['path']
        assert png(path) == (item['width'], item['height']), path
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], path
        if 'frames' in item:
            with Image.open(path) as image:
                assert image.mode == 'RGBA', path
                for index in range(item['frames']):
                    x, y = index % 4 * 480, index // 4 * 320
                    cell = image.crop((x, y, x+480, y+320))
                    bounds = cell.getbbox()
                    assert bounds and bounds[0] >= 8 and bounds[1] >= 8 and bounds[2] <= 472 and bounds[3] <= 312, (path, index, bounds)
                for index in range(item['frames'], image.width//480 * (image.height//320)):
                    x, y = index % 4 * 480, index // 4 * 320
                    assert image.crop((x, y, x+480, y+320)).getbbox() is None, (path, 'unused cell')
    for clip, count in COUNTS.items():
        name = 'fidget' if clip == 'idle_fidget' else clip
        path = Path('source/assets/heroes/tactical') / f'{hero}_{name}.png'
        assert png(path) == (1200, ((count+3)//4)*200), path
    grip = json.loads((Path('source/data') / f'grip_{hero}.json').read_text())
    for clip in ('idle', 'run', 'shoot'):
        assert len(grip[clip]) == COUNTS[clip], (hero, clip)
        assert all(len(frame) == 4 for frame in grip[clip]), (hero, clip)
    print(f'{hero}: 32 PNGs, CRC/IEND, grid, padding and game clips OK')


if __name__ == '__main__':
    for hero in sys.argv[1:] or ['neon_hopper', 'fluffy_chemist', 'pigeon_mafioso', 'sniper_f', 'medic_f']:
        validate(hero)
