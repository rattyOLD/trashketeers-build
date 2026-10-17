#!/usr/bin/env python3
"""Check paired captures from qa_plaza.py; no claim of artistic approval."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    args = parser.parse_args()
    root = args.project
    log = (root / 'render.log').read_text()
    assert 'V36_PLAZA_REVIEW_OK' in log
    assert 'ERROR:' not in log and 'SCRIPT ERROR' not in log, log
    files = {}
    pixels = {}
    for name in ('day', 'evening', 'day_flat', 'evening_flat', 'day_no_shadow'):
        path = root / f'plaza_sample_{name}.png'
        image = Image.open(path).convert('RGB')
        assert image.size == (1280, 720)
        pixels[name] = np.asarray(image).astype(np.int16)
        files[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    comparisons = {}
    for name, other in (('day', 'day_flat'), ('evening', 'evening_flat'), ('day', 'day_no_shadow')):
        delta = np.max(abs(pixels[name] - pixels[other]), axis=2)
        yy, xx = np.where(delta > 1)
        assert len(xx) > 100, f'No measurable effect: {name}/{other}'
        box = [int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max())]
        # Character and contact shadow in the declared close-up camera.
        assert box[0] >= 700 and box[1] >= 340 and box[2] <= 970 and box[3] <= 560, box
        if other.endswith('_flat'):
            assert delta.max() < 32, 'Normals overwhelm the albedo'
        else:
            assert delta.max() > 8, 'No meaningful engine-cast contact shadow'
        comparisons[f'{name}/{other}'] = {'changed_pixels_above_1': len(xx),
            'bounds_inclusive': box, 'max_channel_delta': int(delta.max())}
    result = {'ok': True, 'godot': '4.4.1.stable.official.49a5bc7b6',
        'renderer': 'Compatibility / Mesa llvmpipe software OpenGL 4.5',
        'source_modified': False, 'scope': 'static single idle in actual Bank prototype copy',
        'postprocess': 'prototype screen-mip focus blur, glow and color grade; not physical camera DOF',
        'artistic_approval': False, 'screenshots_sha256': files, 'comparisons': comparisons,
        'limits': ['Old 48 px/m environment and temporary facade art remain',
            'Mobs hidden, actors frozen; no animation/gameplay or phone performance validation',
            'System V-Sync warning only; no scene/script errors']}
    (root / 'render_validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('RICO96_PLAZA_RENDER_OK', json.dumps(comparisons))


if __name__ == '__main__':
    main()
