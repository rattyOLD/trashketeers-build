#!/usr/bin/env python3
"""Separate reviewed full-body drawings into registered tactical animation layers."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label, find_objects, binary_dilation
from numpy.lib.stride_tricks import sliding_window_view

ROOT = Path(__file__).resolve().parents[1]
COUNTS = {'idle': 8, 'run': 8, 'shoot': 4, 'hit': 4, 'dash': 6, 'death': 8, 'revive': 6, 'idle_fidget': 8}


def isolated(image):
    image = image.convert('RGBA')
    alpha = np.asarray(image.getchannel('A'))
    labels, count = label(alpha > 160)
    sizes = np.bincount(labels.ravel()); sizes[0] = 0
    if not count:
        raise ValueError('empty illustration')
    mask = binary_dilation(labels == sizes.argmax(), iterations=2)
    image.putalpha(Image.fromarray(np.where(mask, np.clip((alpha.astype(float) - 20) * 255 / 220, 0, 255), 0).astype('uint8')))
    return image


def figures(path, row_counts, take_first=False):
    image = Image.open(path).convert('RGBA')
    labels, _ = label(np.asarray(image.getchannel('A')) > 160)
    sizes = np.bincount(labels.ravel())
    parts = [(index+1, bounds) for index, bounds in enumerate(find_objects(labels)) if sizes[index+1] > 5000]
    parts.sort(key=lambda part: (part[1][0].start + part[1][0].stop) / 2)
    if take_first:
        parts = parts[:sum(row_counts)]
    assert len(parts) == sum(row_counts), (path, len(parts), row_counts)
    result = []; offset = 0
    for count in row_counts:
        row = sorted(parts[offset:offset+count], key=lambda part: part[1][1].start)
        offset += count
        for ident, bounds in row:
            mask = binary_dilation(labels == ident, iterations=2)
            tile = image.copy()
            tile.putalpha(Image.fromarray(np.where(mask, np.asarray(image.getchannel('A')), 0).astype('uint8')))
            result.append(isolated(tile).crop(tile.getbbox()))
    return result


def sheet(frames):
    output = Image.new('RGBA', (1920, math.ceil(len(frames)/4)*320))
    for i, frame in enumerate(frames):
        output.alpha_composite(frame, (i%4*480, i//4*320))
    return output


def body_frame(image, scale):
    image = image.resize(tuple(round(n*scale) for n in image.size), Image.Resampling.LANCZOS)
    assert image.width <= 440 and image.height <= 292, image.size
    output = Image.new('RGBA', (480, 320))
    output.alpha_composite(image, ((480-image.width)//2, 300-image.height))
    return output


def socket(frame, reference, point):
    x, y = point
    template = np.asarray(reference)[y-7:y+8, x-7:x+8, :3].astype(float)
    bounds = (max(8,x-45), max(8,y-40), min(471,x+45), min(311,y+40))
    xmin, ymin, xmax, ymax = bounds
    area = np.asarray(frame)[ymin-7:ymax+8, xmin-7:xmax+8, :3].astype(float)
    windows = sliding_window_view(area, (15,15), axis=(0,1))
    error = ((windows - template.transpose(2,0,1))**2).mean(axis=(2,3,4))
    iy, ix = np.unravel_index(error.argmin(), error.shape)
    return np.array([xmin+ix, ymin+iy], float)


def package(config):
    hero = config['id']
    target = ROOT / 'astra/inbox/story/heroes_tactical' / hero
    (target/'ui').mkdir(parents=True, exist_ok=True)
    raw = figures(config['body'], [4]*5)
    scale = 270 / np.median([tile.height for tile in raw[:8]])
    bodies = [body_frame(tile, scale) for tile in raw]
    reference = bodies[16]
    master = isolated(Image.open(config['master']))
    scale_arm = 270 / (master.getbbox()[3] - master.getbbox()[1])
    guides = {'convention': 'right=near trigger hand (rearhand); left=far support hand (fronthand)', 'arms': {}, 'frames': {}}
    arms = {}
    for name in ['right', 'left']:
        arm = config['arms'][name]
        mask = Image.new('L', master.size)
        ImageDraw.Draw(mask).polygon([tuple(p) for p in arm['polygon']], fill=255)
        pixels = np.asarray(master).copy()
        pixels[...,3] = (pixels[...,3].astype(float)*np.asarray(mask)/255).astype('uint8')
        image = Image.fromarray(pixels); bounds = image.getbbox(); image = image.crop(bounds)
        points = np.array(arm['joints'], float) - np.array(bounds[:2])
        size = tuple(round(n*scale_arm) for n in image.size)
        points *= np.array(size)/np.array(image.size)
        image = image.resize(size, Image.Resampling.LANCZOS)
        root = np.array(config['socket'], float) + (np.array(config['far_offset'], float) if name == 'left' else 0)
        offset = np.round(root - points[0]).astype(int); points += offset
        output = Image.new('RGBA', (480,320)); output.alpha_composite(image, tuple(offset))
        arms[name] = output
        guides['arms'][name] = {key: point.round(2).tolist() for key, point in zip(['shoulder','elbow','palm'], points)}
    yy, xx = np.mgrid[:320,:480]
    for clip, indexes in [('idle',range(8)), ('run',range(8,16)), ('shoot',range(16,20))]:
        parts = {'body_nohands': [], 'rearhand': [], 'fronthand': [], 'full': []}
        points = []
        for i in indexes:
            near = socket(bodies[i], reference, config['socket'])
            far_offset = config.get('far_offsets', {}).get(clip, config['far_offset'])
            roots = {'right': near, 'left': near+np.array(far_offset,float)}
            layers = {}
            for name, suffix in [('right','rearhand'),('left','fronthand')]:
                delta = np.round(roots[name]-guides['arms'][name]['shoulder']).astype(int)
                shifted = Image.new('RGBA',(480,320)); shifted.alpha_composite(arms[name],tuple(delta))
                layers[name] = shifted; parts[suffix].append(shifted)
            full = layers['left'].copy(); full.alpha_composite(bodies[i])
            shoulder, elbow, palm = np.array([guides['arms']['left'][k] for k in ['shoulder','elbow','palm']])
            elbow += roots['left']-shoulder
            direction = palm-np.array(guides['arms']['left']['elbow']); direction /= np.linalg.norm(direction)
            lower = np.asarray(layers['left']).copy()
            lower[...,3] = (lower[...,3]*np.clip(((xx-elbow[0])*direction[0]+(yy-elbow[1])*direction[1]+5)/3,0,1)).astype('uint8')
            full.alpha_composite(Image.fromarray(lower)); full.alpha_composite(layers['right'])
            parts['full'].append(full); parts['body_nohands'].append(bodies[i])
            points.append({name: point.round(2).tolist() for name,point in roots.items()})
        guides['frames'][clip] = points
        for name, frames in parts.items():
            suffix = '' if name == 'full' else name+'_'
            sheet(frames).save(target/f'{hero}_{suffix}{clip}.png', optimize=True)
    (target/'joint_guides.json').write_text(json.dumps(guides,indent=2)+'\n')
    reactions = figures(config['reactions'], [4]*config.get('reaction_rows', 8), config.get('reaction_rows', 8) < 8)
    reaction_scale = 270 / np.median([tile.height for tile in reactions[22:24]])
    indexes = {'hit': (0,4), 'dash': (4,10), 'death': (10,18), 'revive': (18,24), 'idle_fidget': (24,32)}
    if config.get('fidget'):
        reactions[24:32] = figures(config['fidget'], [4,4])
    fidget_scale = 270 / np.median([tile.height for tile in reactions[24:32]])
    for clip,(start,end) in indexes.items():
        frames = []
        for tile in reactions[start:end]:
            factor = min(fidget_scale if clip == 'idle_fidget' else reaction_scale, 440/tile.width, 292/tile.height)
            frames.append(body_frame(tile, factor))
        sheet(frames).save(target/f'{hero}_{clip}.png', optimize=True)
    ui = figures(config['ui'], [4,4,4,3])
    names = [hero,'face_hit','face_angry','face_grin','face_proud','face_scared','face_tired','win_0','win_1','lose_0','lose_1']+[f'hud_{hero}_{n}' for n in range(4)]
    for name,tile in zip(names,ui):
        tile.thumbnail((468,468),Image.Resampling.LANCZOS)
        output = Image.new('RGBA',(512,512)); output.alpha_composite(tile,((512-tile.width)//2,(512-tile.height)//2))
        output.save(target/'ui'/f'{name}.png',optimize=True)
    assets = []
    for path in sorted(target.rglob('*.png')):
        with Image.open(path) as image:
            record = {'path': str(path.relative_to(target)), 'width': image.width, 'height': image.height,
                'background': 'transparent', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.parent == target:
            clip = next(c for c in COUNTS if path.stem.endswith('_'+c))
            record.update(cellWidth=480,cellHeight=320,columns=4,frames=COUNTS[clip],frameOrder='left-to-right top-to-bottom')
        assets.append(record)
    manifest = {'hero':hero,'brief':'v32 section 8 / v21','cellWidth':480,'cellHeight':320,'columns':4,'clips':COUNTS,
        'layerOrder':['fronthand','body_nohands','rearhand'],'farForearmInFront':True,'assets':assets}
    (target/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    from import_v32_art import manifest as ui_manifest
    ui_manifest(target/'ui')
    print(hero,'packed',len(assets),'PNG files with registered shoulder sockets')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('config',type=Path)
    package(json.loads(parser.parse_args().config.read_text()))
