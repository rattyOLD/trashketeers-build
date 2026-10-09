#!/usr/bin/env python3
"""Import delivered v25 chapter titles and Aquilon checkpoint sign."""
from pathlib import Path
from PIL import Image
from hero_tactical import rgba

ROOT = Path(__file__).resolve().parents[1]


def main():
    target = ROOT / "source/assets/story/chapter_cards"
    target.mkdir(parents=True, exist_ok=True)
    # Only chapters supported by StoryRun; later titles stay in the art inbox.
    for chapter in (1, 2):
        image = Image.open(ROOT / f"astra/inbox/story/chapter_cards/chapter_{chapter}.png").convert("RGBA")
        image.thumbnail((720, 300), Image.Resampling.LANCZOS)
        image.save(target / f"chapter_{chapter}.png", optimize=True)
    image = rgba(str(ROOT / "astra/inbox/story/aquilon/aquilon_gate_sign.png"))
    image = image.crop(image.getchannel("A").getbbox())
    image.thumbnail((192, 96), Image.Resampling.LANCZOS)
    image.save(ROOT / "source/assets/story/gates/aquilon_sign.png", optimize=True)
    print("STORY imported chapter 1/2 titles and Aquilon sign")


if __name__ == "__main__":
    main()
