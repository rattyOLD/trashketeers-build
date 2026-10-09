#!/usr/bin/env python3
"""Остаток набора интерфейса Астры (astra/inbox/story/ui_kit) → source/assets/ui/kit/: фон #FF00FF вырезается astra_key,
размер — под игру (рамки окон 96 «_s», как window_neon_turquoise_s). Запуск из корня: python3 tools/import_ui_kit2.py"""
import os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from astra_key import key
from PIL import Image

SRC = "astra/inbox/story/ui_kit"
DST = "source/assets/ui/kit"
# имя: (макс. сторона, имя в игре). Ленты/неон заголовков и рамки «комикс»/«ржавчина» пока не нужны — не везём.
ITEMS = {
    "boss_bar_frame": (640, "boss_bar_frame"),
    "boss_name_plate": (640, "boss_name_plate"),
    "header_plate": (384, "header_plate"),
    "reward_card_common": (192, "reward_card_common"),
    "reward_card_rare": (192, "reward_card_rare"),
    "reward_card_legendary": (192, "reward_card_legendary"),
    "pass_node_complete": (96, "pass_node_complete"),
    "pass_node_current": (96, "pass_node_current"),
    "pass_node_empty": (96, "pass_node_empty"),
    "pass_node_premium": (96, "pass_node_premium"),
    "window_neon_gold": (96, "window_neon_gold_s"),
    "season_railgun_banner": (640, "season_railgun_banner"),
}

for name, (side, out) in ITEMS.items():
    tmp = tempfile.mktemp(suffix=".png")
    key(f"{SRC}/{name}.png", tmp, side)
    Image.open(tmp).save(f"{DST}/{out}.png", optimize=True)
    print(out, Image.open(f"{DST}/{out}.png").size)
