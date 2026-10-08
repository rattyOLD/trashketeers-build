#!/usr/bin/env python3
"""Герои Астры в тактическом стиле (бриф v21): astra/inbox/story/heroes_tactical/<id>/ -> assets/heroes/tactical/<id>_<clip>.png.
Исходник: ячейка 480x320, 4 в ряд; в игре ячейка 300x200 (как у прежнего енота, экономия видеопамяти).
Фон #FF00FF у листов без прозрачности вырезается astra_key. По слоям рук считаются точки хвата на каждый кадр:
grip — кулак задней руки (rearhand, у пояса), support — ладонь передней (fronthand), на неё ложится ствол.
Кулак вырезается в hand_<clip>.png и рисуется поверх ствола. Итог: data/grip_<id>.json [grip_x, grip_y, support_x, support_y].
Запуск из корня репозитория: python3 tools/hero_tactical.py"""
import json, os, sys, tempfile
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from astra_key import key

SRC = "astra/inbox/story/heroes_tactical"
DST = "source/assets/heroes/tactical"
HEROES = ("raccoon", "red_panda", "snow")
COUNTS = {"idle": 8, "run": 8, "shoot": 4, "hit": 4, "dash": 6, "death": 8, "revive": 6}
HANDS = ("idle", "run", "shoot")
CW, CH = 480, 320
K = 300 / 480
FIST_R = 30.0     # радиус вырезаемого кулака в исходных пикселях
FIST_SOFT = 8.0


def rgba(path):
    im = Image.open(path)
    if im.mode != "RGBA" or im.getchannel("A").getextrema()[0] == 255:
        tmp = tempfile.mktemp(suffix=".png")
        key(path, tmp)
        im = Image.open(tmp)
    return im.convert("RGBA")


def shrink(im):
    return im.resize((round(im.width * K), round(im.height * K)), Image.LANCZOS)


def tip(cell, slab):
    """Центр кисти: конец руки, дальний от плеча (плечо — верх слоя). Рука может быть вытянута вперёд или опущена."""
    a = np.array(cell.getchannel("A")) > 128
    ys, xs = np.nonzero(a)
    if xs.size == 0:
        return None
    top = ys <= ys.min() + 14
    sx, sy = xs[top].mean(), ys[top].mean()
    d = np.sqrt((xs - sx) ** 2 + (ys - sy) ** 2)
    sel = d >= d.max() - slab
    return float(xs[sel].mean()), float(ys[sel].mean())


def cells(sheet, n):
    return [sheet.crop(((i % 4) * CW, (i // 4) * CH, (i % 4 + 1) * CW, (i // 4 + 1) * CH)) for i in range(n)]


def sheet_of(frames):
    rows = (len(frames) + 3) // 4
    out = Image.new("RGBA", (4 * CW, rows * CH), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, ((i % 4) * CW, (i // 4) * CH))
    return out


def anchor(cell):
    """Корпус кадра: x — середина головы (верхние 25 px силуэта), y — макушка. По нему руки идут за телом."""
    a = np.array(cell.getchannel("A")) > 128
    ys, xs = np.nonzero(a)
    top = ys.min()
    return float(xs[ys < top + 25].mean()), float(top)


def shifted(cell, dx, dy):
    out = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    out.paste(cell, (round(dx), round(dy)), cell)
    return out


def smooth_order(frames):
    """Стойка с рывком на стыке цикла (корпус прыгает больше 8 px) — играем первую половину туда-обратно."""
    xs = [anchor(f)[0] for f in frames]
    jump = max(abs(xs[i] - xs[(i + 1) % len(xs)]) for i in range(len(xs)))
    if jump <= 8.0:
        return list(range(len(frames)))
    half = len(frames) // 2
    return list(range(half)) + list(range(half - 1, -1, -1))


def main():
    """Клипы с оружием (idle/run/shoot) собираются из слоёв: тело без рук + руки в позе удержания из первого кадра
    стрельбы, сдвинутые за корпусом. В нарисованных кадрах руки размахивают (бег), и ствол прыгал от кадра к кадру."""
    os.makedirs(DST, exist_ok=True)
    for hero in HEROES:
        base = f"{SRC}/{hero}/{hero}_"
        for clip in COUNTS:
            if clip not in HANDS:
                shrink(rgba(base + clip + ".png")).save(f"{DST}/{hero}_{clip}.png", optimize=True)
        rear = cells(rgba(base + "rearhand_shoot.png"), 1)[0]
        front = cells(rgba(base + "fronthand_shoot.png"), 1)[0]
        ref = anchor(cells(rgba(base + "body_nohands_shoot.png"), 1)[0])
        g0 = tip(rear, 22)
        s0 = tip(front, 18)
        yy, xx = np.mgrid[0:CH, 0:CW]
        fade = np.clip((FIST_R + FIST_SOFT - np.sqrt((xx - g0[0]) ** 2 + (yy - g0[1]) ** 2)) / FIST_SOFT, 0.0, 1.0)
        fist_arr = np.array(rear).astype(np.float32)
        fist_arr[..., 3] *= fade
        fist = Image.fromarray(fist_arr.clip(0, 255).astype(np.uint8), "RGBA")
        grip = {}
        for clip in HANDS:
            bodies = cells(rgba(base + "body_nohands_" + clip + ".png"), COUNTS[clip])
            order = smooth_order(bodies) if clip == "idle" else list(range(len(bodies)))
            frames, hands, points = [], [], []
            for i in order:
                ax, ay = anchor(bodies[i])
                dx, dy = ax - ref[0], ay - ref[1]
                cell = shifted(rear, dx, dy)
                cell.alpha_composite(bodies[i])
                cell.alpha_composite(shifted(front, dx, dy))
                frames.append(cell)
                hands.append(shifted(fist, dx, dy))
                points.append([round((g0[0] + dx) * K, 1), round((g0[1] + dy) * K, 1), round((s0[0] + dx) * K, 1), round((s0[1] + dy) * K, 1)])
            shrink(sheet_of(frames)).save(f"{DST}/{hero}_{clip}.png", optimize=True)
            shrink(sheet_of(hands)).save(f"{DST}/{hero}_hand_{clip}.png", optimize=True)
            grip[clip] = points
        json.dump(grip, open(f"source/data/grip_{hero}.json", "w"))
        print(hero, {c: len(v) for c, v in grip.items()})


# Портреты: карточка героя (assets/ui/portraits/<файл>, до 300 px), лицо в бою по урону (hud/<id>_0..3, 256 px).
UI = {
    "raccoon": {"card": ("ui/rico.png", "vagabond.png"), "talk": ("ui/hud_raccoon_0.png", "rico.png", 192)},
    "red_panda": {"card": ("ui/red_panda.png", "red_panda.png")},
    "snow": {"card": ("ui/portrait_snow_normal.png", "snow.png")},
}
PORTRAITS = "source/assets/ui/portraits"


def fit(im, side):
    box = im.getbbox()
    im = im.crop(box) if box else im
    k = side / max(im.size)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def ui():
    for hero, cfg in UI.items():
        base = f"{SRC}/{hero}/"
        src, dst = cfg["card"]
        fit(rgba(base + src), 300).save(f"{PORTRAITS}/{dst}", optimize=True)
        if "talk" in cfg:
            src, dst, side = cfg["talk"]
            fit(rgba(base + src), side).save(f"{PORTRAITS}/{dst}", optimize=True)
        for i in range(4):
            im = rgba(f"{base}ui/hud_{hero}_{i}.png").resize((256, 256), Image.LANCZOS)
            im.save(f"{PORTRAITS}/hud/{hero}_{i}.png", optimize=True)
    print("ui ok")


if __name__ == "__main__":
    main()
    ui()
