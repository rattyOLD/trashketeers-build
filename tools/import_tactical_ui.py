#!/usr/bin/env python3
"""Подключает готовые UI v21/v27, сохраняя игровые пути и размер текстур."""
from pathlib import Path
from PIL import Image
from hero_tactical import rgba

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "astra/inbox/story/ui_tactical"
DST = ROOT / "source/assets/ui"


def put(name, target, side=None):
    dest = DST / target
    im = rgba(str(SRC / (name + ".png")))
    if dest.exists():
        im = im.resize(Image.open(dest).size, Image.Resampling.LANCZOS)
    elif side and max(im.size) > side:
        im.thumbnail((side, side), Image.Resampling.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, optimize=True)


def main():
    for old, new in {"gold": "orange", "teal": "graphite", "green": "olive", "red": "red"}.items():
        for state in ("normal", "pressed", "disabled"):
            for suffix in ("", "_s"):
                put(f"btn_{new}_{state}{suffix}", f"kit/btn_{old}_{state}{suffix}.png")
    put("window_graphite", "kit/window_neon_turquoise_s.png")
    for src, dst in {"icon_gift": "gift_box", "icon_chest_free": "chest_free",
                     "icon_updates": "news", "icon_vip": "vip", "icon_upgrade": "upgrade",
                     "icon_friends": "friends", "icon_squad": "hero", "icon_skins": "outfit",
                     "coin": "coin"}.items():
        put(src, f"hub/{dst}.png")
    for name in ("attach", "send", "file", "report", "delete", "stickers"):
        put("chat_" + name, f"chat/{name}.png")
    for name in ("level_medal", "level_medal_gold", "portrait_frame"):
        put(name, f"hud/{name}.png", 256)
    put("hud_hp_frame", "hud/hp_frame.png")
    put("hud_xp_frame", "hud/xp_frame.png")
    for name, src in {"ok": "ok", "gg": "gg", "hi": "hi", "lol": "lol", "letsgo": "lets_go"}.items():
        put("reaction_" + src, f"quick/{name}.png", 80)
    for hero in ("raccoon", "red_panda", "snow", "night", "maloy"):
        src = ROOT / f"astra/inbox/story/heroes_tactical/{hero}/ui/avatar_{hero}.png"
        dest = DST / f"portraits/avatar/{hero}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        rgba(str(src)).resize((160, 160), Image.Resampling.LANCZOS).save(dest, optimize=True)
    print("TACTICAL_UI imported buttons, window, menu, chat, medals, frame and 5 avatars")


if __name__ == "__main__":
    main()
