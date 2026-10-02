"""Миссия 2 «Золотой Банк» (Астра): пропсы из inbox/story/m2_bank → assets/props/m2, data/props.json, главы bank*."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "/home/claude/trashketeers-build/astra/inbox/story/m2_bank/"
DST = "/home/claude/raccoon/assets/props/m2/"
os.makedirs(DST, exist_ok=True)
W = {"safe_closed": 70, "safe_damaged": 70, "safe_broken": 80, "gold_cart": 90, "cash_register": 64, "security_booth": 110,
     "coin_press": 96, "bank_counter": 130, "teller_window": 110}


def keyed(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = (np.minimum(r, b) - g) > 120
    lab, _ = ndimage.label(m)
    bd = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(bd))
    near = ndimage.binary_dilation(bg, iterations=2) & ~bg
    out = np.dstack([a.astype(np.uint8), np.where(bg, 0, 255).astype(np.uint8)])
    out[near & ((np.minimum(r, b) - g) > 40), 3] = 0
    im = Image.fromarray(out, "RGBA")
    return im.crop(im.getbbox())


for n, w in W.items():
    im = keyed(SRC + n + ".png")
    tw = w * 2
    im = im.resize((tw, max(1, round(im.height * tw / im.width))), Image.LANCZOS)
    im.save(DST + n + ".png", optimize=True)

P = "/home/claude/raccoon/data/props.json"
d = json.load(open(P)); p = d["props"]; T = "res://assets/props/m2/"
def e(n, w, foot, sh, **x):
    v = {"texture": T + n + ".png", "width": w, "footprint": foot, "shadow": sh, "flip": True}; v.update(x); return v
p["m2_cart"] = e("gold_cart", 90, [72, 36], 32)
p["m2_register"] = e("cash_register", 64, [52, 30], 26)
p["m2_booth"] = e("security_booth", 110, [90, 44], 40)
p["m2_press"] = e("coin_press", 96, [78, 40], 34)
p["m2_counter"] = e("bank_counter", 130, [110, 36], 36)
p["m2_teller"] = e("teller_window", 110, [92, 34], 34)
p["d_safe"] = e("safe_closed", 70, [58, 34], 30, destructible={"hp": 60, "broken": T + "safe_broken.png", "broken_width": 80.0, "reward": 8, "effect": "explode", "sound": "explosion"})
json.dump(d, open(P, "w"), ensure_ascii=False, indent=2)

C = "/home/claude/raccoon/data/chapters.json"
ch = json.load(open(C)); n = 0
for c in ch["chapters"]:
    if c["id"].startswith("bank"):
        for lst, ids in (("cover_big", ["m2_booth", "m2_press", "m2_counter"]), ("cover_small", ["m2_cart", "m2_register", "m2_teller"])):
            a = c.setdefault(lst, [])
            a += [i for i in ids if i not in a]
        c.setdefault("destructibles", {}).setdefault("d_safe", 3)
        n += 1
json.dump(ch, open(C, "w"), ensure_ascii=False, indent=1)
print("глав:", n)
