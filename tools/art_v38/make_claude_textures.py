#!/usr/bin/env python3
"""Temporary pixel textures for the bank front (inscription, carpet, banner) until Astra's art.

96 px/m, hard alpha, dark 1 px outline. Run: python3 tools/art_v38/make_claude_textures.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random

OUT = Path(__file__).resolve().parent / "claude_textures"
OUT.mkdir(exist_ok=True)
GOLD = [(122, 74, 22), (176, 118, 34), (226, 172, 58), (255, 222, 120)]
OUTLINE = (52, 30, 14, 255)


def outline(mask: Image.Image, fill: Image.Image) -> Image.Image:
    """Binary-alpha sprite: fill where mask, dark outline one pixel around it."""
    grown = mask.filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", mask.size, OUTLINE), (0, 0), grown)
    out.paste(fill, (0, 0), mask)
    return out


def inscription() -> None:
    # 4.8 x 0.5 m: antique serif capitals, gilded with a cast shadow below-right so the letters
    # read as raised metal on stone rather than a flat sticker.
    w, h = 460, 48
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 30)
    text = "ЗОЛОТОЙ  БАНК"
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    spacing = 6
    widths = [d.textbbox((0, 0), ch, font=font)[2] for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = (w - total) // 2
    for ch, cw in zip(text, widths):
        d.text((x, 6), ch, fill=255, font=font)
        x += cw + spacing
    mask = mask.point(lambda v: 255 if v > 120 else 0)
    shadow = Image.new("L", (w, h), 0)
    shadow.paste(mask, (2, 2))
    fill = Image.new("RGBA", (w, h))
    px = fill.load()
    tones = [(255, 226, 140), (232, 184, 74), (196, 140, 44), (150, 98, 28)]
    for y in range(h):
        tone = tones[0] if y < 13 else tones[1] if y < 22 else tones[2] if y < 31 else tones[3]
        for xx in range(w):
            px[xx, y] = tone + (255,)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), (58, 38, 20, 255)), (0, 0), shadow)
    out.paste(outline(mask, fill), (0, 0), mask.filter(ImageFilter.MaxFilter(3)))
    out.save(OUT / "bank_inscription.png")


def carpet() -> None:
    # Tiling red velvet 192x192 (2 m): pile rows, soft darker diamonds, no light baked.
    rnd = random.Random(7)
    im = Image.new("RGB", (192, 192))
    px = im.load()
    reds = [(112, 18, 26), (134, 24, 32), (152, 30, 38)]
    for y in range(192):
        for x in range(192):
            dx, dy = (x % 48) - 24, (y % 48) - 24
            diamond = abs(dx) + abs(dy) < 10
            base = 0 if diamond else 1 + ((x + 2 * y) // 3 % 2 if rnd.random() < 0.85 else 1)
            px[x, y] = reds[min(base, 2)]
    im.save(OUT / "bank_carpet.png")


def banner() -> None:
    # 96 x 160 px (1 x 1.67 m) hanging banner: red cloth, gold border, gold coin with pig snout, swallowtail.
    w, h = 96, 160
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.polygon([(4, 0), (w - 5, 0), (w - 5, h - 1), (w // 2, h - 28), (4, h - 1)], fill=255)
    fill = Image.new("RGBA", (w, h), (138, 24, 32, 255))
    f = ImageDraw.Draw(fill)
    for x in range(4, w - 4, 16):
        f.rectangle([x + 10, 0, x + 13, h], fill=(112, 18, 26, 255))
    f.rectangle([4, 0, w - 5, 7], fill=GOLD[2] + (255,))
    f.line([(10, 10), (10, h - 20)], fill=GOLD[1] + (255,), width=3)
    f.line([(w - 11, 10), (w - 11, h - 20)], fill=GOLD[1] + (255,), width=3)
    cx, cy, r = w // 2, 62, 24
    f.ellipse([cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2], fill=GOLD[0] + (255,))
    f.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD[2] + (255,))
    f.ellipse([cx - r + 4, cy - r + 4, cx + r - 6, cy + r - 6], fill=GOLD[3] + (255,))
    f.ellipse([cx - 11, cy - 6, cx + 11, cy + 9], fill=GOLD[1] + (255,))
    f.ellipse([cx - 6, cy - 1, cx - 2, cy + 4], fill=GOLD[0] + (255,))
    f.ellipse([cx + 2, cy - 1, cx + 6, cy + 4], fill=GOLD[0] + (255,))
    outline(mask, fill).save(OUT / "bank_banner.png")


inscription()
carpet()
banner()
print("CLAUDE_TEXTURES_OK", sorted(p.name for p in OUT.glob("*.png")))
