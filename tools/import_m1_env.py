"""Миссия 1 (H3 Астры): вырезает пропсы из inbox/story/m1_env, режет фон #FF00FF, пишет в assets/props/m1 и добавляет в data/props.json и главу «Свалка»."""
import json
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "/home/claude/trashketeers-build/astra/inbox/story/m1_env/"
DST = "/home/claude/raccoon/assets/props/m1/"
import os
os.makedirs(DST, exist_ok=True)

# имя: (ширина в мире, размер подложки-тени, footprint)
PROPS = {
    "broken_fridge": 96, "garbage_bags": 96, "rust_barrel_intact": 54, "rust_barrel_broken": 70,
    "skull_sign": 78, "supply_crate": 74, "tire": 62, "barrier_arm": 150, "toxin_puddle": 110,
}


def keyed(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg_mask = (np.minimum(r, b) - g) > 120
    labels, _ = ndimage.label(bg_mask)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    bg = np.isin(labels, list(border))
    near = ndimage.binary_dilation(bg, iterations=2) & ~bg
    out = np.dstack([a.astype(np.uint8), np.where(bg, 0, 255).astype(np.uint8)])
    # убираем розовую кайму на краю
    fringe = near & ((np.minimum(r, b) - g) > 40)
    out[fringe, 3] = 0
    img = Image.fromarray(out, "RGBA")
    return img.crop(img.getbbox())


sizes = {}
for name, width in PROPS.items():
    img = keyed(SRC + name + ".png")
    tex_w = int(width * 2)  # текстуры в 2x к миру, как у остальных пропсов
    h = max(1, round(img.height * tex_w / img.width))
    img = img.resize((tex_w, h), Image.LANCZOS)
    img.save(DST + name + ".png", optimize=True)
    sizes[name] = (tex_w, h)
    print(name, sizes[name])

P = "/home/claude/raccoon/data/props.json"
data = json.load(open(P))
props = data["props"]
T = "res://assets/props/m1/"


def entry(name, width, foot, shadow, **extra):
    d = {"texture": T + name + ".png", "width": width, "footprint": foot, "shadow": shadow, "flip": True}
    d.update(extra)
    return d


props["m1_fridge"] = entry("broken_fridge", 96, [80, 40], 36)
props["m1_garbage"] = entry("garbage_bags", 96, [78, 38], 32)
props["m1_crate"] = entry("supply_crate", 74, [62, 34], 28)
props["m1_tire"] = entry("tire", 62, [52, 30], 24)
props["m1_skull_sign"] = entry("skull_sign", 78, [34, 22], 30)
props["m1_barrier"] = {"texture": T + "barrier_arm.png", "width": 150, "flat": True, "flip": True}
props["m1_toxin"] = {"texture": T + "toxin_puddle.png", "width": 110, "flat": True, "flip": True}
props["d_rust_barrel"] = entry("rust_barrel_intact", 54, [44, 26], 30, destructible={
    "hp": 28, "broken": T + "rust_barrel_broken.png", "broken_width": 70.0, "reward": 2, "effect": "explode", "sound": "explosion"})
json.dump(data, open(P, "w"), ensure_ascii=False, indent=2)

C = "/home/claude/raccoon/data/chapters.json"
ch = json.load(open(C))
n = 0
for chap in ch["chapters"]:
    if chap.get("floor", "").endswith("ch1_floor.png"):
        for lst, ids in (("cover_big", ["m1_fridge", "m1_skull_sign"]), ("cover_small", ["m1_garbage", "m1_crate", "m1_tire"]), ("flat", ["m1_barrier", "m1_toxin"])):
            arr = chap.setdefault(lst, [])
            for i in ids:
                if i not in arr:
                    arr.append(i)
        dest = chap.setdefault("destructibles", {})
        dest.setdefault("d_rust_barrel", 4)
        n += 1
json.dump(ch, open(C, "w"), ensure_ascii=False, indent=1)
print("глав обновлено:", n)
