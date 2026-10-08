"""Арт Астры под арены: пропсы зон (crossroads/roofs/reactor), мосты, уступы, ломаемые стены, кислота.
Пурпурный фон (#FF00FF) вырезается заливкой от краёв (неон внутри предмета не трогается), кайма
очищается от пурпура, картинка обрезается по содержимому и ужимается до 2× игровой ширины.
Запуск: python3 tools/import_astra_arena.py  (без numpy — чистый PIL)."""
import os
from collections import deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "astra/inbox/story")
DST = os.path.join(ROOT, "source/assets")

# имя → (исходник, папка назначения, игровая ширина)
PROPS = {
    "z_bus": ("zones/m5_center/bus.png", 300), "z_truck": ("zones/m5_center/truck.png", 260),
    "z_crater": ("zones/m5_center/crater.png", 210), "z_dumpster": ("zones/m5_center/dumpster.png", 150),
    "z_gear": ("zones/m5_center/gear.png", 150), "z_hydrant": ("zones/m5_center/hydrant.png", 80),
    "z_rubble": ("zones/m5_center/rubble.png", 170), "z_sign": ("zones/m5_center/sign_blank.png", 170),
    "z_tower": ("zones/m5_center/tower.png", 220), "z_traffic": ("zones/m5_center/traffic_light.png", 100),
    "z_antenna": ("zones/m3_roofs/antenna.png", 120), "z_billboard": ("zones/m3_roofs/billboard_blank.png", 190),
    "z_cable_reel": ("zones/m3_roofs/cable_reel.png", 120), "z_chimney": ("zones/m3_roofs/chimney.png", 110),
    "z_pigeon_tower": ("zones/m3_roofs/pigeon_tower.png", 120), "z_radio_mast": ("zones/m3_roofs/radio_mast.png", 130),
    "z_roof_vent": ("zones/m3_roofs/roof_vent.png", 100), "z_satellite": ("zones/m3_roofs/satellite_dish.png", 130),
    "z_water_tank": ("zones/m3_roofs/water_tank.png", 150), "z_wire_pole": ("zones/m3_roofs/wire_pole.png", 120),
    "z_coil": ("zones/m6_heart/coil.png", 140), "z_console": ("zones/m6_heart/console.png", 120),
    "z_core": ("zones/m6_heart/core.png", 130), "z_pipe": ("zones/m6_heart/pipe.png", 130),
    "z_pump": ("zones/m6_heart/pump.png", 140), "z_speaker": ("zones/m6_heart/speaker.png", 110),
    "z_stuffed_toy": ("zones/m6_heart/stuffed_toy.png", 90), "z_toy_truck": ("zones/m6_heart/toy_truck.png", 140),
    "z_valve": ("zones/m6_heart/valve.png", 100),
    "wall_intact": ("terrain/break_wall_intact.png", 150), "wall_destroyed": ("terrain/break_wall_destroyed.png", 150),
}
TERRAIN = {  # мосты и уступы — без ужатия по ширине (тайлятся/тянутся в игре)
    "bridge_scrap": "terrain/bridge_scrap.png", "bridge_steel": "terrain/bridge_steel.png", "bridge_wood": "terrain/bridge_wood.png",
    "ledge_scrap": "terrain/ledge_scrap.png", "ledge_concrete": "terrain/ledge_concrete.png", "ledge_reactor": "terrain/ledge_reactor.png",
}
OPAQUE = {"acid_01": "terrain/acid_01.png", "acid_02": "terrain/acid_02.png"}


NEON_PINK = {"z_core", "z_coil"}  # свой розовый неон: замкнутые области не вырезаем


def keyed(path, holes=True):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()

    def magenta(p):
        return min(p[0], p[2]) - p[1]

    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if magenta(px[x, y]) > 90 and not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if magenta(px[x, y]) > 90 and not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    # Замкнутые «дыры» (между ножками, перилами): почти чистый пурпур фона — тоже фон, неон предмета светлее.
    for y in range(h if holes else 0):
        for x in range(w):
            r, g, b, _a = px[x, y]
            if not bg[y * w + x] and r > 215 and b > 215 and g < 45:
                bg[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not bg[ny * w + nx] and magenta(px[nx, ny]) > 90:
                bg[ny * w + nx] = 1
                q.append((nx, ny))
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if bg[i]:
                px[x, y] = (0, 0, 0, 0)
                continue
            r, g, b, a = px[x, y]
            m = min(r, b) - g
            near = any(0 <= x + dx < w and 0 <= y + dy < h and bg[(y + dy) * w + x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if near and m > 25:
                # кайма: убрать пурпурный отлив и сделать полупрозрачной
                r = min(r, g + 40)
                b = min(b, g + 40)
                a = int(a * 0.55)
            px[x, y] = (r, g, b, a)
    box = im.getbbox()
    return im.crop(box) if box else im


def main():
    os.makedirs(os.path.join(DST, "props/zones"), exist_ok=True)
    os.makedirs(os.path.join(DST, "terrain"), exist_ok=True)
    for name, (src, width) in PROPS.items():
        im = keyed(os.path.join(SRC, src), name not in NEON_PINK)
        tw = width * 2
        if im.width > tw:
            im = im.resize((tw, max(1, round(im.height * tw / im.width))), Image.LANCZOS)
        im.save(os.path.join(DST, "props/zones", name + ".png"), optimize=True)
    for name, src in TERRAIN.items():
        keyed(os.path.join(SRC, src)).save(os.path.join(DST, "terrain", name + ".png"), optimize=True)
    for name, src in OPAQUE.items():
        Image.open(os.path.join(SRC, src)).convert("RGB").save(os.path.join(DST, "terrain", name + ".png"), optimize=True)
    print("ok", len(PROPS), len(TERRAIN), len(OPAQUE))


if __name__ == "__main__":
    main()
