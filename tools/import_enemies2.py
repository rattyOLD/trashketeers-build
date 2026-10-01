"""Собирает атласы новых врагов Астры (inbox/story/enemies2, блок H4) в assets/enemies|bosses и data/frames.json.
Берутся кадры «вправо» (спрайты зеркалятся движком), клипы: idle/run/windup/strike/hit/death (+боссовые p2_*, aim, rain, wreck, taunt)."""
import json
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = "/home/claude/raccoon"
SRC = "/home/claude/trashketeers-build/astra/inbox/story/enemies2"
PAD = 4

ENEMIES = {
    "courier_rat": {"prefix": "courier_rat", "scale": 0.5, "dir": "enemies", "boss": False},
    "pigeon_bomber": {"prefix": "bomber_pigeon", "scale": 0.5, "dir": "enemies", "boss": False},
    "trash_tank": {"prefix": "trash_tank", "scale": 0.55, "dir": "enemies", "boss": False},
    "cash_collector": {"prefix": "cash_collector", "scale": 0.5, "dir": "enemies", "boss": False},
    "sea_pirate": {"prefix": "trash_sea_pirate", "scale": 0.5, "dir": "bosses", "boss": True},
    "chef_boss": {"prefix": "chef", "scale": 0.5, "dir": "bosses", "boss": True},
}


def keyed(img):
    a = np.asarray(img.convert("RGB")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mag = np.minimum(r, b) - g
    bg_mask = mag > 140
    labels, _ = ndimage.label(bg_mask)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    bg = np.isin(labels, list(border))
    near = ndimage.binary_dilation(bg, iterations=2) & ~bg
    alpha = np.full(mag.shape, 255, np.uint8)
    alpha[bg] = 0
    fringe = near & (mag > 50)
    alpha[fringe] = np.clip(255 - (mag[fringe] - 50) * 2.0, 0, 255).astype(np.uint8)
    out = a.copy()
    out[fringe, 0] = np.minimum(r[fringe], g[fringe] + 30)
    out[fringe, 2] = np.minimum(b[fringe], g[fringe] + 30)
    return Image.fromarray(np.dstack([np.clip(out, 0, 255).astype(np.uint8), alpha]), "RGBA")


def cut(path, scale):
    img = keyed(Image.open(path))
    box = img.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    crop = img.crop(box)
    pivot = (img.width / 2 - box[0], box[3] - box[1])
    crop = crop.resize((max(int(round(crop.width * scale)), 1), max(int(round(crop.height * scale)), 1)), Image.LANCZOS)
    return crop, (pivot[0] * scale, pivot[1] * scale)


def clips_for(n_walk, n_att, n_death, boss):
    walk = list(range(0, 4))
    att = [4, 5, 6]
    death = list(range(7, 7 + n_death))
    c = {
        "idle": {"frames": [walk[0], walk[1], walk[0], walk[3]], "fps": 3.0, "loop": True},
        "run": {"frames": walk, "fps": 9.0, "loop": True},
        "windup": {"frames": [att[0], att[1]], "fps": 3.0, "loop": False},
        "aim": {"frames": [att[0]], "fps": 1.0, "loop": False},
        "strike": {"frames": [att[2]], "fps": 1.0, "loop": False},
        "hit": {"frames": [att[1], walk[0]], "fps": 14.0, "loop": False},
        "taunt": {"frames": [att[0], att[1], att[2], att[1]], "fps": 6.0, "loop": True},
        "death": {"frames": death, "fps": 6.0, "loop": False},
    }
    if boss:
        c["p2_idle"] = {"frames": c["idle"]["frames"], "fps": 4.5, "loop": True}
        c["p2_run"] = {"frames": walk, "fps": 12.0, "loop": True}
        c["p2_windup"] = {"frames": [att[0], att[1]], "fps": 4.0, "loop": False}
        c["p2_hit"] = {"frames": [att[1], walk[0]], "fps": 14.0, "loop": False}
        c["rain"] = {"frames": [att[1]], "fps": 1.0, "loop": False}
        c["wreck"] = {"frames": [death[0], death[1]], "fps": 4.0, "loop": True}
    return c


def main():
    data_path = f"{ROOT}/data/frames.json"
    data = json.load(open(data_path))
    for eid, cfg in ENEMIES.items():
        p = cfg["prefix"]
        files = [f"{p}_walk_right_{i}.png" for i in range(1, 5)] + [f"{p}_attack_{i}.png" for i in range(1, 4)]
        n_death = 4 if cfg["boss"] else 3
        files += [f"{p}_death_{i}.png" for i in range(1, n_death + 1)]
        items = [cut(f"{SRC}/{f}", cfg["scale"]) for f in files]
        atlas_w = 1024
        x = y = row_h = PAD
        placed = []
        for crop, _ in items:
            w, h = crop.size
            if x + w + PAD > atlas_w:
                x, y, row_h = PAD, y + row_h + PAD, 0
            placed.append((x, y))
            x += w + PAD
            row_h = max(row_h, h)
        atlas_h = 1
        while atlas_h < y + row_h + PAD:
            atlas_h *= 2
        atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
        frames = []
        for (crop, pivot), (px, py) in zip(items, placed):
            atlas.alpha_composite(crop, (px, py))
            frames.append([px, py, crop.width, crop.height, round(pivot[0], 1), round(pivot[1], 1)])
        out = f"assets/{cfg['dir']}/{eid}_frames.png"
        atlas.save(f"{ROOT}/{out}", optimize=True)
        data["sheets"][eid] = {
            "texture": f"res://{out}", "regions": [], "region_ranges": {}, "faces_right": True,
            "frames": frames, "names": [f.replace(".png", "") for f in files],
            "clips": clips_for(4, 3, n_death, cfg["boss"]),
        }
        print(eid, atlas.size, len(frames))
    json.dump(data, open(data_path, "w"), ensure_ascii=False)


main()
