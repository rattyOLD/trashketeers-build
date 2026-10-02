#!/usr/bin/env python3
"""Убирает фон #FF00FF у арта Астры и сохраняет PNG с прозрачностью.
Использование: astra_key.py <вход.png> <выход.png> [макс_сторона]
Розовая кайма по краю гасится: пиксели рядом с фоном, сильно розовые, перекрашиваются в цвет контура."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage


def key(path: str, out: str, max_side: int = 0) -> None:
    im = np.array(Image.open(path).convert("RGB")).astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    dist = np.sqrt((r - 255) ** 2 + g ** 2 + (b - 255) ** 2)
    strict = dist < 95
    band = ndimage.binary_dilation(strict, iterations=5) & ~strict
    mag = (np.minimum(r, b) - g) / 255.0
    fringe = band & (mag > 0.35)
    outline = np.array([26, 0, 51], dtype=np.float32)
    im = np.where(fringe[..., None], outline, im)
    alpha = ndimage.gaussian_filter(np.where(strict, 0.0, 255.0), 0.6)
    img = Image.fromarray(np.dstack([im, alpha]).clip(0, 255).astype(np.uint8), "RGBA")
    if max_side and max(img.size) > max_side:
        k = max_side / max(img.size)
        img = img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)
    img.save(out, optimize=True)


if __name__ == "__main__":
    key(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0)
