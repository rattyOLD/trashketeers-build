"""Pack reviewed 4x8 boss drawings with registered feet and isolated alpha gutters."""
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, find_objects, label

ROOT = Path(__file__).resolve().parents[1]
PAD = 10
ATLAS_WIDTH = 2048
WORLD_HEIGHT = {'overlord': 234.0, 'magnate': 269.28}
SOCKETS = {
    'overlord': [
        (265, 73), (518, 73), (772, 73), (1015, 72),
        (271, 267), (522, 270), (781, 267), (1020, 266),
        (268, 472), (528, 480), (775, 475), (1015, 485),
    ],
    'magnate': [
        (236, 88), (491, 89), (751, 86), (997, 87),
        (244, 279), (506, 279), (763, 278), (1003, 279),
        (227, 462), (497, 462), (744, 460), (1009, 463),
        (256, 677), (487, 679), (755, 693), (1008, 688),
    ],
}


def figures(path):
    image = Image.open(path).convert('RGBA')
    pixels = np.asarray(image)
    labels, _ = label(pixels[..., 3] > 120)
    sizes = np.bincount(labels.ravel())
    bounds = find_objects(labels)
    main = [(index + 1, box) for index, box in enumerate(bounds) if sizes[index + 1] > 5000]
    assert len(main) == 32, (path, 'expected 32 separate figures', len(main))
    main.sort(key=lambda part: (part[1][0].start + part[1][0].stop) / 2)
    ordered = []
    for row in range(8):
        ordered.extend(sorted(main[row * 4:row * 4 + 4], key=lambda part: part[1][1].start))
    owners = {ident: index for index, (ident, _) in enumerate(ordered)}
    # Loose crowns, cartridges and small painted effects stay with their figure.
    for ident, box in enumerate(bounds, 1):
        if ident in owners or sizes[ident] < 3:
            continue
        distances = []
        for _, body in ordered:
            dx = max(body[1].start - box[1].stop, box[1].start - body[1].stop, 0)
            dy = max(body[0].start - box[0].stop, box[0].start - body[0].stop, 0)
            distances.append(dx * dx + dy * dy)
        index = int(np.argmin(distances))
        if distances[index] <= 24 * 24:
            owners[ident] = index
    lookup = np.full(len(sizes), -1, dtype=np.int32)
    for ident, index in owners.items():
        lookup[ident] = index
    ownership = lookup[labels]
    results = []
    for index, (_, body) in enumerate(ordered):
        row = index // 4
        baseline = float(np.median([part[1][0].stop for part in ordered[row * 4:row * 4 + 4]]))
        pivot_x = index % 4 * image.width / 4 + image.width / 8
        mask = binary_dilation(ownership == index, iterations=2) & (ownership < 0)
        mask |= ownership == index
        # Never take alpha from a neighboring main silhouette.
        output = pixels.copy()
        output[..., 3] = np.where(mask, pixels[..., 3], 0)
        tile = Image.fromarray(output)
        box = tile.getbbox()
        assert box is not None
        tile = tile.crop(box)
        results.append((tile, [round(pivot_x - box[0], 2), round(baseline - box[1], 2)], (pivot_x, baseline)))
    return results


def clips():
    def clip(indices, fps, loop=False):
        return {'frames': indices, 'fps': fps, 'loop': loop}
    return {
        'idle': clip([0, 1, 2, 3, 2, 1], 5, True),
        'run': clip([4, 5, 6, 7], 6, True),
        'windup': clip([8, 9], 6),
        'aim': clip([9], 1),
        'strike': clip([10, 11], 12),
        'hit': clip([12, 13], 16),
        'wreck': clip([14, 15], 4),
        'rain': clip([9, 10, 11], 8, True),
        'taunt': clip([24, 25, 24], 6, True),
        'p2_idle': clip([16, 17, 18, 19, 18, 17], 5, True),
        'p2_run': clip([20, 21, 22, 23], 8, True),
        'p2_windup': clip([24, 25], 6),
        'p2_hit': clip([26, 27], 16),
        'death': clip([28, 29, 30, 31], 6),
    }


def package(ident, metadata):
    items = figures(ROOT / 'tools/src/boss_motion_v57' / (ident + '.png'))
    x = y = PAD
    row_height = 0
    placements = []
    for image, _, _ in items:
        if x + image.width + PAD > ATLAS_WIDTH:
            x = PAD
            y += row_height + PAD * 2
            row_height = 0
        placements.append((x, y))
        x += image.width + PAD * 2
        row_height = max(row_height, image.height)
    height = 1 << (y + row_height + PAD - 1).bit_length()
    assert height <= 2048, (ident, height)
    atlas = Image.new('RGBA', (ATLAS_WIDTH, height))
    frames = []
    for (image, pivot, _), (x, y) in zip(items, placements):
        atlas.alpha_composite(image, (x, y))
        frames.append([x, y, image.width, image.height, *pivot])
    path = ROOT / 'source/assets/bosses' / (ident + '_frames.png')
    art_path = ROOT / 'source/data/enemy_art.json'
    art = json.loads(art_path.read_text())
    art['assets'][f'res://assets/bosses/{ident}_frames.png'] = {'density': 1, 'logical_size': [ATLAS_WIDTH, height]}
    art_path.write_text(json.dumps(art, ensure_ascii=False, indent=2) + '\n')
    atlas.save(path, optimize=True)
    sheet = metadata['sheets'][ident]
    old_height = sheet['frames'][0][3]
    new_height = float(np.median([image.height for image, _, _ in items[:4]]))
    sheet['frames'] = frames
    sheet['names'] = [f'{group}{i}' for group in ['idle', 'run', 'attack', 'reaction', 'p2_idle', 'p2_run', 'p2_attack', 'death'] for i in range(4)]
    sheet['clips'] = clips()
    if ident == 'overlord':
        sheet['clips']['hit']['frames'] = [8, 9]
    sockets = []
    for index, (_, _, origin) in enumerate(items):
        if index < len(SOCKETS[ident]):
            tip = SOCKETS[ident][index]
            right = [round(tip[0] - origin[0], 2), round(tip[1] - origin[1], 2)]
            left = [right[0] - 152, right[1] + 8] if ident == 'magnate' else right
            sockets.append([right, left, right])
        else:
            sockets.append([])
    sheet['muzzles'] = sockets
    enemies_path = ROOT / 'source/data/enemies.json'
    enemies = json.loads(enemies_path.read_text())
    for enemy in enemies['enemies']:
        if enemy.get('frames') == ident:
            enemy['sprite_scale'] = round(WORLD_HEIGHT[ident] / new_height, 5)
    enemies_path.write_text(json.dumps(enemies, ensure_ascii=False, indent=2) + '\n')
    print(ident, '32 frames', atlas.size, 'idle height', new_height, 'previous height', old_height)


def main():
    path = ROOT / 'source/data/frames.json'
    metadata = json.loads(path.read_text())
    for ident in ['overlord', 'magnate']:
        package(ident, metadata)
    path.write_text(json.dumps(metadata, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
