#!/usr/bin/env python3
"""Агенты Розыска Астры (astra/inbox/story/wanted) → атласы source/assets/enemies/fed_<id>.png + листы в data/frames.json
и спрайты в data/enemies.json (вместо временных свиней). Кадры по одному на #FF00FF, фон вырезается astra_key.
Ряды атласа: idle 2, run 6, attack 4, hit 1, death 5. Высота фигуры в игре — TARGET (как у прежних свиней, чуть крупнее).
Запуск из корня: python3 tools/import_wanted.py"""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from astra_key import key
from PIL import Image

SRC = "astra/inbox/story/wanted"
AGENTS = {"fed_bagel": ("inspector_bublik", 110.0), "fed_agent": ("agent_tushonka", 135.0), "fed_chief": ("bureau_chief", 175.0)}
ROWS = [("idle", 2), ("run", 6), ("attack", 4), ("hit", 1), ("death", 5)]


def frame(name, anim, i):
    tmp = tempfile.mktemp(suffix=".png")
    key(f"{SRC}/{name}_{anim}_{i}.png", tmp)
    return Image.open(tmp).convert("RGBA")


frames_path = "source/data/frames.json"
frames = json.load(open(frames_path))
enemies_path = "source/data/enemies.json"
enemies = json.load(open(enemies_path))
for eid, (name, target) in AGENTS.items():
    raw = {anim: [frame(name, anim, i + 1) for i in range(n)] for anim, n in ROWS}
    box = raw["idle"][0].getbbox()
    k = target / (box[3] - box[1])
    # Общая рамка всех кадров (+запас): пустые поля исходных ячеек в атлас не везём — меньше видеопамяти.
    boxes = [im.getbbox() for ims in raw.values() for im in ims if im.getbbox()]
    u = (max(min(b[0] for b in boxes) - 4, 0), max(min(b[1] for b in boxes) - 4, 0),
         min(max(b[2] for b in boxes) + 4, raw["idle"][0].width), min(max(b[3] for b in boxes) + 4, raw["idle"][0].height))
    raw = {anim: [im.crop(u) for im in ims] for anim, ims in raw.items()}
    cw, ch = round((u[2] - u[0]) * k), round((u[3] - u[1]) * k)
    foot_x = ((box[0] + box[2]) * 0.5 - u[0]) * k
    foot_y = (max(im.getbbox()[3] for im in raw["idle"])) * k
    atlas = Image.new("RGBA", (cw * 6, ch * len(ROWS)))
    regions, names, start = [], [], {}
    for r, (anim, n) in enumerate(ROWS):
        start[anim] = len(regions)
        for i, im in enumerate(raw[anim]):
            atlas.alpha_composite(im.resize((cw, ch), Image.LANCZOS), (i * cw, r * ch))
            regions.append([i * cw, r * ch, cw, ch, round(foot_x, 1), round(foot_y, 1)])
            names.append(f"{anim}{i}")
    out = f"source/assets/enemies/{eid}.png"
    atlas.save(out, optimize=True)
    s = start
    frames["sheets"][eid] = {"texture": f"res://assets/enemies/{eid}.png", "regions": [], "region_ranges": {}, "faces_right": True,
        "frames": regions, "names": names, "clips": {
            "idle": {"frames": [s["idle"], s["idle"] + 1], "fps": 3.0, "loop": True},
            "taunt": {"frames": [s["idle"] + 1], "fps": 1.0, "loop": False},
            "run": {"frames": list(range(s["run"], s["run"] + 6)), "fps": 10.0, "loop": True},
            "windup": {"frames": [s["attack"], s["attack"] + 1], "fps": 5.0, "loop": False},
            "aim": {"frames": [s["attack"]], "fps": 1.0, "loop": False},
            "strike": {"frames": [s["attack"] + 2, s["attack"] + 3], "fps": 10.0, "loop": False},
            "hit": {"frames": [s["hit"]], "fps": 1.0, "loop": False},
            "death": {"frames": list(range(s["death"], s["death"] + 5)), "fps": 8.0, "loop": False}}}
    for e in enemies["enemies"]:
        if e.get("enemy_id") == eid:
            e.pop("rig", None)
            e.pop("rig_variants", None)
            e["sprite"] = f"res://assets/enemies/{eid}.png"
            e["sprite_scale"] = 1.0
            e["frames"] = eid
    print(eid, atlas.size, "cell", cw, ch)
json.dump(frames, open(frames_path, "w"), ensure_ascii=False)
json.dump(enemies, open(enemies_path, "w"), ensure_ascii=False, indent=2)
