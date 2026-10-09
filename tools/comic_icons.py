"""Запуск: python3 tools/comic_icons.py <лист> <выход> <ячейка> (пример: firmware_icons из astra/inbox/world/survival2).
Иконки в стиле ретро-комикса: плоские тона, чернильный контур, растровые точки в тенях, газетная плашка."""
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

INK = (24, 18, 22)
PAPER = (236, 222, 188)


def flat(rgb, levels=4):
    # Плоские тона: постеризация яркости при сохранении оттенка, лёгкое «выцветание» печати.
    a = rgb.astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    q = np.round(lum * (levels - 1)) / (levels - 1)
    k = np.where(lum > 1e-3, q / np.maximum(lum, 1e-3), 0)
    out = np.clip(a * k, 0, 1)
    # Приглушить насыщенность и подтянуть к тёплой бумаге.
    grey = out.mean(axis=2, keepdims=True)
    out = np.clip(grey + (out - grey) * 1.15, 0, 1)
    out = out * 0.88 + np.array(PAPER) / 255.0 * 0.12
    return (out * 255).astype(np.uint8), lum[..., 0]


def halftone(size, step, radius_of):
    h, w = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # Решётка под 45°, как у типографского растра.
    u = (xx + yy) / np.sqrt(2) / step
    v = (xx - yy) / np.sqrt(2) / step
    du = (u - np.round(u)) * step
    dv = (v - np.round(v)) * step
    d = np.sqrt(du * du + dv * dv)
    return d < radius_of


def comic_icon(im, out_size=128, scale=4):
    big = im.resize((im.width * scale, im.height * scale), Image.LANCZOS)
    a = np.array(big).astype(np.uint8)
    alpha = a[..., 3]
    mask = alpha > 110
    # Обрезки соседних иконок по краям ячейки: оставляем только крупные куски.
    from scipy import ndimage
    lab, n = ndimage.label(mask)
    if n > 1:
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        objs = ndimage.find_objects(lab)
        w = mask.shape[1]
        # Обрезок — кусок, прижатый к левому/правому краю ячейки; мелкие детали внутри (искры) оставляем.
        keep = [i + 1 for i, s in enumerate(sizes)
                if s >= sizes.max() * 0.3 or (objs[i][1].start > w * 0.12 and objs[i][1].stop < w * 0.88)]
        mask = np.isin(lab, keep)
    rgb, lum = flat(a[..., :3])
    # Тени — точками: чем темнее, тем крупнее точка.
    dots = halftone(mask.shape, 9.0 * scale / 4, np.clip((0.75 - lum) * 6.0, 0, 3.6) * scale / 4)
    shade = mask & dots & (lum < 0.7)
    rgb[shade] = (rgb[shade].astype(np.float32) * 0.35).astype(np.uint8)
    # Внутренние чернильные линии по границам тонов.
    edge_src = Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.FIND_EDGES)
    edges = (np.array(edge_src.filter(ImageFilter.MaxFilter(5))) > 45) & mask
    rgb[edges] = INK
    # Толстый внешний контур.
    m = Image.fromarray((mask * 255).astype(np.uint8))
    outer = np.array(m.filter(ImageFilter.MaxFilter(5 * scale + 1))) > 0
    canvas = np.zeros((*mask.shape, 4), np.uint8)
    canvas[outer] = (*INK, 255)
    canvas[mask, :3] = rgb[mask]
    canvas[mask, 3] = 255
    icon = Image.fromarray(canvas, "RGBA")
    # Плашка: газетный круг с точками и чернильной рамкой (как фон комикс-панели).
    side = big.width
    badge = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    yy, xx = np.mgrid[0:side, 0:side]
    r = np.sqrt((xx - side / 2) ** 2 + (yy - side / 2) ** 2)
    disc = r < side * 0.47
    bg = np.zeros((side, side, 4), np.uint8)
    bg[disc] = (*PAPER, 255)
    bd = halftone((side, side), 9.0 * scale / 4, 1.6 * scale / 4) & disc
    bg[bd] = (214, 170, 120, 255)
    ring = (r >= side * 0.44) & (r < side * 0.49)
    bg[ring] = (*INK, 255)
    badge = Image.fromarray(bg, "RGBA")
    inner = icon.resize((int(side * 0.86), int(side * 0.86)), Image.LANCZOS)
    off = (side - inner.width) // 2
    badge.alpha_composite(inner, (off, off))
    return badge.resize((out_size, out_size), Image.LANCZOS)


if __name__ == "__main__":
    src, dst, cell = sys.argv[1], sys.argv[2], int(sys.argv[3])
    sheet = Image.open(src).convert("RGBA")
    n = sheet.width // cell
    out = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    for i in range(n):
        out.alpha_composite(comic_icon(sheet.crop((i * cell, 0, (i + 1) * cell, cell)), cell), (i * cell, 0))
    out.save(dst, optimize=True)
