#!/usr/bin/env python3
"""Листы Енота Астры (768x512, фон #FF00FF) -> assets/heroes/raccoon_<clip>.png (ячейка 480x320, 4 в ряд) + data/raccoon_grip.json."""
import json, os, sys, tempfile
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from astra_key import key

SRC = "astra/inbox/story/heroes"
OUT = "/home/claude/raccoon"
K = 0.625
COUNTS = {"idle": 8, "run": 8, "shoot": 4, "hit": 4, "dash": 6, "death": 8, "revive": 6}
GRIP = ("idle", "run", "shoot")
cw, ch = 768, 512
for clip, n in COUNTS.items():
    tmp = tempfile.mktemp(suffix=".png")
    key(f"{SRC}/raccoon_{clip}.png", tmp)
    sheet = Image.open(tmp)
    cols_src = sheet.width // cw
    rows = (n + 3) // 4
    out = Image.new("RGBA", (4 * 480, rows * 320), (0, 0, 0, 0))
    for i in range(n):
        x, y = (i % cols_src) * cw, (i // cols_src) * ch
        cell = sheet.crop((x, y, x + cw, y + ch)).resize((480, 320), Image.LANCZOS)
        out.paste(cell, ((i % 4) * 480, (i // 4) * 320))
    out.save(f"{OUT}/assets/heroes/raccoon_{clip}.png", optimize=True)
grip = json.load(open(f"{SRC}/raccoon_grip.json"))
scaled = {c: [[round(v * K, 1) for v in p[:4]] for p in pts] for c, pts in grip.items() if c in GRIP}
json.dump(scaled, open(f"{OUT}/data/raccoon_grip.json", "w"))
print({c: len(v) for c, v in scaled.items()})
