#!/usr/bin/env python3
"""Pack reviewed drawings into exact game sizes; never synthesize artwork."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, label

ROOT = Path(__file__).resolve().parents[1]
INBOX = ROOT / 'astra/inbox'
GAME = ROOT / 'source/assets'


def sprite(image, size, padding=0.06):
    image = image.convert('RGBA')
    alpha = np.asarray(image.getchannel('A'))
    components, count = label(alpha > 128)
    if count:
        areas = np.bincount(components.ravel())
        areas[0] = 0
        mask = binary_dilation(components == areas.argmax(), iterations=2)
        image.putalpha(Image.fromarray(np.where(mask, alpha, 0).astype('uint8')))
    bounds = image.getbbox()
    if bounds is None:
        raise ValueError('empty sprite')
    image = image.crop(bounds)
    image.thumbnail(tuple(round(n * (1 - padding * 2)) for n in size), Image.Resampling.LANCZOS)
    output = Image.new('RGBA', size)
    output.alpha_composite(image, ((size[0] - image.width) // 2, (size[1] - image.height) // 2))
    return output


def manifest(folder, geometry=None):
    path = folder / 'manifest.json'
    data = json.loads(path.read_text()) if path.exists() else {}
    records = {}
    for file in sorted(folder.glob('*.png')):
        with Image.open(file) as image:
            image.load()
            cell, frames = (geometry or {}).get(file.name, (image.size, 1))
            records[file.name] = {'size': list(image.size), 'cellSize': list(cell), 'frames': frames,
                'order': 'left-to-right, top-to-bottom', 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()}
    data.update({'version': 32, 'images': records})
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def deliver(image, folder, name, game_folder=None):
    target = INBOX / folder
    target.mkdir(parents=True, exist_ok=True)
    image.save(target / name, optimize=True)
    if game_folder:
        runtime = GAME / game_folder
        runtime.mkdir(parents=True, exist_ok=True)
        image.save(runtime / name, optimize=True)


def main(config):
    touched = set()
    for item in config:
        image = Image.open(item['source']).convert('RGBA')
        folder = item['folder']
        if item.get('grid'):
            columns, rows = item['grid']
            for index, name in enumerate(item['names']):
                column, row = index % columns, index // columns
                bounds = (round(column * image.width / columns), round(row * image.height / rows),
                    round((column + 1) * image.width / columns), round((row + 1) * image.height / rows))
                tile = sprite(image.crop(bounds), tuple(item['size']))
                deliver(tile, folder, name + '.png', item.get('game_folder'))
        elif item.get('strip'):
            columns = item['strip']
            size = tuple(item['size'])
            output = Image.new('RGBA', (columns * size[0], size[1]))
            for index in range(columns):
                tile = image.crop((round(index * image.width / columns), 0,
                    round((index + 1) * image.width / columns), image.height))
                if index == 0 and item.get('first_override'):
                    tile = Image.open(item['first_override'])
                output.alpha_composite(sprite(tile, size), (index * size[0], 0))
            deliver(output, folder, item['name'], item.get('game_folder'))
        elif item.get('layers'):
            for index, name in enumerate(item['layers']):
                tile = image.crop((0, round(index * image.height / len(item['layers'])), image.width,
                    round((index + 1) * image.height / len(item['layers']))))
                output = Image.new('RGBA', tuple(item['size']))
                tile = sprite(tile, (item['size'][0] - 64, item['size'][1] - 32), padding=0)
                output.alpha_composite(tile, (32, 32))
                deliver(output, folder, name + '.png', item.get('game_folder'))
        else:
            image = image.resize(tuple(item['size']), Image.Resampling.LANCZOS)
            deliver(image, folder, item['name'], item.get('game_folder'))
        touched.add(folder)
    for folder in touched:
        manifest(INBOX / folder, {'firmware_icons.png': ((128, 128), 8)} if folder.endswith('survival2') else None)
    print('V32_ART packed', len(config), 'drawings into', len(touched), 'folders')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('config', type=Path)
    main(json.loads(parser.parse_args().config.read_text()))
