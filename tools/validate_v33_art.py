#!/usr/bin/env python3
"""Validate the v33 art delivery without changing game assets. Requires Pillow."""
from pathlib import Path
import hashlib
import json
import struct
import zlib
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
INBOX = ROOT / 'astra/inbox'
GROUPS = {
    'maps/night_dump': {'floor.png': (512, 512), 'wear_atlas.png': (1024, 1024)},
    'world/lights': {'pool_fire.png': (256, 256), 'pool_lamp.png': (256, 256),
                     'pool_neon.png': (256, 128), 'reflect_neon_pink.png': (256, 128),
                     'reflect_neon_cyan.png': (256, 128)},
    'ui/boss_intro': {**{boss + '.png': (1024, 1024) for boss in (
        'junk_overlord', 'mud_magnate', 'beer_baron', 'pig_magnate',
        'electric_shaman', 'sea_pirate', 'chef_boss')}, 'stripe.png': (1920, 160)},
    'ui/hub/backdrop_fx': {'sign_on.png': (80, 64), 'sign_off.png': (80, 64),
                           'smoke.png': (512, 512), 'window_glow.png': None},
    'biome': {'ch2_floor.png': (1024, 512)},
}
BOSS_SHEETS = {'junk_overlord': 'overlord', 'mud_magnate': 'magnate', 'beer_baron': 'baron',
               'pig_magnate': 'pig_magnate', 'electric_shaman': 'shaman',
               'sea_pirate': 'sea_pirate', 'chef_boss': 'chef_boss'}

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def check_png(path):
    raw = path.read_bytes()
    require(raw[:8] == b'\x89PNG\r\n\x1a\n', str(path) + ': PNG signature')
    offset = 8
    while offset < len(raw):
        require(offset + 12 <= len(raw), str(path) + ': truncated chunk')
        size = struct.unpack_from('>I', raw, offset)[0]
        kind = raw[offset + 4:offset + 8]
        end = offset + 12 + size
        require(end <= len(raw), str(path) + ': truncated payload')
        expected = struct.unpack_from('>I', raw, end - 4)[0]
        require(zlib.crc32(raw[offset + 4:end - 4]) & 0xffffffff == expected, str(path) + ': CRC')
        offset = end
        if kind == b'IEND':
            require(offset == len(raw), str(path) + ': bytes after IEND')
            return
    raise AssertionError(str(path) + ': missing IEND')

def same_pixels(left, right, message):
    require(left.size == right.size and left.tobytes() == right.tobytes(), message)

def check_seams(image, axes, label):
    width, height = image.size
    if 'x' in axes:
        same_pixels(image.crop((0, 0, 1, height)), image.crop((width - 1, 0, width, height)), label + ': X seam')
    if 'y' in axes:
        same_pixels(image.crop((0, 0, width, 1)), image.crop((0, height - 1, width, height)), label + ': Y seam')

def check_clear_edges(image, label):
    alpha = image.getchannel('A')
    width, height = image.size
    for rectangle in [(0, 0, width, 1), (0, height - 1, width, height), (0, 0, 1, height), (width - 1, 0, width, height)]:
        require(alpha.crop(rectangle).getextrema()[1] == 0, label + ': cut alpha edge')

def rectangle(values):
    x, y, width, height = values
    return (x, y, x + width, y + height)

def validate():
    manifests = {}
    images = {}
    entries = {}
    count = 0
    for folder, expected in GROUPS.items():
        manifest = json.loads((INBOX / folder / 'manifest.json').read_text())
        manifests[folder] = manifest
        expected_brief = 'v34' if folder == 'biome' else 'v33'
        require(manifest['brief'] == expected_brief and manifest['alpha_mode'] == 'straight', folder + ': manifest version/alpha')
        require({entry['file'] for entry in manifest['files']} == set(expected), folder + ': file set')
        require(len(manifest['files']) == len(expected), folder + ': duplicate manifest file')
        for entry in manifest['files']:
            name = entry['file']
            path = INBOX / folder / name
            check_png(path)
            require(path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'], str(path) + ': manifest digest')
            with Image.open(path) as opened:
                opened.load()
                image = opened.copy()
            require(image.mode == 'RGBA', str(path) + ': expected RGBA PNG')
            require(image.size == (entry['width'], entry['height']), str(path) + ': manifest dimensions')
            if expected[name] is not None:
                require(image.size == expected[name], str(path) + ': brief dimensions')
            expected_frames = 4 if name == 'wear_atlas.png' else (32 if folder == 'biome' and name == 'ch2_floor.png' else 1)
            require(entry['frames'] == expected_frames, str(path) + ': frame count')
            if entry.get('opaque'):
                require(image.getchannel('A').getextrema() == (255, 255), str(path) + ': ground must be opaque')
            else:
                low, high = image.getchannel('A').getextrema()
                require(low == 0 and high > 0, str(path) + ': missing transparency/content')
            images[folder + '/' + name] = image
            entries[folder + '/' + name] = entry
            count += 1
    require(count == 20, 'expected 20 PNG files')
    ground = images['maps/night_dump/floor.png']
    bank = images['biome/ch2_floor.png']
    floor_luma = ImageStat.Stat(ground.convert('L')).mean[0]
    bank_luma = ImageStat.Stat(bank.convert('L')).mean[0]
    require(75 <= floor_luma <= 90, 'junkyard luminance outside 75–90')
    require(150 <= bank_luma <= 160, 'bank luminance outside 150–160')
    check_seams(ground, ['x', 'y'], 'floor')
    # Bank is an indexed 8×4 atlas, not a single seamless grass surface.
    bank_manifest = manifests['biome']
    atlas = bank_manifest['atlas']
    require([atlas['columns'], atlas['rows'], atlas['tile_width'], atlas['tile_height'], atlas['tiles']] == [8, 4, 128, 128, 32], 'bank: tile layout')
    require(atlas['whole_sheet_is_not_a_seamless_surface'], 'bank: full sheet must never be repeated as a ground texture')
    require(sha(ROOT / bank_manifest['source']['path']) == bank_manifest['source']['sha256'], 'bank: original source atlas changed; recheck tile mapping')
    materials = [('beige_paving', ['FLOOR']), ('olive_lawn', ['LAWN', 'EDGE']), ('rose_paving', ['LANE', 'GATE']), ('ivory_boss_plaza', ['BOSS'])]
    bank_rows = []
    for row, (material, zones) in enumerate(materials):
        info = atlas['row_materials'][row]
        require(info['row'] == row and info['material'] == material and info['zones'] == zones, 'bank: row material/zone mapping')
        require(info['rect'] == [0, row * 128, 1024, 128], 'bank: row rectangle')
        section = bank.crop(rectangle(info['rect'])).convert('RGB')
        luminance = ImageStat.Stat(section.convert('L')).mean[0]
        require(abs(luminance - info['mean_luminance_255']) < 0.01, 'bank: row luminance metadata')
        for column in range(8):
            tile = section.crop((column * 128, 0, (column + 1) * 128, 128))
            red, green, blue = ImageStat.Stat(tile).mean
            value = ImageStat.Stat(tile.convert('L')).mean[0]
            if row == 0:
                require(140 < value < 205 and red > green > blue and red - blue > 15, 'bank: beige paving replaced by another material')
            elif row == 1:
                require(75 < value < 135 and green > red + 8 and green > blue + 15, 'bank: lawn must remain living green')
            elif row == 2:
                require(125 < value < 180 and red > green + 20 and blue > green + 3, 'bank: rose paving replaced by grass/dirt')
            else:
                require(170 < value < 225 and red > blue and abs(red - green) < 25 and max(red, green, blue) - min(red, green, blue) < 55, 'bank: ivory paving replaced by grass/dirt')
        bank_rows.append({'row': row, 'material': material, 'luminance': round(luminance, 3)})
    bank_edge_pairs = 0
    for row in range(4):
        tiles = [bank.crop((column * 128, row * 128, (column + 1) * 128, (row + 1) * 128)) for column in range(8)]
        for a, tile_a in enumerate(tiles):
            for b, tile_b in enumerate(tiles):
                same_pixels(tile_a.crop((127, 0, 128, 128)), tile_b.crop((0, 0, 1, 128)), f'bank row {row} tiles {a}/{b}: horizontal seam')
                same_pixels(tile_a.crop((0, 127, 128, 128)), tile_b.crop((0, 0, 128, 1)), f'bank row {row} tiles {a}/{b}: vertical seam')
                bank_edge_pairs += 2
    require(bank_edge_pairs == 512, 'bank: incomplete tile adjacency coverage')
    wear = images['maps/night_dump/wear_atlas.png']
    for index in range(4):
        x, y = (index % 2) * 512, (index // 2) * 512
        tile = wear.crop((x, y, x + 512, y + 512))
        for edge in [(0, 0, 512, 1), (0, 511, 512, 512), (0, 0, 1, 512), (511, 0, 512, 512)]:
            same_pixels(tile.crop(edge), ground.crop(edge), 'wear variant must blend to base floor')
    for name, image in images.items():
        if name.startswith('world/lights/') or name.endswith('/stripe.png'):
            check_clear_edges(image, name)
    for name in ['pool_fire', 'pool_lamp', 'pool_neon']:
        image = images['world/lights/' + name + '.png']
        red, green, blue, _ = image.split()
        same_pixels(red, green, name + ': neutral mask R/G')
        same_pixels(red, blue, name + ': neutral mask R/B')
    smoke = images['ui/hub/backdrop_fx/smoke.png']
    check_seams(smoke, ['y'], 'smoke')
    require(smoke.getchannel('A').getextrema()[1] <= 90, 'steam must remain translucent')
    frames = json.loads((ROOT / 'source/data/frames.json').read_text())['sheets']
    densities = json.loads((ROOT / 'source/data/enemy_art.json').read_text())['assets']
    identity_results = {}
    for identity, sheet_id in BOSS_SHEETS.items():
        label = 'ui/boss_intro/' + identity + '.png'
        image, entry = images[label], entries[label]
        source = entry['source']
        sheet = frames[sheet_id]
        require(source['sheet_id'] == sheet_id and source['frame_index'] == 0, identity + ': wrong source identity')
        source_path = ROOT / source['path']
        require(source['path'] == 'source/' + sheet['texture'].removeprefix('res://'), identity + ': source path')
        require(sha(source_path) == source['sha256'], identity + ': source art changed')
        density = int(densities.get(sheet['texture'], {}).get('density', 1))
        physical = [int(value * density) for value in sheet['frames'][0][:4]]
        require(physical == source['physical_frame'], identity + ': source frame rectangle')
        require(entry['faces_repainted'] is False and entry['added_detail'] is False, identity + ': identity policy')
        clear = image.getchannel('A').crop(rectangle(entry['name_clear_area']))
        require(clear.getextrema()[1] == 0, identity + ': name area not clear')
        with Image.open(source_path) as original:
            frame = original.convert('RGBA').crop(rectangle(physical))
        cropped = frame.crop(rectangle(entry['frame_crop']))
        dx, dy, width, height = entry['destination']
        expected = cropped.resize((width, height), Image.Resampling.LANCZOS)
        actual = image.crop((dx, dy, dx + width, dy + height))
        fx, fy, fw, fh = entry['source_face_rect']
        cx, cy, cw, ch = entry['frame_crop']
        require(fx >= cx and fy >= cy and fx + fw <= cx + cw and fy + fh <= cy + ch, identity + ': face clipped')
        face = (round((fx - cx) * width / cw), round((fy - cy) * height / ch),
                round((fx + fw - cx) * width / cw), round((fy + fh - cy) * height / ch))
        expected_face, actual_face = expected.crop(face), actual.crop(face)
        mask = expected_face.getchannel('A').point(lambda value: 255 if value > 250 else 0)
        require(mask.getbbox() is not None, identity + ': empty face')
        # Independent Pillow resampling may differ slightly from Godot Lanczos.
        mean_error = ImageStat.Stat(ImageChops.difference(expected_face, actual_face), mask).mean
        require(max(mean_error) < 2.0, identity + ': face differs from original atlas')
        identity_results[identity] = [round(value, 4) for value in mean_error]
    menu = manifests['ui/hub/backdrop_fx']
    background_info = menu['background']
    background_path = ROOT / background_info['path']
    require(sha(background_path) == background_info['sha256'], 'menu background changed')
    with Image.open(background_path) as opened:
        background = opened.convert('RGBA')
    require(list(background.size) == background_info['size'], 'menu coordinate space')
    on = images['ui/hub/backdrop_fx/sign_on.png']
    off = images['ui/hub/backdrop_fx/sign_off.png']
    same_pixels(on.getchannel('A'), off.getchannel('A'), 'on/off must share registration mask')
    require(ImageChops.difference(on, off).convert('RGB').getbbox() is not None, 'on/off states identical')
    for name in ['sign_on', 'sign_off', 'window_glow', 'smoke']:
        entry = entries['ui/hub/backdrop_fx/' + name + '.png']
        x, y, width, height = entry['background_rect']
        require(x >= 0 and y >= 0 and width > 0 and height > 0 and x + width <= background.width and y + height <= background.height, name + ': background coordinates')
        if name in ['sign_on', 'window_glow']:
            image = images['ui/hub/backdrop_fx/' + name + '.png']
            reference = background.crop((x, y, x + width, y + height))
            mask = image.getchannel('A').point(lambda value: 255 if value > 0 else 0)
            difference = ImageChops.difference(image.convert('RGB'), reference.convert('RGB'))
            require(max(ImageStat.Stat(difference, mask).mean) == 0, name + ': pixel registration/color drift')
    return {'brief': 'v33', 'png_files': count, 'manifests': len(manifests), 'png_crc_iend': 'OK',
            'dimensions_and_sha256': 'OK', 'floor_luminance': round(floor_luma, 3),
            'bank_luminance': round(bank_luma, 3), 'bank_tile_layout': '8x4 / 128x128', 'bank_material_rows': bank_rows, 'bank_edge_pairs': bank_edge_pairs,
            'bank_revision': 'v34', 'bank_max_edge_difference_rgba8': 0,
            'tile_seams': 'whole-sheet floor/smoke; Bank 512 within-row tile pairings', 'wear_edges_match_base': True,
            'portrait_original_faces': identity_results, 'menu_registration': 'OK',
            'game_integration': 'v33 integrated upstream; Bank v34 awaits Claude integration', 'physical_devices_tested': False}

if __name__ == '__main__':
    result = validate()
    print('V33_ART_OK ' + json.dumps(result, ensure_ascii=False, sort_keys=True))
