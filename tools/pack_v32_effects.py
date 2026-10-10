#!/usr/bin/env python3
"""Register reviewed dash/scar artwork into the v32 delivery geometry."""
import argparse
from pathlib import Path
import numpy as np
from PIL import Image
from import_v32_art import deliver, manifest, INBOX, sprite


def trim(image):
    image = image.convert('RGBA')
    alpha = np.asarray(image.getchannel('A'), dtype=float)
    image.putalpha(Image.fromarray(np.clip((alpha-35)*255/220, 0, 255).astype('uint8')))
    return image.crop(image.getbbox())


def fit(image, size, inset=0):
    image = trim(image)
    image.thumbnail((size[0]-inset*2, size[1]-inset*2), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', size)
    out.alpha_composite(image, ((size[0]-image.width)//2, (size[1]-image.height)//2))
    return out


def dash(path):
    image = Image.open(path)
    xs = [0,167,351,595,796,978,1155,1300,1765]
    ys = [0,260,465,680,887]
    for row, name in enumerate(['beer','confetti','dust','ice']):
        tiles = [image.crop((xs[i],ys[row],xs[i+1],ys[row+1])) for i in range(8)]
        sheet = Image.new('RGBA', (768,128))
        for index, tile in enumerate(tiles[:6]):
            sheet.alpha_composite(fit(tile, (128,128),8), (128*index,0))
        folder = f'cosmetics/dash/{name}'
        for file, tile in [('burst.png',sheet),('bit.png',fit(tiles[6],(32,32),2)),('trail.png',fit(tiles[7],(256,64),4))]:
            deliver(tile,folder,file,folder)
        manifest(INBOX/folder,{'burst.png':((128,128),6)})
    print('Four thick dash sets: six frames, bit, trail; all particles preserved')


def scars(path):
    image = Image.open(path)
    xs = [0,325,868,1330,1657,2048]
    names = ['brow','cracked_cap','eye_patch','nose_plaster','torn_ear']
    # Coordinates are registered to the unchanged 512-square hud_raccoon_0.
    sizes = [(28,40),(184,102),(178,66),(42,38),(43,79)]
    centers = [(239,211),(269,105),(261,252),(328,264),(159,151)]
    for i,name in enumerate(names):
        accessory = fit(image.crop((xs[i],0,xs[i+1],image.height)),sizes[i])
        out = Image.new('RGBA',(512,512))
        center = centers[i]
        out.alpha_composite(accessory,(center[0]-accessory.width//2,center[1]-accessory.height//2))
        deliver(out,'story/scars',f'scar_{name}.png','story/scars')
    manifest(INBOX/'story/scars')
    print('Five transparent scar overlays registered to Rico HUD base')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('kind',choices=['dash','scars'])
    parser.add_argument('image',type=Path)
    args=parser.parse_args()
    (dash if args.kind=='dash' else scars)(args.image)
