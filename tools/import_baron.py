"""Собирает атлас Барона Пиво: новые листы Астры (inbox/baron) + старые кадры, увеличенные под тот же масштаб.
Пишет assets/bosses/baron_frames.png и обновляет секцию baron в data/frames.json."""
import json, sys
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = "/home/claude/raccoon"
HERE = "/home/claude/trashketeers-build"
CELL_W, CELL_H = 384, 512
COLS, ROWS = 4, 2
OLD_SCALE = 1.7
PAD = 6


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
    rgba = np.dstack([np.clip(out, 0, 255).astype(np.uint8), alpha])
    return Image.fromarray(rgba, "RGBA")


def cut_sheet(path):
    sheet = keyed(Image.open(path))
    frames = []
    for row in range(ROWS):
        for col in range(COLS):
            x0, y0 = col * CELL_W, row * CELL_H
            cell = sheet.crop((x0, y0, x0 + CELL_W, y0 + CELL_H))
            box = cell.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
            if box is None:
                continue
            crop = cell.crop(box)
            pivot = (CELL_W / 2 - box[0], box[3] - box[1])
            frames.append((crop, pivot))
    return frames


def main():
    old = Image.open(f"{HERE}/tools/src/baron_frames_old.png").convert("RGBA")
    old_meta = json.load(open(f"{HERE}/tools/src/baron_old.json"))
    items = []
    names = []
    for i, f in enumerate(old_meta["frames"]):
        x, y, w, h, px, py = f
        crop = old.crop((int(x), int(y), int(x + w), int(y + h)))
        crop = crop.resize((int(round(w * OLD_SCALE)), int(round(h * OLD_SCALE))), Image.LANCZOS)
        items.append((crop, (px * OLD_SCALE, py * OLD_SCALE)))
        names.append(old_meta["names"][i])
    for sheet, prefix in (("baron_A1", "a1_"), ("baron_C1", "c1_")):
        for i, (crop, pivot) in enumerate(cut_sheet(f"{HERE}/tools/src/astra_baron/{sheet}.png")):
            items.append((crop, pivot))
            names.append(f"{prefix}{i}")

    atlas_w = 2048
    x = y = row_h = PAD
    placed = []
    for crop, pivot in items:
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
    atlas.save(f"{ROOT}/assets/bosses/baron_frames.png", optimize=True)

    idx = {n: i for i, n in enumerate(names)}
    a = [idx[f"a1_{i}"] for i in range(8)]
    c = [idx[f"c1_{i}"] for i in range(8)]
    clips = dict(old_meta["clips"])
    clips["idle"] = {"frames": [a[0], a[1], a[2], a[3], a[2], a[1]], "fps": 6.0, "loop": True}
    clips["run"] = {"frames": [a[4], a[5], a[6], a[7]], "fps": 9.0, "loop": True}
    clips["p2_idle"] = {"frames": [a[0], a[1], a[2], a[3], a[2], a[1]], "fps": 8.5, "loop": True}
    clips["p2_run"] = {"frames": [a[4], a[5], a[6], a[7]], "fps": 12.0, "loop": True}
    clips["windup"] = {"frames": [c[0], c[1]], "fps": 3.0, "loop": False}
    clips["p2_windup"] = {"frames": [c[0], c[1]], "fps": 4.0, "loop": False}
    clips["swing"] = {"frames": [c[2], c[3], c[4]], "fps": 14.0, "loop": False}
    clips["stun"] = {"frames": [c[5], c[6], c[7], c[6]], "fps": 3.0, "loop": True}
    meta = dict(old_meta)
    meta["frames"] = frames
    meta["names"] = names
    meta["clips"] = clips
    path = f"{ROOT}/data/frames.json"
    data = json.load(open(path))
    data["sheets"]["baron"] = meta
    json.dump(data, open(path, "w"), ensure_ascii=False)
    print("atlas", atlas.size, "frames", len(frames))


main()
