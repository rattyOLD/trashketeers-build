#!/usr/bin/env python3
"""Бестиарий v12b: малые портреты вместо загрузки боевых атласов в меню."""
import json
from pathlib import Path
from PIL import Image
import numpy as np
from scipy import ndimage
from hero_tactical import rgba

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
DST = SOURCE / "assets/ui/bestiary"


def main():
    DST.mkdir(parents=True, exist_ok=True)
    for path in sorted((ROOT / "astra/inbox/story/coop/bestiary").glob("*.png")):
        image = rgba(str(path))
        if path.stem.startswith("card_"):
            # Detached ornaments below the border must not displace the text.
            labels, count = ndimage.label(np.array(image.getchannel("A")) > 150)
            if count:
                largest = np.bincount(labels.ravel())[1:].argmax() + 1
                ys, xs = np.nonzero(labels == largest)
                image = image.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
            image = image.resize((192, 256), Image.Resampling.LANCZOS)
        else:
            box = image.getchannel("A").point(lambda value: 255 if value > 100 else 0).getbbox()
            if box:
                image = image.crop(box)
            image.thumbnail((512, 128) if path.stem == "bestiary_banner" else (96, 96), Image.Resampling.LANCZOS)
        image.save(DST / path.name, optimize=True)
    frames = json.loads((SOURCE / "data/frames.json").read_text())["sheets"]
    entries = json.loads((SOURCE / "data/enemies.json").read_text())["enemies"]
    portraits = DST / "portraits"
    portraits.mkdir(exist_ok=True)
    for entry in entries:
        sheet = frames.get(entry.get("frames", ""))
        path = sheet["texture"] if sheet else entry["sprite"]
        im = Image.open(SOURCE / path.removeprefix("res://")).convert("RGBA")
        if sheet:
            first = sheet["clips"]["idle"]["frames"][0]
            x, y, w, h = sheet["frames"][first][:4]
            im = im.crop((x, y, x + w, y + h))
        box = im.getchannel("A").getbbox()
        im = im.crop(box) if box else im
        im.thumbnail((112, 112), Image.Resampling.LANCZOS)
        im.save(portraits / (entry["enemy_id"] + ".png"), optimize=True)
    im = Image.open(SOURCE / "assets/bosses/ice_dragon_idle.png").convert("RGBA")
    im = im.crop((0, 0, im.width // 4, im.height))
    im.thumbnail((112, 112), Image.Resampling.LANCZOS)
    im.save(portraits / "white_dragon.png", optimize=True)
    print(f"BESTIARY imported 21 interface assets and {len(entries) + 1} small portraits")


if __name__ == "__main__":
    main()
