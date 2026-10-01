import os, sys
import numpy as np
from PIL import Image

SRC = '/home/claude/trashketeers-build/astra/inbox/story/'
DST = '/home/claude/raccoon/assets/story/'


def key(im):
    a = np.asarray(im.convert('RGB')).astype(np.float32) / 255
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    m = np.clip((np.minimum(R, B) - G - 0.3) / 0.3, 0, 1) * np.clip((1 - np.abs(R - B) - 0.75) / 0.15, 0, 1)
    al = 1 - m
    cap = G + 0.12
    edge = (al < 0.999) & (al > 0)
    R2 = np.where(edge, np.minimum(R, cap), R)
    B2 = np.where(edge, np.minimum(B, cap), B)
    out = np.dstack([R2, G, B2, al])
    out[al < 0.02] = 0
    return Image.fromarray((out * 255).astype(np.uint8), 'RGBA')


def put(src, dst, keyed=True, size=None):
    im = Image.open(SRC + src)
    im = key(im) if keyed else im.convert('RGBA')
    if size:
        im = im.resize(size, Image.LANCZOS)
    os.makedirs(os.path.dirname(DST + dst), exist_ok=True)
    im.save(DST + dst, optimize=True)


for name in ('rico', 'nell', 'baron', 'king', 'toxic'):
    pass
alts = {'rico': 'annoyed', 'nell': 'annoyed', 'baron': 'laugh', 'king': 'angry', 'toxic': 'panic'}
norms = {'rico': 'normal', 'nell': 'normal', 'baron': 'normal', 'king': 'normal', 'toxic': 'normal'}
for who in alts:
    put('portraits/%s_%s.png' % (who, norms[who]), 'portraits/%s.png' % who, True, (256, 256))
    put('portraits/%s_%s.png' % (who, alts[who]), 'portraits/%s_alt.png' % who, True, (256, 256))

for n in ('closed', 'raise_1', 'raise_2', 'raise_3', 'raise_4', 'open'):
    put('gates/gate_%s.png' % n, 'gates/%s.png' % n)

for n in ('captive_caged_1', 'captive_caged_2', 'captive_freed', 'captive_run_1', 'captive_run_2', 'captive_sway_1', 'captive_sway_2', 'cage_closed', 'cage_open'):
    put('captive/%s.png' % n, 'captive/%s.png' % n)

for i in range(1, 10):
    put('env/poster_%02d.png' % i, 'posters/%d.png' % i)
for i in range(1, 9):
    put('env/graffiti_base_%02d.png' % i, 'graffiti/%d.png' % i, False)
for i in range(1, 4):
    put('env/wall_%02d.png' % i, 'walls/%d.png' % i, False)
    put('env/boss_floor_%02d.png' % i, 'boss/floor_%d.png' % i, False)
for n in ('speakers', 'spotlights', 'throne'):
    put('env/boss_%s.png' % n, 'boss/%s.png' % n)

for f in sorted(os.listdir(SRC + 'heavy_barrel')):
    if f.endswith('_sheet.png'):
        continue
    put('heavy_barrel/' + f, 'hb/' + f)
for n in ('hidden_wall_plate', 'hidden_crate_open', 'hidden_crate_closed', 'wall_debris_01', 'wall_debris_02', 'wall_debris_03', 'wall_debris_04', 'break_wall_intact', 'break_wall_cracked', 'break_wall_destroyed'):
    put('terrain/%s.png' % n, 'terrain/%s.png' % n)
print('ok')
